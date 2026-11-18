# The `foods` table is shared with the Node API (macros per 100 g). A row with a null
# owner_coach_id is a global/admin food; a non-null one is that coach's custom food.
class Food < ApplicationRecord
  belongs_to :owner_coach, class_name: "Coach", optional: true

  def custom? = owner_coach_id.present?
end
