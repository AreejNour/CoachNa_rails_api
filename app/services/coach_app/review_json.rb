module CoachApp
  # One client review for the coach app. Only the reviewer's first name is shown (as on the public
  # page). Photo urls point at the coach photo endpoint (served in Milestone 23 Plan 2).
  module ReviewJson
    PHOTO_ORDER = { "before" => 0, "after" => 1 }.freeze

    def self.call(review)
      {
        id: review.id,
        rating: review.rating,
        body: review.body,
        reviewerFirstName: review.client.full_name.to_s.split.first,
        planName: review.subscription&.coach_package&.name,
        createdAt: review.created_at.iso8601,
        photos: photos(review)
      }
    end

    def self.photos(review)
      review.review_photos.select { |p| p.status == "visible" }
            .sort_by { |p| PHOTO_ORDER.fetch(p.kind, 2) }
            .map { |p| { id: p.id, kind: p.kind, url: "/coach/reviews/photos/#{p.id}" } }
    end
  end
end
