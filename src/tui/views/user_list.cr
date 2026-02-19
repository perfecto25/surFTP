module SurFTP
  module TUI
    class UserListView
      getter selected = 0
      @users : Array(User) = [] of User
      @message : String? = nil

      def initialize
        refresh_users
      end

      def refresh_users
        @users = UserRepo.list
        @selected = @selected.clamp(0, Math.max(@users.size - 1, 0))
      end

      def draw
        Terminal.clear
        Components.header("SurFTP - Users")

        if @users.empty?
          Components.message("No users configured. Press 'a' to add a user.", 4)
        else
          headers = ["USERNAME", "STATUS", "HOME", "KEYS"]
          rows = @users.map do |u|
            [u.username, u.status_label, u.home_directory, u.ssh_key_list.size.to_s]
          end
          Components.table(headers, rows, @selected, start_row: 3)
        end

        if msg = @message
          rows, _ = Terminal.size
          Components.message(msg, rows - 2, Terminal::FG_GREEN)
        end

        Components.footer("↑↓ Navigate  Enter View  a Add  d Delete  e Enable/Disable  Esc Back")
      end

      def handle_key(key : String) : Symbol | User?
        @message = nil

        case key
        when "up"
          @selected = (@selected - 1).clamp(0, Math.max(@users.size - 1, 0))
          :redraw
        when "down"
          @selected = (@selected + 1).clamp(0, Math.max(@users.size - 1, 0))
          :redraw
        when "enter"
          if @users.empty?
            :none
          else
            @users[@selected]
          end
        when "a"
          :add_user
        when "d"
          if !@users.empty?
            :delete_user
          else
            :none
          end
        when "e"
          if !@users.empty?
            user = @users[@selected]
            UserRepo.update_enabled(user.username, !user.enabled)
            @message = "#{user.username} #{user.enabled ? "disabled" : "enabled"}"
            refresh_users
            :redraw
          else
            :none
          end
        when "escape"
          :back
        when "q"
          :back
        else
          :none
        end
      end

      def current_user : User?
        return nil if @users.empty?
        @users[@selected]?
      end
    end
  end
end
