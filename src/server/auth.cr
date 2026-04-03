module SurFTP
  module SSHAuth
    MAX_AUTH_ATTEMPTS = 10

    def self.authenticate(session : LibSSH::SSHSession) : String?
      auth_methods = LibSSH::SSH_AUTH_METHOD_PASSWORD | LibSSH::SSH_AUTH_METHOD_PUBLICKEY
      LibSSH.ssh_set_auth_methods(session, auth_methods.to_i32)

      attempts = 0
      Log.debug "Starting authentication (methods: password+publickey)"

      loop do
        msg = LibSSH.ssh_message_get(session)
        if msg.null?
          Log.debug "Auth: ssh_message_get returned null"
          return nil
        end

        msg_type = LibSSH.ssh_message_type(msg)
        Log.debug "Auth message: type=#{msg_type}"

        case msg_type
        when LibSSH::SSH_REQUEST_AUTH
          result = handle_auth_message(msg, auth_methods.to_i32, attempts)
          case result
          when String
            # Successful auth — msg already freed inside
            return result
          when :next
            # pk_ok sent, msg already freed inside
            next
          when :denied
            # Max attempts reached, msg already freed inside
            return nil
          when :skip
            # Method probe (none/unknown) — don't count toward attempt limit
          else
            # Actual failed auth attempt
            attempts += 1
          end

        when LibSSH::SSH_REQUEST_SERVICE
          LibSSH.ssh_message_service_reply_success(msg)

        else
          LibSSH.ssh_message_reply_default(msg)
        end

        LibSSH.ssh_message_free(msg)
      end
    end

    # Returns:
    #   String  — authenticated username (msg freed)
    #   :next   — pubkey probe accepted (msg freed)
    #   :denied — max attempts exceeded (msg freed)
    #   :skip   — none/unknown probe, don't count (caller frees msg)
    #   nil     — actual failed auth attempt (caller frees msg)
    private def self.handle_auth_message(msg : LibSSH::SSHMessage, auth_methods : Int32, attempts : Int32) : String | Symbol | Nil
      subtype = LibSSH.ssh_message_subtype(msg)

      case subtype
      when LibSSH::SSH_AUTH_PASSWORD_SUBTYPE
        username = read_string(LibSSH.ssh_message_auth_user(msg))
        password = read_string(LibSSH.ssh_message_auth_password(msg))
        Log.debug "Auth: password attempt for user '#{username}'"

        if username && password && verify_password(username, password)
          Log.info "Auth: password accepted for '#{username}'"
          LibSSH.ssh_message_auth_reply_success(msg, 0)
          LibSSH.ssh_message_free(msg)
          return username
        end

        Log.debug "Auth: password rejected for '#{username}' (attempt #{attempts + 1}/#{MAX_AUTH_ATTEMPTS})"

        if attempts + 1 >= MAX_AUTH_ATTEMPTS
          LibSSH.ssh_message_reply_default(msg)
          LibSSH.ssh_message_free(msg)
          return :denied
        end

        LibSSH.ssh_message_auth_set_methods(msg, auth_methods)
        LibSSH.ssh_message_reply_default(msg)
        nil

      when LibSSH::SSH_AUTH_PUBLICKEY_SUBTYPE
        username = read_string(LibSSH.ssh_message_auth_user(msg))
        client_key = LibSSH.ssh_message_auth_pubkey(msg)
        pk_state = LibSSH.ssh_message_auth_publickey_state(msg)
        Log.debug "Auth: pubkey attempt for user '#{username}' (state=#{pk_state})"

        if username && !client_key.null? && key_matches?(username, client_key)
          if pk_state == LibSSH::SSH_PUBLICKEY_STATE_NONE
            Log.debug "Auth: pubkey probe accepted for '#{username}'"
            LibSSH.ssh_message_auth_reply_pk_ok_simple(msg)
            LibSSH.ssh_message_free(msg)
            return :next
          else
            Log.info "Auth: pubkey accepted for '#{username}'"
            LibSSH.ssh_message_auth_reply_success(msg, 0)
            LibSSH.ssh_message_free(msg)
            return username
          end
        end
        Log.debug "Auth: pubkey rejected for '#{username}'"

        if attempts + 1 >= MAX_AUTH_ATTEMPTS
          LibSSH.ssh_message_reply_default(msg)
          LibSSH.ssh_message_free(msg)
          return :denied
        end

        LibSSH.ssh_message_auth_set_methods(msg, auth_methods)
        LibSSH.ssh_message_reply_default(msg)
        nil

      else
        # SSH_AUTH_METHOD_NONE or unknown — just tell client what methods to use
        LibSSH.ssh_message_auth_set_methods(msg, auth_methods)
        LibSSH.ssh_message_reply_default(msg)
        :skip
      end
    end

    private def self.verify_password(username : String, password : String) : Bool
      user = UserRepo.find_by_username(username)
      return false unless user
      return false unless user.enabled
      return false unless hash = user.password_hash
      PasswordUtils.verify_password(password, hash)
    end

    private def self.key_matches?(username : String, client_key : LibSSH::SSHKey) : Bool
      user = UserRepo.find_by_username(username)
      return false unless user
      return false unless user.enabled

      user.ssh_key_list.each do |stored_key|
        parts = stored_key.strip.split(/\s+/, 3)
        next if parts.size < 2

        key_type_name = parts[0]
        key_data = parts[1]

        key_type = LibSSH.ssh_key_type_from_name(key_type_name)
        next if key_type == 0 # SSH_KEYTYPE_UNKNOWN

        imported_key = uninitialized LibSSH::SSHKey
        rc = LibSSH.ssh_pki_import_pubkey_base64(key_data, key_type, pointerof(imported_key))
        next unless rc == LibSSH::SSH_OK

        match = LibSSH.ssh_key_cmp(client_key, imported_key, LibSSH::SSH_KEY_CMP_PUBLIC) == 0
        LibSSH.ssh_key_free(imported_key)

        return true if match
      end

      false
    end

    private def self.read_string(ptr : LibC::Char*) : String?
      return nil if ptr.null?
      String.new(ptr)
    end
  end
end
