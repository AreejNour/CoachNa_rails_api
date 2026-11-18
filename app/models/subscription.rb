# The `subscriptions` table is owned by the Node API. Rails reads a coach's subscribers.
class Subscription < ApplicationRecord
  belongs_to :coach
  belongs_to :client
  belongs_to :coach_package, foreign_key: :package_id, optional: true, inverse_of: false
  has_many :plans
  has_one :conversation
end
