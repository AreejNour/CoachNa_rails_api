# The `coach_status_changes` table is Rails-owned (admin panel, M34); not part of the Node API schema.
class CoachStatusChange < ApplicationRecord
  belongs_to :coach
  belongs_to :admin_user, foreign_key: :admin_id
end
