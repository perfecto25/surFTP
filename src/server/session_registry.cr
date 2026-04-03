module SurFTP
  class SessionRegistry
    @@sessions : Hash(String, Array(LibSSH::SSHSession)) = {} of String => Array(LibSSH::SSHSession)
    @@mutex = Mutex.new

    def self.register(username : String, session : LibSSH::SSHSession)
      @@mutex.synchronize do
        @@sessions[username] ||= [] of LibSSH::SSHSession
        @@sessions[username] << session
      end
    end

    def self.deregister(username : String, session : LibSSH::SSHSession)
      @@mutex.synchronize do
        if arr = @@sessions[username]?
          arr.delete(session)
          @@sessions.delete(username) if arr.empty?
        end
      end
    end

    # Close the fd for each active session for this user.
    # Closing the fd unblocks any blocking libssh call (sftp_get_client_message,
    # ssh_message_get, etc.) in the connection thread, which then exits cleanly.
    def self.kill(username : String) : Int32
      sessions_to_kill = @@mutex.synchronize do
        @@sessions.delete(username) || [] of LibSSH::SSHSession
      end
      sessions_to_kill.each do |session|
        fd = LibSSH.ssh_get_fd(session)
        LibC.close(fd) if fd >= 0
      end
      sessions_to_kill.size
    end

    def self.active_users : Array(String)
      @@mutex.synchronize { @@sessions.keys.dup }
    end
  end
end
