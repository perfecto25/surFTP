module SurFTP
  module AuditLog
    @@path : String? = nil
    @@mutex = Mutex.new

    def self.configure(path : String?)
      return unless path
      dir = File.dirname(path)
      Dir.mkdir_p(dir) unless Dir.exists?(dir)
      @@path = path
    rescue ex
      STDERR.puts "Warning: Cannot create audit log directory for #{path}: #{ex.message}"
    end

    def self.log(username : String, remote : String, action : String, detail : String = "")
      return unless path = @@path
      timestamp = Time.local.to_s("%Y-%m-%d %H:%M:%S")
      entry = detail.empty? ? action : "#{action} #{detail}"
      line = "#{timestamp} [#{username}@#{remote}] #{entry}\n"
      @@mutex.synchronize do
        File.open(path, "a") { |f| f.print(line) }
      end
    rescue ex
      STDERR.puts "Warning: Audit log write failed: #{ex.message}"
      @@path = nil  # stop retrying after first failure
    end
  end
end
