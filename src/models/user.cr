module SurFTP
  struct User
    property id : Int64
    property username : String
    property password_hash : String?
    property home_directory : String
    property ssh_keys : String?
    property enabled : Bool
    property created_at : String
    property updated_at : String

    def initialize(@id, @username, @password_hash, @home_directory, @ssh_keys, @enabled, @created_at, @updated_at)
    end

    def ssh_key_list : Array(String)
      if keys = @ssh_keys
        keys.split('\n').reject(&.blank?)
      else
        [] of String
      end
    end

    def status_label : String
      @enabled ? "enabled" : "disabled"
    end
  end
end
