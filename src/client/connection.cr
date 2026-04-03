require "file_utils"

module SurFTP
  class SFTPClient
    getter config : ClientConfig

    def initialize(@config : ClientConfig)
    end

    def list_files
      run_sftp_batch("ls #{config.remote_path}")
    end

    def push_file(filename : String)
      local = File.join(config.local_path, filename)
      unless File.exists?(local)
        raise "Local file not found: #{local}"
      end
      run_sftp_batch("put #{local} #{config.remote_path}/#{filename}")
    end

    def pull_file(filename : String)
      Dir.mkdir_p(config.local_path) unless Dir.exists?(config.local_path)
      run_sftp_batch("get #{config.remote_path}/#{filename} #{config.local_path}/#{filename}")
    end

    private def run_sftp_batch(command : String)
      batch_file = File.tempfile("surftp_batch") do |f|
        f.print(command)
      end

      askpass_path : String? = nil

      begin
        sftp_args = build_sftp_args(batch_file.path)
        env, askpass_path = build_password_env

        stdout = IO::Memory.new
        stderr = IO::Memory.new
        status = Process.run("sftp", sftp_args, env: env, output: stdout, error: stderr)

        unless status.success?
          err = stderr.to_s.strip
          raise "SFTP command failed: #{err.empty? ? "exit code #{status.exit_code}" : err}"
        end

        output = stdout.to_s.strip
        puts output unless output.empty?
      ensure
        batch_file.delete
        File.delete(askpass_path) if askpass_path && File.exists?(askpass_path)
      end
    end

    private def build_sftp_args(batch_path : String) : Array(String)
      args = ["-o", "StrictHostKeyChecking=no", "-b", batch_path]
      args += ["-P", config.port.to_s] if config.port != 22

      if config.auth_type == "key" && (key = config.private_key)
        args += ["-i", key]
      end

      args << "#{config.username}@#{config.host}"
      args
    end

    # Returns {env_overrides_or_nil, askpass_script_path_or_nil}.
    # Uses SSH_ASKPASS to supply the password without needing sshpass installed.
    private def build_password_env : {Hash(String, String)?, String?}
      return {nil, nil} unless config.auth_type == "password"
      enc_password = config.password
      return {nil, nil} unless enc_password

      password = begin
        Encryption.decrypt_password(enc_password)
      rescue ex
        raise "Failed to decrypt password in client config: #{ex.message}\n" \
              "Run 'surftp client encrypt-password' to generate a valid encrypted password."
      end

      # Write a minimal shell script that prints the password
      tmpfile = File.tempfile("surftp_ask", ".sh") do |f|
        escaped = password.gsub("'", "'\\''")
        f.print("#!/bin/sh\nprintf '%s' '#{escaped}'\n")
      end
      File.chmod(tmpfile.path, 0o700)

      env = {
        "SSH_ASKPASS"         => tmpfile.path,
        "SSH_ASKPASS_REQUIRE" => "force", # OpenSSH 8.4+
        "DISPLAY"             => "x",     # fallback for older OpenSSH
      }
      {env, tmpfile.path}
    end
  end
end
