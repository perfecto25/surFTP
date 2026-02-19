module SurFTP
  module TUI
    class ServerStatusView
      @message : String? = nil

      def draw
        Terminal.clear
        Components.header("SurFTP - Server Status")

        running = ServerManager.running?
        pid = ServerManager.read_pid
        port = UserRepo.get_config("port") || "2222"

        row = 4
        Terminal.move_to(row, 3)
        print "#{Terminal::BOLD}Status:#{Terminal::RESET} "
        if running
          print "#{Terminal::FG_GREEN}Running#{Terminal::RESET}"
        else
          print "#{Terminal::FG_RED}Stopped#{Terminal::RESET}"
        end

        Terminal.move_to(row + 1, 3)
        print "#{Terminal::BOLD}Port:#{Terminal::RESET}   #{port}"

        if running && pid
          Terminal.move_to(row + 2, 3)
          print "#{Terminal::BOLD}PID:#{Terminal::RESET}    #{pid}"
        end

        user_count = UserRepo.list.size
        Terminal.move_to(row + 4, 3)
        print "#{Terminal::BOLD}Users:#{Terminal::RESET}  #{user_count} configured"

        # Actions
        Terminal.move_to(row + 6, 3)
        print Terminal::DIM
        if running
          print "Press 's' to stop the server"
        else
          print "Press 's' to start the server"
        end
        print Terminal::RESET

        if msg = @message
          Components.message(msg, row + 8, Terminal::FG_GREEN)
        end

        Components.footer("s Start/Stop  Esc Back")
      end

      def handle_key(key : String) : Symbol
        @message = nil

        case key
        when "s"
          begin
            if ServerManager.running?
              ServerManager.stop
              @message = "Server stopped"
            else
              port = (UserRepo.get_config("port") || "2222").to_i
              ServerManager.start(port)
              @message = "Server started on port #{port}"
            end
          rescue ex
            @message = "Error: #{ex.message}"
          end
          :redraw
        when "escape", "q"
          :back
        else
          :none
        end
      end
    end
  end
end
