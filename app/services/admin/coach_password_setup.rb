module Admin
  # The link a coach created by an admin uses to choose their own password. The token holds the
  # coach id and a fingerprint of the current password hash, so it stops working once a password is set.
  module CoachPasswordSetup
    PURPOSE = :coach_password_setup
    EXPIRES_IN = 72.hours

    def self.token_for(coach)
      verifier.generate([ coach.id, fingerprint(coach.password_hash) ], expires_in: EXPIRES_IN)
    end

    def self.link_for(coach)
      "#{ENV.fetch('COACH_PASSWORD_URL_BASE', 'http://localhost:3003')}/coach-password/#{token_for(coach)}"
    end

    def self.fingerprint(password_hash)
      Digest::SHA256.hexdigest(password_hash.to_s)[0, 16]
    end

    def self.verifier
      Rails.application.message_verifier(PURPOSE)
    end
    private_class_method :verifier
  end
end
