require "yaml"

module SurFTP
  class Config
    SEARCH_PATHS = [
      "/etc/surftp/surftp.yaml",
      "/etc/surftp/surftp.yml",
    ]

    property log_level : String = "info"
    property log_file : String = "stdout"
    property audit_log : String? = nil
    property bind_address : String = "0.0.0.0"
    property port : Int32 = 2222
    property host_key : String = "/etc/surftp/ssh_host_ed25519_key"
    property home_base : String = "/srv/surftp"

    def initialize
    end

    def self.load(path : String? = nil) : Config
      config = Config.new

      file = if path && File.exists?(path)
               path
             else
               SEARCH_PATHS.find { |p| File.exists?(p) }
             end

      if file
        begin
          yaml = YAML.parse(File.read(file))

          if log = yaml["log"]?
            if level = log["level"]?
              config.log_level = level.as_s
            end
            if output = log["file"]?
              config.log_file = output.as_s
            end
            if audit = log["audit"]?
              config.audit_log = audit.as_s
            end
          end

          if server = yaml["server"]?
            if addr = server["bind_address"]?
              config.bind_address = addr.as_s
            end
            if p = server["port"]?
              config.port = p.as_i
            end
            if key = server["host_key"]?
              config.host_key = key.as_s
            end
          end

          if users = yaml["users"]?
            if base = users["home_base"]?
              config.home_base = base.as_s
            end
          end
        rescue ex
          STDERR.puts "Warning: Failed to parse config #{file}: #{ex.message}"
        end
      end

      config
    end
  end
end
