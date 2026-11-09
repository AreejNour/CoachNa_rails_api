module CoachApp
  # Sign-up codes for coaches. Same table, settings and messages as the Node API's OTP service,
  # which keeps client codes in the same table under account_type 'client'.
  module Otp
    ACCOUNT_TYPE = "coach"

    def self.create(phone)
      enforce_limits(phone)
      scope(phone).where(consumed_at: nil).update_all(consumed_at: Time.current)

      code = generate_code
      PhoneVerification.create!(
        phone: phone, account_type: ACCOUNT_TYPE, code_hash: digest(code), expires_at: ttl_seconds.seconds.from_now
      )
      { code: code, expires_in_seconds: ttl_seconds }
    end

    # Yields only for the right code. The code is consumed in the block's transaction, so it stays
    # usable if the block fails. A wrong code raises after the commit, because raising inside
    # would roll back the attempt it just counted.
    def self.verify_and_consume(phone, code)
      failure = nil
      result = PhoneVerification.transaction do
        row = scope(phone).where(consumed_at: nil).where("expires_at > ?", Time.current)
          .order(created_at: :desc).lock.first
        failure = check(row, code)
        next if failure

        row.update!(consumed_at: Time.current)
        yield
      end
      raise ApiError.new(400, failure) if failure

      result
    end

    def self.check(row, code)
      return "otp expired" unless row
      return "too many attempts" if row.attempts >= max_attempts
      return if ActiveSupport::SecurityUtils.secure_compare(row.code_hash, digest(code))

      row.update!(attempts: row.attempts + 1)
      row.attempts >= max_attempts ? "too many attempts" : "invalid code"
    end
    private_class_method :check

    def self.enforce_limits(phone)
      recent = scope(phone).where(created_at: 1.hour.ago..)
      newest = recent.maximum(:created_at)
      if newest && newest > cooldown_seconds.seconds.ago
        raise ApiError.new(429, "otp cooldown, try again shortly")
      end
      raise ApiError.new(429, "too many otp requests, try again later") if recent.count >= max_per_hour
    end
    private_class_method :enforce_limits

    def self.scope(phone) = PhoneVerification.where(phone: phone, account_type: ACCOUNT_TYPE)
    private_class_method :scope

    def self.digest(code) = Digest::SHA256.hexdigest(code)
    private_class_method :digest

    def self.generate_code
      length = ENV.fetch("OTP_LENGTH", 6).to_i
      SecureRandom.random_number(10**length).to_s.rjust(length, "0")
    end
    private_class_method :generate_code

    def self.ttl_seconds = ENV.fetch("OTP_TTL_SECONDS", 300).to_i
    private_class_method :ttl_seconds

    def self.max_attempts = ENV.fetch("OTP_MAX_ATTEMPTS", 5).to_i
    private_class_method :max_attempts

    def self.cooldown_seconds = ENV.fetch("OTP_RESEND_COOLDOWN_SECONDS", 60).to_i
    private_class_method :cooldown_seconds

    def self.max_per_hour = ENV.fetch("OTP_MAX_PER_HOUR", 5).to_i
    private_class_method :max_per_hour
  end
end
