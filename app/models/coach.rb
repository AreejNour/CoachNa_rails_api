# The `coaches` table is shared with the Node API, whose migrations define it.
class Coach < ApplicationRecord
  EDITABLE_STATUSES = %w[incomplete].freeze
  SPECIALTIES = %w[weight_loss muscle_gain diabetes_friendly sports womens_health general].freeze

  has_many :coach_status_changes
  has_many :coach_documents
  has_many :coach_packages
  has_many :subscriptions
  has_many :coach_reviews
  has_many :foods, foreign_key: :owner_coach_id, inverse_of: :owner_coach
  has_one :questionnaire
end
