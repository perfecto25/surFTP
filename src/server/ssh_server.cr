lib LibC
  fun close(fd : Int32) : Int32
end

module SurFTP
  class SSHServer
    @bind : LibSSH::SSHBind?
    @running = false
    @config : Config

    def initialize(@config : Config)
    end

    def start
      LibSSH.ssh_init
      ensure_host_key

      @running = true

      # Channel to receive startup result from the accept thread
      ready = Channel(Exception?).new

      # All bind operations (listen + accept) must happen on the same OS thread
      Thread.new(name: "sftp-accept") { accept_thread(ready) }

      if ex = ready.receive
        @running = false
        raise ex
      end

      # Keep this fiber alive (TUI uses spawn { start }, CLI calls start directly)
      while @running
        sleep 1.second
      end
    end

    def stop
      @running = false
      if bind = @bind
        fd = LibSSH.ssh_bind_get_fd(bind)
        LibC.close(fd) if fd >= 0
      end
    end

    def running? : Bool
      @running
    end

    private def accept_thread(ready : Channel(Exception?))
      bind = LibSSH.ssh_bind_new
      if bind.null?
        ready.send(Exception.new("Failed to create ssh_bind"))
        return
      end

      @config.bind_address.to_unsafe.tap do |ptr|
        LibSSH.ssh_bind_options_set(bind, LibSSH::SSH_BIND_OPTIONS_BINDADDR, ptr.as(Void*))
      end

      port_val = @config.port
      pointerof(port_val).tap do |ptr|
        LibSSH.ssh_bind_options_set(bind, LibSSH::SSH_BIND_OPTIONS_BINDPORT, ptr.as(Void*))
      end

      key_path = @config.host_key
      key_path.to_unsafe.tap do |ptr|
        if LibSSH.ssh_bind_options_set(bind, LibSSH::SSH_BIND_OPTIONS_HOSTKEY, ptr.as(Void*)) != LibSSH::SSH_OK
          err = String.new(LibSSH.ssh_get_error(bind.as(Void*)))
          LibSSH.ssh_bind_free(bind)
          ready.send(Exception.new("Failed to set host key: #{err}"))
          return
        end
      end

      if LibSSH.ssh_bind_listen(bind) != LibSSH::SSH_OK
        err = String.new(LibSSH.ssh_get_error(bind.as(Void*)))
        LibSSH.ssh_bind_free(bind)
        ready.send(Exception.new("Failed to listen: #{err}"))
        return
      end

      @bind = bind
      Log.info "SFTP server started on #{@config.bind_address}:#{@config.port}"
      ready.send(nil)

      while @running
        session = LibSSH.ssh_new
        if session.null?
          Log.error "Failed to allocate SSH session"
          sleep 0.1.seconds
          next
        end

        rc = LibSSH.ssh_bind_accept(bind, session)
        unless rc == LibSSH::SSH_OK
          LibSSH.ssh_free(session)
          next unless @running
          Log.error "Accept failed: #{String.new(LibSSH.ssh_get_error(bind.as(Void*)))}"
          next
        end

        remote = peer_address(LibSSH.ssh_get_fd(session))
        Log.info "Connection from #{remote}"

        spawn_connection(session, remote)
      end

      LibSSH.ssh_bind_free(bind)
      @bind = nil
    end

    private def peer_address(fd : Int32) : String
      return "unknown" if fd < 0
      addr = uninitialized LibC::SockaddrIn
      len = LibC::SocklenT.new(sizeof(LibC::SockaddrIn))
      return "unknown" if LibC.getpeername(fd, pointerof(addr).as(LibC::Sockaddr*), pointerof(len)) != 0
      buf = StaticArray(UInt8, 46).new(0_u8)
      sin_addr = addr.sin_addr
      ptr = LibC.inet_ntop(LibC::AF_INET, pointerof(sin_addr).as(Void*), buf.to_unsafe.as(LibC::Char*), 46)
      return "unknown" if ptr.null?
      ip = String.new(buf.to_unsafe.as(LibC::Char*))
      port = LibC.ntohs(addr.sin_port)
      "#{ip}:#{port}"
    rescue
      "unknown"
    end

    private def spawn_connection(session : LibSSH::SSHSession, remote : String)
      Thread.new(name: "sftp-conn") { handle_connection(session, remote) }
    end

    private def handle_connection(session : LibSSH::SSHSession, remote : String)
      LibSSH.ssh_set_blocking(session, 1)

      # Key exchange
      if LibSSH.ssh_handle_key_exchange(session) != LibSSH::SSH_OK
        Log.error "Key exchange failed for #{remote}: #{String.new(LibSSH.ssh_get_error(session.as(Void*)))}"
        cleanup_session(session)
        return
      end
      Log.debug "Key exchange completed for #{remote}"

      # Authenticate
      username = SSHAuth.authenticate(session)
      unless username
        Log.warn "Authentication failed for #{remote}"
        cleanup_session(session)
        return
      end
      Log.info "User '#{username}' authenticated from #{remote}"
      SessionRegistry.register(username, session)
      session_id = UserRepo.add_session(username, remote)

      # Wait for channel open
      channel = wait_for_channel(session)
      unless channel
        Log.error "Channel open failed for #{username}@#{remote}"
        cleanup_session(session)
        return
      end
      Log.debug "Channel opened for #{username}@#{remote}"

      # Wait for sftp subsystem request
      unless wait_for_sftp_subsystem(session, channel)
        Log.error "SFTP subsystem request failed for #{username}@#{remote}"
        LibSSH.ssh_channel_close(channel)
        LibSSH.ssh_channel_free(channel)
        cleanup_session(session)
        return
      end
      Log.debug "SFTP subsystem started for #{username}@#{remote}"

      # Get user for home directory
      user = UserRepo.find_by_username(username)
      unless user
        Log.error "User '#{username}' not found in database after auth"
        LibSSH.ssh_channel_close(channel)
        LibSSH.ssh_channel_free(channel)
        cleanup_session(session)
        return
      end

      # Create SFTP session
      sftp = LibSSH.sftp_server_new(session, channel)
      if sftp.null?
        Log.error "Failed to create SFTP session for #{username}@#{remote}"
        LibSSH.ssh_channel_close(channel)
        LibSSH.ssh_channel_free(channel)
        cleanup_session(session)
        return
      end

      if LibSSH.sftp_server_init(sftp) != LibSSH::SSH_OK
        Log.error "Failed to init SFTP session for #{username}@#{remote}"
        LibSSH.sftp_server_free(sftp)
        LibSSH.ssh_channel_close(channel)
        LibSSH.ssh_channel_free(channel)
        cleanup_session(session)
        return
      end

      # Run SFTP handler
      vfs = VirtualFS.new(username, user.home_directory)
      handler = SFTPHandler.new(sftp, vfs, username, remote)
      handler.run

      Log.info "Session ended for #{username}@#{remote}"
      SessionRegistry.deregister(username, session)
      UserRepo.remove_session(session_id)

      LibSSH.sftp_server_free(sftp)
      LibSSH.ssh_channel_close(channel)
      LibSSH.ssh_channel_free(channel)
      cleanup_session(session)
    rescue ex
      Log.error "Connection error for #{remote}: #{ex.class.name}: #{ex.message}"
      cleanup_session(session) rescue nil
    end

    private def wait_for_channel(session : LibSSH::SSHSession) : LibSSH::SSHChannel?
      10.times do
        msg = LibSSH.ssh_message_get(session)
        next if msg.null?

        msg_type = LibSSH.ssh_message_type(msg)
        msg_sub = LibSSH.ssh_message_subtype(msg)
        Log.debug "Channel wait: type=#{msg_type} subtype=#{msg_sub}"

        if msg_type == LibSSH::SSH_REQUEST_CHANNEL_OPEN
          channel = LibSSH.ssh_message_channel_request_open_reply_accept(msg)
          LibSSH.ssh_message_free(msg)
          return channel unless channel.null?
        else
          LibSSH.ssh_message_reply_default(msg)
          LibSSH.ssh_message_free(msg)
        end
      end
      nil
    end

    private def wait_for_sftp_subsystem(session : LibSSH::SSHSession, channel : LibSSH::SSHChannel) : Bool
      10.times do
        msg = LibSSH.ssh_message_get(session)
        next if msg.null?

        msg_type = LibSSH.ssh_message_type(msg)
        msg_sub = LibSSH.ssh_message_subtype(msg)
        Log.debug "Subsystem wait: type=#{msg_type} subtype=#{msg_sub}"

        if msg_type == LibSSH::SSH_REQUEST_CHANNEL &&
           msg_sub == LibSSH::SSH_CHANNEL_REQUEST_SUBSYSTEM
          subsystem_ptr = LibSSH.ssh_message_channel_request_subsystem(msg)
          unless subsystem_ptr.null?
            subsystem = String.new(subsystem_ptr)
            Log.debug "Subsystem requested: #{subsystem}"
            if subsystem == "sftp"
              LibSSH.ssh_message_channel_request_reply_success(msg)
              LibSSH.ssh_message_free(msg)
              return true
            end
          end
        end
        LibSSH.ssh_message_reply_default(msg)
        LibSSH.ssh_message_free(msg)
      end
      false
    end

    private def cleanup_session(session : LibSSH::SSHSession)
      LibSSH.ssh_disconnect(session)
      LibSSH.ssh_free(session)
    end

    private def ensure_host_key
      key_path = @config.host_key
      return if File.exists?(key_path)

      dir = File.dirname(key_path)
      Dir.mkdir_p(dir) unless Dir.exists?(dir)

      stderr = IO::Memory.new
      result = Process.run(
        "ssh-keygen",
        ["-t", "ed25519", "-f", key_path, "-N", ""],
        error: stderr,
        output: Process::Redirect::Close
      )
      unless result.success?
        raise "Failed to generate host key: #{stderr}"
      end
      Log.info "Generated host key at #{key_path}"
    end
  end
end
