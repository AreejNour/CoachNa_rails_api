module CoachApp
  # Password hashes shared with the Node API, which writes them with bcryptjs.
  module Password
    COST = 12

    def self.digest(plain)
      raise ArgumentError, "password contains a null byte" if plain.include?("\0")

      BCrypt::Password.create(plain, cost: COST).to_s
    end

    def self.verify(plain, stored_hash)
      # bcrypt stops reading at a null byte, so everything after it would be ignored.
      return false unless plain.is_a?(String) && !plain.include?("\0")

      BCrypt::Password.new(stored_hash).is_password?(plain)
    rescue BCrypt::Errors::InvalidHash
      false
    end
  end
end
