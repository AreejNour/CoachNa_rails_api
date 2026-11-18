# The `review_photos` table is shared with the Node API (before/after photos on a review).
class ReviewPhoto < ApplicationRecord
  belongs_to :coach_review, foreign_key: :review_id, inverse_of: :review_photos
end
