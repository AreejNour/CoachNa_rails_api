# The `coach_reviews` table is shared with the Node API, which owns writes and moderation.
# Rails only reads a coach's reviews.
class CoachReview < ApplicationRecord
  belongs_to :coach
  belongs_to :client
  belongs_to :subscription, optional: true
  has_many :review_photos, foreign_key: :review_id, inverse_of: :coach_review
end
