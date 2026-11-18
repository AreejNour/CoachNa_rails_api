# One full daily option of a plan (shared table). The client follows one option per day.
class PlanOption < ApplicationRecord
  belongs_to :plan
  has_many :plan_meals, dependent: :delete_all
end
