require "crypto/bcrypt/password"

module SurFTP
  module PasswordUtils
    def self.hash_password(password : String) : String
      ::Crypto::Bcrypt::Password.create(password, cost: 10).to_s
    end

    def self.verify_password(password : String, hash : String) : Bool
      bcrypt = ::Crypto::Bcrypt::Password.new(hash)
      bcrypt.verify(password)
    end
  end
end
