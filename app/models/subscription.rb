# The `subscriptions` table is owned by the Node API. Rails reads a coach's subscribers.
class Subscription < ApplicationRecord
  belongs_to :coach
  belongs_to :client
  belongs_to :coach_package, foreign_key: :package_id, optional: true, inverse_of: false
  has_many :plans
  has_many :payments
  has_one :conversation

  # Admin overview (M36): filter by lifecycle status; blank means "all".
  scope :for_status, ->(status) { where(status: status) if status.present? }

  # Admin overview (M36): free-text lookup across the client's name/phone and the coach's name.
  # ILIKE wildcards in the term are escaped so they match literally.
  scope :search, lambda { |q|
    next if q.blank?

    like = "%#{sanitize_sql_like(q)}%"
    joins(:client, :coach).where(
      "clients.full_name ILIKE :like OR clients.phone ILIKE :like OR coaches.full_name ILIKE :like",
      like: like,
    )
  }
end
