require "db"
require "sqlite3"

module SurFTP
  class Database
    DB_PATH = "/var/lib/surftp/surftp.db"

    @@db : DB::Database? = nil

    def self.connection : DB::Database
      @@db ||= DB.open("sqlite3://#{DB_PATH}").tap do |db|
        db.exec "PRAGMA journal_mode=WAL"
        db.exec "PRAGMA foreign_keys=ON"
        migrate(db)
      end
    end

    def self.close
      @@db.try &.close
      @@db = nil
    end

    def self.ensure_directory
      dir = File.dirname(DB_PATH)
      Dir.mkdir_p(dir) unless Dir.exists?(dir)
    end

    private def self.migrate(db : DB::Database)
      db.exec <<-SQL
        CREATE TABLE IF NOT EXISTS users (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          username TEXT UNIQUE NOT NULL,
          password_hash TEXT,
          home_directory TEXT NOT NULL,
          ssh_keys TEXT,
          enabled INTEGER DEFAULT 1,
          created_at TEXT DEFAULT CURRENT_TIMESTAMP,
          updated_at TEXT DEFAULT CURRENT_TIMESTAMP
        )
      SQL

      db.exec <<-SQL
        CREATE TABLE IF NOT EXISTS config (
          key TEXT PRIMARY KEY,
          value TEXT NOT NULL
        )
      SQL
    end
  end
end
