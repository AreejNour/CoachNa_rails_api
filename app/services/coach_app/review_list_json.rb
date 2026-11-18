module CoachApp
  # The coach's rating summary plus their reviews.
  module ReviewListJson
    def self.call(coach, reviews)
      {
        summary: { averageRating: coach.average_rating&.to_f, reviewCount: coach.review_count },
        reviews: reviews.map { |review| ReviewJson.call(review) }
      }
    end
  end
end
