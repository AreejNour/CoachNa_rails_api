# The `subscriptions` table is owned by the Node API. Rails reads a coach's subscribers.
class Subscription < ApplicationRecord
  belongs_to :coach
  belongs_to :client
  belongs_to :coach_package, foreign_key: :package_id, optional: true, inverse_of: false
  belongs_to :promo_code, optional: true
  has_many :plans
  has_many :payments
  has_one :conversation

  # Admin lists' default view: leaves out checkouts nobody paid for, i.e. `checkout_open` (the card
  # form is open) and replaced checkouts (the Node API closed them with payment failed / `replaced`
  # when the client subscribed again, e.g. to apply a promo code).
  scope :listed, lambda {
    replaced = Payment.where(status: "failed", failure_reason: "replaced").where.not(subscription_id: nil)
    where.not(status: "checkout_open").where.not(id: replaced.select(:subscription_id))
  }

  # Admin overview (M36): filter by lifecycle status. Blank means "all", the `listed` view; a
  # status filter shows every row with that status.
  scope :for_status, lambda { |status|
    status.present? ? where(status: status) : listed
  }

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
