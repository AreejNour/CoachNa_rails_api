module CoachApp
  # Single-use refresh tokens. The table stores only a digest, in the same format as the Node API.
  module RefreshTokens
    LIFETIME = 30.days

    def self.issue(coach_id)
      token = SecureRandom.urlsafe_base64(32)
      CoachRefreshToken.create!(coach_id: coach_id, token: digest(token), expires_at: LIFETIME.from_now)
      token
    end

    # The owning coach's id, or nil. One statement, so two simultaneous refreshes can't both win.
    def self.rotate(presented)
      return unless presented.is_a?(String)

      CoachRefreshToken.with_connection do |connection|
        connection.exec_query(
          "DELETE FROM coach_refresh_tokens WHERE token = $1 AND expires_at > now() RETURNING coach_id",
          "Rotate refresh token",
          [ digest(presented) ]
        ).rows.dig(0, 0)
      end
    end

    def self.revoke(presented)
      CoachRefreshToken.where(token: digest(presented)).delete_all if presented.is_a?(String)
      nil
    end

    def self.digest(token)
      Digest::SHA256.hexdigest(token)
    end
    private_class_method :digest
  end
end
