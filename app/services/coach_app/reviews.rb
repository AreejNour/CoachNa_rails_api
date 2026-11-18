module CoachApp
  # The coach's view of client reviews (Milestone 23): the same set the public coach page shows
  # (status 'visible', visible photos), but all of them rather than the newest 10.
  module Reviews
    def self.list(coach)
      reviews = coach.coach_reviews.where(status: "visible").joins(:client).order(created_at: :desc)
                     .includes(:client, :review_photos, subscription: :coach_package)
      ReviewListJson.call(coach, reviews)
    end
  end
end
