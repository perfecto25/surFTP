require "yaml"

module SurFTP
  struct ClientConfig
    include YAML::Serializable

    getter action : String
    getter host : String
    getter port : Int32 = 22
    getter username : String
    getter password : String?
    getter auth_type : String = "password"
    getter private_key : String?
    getter remote_path : String
    getter local_path : String
  end

  module ClientConfigLoader
    CONFIG_DIR = "/etc/surftp/clients"

    def self.load(client : String, env : String) : ClientConfig
      path = File.join(CONFIG_DIR, "#{client}.yaml")
      unless File.exists?(path)
        raise "Client config not found: #{path}"
      end

      yaml = File.read(path)
      envs = Hash(String, ClientConfig).from_yaml(yaml)

      config = envs[env]?
      unless config
        available = envs.keys.join(", ")
        raise "Environment '#{env}' not found in #{path}. Available: #{available}"
      end

      config
    end
  end
end
