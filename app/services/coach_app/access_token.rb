module CoachApp
  # Coach access tokens. Signed like the Node API's, so each backend accepts the other's.
  module AccessToken
    ALGORITHM = "HS256"
    LIFETIME_SECONDS = 15 * 60

    def self.sign(coach_id)
      now = Time.now.to_i
      JWT.encode({ sub: coach_id, type: "coach", iat: now, exp: now + LIFETIME_SECONDS }, secret, ALGORITHM)
    end

    # The coach id, or nil unless the token is valid, unexpired and a coach's.
    def self.verify(token)
      return unless token.is_a?(String)

      payload, = JWT.decode(token, secret, true, algorithm: ALGORITHM)
      payload["sub"] if payload["type"] == "coach" && payload["sub"].is_a?(String) && payload["exp"]
    rescue JWT::DecodeError
      nil
    end

    def self.secret
      ENV.fetch("JWT_ACCESS_SECRET").presence || raise(KeyError, "JWT_ACCESS_SECRET is empty")
    end
    private_class_method :secret
  end
end
