# The `promo_code_clients` table (Node API migration 0026) is a promo code's allow-list: when it has
# rows, only those client accounts can use the code.
class PromoCodeClient < ApplicationRecord
  self.primary_key = [ :promo_code_id, :client_id ]

  belongs_to :promo_code
  belongs_to :client
end
