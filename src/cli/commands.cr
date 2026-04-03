module SurFTP
  module CLI
    module Commands
      DEFAULT_HOME_BASE = "/srv/surftp"

      def self.server_start(port : Int32, config_path : String? = nil)
        Database.ensure_directory

        config = Config.load(config_path)
        config.port = port if port != 2222 || config_path.nil?

        UserRepo.set_config("port", config.port.to_s)
        UserRepo.set_config("home_base", config.home_base)

        # Block on signal for clean shutdown
        done = Channel(Nil).new
        Signal::INT.trap { done.send(nil) }
        Signal::TERM.trap { done.send(nil) }

        spawn do
          begin
            ServerManager.start(config)
          rescue ex
            STDERR.puts "Server error: #{ex.message}"
            done.send(nil)
          end
        end

        done.receive
        ServerManager.stop
      end

      def self.server_stop
        ServerManager.stop
      end

      def self.server_status
        ServerManager.status
      end

      def self.user_add(username : String, password : String?, home : String?)
        Database.ensure_directory
        home_dir = home || File.join(DEFAULT_HOME_BASE, username)

        # Check if user already exists in DB
        if UserRepo.find_by_username(username)
          STDERR.puts "User '#{username}' already exists"
          exit 1
        end

        # Create home directory
        files_dir = File.join(home_dir, "files")
        begin
          Dir.mkdir_p(files_dir)
        rescue ex
          STDERR.puts "Failed to create directory: #{ex.message}"
          exit 1
        end

        password_hash = password ? SurFTP::PasswordUtils.hash_password(password) : nil
        user = UserRepo.create(username, password_hash, home_dir)

        puts "User '#{username}' created"
        puts "  Home: #{home_dir}"
        puts "  Password: #{password ? "set" : "not set"}"
      end

      def self.user_remove(username : String)
        Database.ensure_directory
        user = UserRepo.find_by_username(username)
        unless user
          STDERR.puts "User '#{username}' not found"
          exit 1
        end

        UserRepo.delete(username)
        puts "User '#{username}' removed"
      end

      def self.user_list
        Database.ensure_directory
        users = UserRepo.list
        if users.empty?
          puts "No users configured"
          return
        end

        # Print header
        printf "%-20s %-10s %-30s %-5s\n", "USERNAME", "STATUS", "HOME", "KEYS"
        puts "-" * 70

        users.each do |user|
          key_count = user.ssh_key_list.size
          printf "%-20s %-10s %-30s %-5d\n", user.username, user.status_label, user.home_directory, key_count
        end
      end

      def self.user_show(username : String)
        Database.ensure_directory
        user = UserRepo.find_by_username(username)
        unless user
          STDERR.puts "User '#{username}' not found"
          exit 1
        end

        puts "Username:  #{user.username}"
        puts "Status:    #{user.status_label}"
        puts "Home:      #{user.home_directory}"
        puts "Password:  #{user.password_hash ? "set" : "not set"}"
        puts "Created:   #{user.created_at}"
        puts "Updated:   #{user.updated_at}"

        keys = user.ssh_key_list
        if keys.empty?
          puts "SSH Keys:  none"
        else
          puts "SSH Keys:"
          keys.each_with_index do |key, i|
            # Show truncated key
            display = key.size > 60 ? "#{key[0..59]}..." : key
            puts "  [#{i}] #{display}"
          end
        end
      end

      def self.sessions_list
        Database.ensure_directory
        sessions = UserRepo.list_sessions
        if sessions.empty?
          puts "No active sessions"
          return
        end
        puts "%-4s  %-20s  %-25s  %s" % ["ID", "Username", "Remote", "Connected At"]
        puts "-" * 75
        sessions.each do |s|
          puts "%-4d  %-20s  %-25s  %s" % [s.id, s.username, s.remote, s.connected_at]
        end
      end

      def self.user_kill(username : String)
        Database.ensure_directory

        unless UserRepo.find_by_username(username)
          STDERR.puts "User '#{username}' not found"
          exit 1
        end

        pid_str = UserRepo.get_config("server_pid")
        if pid_str.nil? || pid_str.empty?
          STDERR.puts "Server does not appear to be running"
          exit 1
        end

        pid = pid_str.to_i? || begin
          STDERR.puts "Invalid server PID in database"
          exit 1
        end

        UserRepo.push_kill(username)

        begin
          Process.signal(Signal::USR1, pid)
          puts "Killed active sessions for '#{username}'"
        rescue ex
          STDERR.puts "Failed to signal server (PID #{pid}): #{ex.message}"
          STDERR.puts "Server may not be running"
          exit 1
        end
      end

      def self.user_enable(username : String)
        Database.ensure_directory
        user = UserRepo.find_by_username(username)
        unless user
          STDERR.puts "User '#{username}' not found"
          exit 1
        end
        UserRepo.update_enabled(username, true)
        puts "User '#{username}' enabled"
      end

      def self.user_disable(username : String)
        Database.ensure_directory
        user = UserRepo.find_by_username(username)
        unless user
          STDERR.puts "User '#{username}' not found"
          exit 1
        end
        UserRepo.update_enabled(username, false)
        puts "User '#{username}' disabled"
      end

      def self.user_passwd(username : String)
        Database.ensure_directory
        user = UserRepo.find_by_username(username)
        unless user
          STDERR.puts "User '#{username}' not found"
          exit 1
        end

        STDERR.print "New password: "
        password = STDIN.noecho { (STDIN.gets || "").chomp }
        STDERR.puts

        if password.empty?
          STDERR.puts "Password cannot be empty"
          exit 1
        end

        hash = SurFTP::PasswordUtils.hash_password(password)
        UserRepo.update_password(username, hash)

        puts "Password updated for '#{username}'"
      end

      def self.user_key_add(username : String, pubkey_file : String)
        Database.ensure_directory
        user = UserRepo.find_by_username(username)
        unless user
          STDERR.puts "User '#{username}' not found"
          exit 1
        end

        unless File.exists?(pubkey_file)
          STDERR.puts "File not found: #{pubkey_file}"
          exit 1
        end

        key = File.read(pubkey_file).strip
        if key.empty?
          STDERR.puts "Key file is empty"
          exit 1
        end

        existing_keys = user.ssh_key_list
        existing_keys << key
        UserRepo.update_ssh_keys(username, existing_keys.join('\n'))

        puts "SSH key added for '#{username}' (#{existing_keys.size} total)"
      end

      def self.user_key_remove(username : String, index : Int32)
        Database.ensure_directory
        user = UserRepo.find_by_username(username)
        unless user
          STDERR.puts "User '#{username}' not found"
          exit 1
        end

        keys = user.ssh_key_list
        if index < 0 || index >= keys.size
          STDERR.puts "Invalid key index: #{index} (user has #{keys.size} keys)"
          exit 1
        end

        keys.delete_at(index)
        new_keys = keys.empty? ? nil : keys.join('\n')
        UserRepo.update_ssh_keys(username, new_keys)

        puts "SSH key removed for '#{username}' (#{keys.size} remaining)"
      end
      def self.client_init_master_key
        if File.exists?(Encryption::MASTER_KEY_PATH)
          STDERR.puts "Master key already exists at #{Encryption::MASTER_KEY_PATH}"
          STDERR.puts "Delete it first if you want to regenerate (WARNING: existing encrypted passwords will become unreadable)"
          exit 1
        end

        Encryption.generate_master_key
        puts "Master key generated at #{Encryption::MASTER_KEY_PATH}"
      end

      def self.client_encrypt_password
        STDERR.print "Password: "
        password = STDIN.noecho { (STDIN.gets || "").chomp }
        STDERR.puts

        if password.empty?
          STDERR.puts "Password cannot be empty"
          exit 1
        end

        encrypted = Encryption.encrypt_password(password)
        puts encrypted
      end

      def self.connect_generate(username : String)
        dir = "/etc/surftp/clients"
        begin
          Dir.mkdir_p(dir)
        rescue ex
          STDERR.puts "Failed to create directory #{dir}: #{ex.message}"
          exit 1
        end

        path = File.join(dir, "#{username}.yaml")
        if File.exists?(path)
          STDERR.puts "Config already exists: #{path}"
          exit 1
        end

        content = <<-YAML
        prod:
          action: push
          host: your-sftp-host.example.com
          port: 2222
          username: #{username}
          auth_type: password
          password: # run 'surftp client encrypt-password' to generate
          remote_path: /files
          local_path: /tmp/#{username}

        dev:
          action: pull
          host: dev.your-sftp-host.example.com
          port: 2222
          username: #{username}
          auth_type: key
          private_key: /home/#{username}/.ssh/id_rsa
          remote_path: /files
          local_path: /tmp/#{username}
        YAML

        File.write(path, content)
        puts "Generated client config: #{path}"
      end

      def self.connect(client : String, env : String, list : Bool, file : String?)
        config = ClientConfigLoader.load(client, env)
        sftp = SFTPClient.new(config)

        if list
          sftp.list_files
        elsif f = file
          case config.action
          when "push"
            sftp.push_file(f)
          when "pull"
            sftp.pull_file(f)
          else
            STDERR.puts "Unknown action '#{config.action}' in config. Use 'push' or 'pull'."
            exit 1
          end
        else
          STDERR.puts "Specify -l to list files or -f <file> to push/pull"
          exit 1
        end
      rescue ex
        STDERR.puts "Error: #{ex.message}"
        exit 1
      end
    end
  end
end
