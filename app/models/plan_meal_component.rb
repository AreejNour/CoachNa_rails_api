# One component of a meal (shared table): either structured (food + quantity + unit) or free-text.
# A DB CHECK enforces the XOR; the component FK to foods is ON DELETE RESTRICT.
class PlanMealComponent < ApplicationRecord
  belongs_to :plan_meal
  belongs_to :food, optional: true
end
