module SurFTP
  class ServerManager
    @@server : SSHServer? = nil

    def self.start(config : Config)
      if running?
        STDERR.puts "Server is already running"
        return
      end

      Log.setup(config)
      AuditLog.configure(config.audit_log)
      Log.info "Starting SurFTP server"

      UserRepo.set_config("server_pid", Process.pid.to_s)
      UserRepo.clear_sessions

      Signal::USR1.trap do
        UserRepo.pop_kills.each do |username|
          count = SessionRegistry.kill(username)
          Log.info "Killed #{count} session(s) for user '#{username}'"
        end
      end

      server = SSHServer.new(config)
      @@server = server
      server.start
    end

    def self.stop
      unless running?
        STDERR.puts "Server is not running"
        return
      end

      if server = @@server
        server.stop
        Log.info "Server stopped"
        puts "Server stopped"
      end
      @@server = nil
      UserRepo.set_config("server_pid", "")
    end

    def self.status
      if running?
        puts "SFTP server is running"
      else
        puts "SFTP server is not running"
      end
    end

    def self.running? : Bool
      if server = @@server
        return true if server.running?
      end
      port_in_use?
    end

    private def self.port_in_use? : Bool
      port = (UserRepo.get_config("port") || "2222").to_i
      socket = TCPSocket.new("127.0.0.1", port, connect_timeout: 0.5.seconds)
      socket.close
      true
    rescue
      false
    end
  end
end
