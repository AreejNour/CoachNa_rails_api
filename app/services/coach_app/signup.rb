module CoachApp
  # A new coach signs up in two calls: ask for a code, then send it back with their details.
  module Signup
    def self.request_otp(phone:, country:)
      e164 = Input.phone(phone, country)
      refuse_registered(e164)

      otp = Otp.create(e164)
      OtpSender.deliver(e164, otp[:code])
      { expiresInSeconds: otp[:expires_in_seconds], devCode: (otp[:code] unless Rails.env.production?) }.compact
    end

    def self.check_code(phone:, country:, code:)
      code = normalized_code(code)
      e164 = Input.phone(phone, country)
      refuse_registered(e164)

      Otp.check_code(e164, code)
      {}
    end

    def self.verify(phone:, country:, code:, password:, full_name:, email:)
      code = normalized_code(code)
      password = Input.password(password)
      full_name = Input.full_name(full_name)
      email = Input.email(email) unless email.nil?
      e164 = Input.phone(phone, country)
      refuse_registered(e164)

      coach = Otp.verify_and_consume(e164, code) do
        Coach.create!(
          phone: e164, email: email, full_name: full_name,
          password_hash: Password.digest(password), phone_verified_at: Time.current
        )
      end
      {
        coach: CoachJson.call(coach),
        accessToken: AccessToken.sign(coach.id),
        refreshToken: RefreshTokens.issue(coach.id)
      }
    rescue ActiveRecord::RecordNotUnique => error
      raise ApiError.new(409, error.message.include?("coaches_email_unique") ? "email already registered" : "phone already registered")
    end

    def self.normalized_code(code)
      PhoneNumber.ascii_digits(Input.text(code)).strip
    end
    private_class_method :normalized_code

    def self.refuse_registered(e164)
      raise ApiError.new(409, "phone already registered") if Coach.exists?(phone: e164)
    end
    private_class_method :refuse_registered
  end
end
