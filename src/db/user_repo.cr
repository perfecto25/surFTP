module SurFTP
  class UserRepo
    def self.create(username : String, password_hash : String?, home_directory : String) : User
      db = Database.connection
      db.exec(
        "INSERT INTO users (username, password_hash, home_directory) VALUES (?, ?, ?)",
        username, password_hash, home_directory
      )
      find_by_username!(username)
    end

    def self.list : Array(User)
      db = Database.connection
      users = [] of User
      db.query("SELECT id, username, password_hash, home_directory, ssh_keys, enabled, created_at, updated_at FROM users ORDER BY username") do |rs|
        rs.each do
          users << read_user(rs)
        end
      end
      users
    end

    def self.find(id : Int64) : User?
      db = Database.connection
      db.query("SELECT id, username, password_hash, home_directory, ssh_keys, enabled, created_at, updated_at FROM users WHERE id = ?", id) do |rs|
        rs.each do
          return read_user(rs)
        end
      end
      nil
    end

    def self.find_by_username(username : String) : User?
      db = Database.connection
      db.query("SELECT id, username, password_hash, home_directory, ssh_keys, enabled, created_at, updated_at FROM users WHERE username = ?", username) do |rs|
        rs.each do
          return read_user(rs)
        end
      end
      nil
    end

    def self.find_by_username!(username : String) : User
      find_by_username(username) || raise "User '#{username}' not found"
    end

    def self.update_password(username : String, password_hash : String)
      db = Database.connection
      db.exec("UPDATE users SET password_hash = ?, updated_at = CURRENT_TIMESTAMP WHERE username = ?", password_hash, username)
    end

    def self.update_enabled(username : String, enabled : Bool)
      db = Database.connection
      val = enabled ? 1 : 0
      db.exec("UPDATE users SET enabled = ?, updated_at = CURRENT_TIMESTAMP WHERE username = ?", val, username)
    end

    def self.update_ssh_keys(username : String, keys : String?)
      db = Database.connection
      db.exec("UPDATE users SET ssh_keys = ?, updated_at = CURRENT_TIMESTAMP WHERE username = ?", keys, username)
    end

    def self.delete(username : String)
      db = Database.connection
      db.exec("DELETE FROM users WHERE username = ?", username)
    end

    def self.get_config(key : String) : String?
      db = Database.connection
      db.query("SELECT value FROM config WHERE key = ?", key) do |rs|
        rs.each do
          return rs.read(String)
        end
      end
      nil
    end

    def self.add_session(username : String, remote : String) : Int64
      db = Database.connection
      result = db.exec("INSERT INTO active_sessions (username, remote) VALUES (?, ?)", username, remote)
      result.last_insert_id
    end

    def self.remove_session(id : Int64)
      Database.connection.exec("DELETE FROM active_sessions WHERE id = ?", id)
    end

    def self.clear_sessions
      Database.connection.exec("DELETE FROM active_sessions")
    end

    record ActiveSession, id : Int64, username : String, remote : String, connected_at : String

    def self.list_sessions : Array(ActiveSession)
      sessions = [] of ActiveSession
      Database.connection.query("SELECT id, username, remote, connected_at FROM active_sessions ORDER BY connected_at") do |rs|
        rs.each do
          sessions << ActiveSession.new(
            id: rs.read(Int64),
            username: rs.read(String),
            remote: rs.read(String),
            connected_at: rs.read(String)
          )
        end
      end
      sessions
    end

    def self.push_kill(username : String)
      db = Database.connection
      db.exec("INSERT INTO kill_pending (username) VALUES (?)", username)
    end

    def self.pop_kills : Array(String)
      db = Database.connection
      usernames = [] of String
      db.query("SELECT username FROM kill_pending") do |rs|
        rs.each { usernames << rs.read(String) }
      end
      db.exec("DELETE FROM kill_pending") unless usernames.empty?
      usernames
    end

    def self.set_config(key : String, value : String)
      db = Database.connection
      db.exec("INSERT OR REPLACE INTO config (key, value) VALUES (?, ?)", key, value)
    end

    private def self.read_user(rs) : User
      User.new(
        id: rs.read(Int64),
        username: rs.read(String),
        password_hash: rs.read(String?),
        home_directory: rs.read(String),
        ssh_keys: rs.read(String?),
        enabled: rs.read(Int64) != 0,
        created_at: rs.read(String),
        updated_at: rs.read(String)
      )
    end
  end
end
