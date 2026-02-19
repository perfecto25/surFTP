module SurFTP
  module AuthHandler
    def self.handle(username : String)
      user = UserRepo.find_by_username(username)
      if user && user.enabled
        user.ssh_key_list.each do |key|
          puts key
        end
      end
    end
  end
end
