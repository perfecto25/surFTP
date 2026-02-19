module SurFTP
  module TUI
    module Terminal
      # ANSI escape sequences
      ESC        = "\e["
      CLEAR      = "#{ESC}2J"
      HOME       = "#{ESC}H"
      HIDE_CUR   = "#{ESC}?25l"
      SHOW_CUR   = "#{ESC}?25h"
      BOLD       = "#{ESC}1m"
      DIM        = "#{ESC}2m"
      RESET      = "#{ESC}0m"
      REVERSE    = "#{ESC}7m"
      FG_GREEN   = "#{ESC}32m"
      FG_RED     = "#{ESC}31m"
      FG_YELLOW  = "#{ESC}33m"
      FG_CYAN    = "#{ESC}36m"
      FG_WHITE   = "#{ESC}37m"
      FG_GRAY    = "#{ESC}90m"

      @@raw_mode = false
      @@original_termios : LibC::Termios? = nil

      def self.enable_raw_mode
        return if @@raw_mode
        termios = uninitialized LibC::Termios
        LibC.tcgetattr(STDIN.fd, pointerof(termios))
        @@original_termios = termios
        termios.c_lflag &= ~(LibC::ECHO | LibC::ICANON | LibC::ISIG)
        termios.c_cc[6] = 1  # VMIN
        termios.c_cc[5] = 0  # VTIME
        LibC.tcsetattr(STDIN.fd, LibC::TCSAFLUSH, pointerof(termios))
        @@raw_mode = true
        print HIDE_CUR
      end

      def self.disable_raw_mode
        return unless @@raw_mode
        if orig = @@original_termios
          copy = orig
          LibC.tcsetattr(STDIN.fd, LibC::TCSAFLUSH, pointerof(copy))
        end
        @@raw_mode = false
        print SHOW_CUR
      end

      def self.clear
        print CLEAR
        print HOME
      end

      def self.move_to(row : Int32, col : Int32)
        print "#{ESC}#{row};#{col}H"
      end

      def self.size : {Int32, Int32}
        # Try to get terminal size
        ws = uninitialized LibC::Winsize
        if LibC.ioctl(STDOUT.fd, LibC::TIOCGWINSZ, pointerof(ws)) == 0
          {ws.ws_row.to_i32, ws.ws_col.to_i32}
        else
          {24, 80}
        end
      end

      def self.read_key : String
        buf = Bytes.new(6)
        bytes_read = STDIN.read(buf)
        return "" if bytes_read == 0

        if buf[0] == 27 && bytes_read > 1 # Escape sequence
          if buf[1] == 91 # CSI
            case buf[2]
            when 65 then return "up"
            when 66 then return "down"
            when 67 then return "right"
            when 68 then return "left"
            when 51      # Delete key (ESC[3~)
              return "delete" if bytes_read > 3 && buf[3] == 126
            end
          end
          return "escape"
        end

        case buf[0]
        when 13, 10 then "enter"
        when 127    then "backspace"
        when 9      then "tab"
        when 3      then "ctrl-c"
        when 17     then "ctrl-q"
        else
          String.new(buf[0, bytes_read])
        end
      end
    end

    module Components
      def self.header(title : String)
        rows, cols = Terminal.size
        Terminal.move_to(1, 1)
        print Terminal::BOLD
        print Terminal::REVERSE
        print " #{title}".ljust(cols)
        print Terminal::RESET
      end

      def self.footer(text : String)
        rows, cols = Terminal.size
        Terminal.move_to(rows, 1)
        print Terminal::DIM
        print text.ljust(cols)
        print Terminal::RESET
      end

      def self.menu(items : Array(String), selected : Int32, start_row : Int32 = 3) : Nil
        items.each_with_index do |item, i|
          Terminal.move_to(start_row + i, 3)
          if i == selected
            print Terminal::REVERSE
            print Terminal::BOLD
            print " > #{item} "
            print Terminal::RESET
          else
            print "   #{item} "
          end
        end
      end

      def self.table(headers : Array(String), rows : Array(Array(String)), selected : Int32 = -1, start_row : Int32 = 3)
        _, cols = Terminal.size
        col_widths = headers.map(&.size)
        rows.each do |row|
          row.each_with_index do |cell, i|
            if i < col_widths.size && cell.size > col_widths[i]
              col_widths[i] = cell.size
            end
          end
        end

        # Cap widths
        col_widths = col_widths.map { |w| Math.min(w + 2, 40) }

        # Header
        Terminal.move_to(start_row, 2)
        print Terminal::BOLD
        headers.each_with_index do |h, i|
          printf "%-#{col_widths[i]}s", h
        end
        print Terminal::RESET

        # Separator
        Terminal.move_to(start_row + 1, 2)
        print Terminal::DIM
        print "-" * col_widths.sum
        print Terminal::RESET

        # Rows
        rows.each_with_index do |row, ri|
          Terminal.move_to(start_row + 2 + ri, 2)
          if ri == selected
            print Terminal::REVERSE
          end
          row.each_with_index do |cell, ci|
            if ci < col_widths.size
              printf "%-#{col_widths[ci]}s", cell[0...col_widths[ci]]
            end
          end
          if ri == selected
            print Terminal::RESET
          end
        end
      end

      def self.text_input(prompt : String, row : Int32, value : String = "") : Nil
        Terminal.move_to(row, 3)
        print "#{Terminal::BOLD}#{prompt}:#{Terminal::RESET} #{value}"
        print Terminal::SHOW_CUR
      end

      def self.message(text : String, row : Int32, color : String = Terminal::FG_WHITE)
        Terminal.move_to(row, 3)
        print "#{color}#{text}#{Terminal::RESET}"
      end

      def self.confirm(question : String, row : Int32) : Nil
        Terminal.move_to(row, 3)
        print "#{Terminal::FG_YELLOW}#{question} (y/n)#{Terminal::RESET}"
      end
    end
  end
end

lib LibC
  struct Winsize
    ws_row : UInt16
    ws_col : UInt16
    ws_xpixel : UInt16
    ws_ypixel : UInt16
  end

  TIOCGWINSZ = 0x5413

  fun ioctl(fd : Int32, request : UInt64, ...) : Int32
end
