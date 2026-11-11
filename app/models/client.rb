# The `clients` table is owned by the Node API (client app sign-up). Rails only reads it.
class Client < ApplicationRecord
  has_one :client_health_profile
end
