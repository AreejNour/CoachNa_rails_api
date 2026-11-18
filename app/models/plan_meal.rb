# One meal of an option (shared table); its macros are the sum of its components (computed by
# the Node read, not stored).
class PlanMeal < ApplicationRecord
  belongs_to :plan_option
  has_many :plan_meal_components, -> { order(:position) }, dependent: :delete_all
end
