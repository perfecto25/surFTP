module SurFTP
  module Log
    enum Level
      Debug
      Info
      Warn
      Error
    end

    @@level : Level = Level::Info
    @@output : IO = STDERR
    @@mutex = Mutex.new

    def self.setup(config : Config)
      @@level = parse_level(config.log_level)

      case config.log_file
      when "stdout"
        @@output = STDOUT
      when "stderr"
        @@output = STDERR
      else
        begin
          dir = File.dirname(config.log_file)
          Dir.mkdir_p(dir) unless Dir.exists?(dir)
          @@output = File.open(config.log_file, "a")
        rescue ex
          STDERR.puts "Warning: Cannot open log file #{config.log_file}: #{ex.message}, falling back to stderr"
          @@output = STDERR
        end
      end
    end

    def self.debug(msg : String)
      write(Level::Debug, msg)
    end

    def self.info(msg : String)
      write(Level::Info, msg)
    end

    def self.warn(msg : String)
      write(Level::Warn, msg)
    end

    def self.error(msg : String)
      write(Level::Error, msg)
    end

    private def self.write(level : Level, msg : String)
      return if level < @@level

      timestamp = Time.utc.to_s("%Y-%m-%d %H:%M:%S")
      label = level.to_s.upcase.ljust(5)
      line = "#{timestamp} #{label} #{msg}\n"

      @@mutex.synchronize do
        @@output.print(line)
        @@output.flush
      end
    end

    private def self.parse_level(str : String) : Level
      case str.downcase
      when "debug" then Level::Debug
      when "info"  then Level::Info
      when "warn"  then Level::Warn
      when "error" then Level::Error
      else              Level::Info
      end
    end
  end
end
