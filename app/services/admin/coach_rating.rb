module Admin
  # Recomputes a coach's aggregate rating from their visible reviews.
  # Mirrors the Node `recomputeCoachRating` in coaches.service.ts exactly:
  #   average_rating = visibleCount > 0 ? Math.round(avg*10)/10 : null
  #   review_count   = visibleCount
  module CoachRating
    def self.recompute(coach_id)
      avg, count = CoachReview
        .where(coach_id: coach_id, status: "visible")
        .pick(Arel.sql("AVG(rating)"), Arel.sql("COUNT(*)"))

      count = count.to_i
      average_rating = count.positive? ? (avg.to_f * 10).round / 10.0 : nil

      Coach.where(id: coach_id).update_all(
        average_rating: average_rating,
        review_count:   count
      )
    end
  end
end
