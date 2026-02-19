module SurFTP
  class ServerManager
    PID_FILE = ConfigGenerator::PID_FILE

    def self.start(port : Int32 = 2222)
      if running?
        STDERR.puts "Server is already running (PID: #{read_pid})"
        return
      end

      ConfigGenerator.write_config(port)

      # Validate config
      stderr = IO::Memory.new
      result = Process.run(
        "/usr/sbin/sshd",
        ["-t", "-f", ConfigGenerator::CONFIG_FILE],
        error: stderr,
        output: Process::Redirect::Close
      )
      unless result.success?
        raise "sshd config validation failed: #{stderr}"
      end

      # Start sshd
      stderr = IO::Memory.new
      result = Process.run(
        "/usr/sbin/sshd",
        ["-f", ConfigGenerator::CONFIG_FILE],
        error: stderr,
        output: Process::Redirect::Close
      )
      unless result.success?
        raise "Failed to start sshd: #{stderr}"
      end

      puts "SFTP server started on port #{port}"
    end

    def self.stop
      unless running?
        STDERR.puts "Server is not running"
        return
      end

      pid = read_pid
      if pid
        Process.signal(Signal::TERM, pid)
        puts "Server stopped (PID: #{pid})"
        File.delete(PID_FILE) if File.exists?(PID_FILE)
      end
    end

    def self.status
      if running?
        pid = read_pid
        port = UserRepo.get_config("port") || "2222"
        puts "SFTP server is running"
        puts "  PID:  #{pid}"
        puts "  Port: #{port}"
      else
        puts "SFTP server is not running"
      end
    end

    def self.running? : Bool
      pid = read_pid
      return false unless pid
      File.exists?("/proc/#{pid}")
    end

    def self.read_pid : Int64?
      return nil unless File.exists?(PID_FILE)
      content = File.read(PID_FILE).strip
      return nil if content.empty?
      content.to_i64?
    end
  end
end
