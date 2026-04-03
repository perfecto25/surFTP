@[Link("ssh")]
lib LibSSH
  # Opaque types
  type SSHSession = Void*
  type SSHBind = Void*
  type SSHChannel = Void*
  type SSHMessage = Void*
  type SSHKey = Void*
  type SSHString = Void*
  type SSHEvent = Void*
  type SFTPSession = Void*
  type SFTPClientMessage = Void*
  type SFTPAttributes = Void*

  # Return codes
  SSH_OK    =  0
  SSH_ERROR = -1
  SSH_AGAIN = -2

  # Auth methods (bitmask)
  SSH_AUTH_METHOD_PASSWORD  = 0x0002_u32
  SSH_AUTH_METHOD_PUBLICKEY = 0x0004_u32

  # Message types
  SSH_REQUEST_AUTH         = 1
  SSH_REQUEST_CHANNEL_OPEN = 2
  SSH_REQUEST_CHANNEL      = 3
  SSH_REQUEST_SERVICE       = 4

  # Auth subtypes — ssh_message_subtype() returns SSH_AUTH_METHOD_* values
  SSH_AUTH_METHOD_NONE_INT        = 0
  SSH_AUTH_PASSWORD_SUBTYPE       = 2  # SSH_AUTH_METHOD_PASSWORD
  SSH_AUTH_PUBLICKEY_SUBTYPE      = 4  # SSH_AUTH_METHOD_PUBLICKEY

  # Pubkey state
  SSH_PUBLICKEY_STATE_NONE  = 0
  SSH_PUBLICKEY_STATE_VALID = 1

  # Key types
  SSH_KEYTYPE_ED25519 = 5

  # Key comparison enum
  SSH_KEY_CMP_PUBLIC = 0

  # Bind options
  SSH_BIND_OPTIONS_BINDADDR  = 0
  SSH_BIND_OPTIONS_BINDPORT  = 1
  SSH_BIND_OPTIONS_HOSTKEY   = 3
  SSH_BIND_OPTIONS_RSAKEY    = 5

  # Channel request subtypes
  SSH_CHANNEL_REQUEST_ENV       = 4
  SSH_CHANNEL_REQUEST_SUBSYSTEM = 5

  # SFTP message types
  SSH_FXP_INIT     =  1
  SSH_FXP_OPEN     =  3
  SSH_FXP_CLOSE    =  4
  SSH_FXP_READ     =  5
  SSH_FXP_WRITE    =  6
  SSH_FXP_LSTAT    =  7
  SSH_FXP_FSTAT    =  8
  SSH_FXP_SETSTAT  =  9
  SSH_FXP_FSETSTAT = 10
  SSH_FXP_OPENDIR  = 11
  SSH_FXP_READDIR  = 12
  SSH_FXP_REMOVE   = 13
  SSH_FXP_MKDIR    = 14
  SSH_FXP_RMDIR    = 15
  SSH_FXP_REALPATH = 16
  SSH_FXP_STAT     = 17
  SSH_FXP_RENAME   = 18

  # SFTP status codes
  SSH_FX_OK                = 0_u32
  SSH_FX_EOF               = 1_u32
  SSH_FX_NO_SUCH_FILE      = 2_u32
  SSH_FX_PERMISSION_DENIED = 3_u32
  SSH_FX_FAILURE           = 4_u32
  SSH_FX_BAD_MESSAGE       = 5_u32
  SSH_FX_OP_UNSUPPORTED    = 8_u32

  # SFTP open flags
  SSH_FXF_READ   = 0x01_u32
  SSH_FXF_WRITE  = 0x02_u32
  SSH_FXF_APPEND = 0x04_u32
  SSH_FXF_CREAT  = 0x08_u32
  SSH_FXF_TRUNC  = 0x10_u32
  SSH_FXF_EXCL   = 0x20_u32

  # SFTP attribute flags
  SSH_FILEXFER_ATTR_SIZE        = 0x00000001_u32
  SSH_FILEXFER_ATTR_UIDGID      = 0x00000002_u32
  SSH_FILEXFER_ATTR_PERMISSIONS = 0x00000004_u32
  SSH_FILEXFER_ATTR_ACMODTIME   = 0x00000008_u32

  # SFTP file types
  SSH_FILEXFER_TYPE_REGULAR   = 1_u8
  SSH_FILEXFER_TYPE_DIRECTORY = 2_u8
  SSH_FILEXFER_TYPE_SYMLINK   = 3_u8
  SSH_FILEXFER_TYPE_SPECIAL   = 4_u8
  SSH_FILEXFER_TYPE_UNKNOWN   = 5_u8

  # --- Core SSH functions ---
  fun ssh_init : Int32
  fun ssh_new : SSHSession
  fun ssh_free(session : SSHSession)
  fun ssh_disconnect(session : SSHSession)
  fun ssh_get_error(error : Void*) : LibC::Char*
  fun ssh_handle_key_exchange(session : SSHSession) : Int32
  fun ssh_set_auth_methods(session : SSHSession, auth_methods : Int32)
  fun ssh_set_blocking(session : SSHSession, blocking : Int32)
  fun ssh_get_fd(session : SSHSession) : Int32

  # --- SSH bind ---
  fun ssh_bind_new : SSHBind
  fun ssh_bind_options_set(sshbind : SSHBind, type : Int32, value : Void*) : Int32
  fun ssh_bind_listen(sshbind : SSHBind) : Int32
  fun ssh_bind_accept(sshbind : SSHBind, session : SSHSession) : Int32
  fun ssh_bind_free(sshbind : SSHBind)
  fun ssh_bind_set_blocking(sshbind : SSHBind, blocking : Int32)
  fun ssh_bind_get_fd(sshbind : SSHBind) : Int32
  fun ssh_bind_accept_fd(sshbind : SSHBind, session : SSHSession, fd : Int32) : Int32

  # --- SSH messages ---
  fun ssh_message_get(session : SSHSession) : SSHMessage
  fun ssh_message_type(msg : SSHMessage) : Int32
  fun ssh_message_subtype(msg : SSHMessage) : Int32
  fun ssh_message_free(msg : SSHMessage)
  fun ssh_message_reply_default(msg : SSHMessage) : Int32

  # --- Auth messages ---
  fun ssh_message_auth_user(msg : SSHMessage) : LibC::Char*
  fun ssh_message_auth_password(msg : SSHMessage) : LibC::Char*
  fun ssh_message_auth_pubkey(msg : SSHMessage) : SSHKey
  fun ssh_message_auth_publickey_state(msg : SSHMessage) : Int32
  fun ssh_message_auth_set_methods(msg : SSHMessage, methods : Int32) : Int32
  fun ssh_message_auth_reply_success(msg : SSHMessage, partial : Int32) : Int32
  fun ssh_message_auth_reply_pk_ok_simple(msg : SSHMessage) : Int32

  # --- Service messages ---
  fun ssh_message_service_reply_success(msg : SSHMessage) : Int32

  # --- Channel messages ---
  fun ssh_message_channel_request_open_reply_accept(msg : SSHMessage) : SSHChannel
  fun ssh_message_channel_request_reply_success(msg : SSHMessage) : Int32
  fun ssh_message_channel_request_subsystem(msg : SSHMessage) : LibC::Char*

  # --- Channel ---
  fun ssh_channel_is_open(channel : SSHChannel) : Int32
  fun ssh_channel_close(channel : SSHChannel) : Int32
  fun ssh_channel_free(channel : SSHChannel)

  # --- Key operations ---
  fun ssh_pki_import_pubkey_base64(b64_key : LibC::Char*, type : Int32, pkey : SSHKey*) : Int32
  fun ssh_key_cmp(k1 : SSHKey, k2 : SSHKey, what : Int32) : Int32
  fun ssh_key_free(key : SSHKey)
  fun ssh_key_type_from_name(name : LibC::Char*) : Int32

  # --- SFTP server ---
  fun sftp_server_new(session : SSHSession, chan : SSHChannel) : SFTPSession
  fun sftp_server_init(sftp : SFTPSession) : Int32
  fun sftp_server_free(sftp : SFTPSession)

  # --- SFTP client messages ---
  fun sftp_get_client_message(sftp : SFTPSession) : SFTPClientMessage
  fun sftp_client_message_free(msg : SFTPClientMessage)
  fun sftp_client_message_get_type(msg : SFTPClientMessage) : UInt8
  fun sftp_client_message_get_filename(msg : SFTPClientMessage) : LibC::Char*
  fun sftp_client_message_get_data(msg : SFTPClientMessage) : LibC::Char*
  fun sftp_client_message_get_flags(msg : SFTPClientMessage) : UInt32

  # --- SFTP replies ---
  fun sftp_reply_status(msg : SFTPClientMessage, status : UInt32, message : LibC::Char*) : Int32
  fun sftp_reply_handle(msg : SFTPClientMessage, handle : SSHString) : Int32
  fun sftp_reply_data(msg : SFTPClientMessage, data : Void*, len : Int32) : Int32
  fun sftp_reply_names_add(msg : SFTPClientMessage, file : LibC::Char*, longname : LibC::Char*, attr : SFTPAttributes) : Int32
  fun sftp_reply_names(msg : SFTPClientMessage) : Int32
  fun sftp_reply_attr(msg : SFTPClientMessage, attr : SFTPAttributes) : Int32
  fun sftp_reply_name(msg : SFTPClientMessage, name : LibC::Char*, attr : SFTPAttributes) : Int32

  # --- SFTP handles ---
  fun sftp_handle_alloc(sftp : SFTPSession, info : Void*) : SSHString
  fun sftp_handle(sftp : SFTPSession, handle : SSHString) : Void*
  fun sftp_handle_remove(sftp : SFTPSession, handle : Void*)

  # --- SSH event loop ---
  fun ssh_event_new : SSHEvent
  fun ssh_event_add_session(event : SSHEvent, session : SSHSession) : Int32
  fun ssh_event_dopoll(event : SSHEvent, timeout : Int32) : Int32
  fun ssh_event_remove_session(event : SSHEvent, session : SSHSession) : Int32
  fun ssh_event_free(event : SSHEvent)
end
