module Admin
  # Six state-machine actions for coach status management, executed atomically
  # (guard + coach update + audit row + push/email notifications in one transaction).
  module CoachDecision
    class Error < StandardError; end

    # pending_review → approved
    def self.approve!(coach:, admin:, commission:)
      percent = parse_commission(commission)
      transition!(
        coach, admin,
        from:        %w[pending_review],
        to:          "approved",
        event:       :approved,
        email:       "coach_application_approved",
        reason:      nil,
        commission:  percent,
        coach_attrs: { status: "approved", commission_percent: percent,
                       reviewed_at: Time.current, rejection_reason: nil }
      )
    end

    # pending_review → incomplete
    def self.request_changes!(coach:, admin:, reason:)
      stripped = require_reason!(reason)
      transition!(
        coach, admin,
        from:        %w[pending_review],
        to:          "incomplete",
        event:       :needs_changes,
        email:       "coach_application_needs_changes",
        reason:      stripped,
        coach_attrs: { status: "incomplete", rejection_reason: stripped, reviewed_at: Time.current }
      )
    end

    # pending_review → rejected
    def self.reject!(coach:, admin:, reason:)
      stripped = require_reason!(reason)
      transition!(
        coach, admin,
        from:        %w[pending_review],
        to:          "rejected",
        event:       :rejected,
        email:       "coach_application_rejected",
        reason:      stripped,
        coach_attrs: { status: "rejected", rejection_reason: stripped, reviewed_at: Time.current }
      )
    end

    # approved → suspended
    def self.suspend!(coach:, admin:, reason:)
      stripped = require_reason!(reason)
      transition!(
        coach, admin,
        from:        %w[approved],
        to:          "suspended",
        event:       :suspended,
        email:       "coach_suspended",
        reason:      stripped,
        coach_attrs: { status: "suspended" }
      )
    end

    # suspended → approved
    def self.reactivate!(coach:, admin:, reason:)
      stripped = require_reason!(reason)
      transition!(
        coach, admin,
        from:        %w[suspended],
        to:          "approved",
        event:       :reactivated,
        email:       "coach_reactivated",
        reason:      stripped,
        coach_attrs: { status: "approved" }
      )
    end

    # approved OR suspended → deactivated
    def self.deactivate!(coach:, admin:, reason:)
      stripped = require_reason!(reason)
      transition!(
        coach, admin,
        from:        %w[approved suspended],
        to:          "deactivated",
        event:       :deactivated,
        email:       "coach_deactivated",
        reason:      stripped,
        coach_attrs: { status: "deactivated" }
      )
    end

    # -------------------------------------------------------------------------
    private_class_method def self.transition!(coach, admin, from:, to:, event:, email:, reason:, coach_attrs:, commission: nil)
      current_status = coach.status
      unless from.include?(current_status)
        raise Error, "Cannot perform this action: coach is #{current_status} (expected one of: #{from.join(", ")})"
      end

      Coach.transaction do
        coach.update!(coach_attrs)

        coach.coach_status_changes.create!(
          admin_id:          admin.id,
          from_status:       current_status,
          to_status:         to,
          reason:            reason,
          commission_percent: commission
        )

        CoachApp::CoachEvents.push_coach!(coach, event)
        CoachApp::CoachEvents.email_coach!(coach, email, reason: reason)
      end

      coach.reload
    end

    private_class_method def self.parse_commission(value)
      percent = Float(value.to_s, exception: false)
      raise Error, "COMMISSION must be a number from 0 to 100." unless percent&.between?(0, 100)

      percent
    end

    private_class_method def self.require_reason!(reason)
      stripped = reason.to_s.strip
      raise Error, "Reason can't be blank." if stripped.empty?

      stripped
    end
  end
end
