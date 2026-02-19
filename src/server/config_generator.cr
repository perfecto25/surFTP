module SurFTP
  class ConfigGenerator
    CONFIG_DIR  = "/etc/surftp"
    CONFIG_FILE = File.join(CONFIG_DIR, "sshd_config")
    HOST_KEY    = File.join(CONFIG_DIR, "ssh_host_ed25519_key")
    PID_FILE    = "/var/run/surftp/sshd.pid"

    def self.generate(port : Int32 = 2222) : String
      surftp_bin = Process.executable_path || "/usr/local/bin/surftp"

      <<-CONFIG
      # SurFTP sshd configuration - auto-generated
      # Do not edit manually

      Port #{port}
      ListenAddress 0.0.0.0
      PidFile #{PID_FILE}

      HostKey #{HOST_KEY}

      # Logging
      SyslogFacility AUTH
      LogLevel INFO

      # Authentication
      PermitRootLogin no
      PasswordAuthentication yes
      PubkeyAuthentication yes
      AuthorizedKeysFile none
      AuthorizedKeysCommand #{surftp_bin} auth-keys %u
      AuthorizedKeysCommandUser root

      # SFTP only
      Subsystem sftp internal-sftp

      Match Group #{UserManager::SFTP_GROUP}
        ForceCommand internal-sftp
        ChrootDirectory %h
        AllowTcpForwarding no
        X11Forwarding no
        PermitTunnel no
      CONFIG
    end

    def self.write_config(port : Int32 = 2222)
      Dir.mkdir_p(CONFIG_DIR) unless Dir.exists?(CONFIG_DIR)
      Dir.mkdir_p(File.dirname(PID_FILE)) unless Dir.exists?(File.dirname(PID_FILE))

      File.write(CONFIG_FILE, generate(port))
      File.chmod(CONFIG_FILE, 0o600)

      generate_host_key unless File.exists?(HOST_KEY)
    end

    def self.generate_host_key
      result = Process.run(
        "ssh-keygen",
        ["-t", "ed25519", "-f", HOST_KEY, "-N", ""],
        error: Process::Redirect::Close,
        output: Process::Redirect::Close
      )
      unless result.success?
        raise "Failed to generate host key"
      end
      File.chmod(HOST_KEY, 0o600)
    end
  end
end
