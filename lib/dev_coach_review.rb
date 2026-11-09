# Stand-in for the admin panel (Milestones 33-34), which is where coaches will really be approved
# or rejected. For development only: see docs/temporary-code-to-remove.md.
module DevCoachReview
  class Refused < StandardError; end

  def self.approve!(phone:, commission:)
    percent = parse_commission(commission)
    review(phone, status: "approved", commission_percent: percent, rejection_reason: nil)
  end

  def self.reject!(phone:, reason:)
    raise Refused, "REASON can't be blank: the coach reads it." if reason.to_s.strip.empty?

    review(phone, status: "rejected", rejection_reason: reason.strip)
  end

  def self.review(phone, attributes)
    raise Refused, "This command doesn't run in production. Use the admin panel." if Rails.env.production?

    coach = Coach.find_by(phone: phone) || raise(Refused, "No coach has the phone #{phone.inspect}. Use the +20... form.")
    unless coach.status == "pending_review"
      raise Refused, "This coach is #{coach.status}, and only a coach in pending_review can be reviewed."
    end

    coach.update!(attributes.merge(reviewed_at: Time.current))
    coach
  end
  private_class_method :review

  def self.parse_commission(value)
    percent = Float(value.to_s, exception: false)
    raise Refused, "COMMISSION must be a number from 0 to 100." unless percent&.between?(0, 100)

    percent
  end
  private_class_method :parse_commission
end
