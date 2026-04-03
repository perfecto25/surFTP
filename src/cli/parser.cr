module SurFTP
  module CLI
    class Parser
      def self.run(args : Array(String))
        if args.empty?
          print_usage
          return
        end

        case args[0]
        when "server"
          handle_server(args[1..])
        when "user"
          handle_user(args[1..])
        when "client"
          handle_client(args[1..])
        when "connect"
          handle_connect(args[1..])
        when "sessions"
          Commands.sessions_list
        when "tui"
          TUI::App.new.run
        when "help", "--help", "-h"
          print_usage
        else
          STDERR.puts "Unknown command: #{args[0]}"
          print_usage
          exit 1
        end
      end

      private def self.handle_server(args : Array(String))
        if args.empty?
          STDERR.puts "Usage: surftp server <start|stop|status>"
          exit 1
        end

        case args[0]
        when "start"
          port = 2222
          config_path : String? = nil
          if idx = args.index("--port") || args.index("-p")
            if val = args[idx + 1]?
              port = val.to_i
            end
          end
          if idx = args.index("--config") || args.index("-c")
            config_path = args[idx + 1]?
          end
          Commands.server_start(port, config_path)
        when "stop"
          Commands.server_stop
        when "status"
          Commands.server_status
        else
          STDERR.puts "Unknown server command: #{args[0]}"
          exit 1
        end
      end

      private def self.handle_user(args : Array(String))
        if args.empty?
          STDERR.puts "Usage: surftp user <add|remove|list|show|enable|disable|passwd|key|kill>"
          exit 1
        end

        case args[0]
        when "add"
          handle_user_add(args[1..])
        when "remove"
          handle_user_remove(args[1..])
        when "list"
          Commands.user_list
        when "show"
          handle_user_show(args[1..])
        when "enable"
          handle_user_enable(args[1..])
        when "disable"
          handle_user_disable(args[1..])
        when "passwd"
          handle_user_passwd(args[1..])
        when "key"
          handle_user_key(args[1..])
        when "kill"
          handle_user_kill(args[1..])
        else
          STDERR.puts "Unknown user command: #{args[0]}"
          exit 1
        end
      end

      private def self.handle_user_add(args : Array(String))
        if args.empty?
          STDERR.puts "Usage: surftp user add <username> [--password <pass>] [--home <dir>]"
          exit 1
        end

        username = args[0]
        password : String? = nil
        home : String? = nil

        i = 1
        while i < args.size
          case args[i]
          when "--password"
            password = args[i + 1]?
            i += 2
          when "--home"
            home = args[i + 1]?
            i += 2
          else
            i += 1
          end
        end

        Commands.user_add(username, password, home)
      end

      private def self.handle_user_remove(args : Array(String))
        if args.empty?
          STDERR.puts "Usage: surftp user remove <username>"
          exit 1
        end
        Commands.user_remove(args[0])
      end

      private def self.handle_user_show(args : Array(String))
        if args.empty?
          STDERR.puts "Usage: surftp user show <username>"
          exit 1
        end
        Commands.user_show(args[0])
      end

      private def self.handle_user_enable(args : Array(String))
        if args.empty?
          STDERR.puts "Usage: surftp user enable <username>"
          exit 1
        end
        Commands.user_enable(args[0])
      end

      private def self.handle_user_disable(args : Array(String))
        if args.empty?
          STDERR.puts "Usage: surftp user disable <username>"
          exit 1
        end
        Commands.user_disable(args[0])
      end

      private def self.handle_user_passwd(args : Array(String))
        if args.empty?
          STDERR.puts "Usage: surftp user passwd <username>"
          exit 1
        end
        Commands.user_passwd(args[0])
      end

      private def self.handle_user_kill(args : Array(String))
        if args.empty?
          STDERR.puts "Usage: surftp user kill <username>"
          exit 1
        end
        Commands.user_kill(args[0])
      end

      private def self.handle_user_key(args : Array(String))
        if args.size < 2
          STDERR.puts "Usage: surftp user key <add|remove> <username> [<pubkey_file|key_index>]"
          exit 1
        end

        case args[0]
        when "add"
          if args.size < 3
            STDERR.puts "Usage: surftp user key add <username> <pubkey_file>"
            exit 1
          end
          Commands.user_key_add(args[1], args[2])
        when "remove"
          if args.size < 3
            STDERR.puts "Usage: surftp user key remove <username> <key_index>"
            exit 1
          end
          Commands.user_key_remove(args[1], args[2].to_i)
        else
          STDERR.puts "Unknown key command: #{args[0]}"
          exit 1
        end
      end

      private def self.handle_client(args : Array(String))
        if args.empty?
          STDERR.puts "Usage: surftp client <init-master-key|encrypt-password>"
          exit 1
        end

        case args[0]
        when "init-master-key"
          Commands.client_init_master_key
        when "encrypt-password"
          Commands.client_encrypt_password
        else
          STDERR.puts "Unknown client command: #{args[0]}"
          exit 1
        end
      end

      private def self.handle_connect(args : Array(String))
        if args[0]? == "--generate"
          username = args[1]?
          unless username
            STDERR.puts "Usage: surftp connect --generate <username>"
            exit 1
          end
          Commands.connect_generate(username)
          return
        end

        client : String? = nil
        env : String? = nil
        list = false
        file : String? = nil

        i = 0
        while i < args.size
          case args[i]
          when "-c"
            client = args[i + 1]?
            i += 2
          when "-e"
            env = args[i + 1]?
            i += 2
          when "-l"
            list = true
            i += 1
          when "-f"
            file = args[i + 1]?
            i += 2
          else
            i += 1
          end
        end

        unless client && env
          STDERR.puts "Usage: surftp connect -c <client> -e <env> [-l | -f <file>]"
          exit 1
        end

        Commands.connect(client, env, list, file)
      end

      private def self.print_usage
        puts <<-USAGE
        SurFTP - SFTP Server Manager v#{SurFTP::VERSION}
        https://github.com/perfecto25/surftp

        Usage: surftp <command> [options]

        Commands:
          server start [--port 2222] [--config /path/to/surftp.yaml]
                                       Start the SFTP server
          server stop                  Stop the SFTP server
          server status                Show server status

          user add <name> [--password <pass>] [--home <dir>]
          user remove <name>           Remove a user
          user list                    List all users
          user show <name>             Show user details
          user enable <name>           Enable a user
          user disable <name>          Disable a user
          user passwd <name>           Change user password
          user key add <name> <file>   Add SSH key from file
          user key remove <name> <idx> Remove SSH key by index
          user kill <name>             Kill a user's active FTP session
          sessions                     Show active FTP sessions

          client init-master-key       Generate encryption master key
          client encrypt-password      Encrypt a password for client config

          connect --generate <username>             Generate sample client YAML in /etc/surftp/clients/
          connect -c <client> -e <env> -l          List remote files
          connect -c <client> -e <env> -f <file>   Push or pull a file

          tui                          Launch terminal UI
        USAGE
      end
    end
  end
end
