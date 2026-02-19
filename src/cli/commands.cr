module SurFTP
  module CLI
    module Commands
      DEFAULT_HOME_BASE = "/srv/surftp"

      def self.server_start(port : Int32)
        Database.ensure_directory
        UserRepo.set_config("port", port.to_s)
        ServerManager.start(port)
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

        # Create system user and home directory first
        begin
          UserManager.create_system_user(username, home_dir, password)
        rescue ex
          STDERR.puts "Failed to create user: #{ex.message}"
          STDERR.puts "  (You may need to run as root)"
          exit 1
        end

        # Only create DB record after system user succeeds
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

        begin
          UserManager.delete_system_user(username)
        rescue ex
          STDERR.puts "Warning: Failed to remove system user: #{ex.message}"
        end

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
        password = STDIN.noecho { STDIN.gets_to_end.chomp }
        STDERR.puts

        if password.empty?
          STDERR.puts "Password cannot be empty"
          exit 1
        end

        hash = SurFTP::PasswordUtils.hash_password(password)
        UserRepo.update_password(username, hash)

        begin
          UserManager.set_password(username, password)
        rescue ex
          STDERR.puts "Warning: Failed to set system password: #{ex.message}"
        end

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
    end
  end
end
