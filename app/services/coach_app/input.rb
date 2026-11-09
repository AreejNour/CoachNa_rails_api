module CoachApp
  # Checks values from a request body. Anything unusable is a 400, and a null byte or broken
  # encoding must stop here because Postgres would refuse it with a 500.
  module Input
    EMAIL = /\A[^@\s]+@[^@\s]+\.[^@\s]+\z/
    FULL_NAME_MAX = 100
    EMAIL_MAX = 254
    PASSWORD_MIN = 8

    def self.text(value)
      invalid! unless value.is_a?(String) && value.valid_encoding? && !value.include?("\0") && !value.empty?
      value
    end

    def self.trimmed(value, max:)
      trimmed = text(value).strip
      invalid! if trimmed.empty? || trimmed.length > max
      trimmed
    end

    def self.full_name(value) = trimmed(value, max: FULL_NAME_MAX)

    def self.email(value)
      email = trimmed(value, max: EMAIL_MAX)
      invalid! unless email.match?(EMAIL)
      email
    end

    def self.password(value)
      invalid! if text(value).length < PASSWORD_MIN
      value
    end

    def self.country(value)
      invalid! unless value.is_a?(String) && Phonelib.phone_data.key?(value)
      value
    end

    def self.invalid!
      raise ApiError.new(400, "validation failed")
    end
  end
end
