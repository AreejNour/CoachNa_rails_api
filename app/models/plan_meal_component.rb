# One component of a meal (shared table), one of four kinds: food, macro, portion or text.
# DB CHECKs enforce one column shape per kind; the component FK to foods is ON DELETE RESTRICT.
class PlanMealComponent < ApplicationRecord
  belongs_to :plan_meal
  belongs_to :food, optional: true
end
