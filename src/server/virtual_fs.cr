module SurFTP
  class VirtualFS
    getter root : String

    def initialize(@username : String, home_directory : String)
      @root = File.join(home_directory, "files")
    end

    def resolve(sftp_path : String) : String?
      # Normalize: treat empty or relative paths as relative to root
      path = sftp_path.starts_with?("/") ? sftp_path : "/#{sftp_path}"
      full = File.expand_path(File.join(@root, path))

      # Ensure resolved path is within root (prevent traversal)
      return nil unless full.starts_with?(@root)
      full
    end

    def virtual_path(real_path : String) : String
      rel = real_path.sub(@root, "")
      rel = "/" if rel.empty?
      rel
    end

    def ensure_root
      Dir.mkdir_p(@root) unless Dir.exists?(@root)
    end
  end
end
