# The `subscriptions` table is owned by the Node API. Rails reads a coach's subscribers.
class Subscription < ApplicationRecord
  belongs_to :coach
  belongs_to :client
end
