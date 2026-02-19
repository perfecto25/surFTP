module SurFTP
  module TUI
    class MainMenuView
      ITEMS = ["Users", "Server", "Quit"]

      getter selected = 0

      def draw
        Terminal.clear
        Components.header("SurFTP - SFTP Server Manager")
        Components.menu(ITEMS, @selected, start_row: 4)
        Components.footer("↑↓ Navigate  Enter Select  q Quit")
      end

      def handle_key(key : String) : Symbol
        case key
        when "up"
          @selected = (@selected - 1).clamp(0, ITEMS.size - 1)
          :redraw
        when "down"
          @selected = (@selected + 1).clamp(0, ITEMS.size - 1)
          :redraw
        when "enter"
          case @selected
          when 0 then :users
          when 1 then :server
          when 2 then :quit
          else        :none
          end
        when "q", "ctrl-q", "ctrl-c"
          :quit
        else
          :none
        end
      end
    end
  end
end
