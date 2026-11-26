# The `clients` table is owned by the Node API (client app sign-up). Rails reads it for the admin
# panel and, in M37b, writes `status` (suspend / reactivate / deactivate via Admin::ClientDecision).
class Client < ApplicationRecord
  has_one :client_health_profile
  has_many :subscriptions
  has_many :client_refresh_tokens

  # Admin clients list (M37b): filter by account status; blank means "all".
  scope :for_status, ->(status) { where(status: status) if status.present? }

  # Admin clients list (M37b): free-text lookup across the client's name, phone, and email.
  # ILIKE wildcards in the term are escaped so they match literally.
  scope :search, lambda { |q|
    next if q.blank?

    like = "%#{sanitize_sql_like(q)}%"
    where("full_name ILIKE :like OR phone ILIKE :like OR email ILIKE :like", like: like)
  }
end
