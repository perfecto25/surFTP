module SurFTP
  class SFTPHandler
    # Handle types
    FILE_HANDLE = 0_u8
    DIR_HANDLE  = 1_u8

    class FileHandle
      property fd : IO::FileDescriptor
      property path : String

      def initialize(@fd, @path)
      end
    end

    class DirHandle
      property path : String
      property entries : Array(String)
      property sent : Bool

      def initialize(@path)
        @entries = Dir.entries(@path)
        @sent = false
      end
    end

    alias Handle = FileHandle | DirHandle

    @sftp : LibSSH::SFTPSession
    @vfs : VirtualFS
    @username : String
    @remote : String
    @handles : Hash(UInt32, Handle) = {} of UInt32 => Handle
    @next_handle_id : UInt32 = 1_u32

    def initialize(@sftp, @vfs, @username, @remote)
    end

    def run
      Log.info "SFTP session started for #{@username}@#{@remote}"
      AuditLog.log(@username, @remote, "CONNECT")
      loop do
        msg = LibSSH.sftp_get_client_message(@sftp)
        break if msg.null?

        msg_type = LibSSH.sftp_client_message_get_type(msg)
        Log.debug "SFTP msg type=#{msg_type} from #{@username}@#{@remote}"

        case msg_type
        when LibSSH::SSH_FXP_REALPATH then handle_realpath(msg)
        when LibSSH::SSH_FXP_STAT     then handle_stat(msg)
        when LibSSH::SSH_FXP_LSTAT    then handle_lstat(msg)
        when LibSSH::SSH_FXP_FSTAT    then handle_fstat(msg)
        when LibSSH::SSH_FXP_OPENDIR  then handle_opendir(msg)
        when LibSSH::SSH_FXP_READDIR  then handle_readdir(msg)
        when LibSSH::SSH_FXP_OPEN     then handle_open(msg)
        when LibSSH::SSH_FXP_READ     then handle_read(msg)
        when LibSSH::SSH_FXP_WRITE    then handle_write(msg)
        when LibSSH::SSH_FXP_CLOSE    then handle_close(msg)
        when LibSSH::SSH_FXP_MKDIR    then handle_mkdir(msg)
        when LibSSH::SSH_FXP_RMDIR    then handle_rmdir(msg)
        when LibSSH::SSH_FXP_REMOVE   then handle_remove(msg)
        when LibSSH::SSH_FXP_RENAME   then handle_rename(msg)
        when LibSSH::SSH_FXP_SETSTAT  then handle_setstat(msg)
        when LibSSH::SSH_FXP_FSETSTAT then handle_setstat(msg)
        else
          Log.warn "Unsupported SFTP op #{msg_type} from #{@username}@#{@remote}"
          LibSSH.sftp_reply_status(msg, LibSSH::SSH_FX_OP_UNSUPPORTED, "Not supported")
        end

        LibSSH.sftp_client_message_free(msg)
      end
    ensure
      AuditLog.log(@username, @remote, "DISCONNECT")
      Log.info "SFTP session ended for #{@username}@#{@remote}"
      # Close any remaining handles
      @handles.each_value do |handle|
        case handle
        when FileHandle
          handle.fd.close rescue nil
        end
      end
      @handles.clear
    end

    private def handle_realpath(msg : LibSSH::SFTPClientMessage)
      filename_ptr = LibSSH.sftp_client_message_get_filename(msg)
      path = filename_ptr.null? ? "/" : String.new(filename_ptr)

      real = @vfs.resolve(path)
      unless real
        LibSSH.sftp_reply_status(msg, LibSSH::SSH_FX_PERMISSION_DENIED, "Access denied")
        return
      end

      # For realpath, if the resolved path doesn't exist, just return the virtual root
      vpath = @vfs.virtual_path(real)

      attrs = build_attrs_for(real)
      if attrs
        LibSSH.sftp_reply_name(msg, vpath, attrs)
      else
        # Path doesn't exist — return virtual root
        dummy = build_directory_attrs
        LibSSH.sftp_reply_name(msg, "/", dummy)
      end
    end

    private def handle_stat(msg : LibSSH::SFTPClientMessage)
      real = resolve_filename(msg)
      return unless real

      attrs = build_attrs_for(real)
      unless attrs
        LibSSH.sftp_reply_status(msg, LibSSH::SSH_FX_NO_SUCH_FILE, "No such file")
        return
      end

      LibSSH.sftp_reply_attr(msg, attrs)
    end

    private def handle_lstat(msg : LibSSH::SFTPClientMessage)
      handle_stat(msg)
    end

    private def handle_fstat(msg : LibSSH::SFTPClientMessage)
      handle_id = read_handle_id(msg)
      unless handle_id
        LibSSH.sftp_reply_status(msg, LibSSH::SSH_FX_BAD_MESSAGE, "Invalid handle")
        return
      end

      handle = @handles[handle_id]?
      unless handle
        LibSSH.sftp_reply_status(msg, LibSSH::SSH_FX_BAD_MESSAGE, "Invalid handle")
        return
      end

      path = case handle
             when FileHandle then handle.path
             when DirHandle  then handle.path
             else
               LibSSH.sftp_reply_status(msg, LibSSH::SSH_FX_BAD_MESSAGE, "Invalid handle")
               return
             end

      attrs = build_attrs_for(path)
      unless attrs
        LibSSH.sftp_reply_status(msg, LibSSH::SSH_FX_NO_SUCH_FILE, "No such file")
        return
      end

      LibSSH.sftp_reply_attr(msg, attrs)
    end

    private def handle_opendir(msg : LibSSH::SFTPClientMessage)
      real = resolve_filename(msg)
      return unless real

      unless Dir.exists?(real)
        LibSSH.sftp_reply_status(msg, LibSSH::SSH_FX_NO_SUCH_FILE, "No such directory")
        return
      end

      id = alloc_handle_id
      @handles[id] = DirHandle.new(real)

      handle_str = make_handle_string(id)
      if handle_str.null?
        @handles.delete(id)
        LibSSH.sftp_reply_status(msg, LibSSH::SSH_FX_FAILURE, "Failed to allocate handle")
        return
      end

      LibSSH.sftp_reply_handle(msg, handle_str)
    end

    private def handle_readdir(msg : LibSSH::SFTPClientMessage)
      handle_id = read_handle_id(msg)
      unless handle_id
        LibSSH.sftp_reply_status(msg, LibSSH::SSH_FX_BAD_MESSAGE, "Invalid handle")
        return
      end

      handle = @handles[handle_id]?
      unless handle.is_a?(DirHandle)
        LibSSH.sftp_reply_status(msg, LibSSH::SSH_FX_BAD_MESSAGE, "Not a directory handle")
        return
      end

      if handle.sent
        LibSSH.sftp_reply_status(msg, LibSSH::SSH_FX_EOF, "")
        return
      end

      count = 0
      handle.entries.each do |entry|
        entry_path = File.join(handle.path, entry)
        vpath = @vfs.virtual_path(entry_path)
        longname = build_longname(entry, entry_path)
        attrs = build_attrs_for(entry_path)
        next unless attrs

        LibSSH.sftp_reply_names_add(msg, entry, longname, attrs)
        count += 1
      end

      handle.sent = true

      if count > 0
        LibSSH.sftp_reply_names(msg)
      else
        LibSSH.sftp_reply_status(msg, LibSSH::SSH_FX_EOF, "")
      end
    end

    private def handle_open(msg : LibSSH::SFTPClientMessage)
      real = resolve_filename(msg)
      return unless real

      flags = LibSSH.sftp_client_message_get_flags(msg)

      mode = "r"
      file_flags = File::Flags::None

      if (flags & LibSSH::SSH_FXF_WRITE) != 0
        if (flags & LibSSH::SSH_FXF_READ) != 0
          mode = "r+"
        elsif (flags & LibSSH::SSH_FXF_APPEND) != 0
          mode = "a"
        else
          mode = "w"
        end
      end

      if (flags & LibSSH::SSH_FXF_CREAT) != 0
        if (flags & LibSSH::SSH_FXF_TRUNC) != 0
          mode = "w" if mode == "r+"
        end
        # Create parent dir if needed
        parent = File.dirname(real)
        Dir.mkdir_p(parent) unless Dir.exists?(parent)
      end

      if (flags & LibSSH::SSH_FXF_CREAT) != 0 && !File.exists?(real)
        # Create the file
        File.touch(real)
      end

      unless File.exists?(real)
        LibSSH.sftp_reply_status(msg, LibSSH::SSH_FX_NO_SUCH_FILE, "No such file")
        return
      end

      begin
        fd = File.open(real, mode)
      rescue ex
        LibSSH.sftp_reply_status(msg, LibSSH::SSH_FX_PERMISSION_DENIED, ex.message || "Permission denied")
        return
      end

      id = alloc_handle_id
      @handles[id] = FileHandle.new(fd, real)

      handle_str = make_handle_string(id)
      if handle_str.null?
        fd.close
        @handles.delete(id)
        LibSSH.sftp_reply_status(msg, LibSSH::SSH_FX_FAILURE, "Failed to allocate handle")
        return
      end

      action = (flags & LibSSH::SSH_FXF_WRITE) != 0 ? "UPLOAD" : "DOWNLOAD"
      AuditLog.log(@username, @remote, action, @vfs.virtual_path(real))

      LibSSH.sftp_reply_handle(msg, handle_str)
    end

    private def handle_read(msg : LibSSH::SFTPClientMessage)
      handle_id = read_handle_id(msg)
      unless handle_id
        LibSSH.sftp_reply_status(msg, LibSSH::SSH_FX_BAD_MESSAGE, "Invalid handle")
        return
      end

      handle = @handles[handle_id]?
      unless handle.is_a?(FileHandle)
        LibSSH.sftp_reply_status(msg, LibSSH::SSH_FX_BAD_MESSAGE, "Not a file handle")
        return
      end

      # Read offset and length from the message struct fields
      # Access through the opaque struct by reading the client message fields
      msg_struct = msg.as(Pointer(SFTPClientMessageRaw))
      offset = msg_struct.value.offset
      len = msg_struct.value.len

      handle.fd.seek(offset.to_i64, IO::Seek::Set)

      buf = Bytes.new(len.clamp(1_u32, 65536_u32))
      bytes_read = handle.fd.read(buf)

      if bytes_read == 0
        LibSSH.sftp_reply_status(msg, LibSSH::SSH_FX_EOF, "")
      else
        LibSSH.sftp_reply_data(msg, buf.to_unsafe.as(Void*), bytes_read.to_i32)
      end
    end

    private def handle_write(msg : LibSSH::SFTPClientMessage)
      handle_id = read_handle_id(msg)
      unless handle_id
        LibSSH.sftp_reply_status(msg, LibSSH::SSH_FX_BAD_MESSAGE, "Invalid handle")
        return
      end

      handle = @handles[handle_id]?
      unless handle.is_a?(FileHandle)
        LibSSH.sftp_reply_status(msg, LibSSH::SSH_FX_BAD_MESSAGE, "Not a file handle")
        return
      end

      msg_struct = msg.as(Pointer(SFTPClientMessageRaw))
      offset = msg_struct.value.offset
      data_raw = msg_struct.value.data

      if data_raw.null?
        LibSSH.sftp_reply_status(msg, LibSSH::SSH_FX_BAD_MESSAGE, "No data")
        return
      end

      # ssh_string: first 4 bytes are BE length, then data
      data_ptr = (data_raw.as(UInt8*) + 4)
      data_len = IO::ByteFormat::BigEndian.decode(UInt32, Slice.new(data_raw.as(UInt8*), 4))

      handle.fd.seek(offset.to_i64, IO::Seek::Set)
      handle.fd.write(Slice.new(data_ptr, data_len))
      handle.fd.flush

      LibSSH.sftp_reply_status(msg, LibSSH::SSH_FX_OK, "")
    end

    private def handle_close(msg : LibSSH::SFTPClientMessage)
      handle_id = read_handle_id(msg)
      unless handle_id
        LibSSH.sftp_reply_status(msg, LibSSH::SSH_FX_BAD_MESSAGE, "Invalid handle")
        return
      end

      handle = @handles.delete(handle_id)
      unless handle
        LibSSH.sftp_reply_status(msg, LibSSH::SSH_FX_BAD_MESSAGE, "Invalid handle")
        return
      end

      case handle
      when FileHandle
        handle.fd.close rescue nil
      end

      LibSSH.sftp_reply_status(msg, LibSSH::SSH_FX_OK, "")
    end

    private def handle_mkdir(msg : LibSSH::SFTPClientMessage)
      real = resolve_filename(msg)
      return unless real

      begin
        Dir.mkdir(real)
        AuditLog.log(@username, @remote, "MKDIR", @vfs.virtual_path(real))
        LibSSH.sftp_reply_status(msg, LibSSH::SSH_FX_OK, "")
      rescue ex
        LibSSH.sftp_reply_status(msg, LibSSH::SSH_FX_FAILURE, ex.message || "Failed")
      end
    end

    private def handle_rmdir(msg : LibSSH::SFTPClientMessage)
      real = resolve_filename(msg)
      return unless real

      begin
        Dir.delete(real)
        AuditLog.log(@username, @remote, "RMDIR", @vfs.virtual_path(real))
        LibSSH.sftp_reply_status(msg, LibSSH::SSH_FX_OK, "")
      rescue ex
        LibSSH.sftp_reply_status(msg, LibSSH::SSH_FX_FAILURE, ex.message || "Failed")
      end
    end

    private def handle_remove(msg : LibSSH::SFTPClientMessage)
      real = resolve_filename(msg)
      return unless real

      begin
        File.delete(real)
        AuditLog.log(@username, @remote, "DELETE", @vfs.virtual_path(real))
        LibSSH.sftp_reply_status(msg, LibSSH::SSH_FX_OK, "")
      rescue ex
        LibSSH.sftp_reply_status(msg, LibSSH::SSH_FX_FAILURE, ex.message || "Failed")
      end
    end

    private def handle_rename(msg : LibSSH::SFTPClientMessage)
      real = resolve_filename(msg)
      return unless real

      data_ptr = LibSSH.sftp_client_message_get_data(msg)
      if data_ptr.null?
        LibSSH.sftp_reply_status(msg, LibSSH::SSH_FX_BAD_MESSAGE, "Missing target")
        return
      end

      new_name = String.new(data_ptr)
      new_real = @vfs.resolve(new_name)
      unless new_real
        LibSSH.sftp_reply_status(msg, LibSSH::SSH_FX_PERMISSION_DENIED, "Access denied")
        return
      end

      begin
        File.rename(real, new_real)
        AuditLog.log(@username, @remote, "RENAME", "#{@vfs.virtual_path(real)} -> #{@vfs.virtual_path(new_real)}")
        LibSSH.sftp_reply_status(msg, LibSSH::SSH_FX_OK, "")
      rescue ex
        LibSSH.sftp_reply_status(msg, LibSSH::SSH_FX_FAILURE, ex.message || "Failed")
      end
    end

    private def handle_setstat(msg : LibSSH::SFTPClientMessage)
      # Accept but ignore — we don't change permissions for virtual users
      LibSSH.sftp_reply_status(msg, LibSSH::SSH_FX_OK, "")
    end

    # --- Helpers ---

    private def resolve_filename(msg : LibSSH::SFTPClientMessage) : String?
      filename_ptr = LibSSH.sftp_client_message_get_filename(msg)
      if filename_ptr.null?
        LibSSH.sftp_reply_status(msg, LibSSH::SSH_FX_BAD_MESSAGE, "Missing filename")
        return nil
      end

      path = String.new(filename_ptr)
      real = @vfs.resolve(path)
      unless real
        LibSSH.sftp_reply_status(msg, LibSSH::SSH_FX_PERMISSION_DENIED, "Access denied")
        return nil
      end
      real
    end

    private def alloc_handle_id : UInt32
      id = @next_handle_id
      @next_handle_id &+= 1
      id
    end

    private def make_handle_string(id : UInt32) : LibSSH::SSHString
      # Use sftp_handle_alloc with a boxed ID pointer
      # Store the ID as a tagged pointer value (not a real pointer)
      LibSSH.sftp_handle_alloc(@sftp, Pointer(Void).new(id.to_u64))
    end

    private def read_handle_id(msg : LibSSH::SFTPClientMessage) : UInt32?
      # Read the handle from the message struct
      msg_struct = msg.as(Pointer(SFTPClientMessageRaw))
      handle_raw = msg_struct.value.handle

      return nil if handle_raw.null?

      # Look up through sftp_handle — cast Void* to SSHString
      ptr = LibSSH.sftp_handle(@sftp, handle_raw.as(LibSSH::SSHString))
      return nil if ptr.null?

      ptr.address.to_u32
    end

    private def build_attrs_for(path : String) : LibSSH::SFTPAttributes?
      return nil unless File.exists?(path) || Dir.exists?(path)

      info = File.info(path, follow_symlinks: false)
      attrs = Pointer(SFTPAttributesRaw).malloc(1)

      # Zero it out
      attrs.value = SFTPAttributesRaw.new

      attrs.value.flags = LibSSH::SSH_FILEXFER_ATTR_SIZE |
                          LibSSH::SSH_FILEXFER_ATTR_UIDGID |
                          LibSSH::SSH_FILEXFER_ATTR_PERMISSIONS |
                          LibSSH::SSH_FILEXFER_ATTR_ACMODTIME

      attrs.value.size = info.size.to_u64
      attrs.value.uid = 1000_u32
      attrs.value.gid = 1000_u32
      attrs.value.permissions = info.permissions.value.to_u32

      if info.directory?
        attrs.value.type = LibSSH::SSH_FILEXFER_TYPE_DIRECTORY
        attrs.value.permissions = attrs.value.permissions | 0o40000_u32
      elsif info.symlink?
        attrs.value.type = LibSSH::SSH_FILEXFER_TYPE_SYMLINK
      else
        attrs.value.type = LibSSH::SSH_FILEXFER_TYPE_REGULAR
        attrs.value.permissions = attrs.value.permissions | 0o100000_u32
      end

      attrs.value.mtime = info.modification_time.to_unix.to_u32
      attrs.value.atime = info.modification_time.to_unix.to_u32

      attrs.as(LibSSH::SFTPAttributes)
    end

    private def build_directory_attrs : LibSSH::SFTPAttributes
      attrs = Pointer(SFTPAttributesRaw).malloc(1)
      attrs.value = SFTPAttributesRaw.new
      attrs.value.flags = LibSSH::SSH_FILEXFER_ATTR_SIZE |
                          LibSSH::SSH_FILEXFER_ATTR_PERMISSIONS
      attrs.value.type = LibSSH::SSH_FILEXFER_TYPE_DIRECTORY
      attrs.value.permissions = 0o40755_u32
      attrs.value.size = 0_u64
      attrs.as(LibSSH::SFTPAttributes)
    end

    private def build_longname(name : String, path : String) : String
      begin
        info = File.info(path, follow_symlinks: false)
        type_char = info.directory? ? 'd' : '-'
        perms = info.permissions.value
        size = info.size
        mtime = info.modification_time
        time_str = mtime.to_s("%b %e %H:%M")
        "#{type_char}#{format_perms(perms)} 1 owner group #{size.to_s.rjust(8)} #{time_str} #{name}"
      rescue
        "---------- 1 owner group        0 Jan  1 00:00 #{name}"
      end
    end

    private def format_perms(perms : Int) : String
      String.build do |s|
        [0o400, 0o200, 0o100, 0o040, 0o020, 0o010, 0o004, 0o002, 0o001].each_with_index do |bit, i|
          if (perms & bit) != 0
            s << "rwx"[i % 3]
          else
            s << '-'
          end
        end
      end
    end
  end

  # Raw struct matching sftp_client_message_struct in sftp.h
  # Used for reading offset/len/handle/data fields directly
  struct SFTPClientMessageRaw
    property sftp : Void* = Pointer(Void).null
    property type : UInt8 = 0_u8
    property id : UInt32 = 0_u32
    property filename : Void* = Pointer(Void).null   # char*
    property flags : UInt32 = 0_u32
    property attr : Void* = Pointer(Void).null        # sftp_attributes
    property handle : Void* = Pointer(Void).null      # ssh_string
    property offset : UInt64 = 0_u64
    property len : UInt32 = 0_u32
    property attr_num : Int32 = 0_i32
    property attrbuf : Void* = Pointer(Void).null     # ssh_buffer
    property data : Void* = Pointer(Void).null        # ssh_string
    property complete_message : Void* = Pointer(Void).null # ssh_buffer
    property str_data : Void* = Pointer(Void).null    # char*
    property submessage : Void* = Pointer(Void).null  # char*
  end

  # Raw struct matching sftp_attributes_struct in sftp.h
  struct SFTPAttributesRaw
    property name : Void* = Pointer(Void).null        # char*
    property longname : Void* = Pointer(Void).null    # char*
    property flags : UInt32 = 0_u32
    property type : UInt8 = 0_u8
    property size : UInt64 = 0_u64
    property uid : UInt32 = 0_u32
    property gid : UInt32 = 0_u32
    property owner : Void* = Pointer(Void).null       # char*
    property group : Void* = Pointer(Void).null       # char*
    property permissions : UInt32 = 0_u32
    property atime64 : UInt64 = 0_u64
    property atime : UInt32 = 0_u32
    property atime_nseconds : UInt32 = 0_u32
    property createtime : UInt64 = 0_u64
    property createtime_nseconds : UInt32 = 0_u32
    property mtime64 : UInt64 = 0_u64
    property mtime : UInt32 = 0_u32
    property mtime_nseconds : UInt32 = 0_u32
    property acl : Void* = Pointer(Void).null         # ssh_string
    property extended_count : UInt32 = 0_u32
    property extended_type : Void* = Pointer(Void).null  # ssh_string
    property extended_data : Void* = Pointer(Void).null  # ssh_string
  end
end
