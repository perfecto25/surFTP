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
        when "tui"
          TUI::App.new.run
        when "auth-keys"
          if args.size < 2
            STDERR.puts "Usage: surftp auth-keys <username>"
            exit 1
          end
          AuthHandler.handle(args[1])
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
          if idx = args.index("--port")
            if val = args[idx + 1]?
              port = val.to_i
            end
          end
          Commands.server_start(port)
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
          STDERR.puts "Usage: surftp user <add|remove|list|show|enable|disable|passwd|key>"
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

      private def self.print_usage
        puts <<-USAGE
        SurFTP - SFTP Server Manager v#{SurFTP::VERSION}
        https://github.com/perfecto25/surftp

        Usage: surftp <command> [options]

        Commands:
          server start [--port 2222]   Start the SFTP server
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

          tui                          Launch terminal UI

          auth-keys <name>             (internal) Print SSH keys for user
        USAGE
      end
    end
  end
end
