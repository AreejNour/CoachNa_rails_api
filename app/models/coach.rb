# The `coaches` table is shared with the Node API, whose migrations define it.
class Coach < ApplicationRecord
  EDITABLE_STATUSES = %w[incomplete rejected].freeze
  SPECIALTIES = %w[weight_loss muscle_gain diabetes_friendly sports womens_health general].freeze
end
