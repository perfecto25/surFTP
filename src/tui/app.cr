module SurFTP
  module TUI
    class App
      enum Screen
        MainMenu
        UserList
        UserForm
        ServerStatus
      end

      @screen : Screen = Screen::MainMenu
      @main_menu = MainMenuView.new
      @user_list : UserListView? = nil
      @user_form : UserFormView? = nil
      @server_status : ServerStatusView? = nil
      @confirming_delete = false

      def run
        Database.ensure_directory

        Terminal.enable_raw_mode
        STDOUT.flush

        begin
          draw
          loop do
            STDOUT.flush
            key = Terminal.read_key
            next if key.empty?

            result = handle_input(key)
            break if result == :quit

            draw
          end
        ensure
          Terminal.disable_raw_mode
          Terminal.clear
          STDOUT.flush
        end
      end

      private def draw
        case @screen
        when Screen::MainMenu
          @main_menu.draw
        when Screen::UserList
          user_list.draw
          if @confirming_delete
            rows, _ = Terminal.size
            Components.confirm("Delete user '#{user_list.current_user.try(&.username)}'?", rows - 3)
          end
        when Screen::UserForm
          @user_form.try &.draw
        when Screen::ServerStatus
          server_status.draw
        end
        STDOUT.flush
      end

      private def handle_input(key : String) : Symbol
        if @confirming_delete
          return handle_delete_confirm(key)
        end

        case @screen
        when Screen::MainMenu
          result = @main_menu.handle_key(key)
          case result
          when :users
            @screen = Screen::UserList
            @user_list = UserListView.new
          when :server
            @screen = Screen::ServerStatus
            @server_status = ServerStatusView.new
          when :quit
            return :quit
          end
        when Screen::UserList
          result = user_list.handle_key(key)
          case result
          when :back
            @screen = Screen::MainMenu
          when :add_user
            @user_form = UserFormView.new
            @screen = Screen::UserForm
          when :delete_user
            @confirming_delete = true
          when User
            # View/edit user
            @user_form = UserFormView.new(editing: true, user: result.as(User))
            @screen = Screen::UserForm
          end
        when Screen::UserForm
          if form = @user_form
            result = form.handle_key(key)
            case result
            when :saved, :cancel
              @screen = Screen::UserList
              @user_list = UserListView.new
              @user_form = nil
            end
          end
        when Screen::ServerStatus
          result = server_status.handle_key(key)
          case result
          when :back
            @screen = Screen::MainMenu
          end
        end

        :continue
      end

      private def handle_delete_confirm(key : String) : Symbol
        @confirming_delete = false
        if key == "y"
          if user = user_list.current_user
            begin
              UserRepo.delete(user.username)
              UserManager.delete_system_user(user.username)
            rescue
            end
            @user_list = UserListView.new
          end
        end
        :continue
      end

      private def user_list : UserListView
        @user_list ||= UserListView.new
      end

      private def server_status : ServerStatusView
        @server_status ||= ServerStatusView.new
      end
    end
  end
end
