module SurFTP
  module TUI
    class UserFormView
      enum Field
        Username
        Password
        Home
        Submit
      end

      @field : Field = Field::Username
      @username = ""
      @password = ""
      @home = ""
      @error : String? = nil
      @editing : Bool = false

      def initialize(@editing = false, user : User? = nil)
        if u = user
          @username = u.username
          @home = u.home_directory
          @field = Field::Password # Skip username when editing
        end
      end

      def draw
        Terminal.clear
        title = @editing ? "SurFTP - Edit User" : "SurFTP - Add User"
        Components.header(title)

        row = 4
        draw_field("Username", @username, Field::Username, row)
        draw_field("Password", "*" * @password.size, Field::Password, row + 2)
        draw_field("Home Dir", @home, Field::Home, row + 4)

        # Submit button
        Terminal.move_to(row + 7, 3)
        if @field == Field::Submit
          print "#{Terminal::REVERSE}#{Terminal::BOLD} [ Save ] #{Terminal::RESET}"
        else
          print " [ Save ] "
        end

        if err = @error
          Components.message(err, row + 9, Terminal::FG_RED)
        end

        Components.footer("Tab/↑↓ Navigate fields  Type to edit  Enter Submit  Esc Cancel")

        # Show cursor on current text field
        if @field != Field::Submit
          print Terminal::SHOW_CUR
        else
          print Terminal::HIDE_CUR
        end
      end

      private def draw_field(label : String, value : String, field : Field, row : Int32)
        Terminal.move_to(row, 3)
        active = @field == field
        if active
          print "#{Terminal::FG_CYAN}#{Terminal::BOLD}#{label}:#{Terminal::RESET} "
          print "#{Terminal::REVERSE} #{value} #{Terminal::RESET}"
        else
          print "#{Terminal::DIM}#{label}:#{Terminal::RESET} #{value}"
        end
      end

      def handle_key(key : String) : Symbol
        @error = nil

        case key
        when "tab", "down"
          advance_field
          :redraw
        when "up"
          retreat_field
          :redraw
        when "enter"
          if @field == Field::Submit
            return try_submit
          else
            advance_field
            :redraw
          end
        when "escape"
          :cancel
        when "backspace"
          handle_backspace
          :redraw
        else
          if key.size == 1 && @field != Field::Submit
            handle_char(key)
            :redraw
          else
            :none
          end
        end
      end

      private def advance_field
        @field = case @field
                 when Field::Username then Field::Password
                 when Field::Password then Field::Home
                 when Field::Home     then Field::Submit
                 when Field::Submit   then Field::Username
                 else                      Field::Username
                 end
      end

      private def retreat_field
        @field = case @field
                 when Field::Username then Field::Submit
                 when Field::Password then Field::Username
                 when Field::Home     then Field::Password
                 when Field::Submit   then Field::Home
                 else                      Field::Username
                 end
      end

      private def handle_char(ch : String)
        case @field
        when Field::Username then @username += ch
        when Field::Password then @password += ch
        when Field::Home     then @home += ch
        end
      end

      private def handle_backspace
        case @field
        when Field::Username
          @username = @username[0...-1] if @username.size > 0
        when Field::Password
          @password = @password[0...-1] if @password.size > 0
        when Field::Home
          @home = @home[0...-1] if @home.size > 0
        end
      end

      private def try_submit : Symbol
        if @username.blank?
          @error = "Username is required"
          return :redraw
        end

        if !@editing && @password.blank?
          @error = "Password is required for new users"
          return :redraw
        end

        home = @home.blank? ? "/srv/surftp/#{@username}" : @home
        password = @password.blank? ? nil : @password

        begin
          if @editing
            if pw = password
              hash = SurFTP::PasswordUtils.hash_password(pw)
              UserRepo.update_password(@username, hash)
              begin
                UserManager.set_password(@username, pw)
              rescue
              end
            end
          else
            hash = password ? SurFTP::PasswordUtils.hash_password(password) : nil
            UserRepo.create(@username, hash, home)
            begin
              UserManager.create_system_user(@username, home, password)
            rescue
            end
          end
          :saved
        rescue ex
          @error = ex.message || "Unknown error"
          :redraw
        end
      end
    end
  end
end
