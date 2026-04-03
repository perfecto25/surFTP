require "openssl/cipher"
require "openssl/hmac"
require "random/secure"
require "base64"

module SurFTP
  module Encryption
    MASTER_KEY_PATH = "/etc/surftp/master.key"
    KEY_SIZE        = 32 # AES-256
    IV_SIZE         = 16 # CBC block size

    def self.generate_master_key
      dir = File.dirname(MASTER_KEY_PATH)
      Dir.mkdir_p(dir) unless Dir.exists?(dir)

      key = Random::Secure.random_bytes(KEY_SIZE)
      File.write(MASTER_KEY_PATH, key)
      File.chmod(MASTER_KEY_PATH, 0o600)
    end

    def self.load_master_key : Bytes
      unless File.exists?(MASTER_KEY_PATH)
        raise "Master key not found at #{MASTER_KEY_PATH}. Run: surftp client init-master-key"
      end
      File.read(MASTER_KEY_PATH).to_slice
    end

    # Derive separate encryption and HMAC keys from the master key
    private def self.derive_keys(master : Bytes) : {Bytes, Bytes}
      enc_key = OpenSSL::HMAC.digest(:sha256, master, "surftp-enc")
      mac_key = OpenSSL::HMAC.digest(:sha256, master, "surftp-mac")
      {enc_key, mac_key}
    end

    def self.encrypt_password(plaintext : String) : String
      master = load_master_key
      enc_key, mac_key = derive_keys(master)
      iv = Random::Secure.random_bytes(IV_SIZE)

      cipher = OpenSSL::Cipher.new("aes-256-cbc")
      cipher.encrypt
      cipher.key = enc_key
      cipher.iv = iv

      encrypted = IO::Memory.new
      encrypted.write(cipher.update(plaintext))
      encrypted.write(cipher.final)
      ciphertext = encrypted.to_slice

      # HMAC over iv + ciphertext (encrypt-then-MAC)
      mac_input = IO::Memory.new
      mac_input.write(iv)
      mac_input.write(ciphertext)
      hmac = OpenSSL::HMAC.digest(:sha256, mac_key, mac_input.to_slice)

      ciphertext_b64 = Base64.strict_encode(ciphertext)
      iv_b64 = Base64.strict_encode(iv)
      hmac_b64 = Base64.strict_encode(hmac)

      "ENC:#{ciphertext_b64}:#{iv_b64}:#{hmac_b64}"
    end

    def self.decrypt_password(encrypted : String) : String
      unless encrypted.starts_with?("ENC:")
        return encrypted
      end

      parts = encrypted.split(":")
      if parts.size != 4
        raise "Invalid encrypted password format"
      end

      ciphertext = Base64.decode(parts[1])
      iv = Base64.decode(parts[2])
      stored_hmac = Base64.decode(parts[3])

      master = load_master_key
      enc_key, mac_key = derive_keys(master)

      # Verify HMAC first (encrypt-then-MAC)
      mac_input = IO::Memory.new
      mac_input.write(iv)
      mac_input.write(ciphertext)
      computed_hmac = OpenSSL::HMAC.digest(:sha256, mac_key, mac_input.to_slice)

      unless computed_hmac == stored_hmac
        raise "Password integrity check failed (HMAC mismatch)"
      end

      cipher = OpenSSL::Cipher.new("aes-256-cbc")
      cipher.decrypt
      cipher.key = enc_key
      cipher.iv = iv

      decrypted = IO::Memory.new
      decrypted.write(cipher.update(ciphertext))
      decrypted.write(cipher.final)

      String.new(decrypted.to_slice)
    end
  end
end
