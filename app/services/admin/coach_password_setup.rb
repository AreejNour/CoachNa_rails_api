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

    # The coach the token belongs to, or nil if it is expired, tampered with or already used.
    def self.verify(token)
      id, print = verifier.verified(token.to_s)
      return nil unless id.is_a?(String) && print.is_a?(String)

      coach = Coach.find_by(id: id)
      coach if coach && usable?(coach, print)
    end

    # Sets the password once: the row is locked and the token re-checked, so two submits of one
    # link cannot both succeed. Returns the coach, or nil when the token is no longer valid.
    def self.set_password!(token, password, confirmation)
      CoachApp::Input.password(password)
      raise ArgumentError, "passwords do not match" unless password == confirmation

      id, print = verifier.verified(token.to_s)
      return nil unless id.is_a?(String) && print.is_a?(String)

      Coach.transaction do
        coach = Coach.lock.find_by(id: id)
        next nil unless coach && usable?(coach, print)

        coach.update!(password_hash: CoachApp::Password.digest(password))
        CoachApp::RefreshTokens.revoke_all(coach.id)
        coach
      end
    end

    # Queues the set-password email for an existing coach.
    def self.send_email!(coach)
      raise ArgumentError, "coach has no email" if coach.email.blank?

      data = { firstName: coach.full_name.to_s.split.first, link: link_for(coach) }
      CoachApp::Outbox.enqueue_and_publish_after_commit!(
        kind: "email", payload: { to: coach.email, template: "coach_account_created", data: data }
      )
    end

    def self.usable?(coach, print)
      %w[approved suspended].include?(coach.status) && matches?(coach, print)
    end
    private_class_method :usable?

    def self.matches?(coach, print)
      ActiveSupport::SecurityUtils.secure_compare(fingerprint(coach.password_hash), print)
    end
    private_class_method :matches?

    def self.fingerprint(password_hash)
      Digest::SHA256.hexdigest(password_hash.to_s)[0, 16]
    end

    def self.verifier
      Rails.application.message_verifier(PURPOSE)
    end
    private_class_method :verifier
  end
end
