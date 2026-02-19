module SurFTP
  module UserManager
    SFTP_GROUP = "surftp"

    def self.create_system_user(username : String, home_directory : String, password : String?)
      ensure_group_exists

      # Create home directory structure for chroot
      # Chroot dir must be owned by root, user gets a subdir inside
      Dir.mkdir_p(home_directory) unless Dir.exists?(home_directory)
      upload_dir = File.join(home_directory, "files")
      Dir.mkdir_p(upload_dir) unless Dir.exists?(upload_dir)

      # Create system user with nologin shell
      stderr = IO::Memory.new
      result = Process.run("useradd", [
        "--system",
        "--home-dir", home_directory,
        "--shell", "/usr/sbin/nologin",
        "--gid", SFTP_GROUP,
        "--no-create-home",
        username,
      ], error: stderr, output: Process::Redirect::Close)

      unless result.success?
        err = stderr.to_s
        # Ignore if user already exists
        unless err.includes?("already exists")
          raise "Failed to create system user '#{username}': #{err}"
        end
      end

      # Set ownership: chroot dir owned by root, upload dir owned by user
      Process.run("chown", ["root:#{SFTP_GROUP}", home_directory])
      Process.run("chmod", ["755", home_directory])
      Process.run("chown", ["#{username}:#{SFTP_GROUP}", upload_dir])
      Process.run("chmod", ["755", upload_dir])

      # Set password if provided
      if pw = password
        set_password(username, pw)
      end
    end

    def self.delete_system_user(username : String)
      Process.run("userdel", [username], error: Process::Redirect::Close, output: Process::Redirect::Close)
    end

    def self.set_password(username : String, password : String)
      process = Process.new("chpasswd", input: Process::Redirect::Pipe, output: Process::Redirect::Close, error: Process::Redirect::Close)
      process.input.print("#{username}:#{password}")
      process.input.close
      status = process.wait
      unless status.success?
        raise "Failed to set password for '#{username}'"
      end
    end

    def self.user_exists?(username : String) : Bool
      result = Process.run("id", [username], error: Process::Redirect::Close, output: Process::Redirect::Close)
      result.success?
    end

    private def self.ensure_group_exists
      result = Process.run("getent", ["group", SFTP_GROUP], error: Process::Redirect::Close, output: Process::Redirect::Close)
      unless result.success?
        Process.run("groupadd", [SFTP_GROUP], error: Process::Redirect::Close, output: Process::Redirect::Close)
      end
    end
  end
end
