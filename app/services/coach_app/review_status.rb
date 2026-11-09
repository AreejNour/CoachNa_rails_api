module CoachApp
  # Where a coach stands with review, and sending their profile in.
  module ReviewStatus
    def self.missing(coach, documents)
      types = documents.map(&:type)
      missing = []
      missing << "about" unless profile_complete?(coach)
      missing + CoachDocument::TYPES.reject { |type| types.include?(type) }
    end

    def self.call(coach)
      documents = coach.coach_documents.order(:created_at).to_a
      {
        status: coach.status,
        missing: missing(coach, documents),
        documents: documents.map { |document| DocumentJson.call(document) },
        rejectionReason: coach.rejection_reason,
        commissionPercent: coach.commission_percent&.to_f
      }
    end

    # Holds the coach's row lock, like uploads and removals, so a document can't be removed
    # between checking it's there and submitting.
    def self.submit!(coach)
      coach.with_lock do
        unless Coach::EDITABLE_STATUSES.include?(coach.status)
          raise ApiError.new(409, "profile not submittable in current state")
        end

        gaps = missing(coach, coach.coach_documents.to_a)
        raise ApiError.new(400, "missing requirements", missing: gaps) if gaps.any?

        coach.update!(status: "pending_review", profile_submitted_at: Time.current, rejection_reason: nil)
      end
      { status: coach.status }
    end

    def self.profile_complete?(coach)
      coach.bio.present? && !coach.years_experience.nil? && coach.specialties.any?
    end
    private_class_method :profile_complete?
  end
end
