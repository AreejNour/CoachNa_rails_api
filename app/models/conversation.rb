# The `conversations` table is shared with the Node API (one per subscription). Node owns the
# client side; Rails reads/writes the coach side. `coach_last_read_at` is the coach's read cursor.
class Conversation < ApplicationRecord
  belongs_to :subscription
  has_many :messages, dependent: :destroy
end
