module CoachApp
  # The coach as the API shows it. Fields are listed one by one so a new column, or the password
  # hash or commission, can never reach a response by accident.
  module CoachJson
    def self.call(coach)
      {
        id: coach.id,
        phone: coach.phone,
        email: coach.email,
        fullName: coach.full_name,
        bio: coach.bio,
        yearsExperience: coach.years_experience,
        specialties: coach.specialties,
        status: coach.status,
        rejectionReason: coach.rejection_reason,
        phoneVerifiedAt: coach.phone_verified_at&.iso8601(3),
        profileSubmittedAt: coach.profile_submitted_at&.iso8601(3)
      }
    end
  end
end
