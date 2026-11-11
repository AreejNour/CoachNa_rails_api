# The `client_health_profiles` table is owned by the Node API; its primary key is client_id
# (one profile per client). Rails only reads it.
class ClientHealthProfile < ApplicationRecord
  self.primary_key = "client_id"

  belongs_to :client
end
