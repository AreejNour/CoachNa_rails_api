# The `payments` table is owned by the Node API (built M6). Rails reads a coach's paid subscription
# payments to compute earnings (Milestone 24).
class Payment < ApplicationRecord
  belongs_to :subscription, optional: true
end
