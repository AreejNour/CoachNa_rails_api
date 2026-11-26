# The `client_refresh_tokens` table is owned by the Node API (client sessions). The admin panel
# deletes a client's tokens when it suspends or deactivates them (M37b), so the session cannot
# be refreshed; the Node API already blocks login/refresh for a non-active client.
class ClientRefreshToken < ApplicationRecord
  belongs_to :client
end
