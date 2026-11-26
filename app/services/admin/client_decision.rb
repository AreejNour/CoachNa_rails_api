module Admin
  # Three state-machine actions for client account status (M37b), each executed atomically
  # (guard + clients.status update + refresh-token revocation in one transaction). Clients have
  # no audit table and no reason column (unlike coaches), so nothing else is persisted; the Node
  # API already blocks login/refresh for a non-active client.
  module ClientDecision
    class Error < StandardError; end

    # active → suspended
    def self.suspend!(client:)
      transition!(client, from: %w[active], to: "suspended", revoke_tokens: true)
    end

    # suspended → active
    def self.reactivate!(client:)
      transition!(client, from: %w[suspended], to: "active", revoke_tokens: false)
    end

    # active OR suspended → deactivated (terminal)
    def self.deactivate!(client:)
      transition!(client, from: %w[active suspended], to: "deactivated", revoke_tokens: true)
    end

    private_class_method def self.transition!(client, from:, to:, revoke_tokens:)
      current_status = client.status
      unless from.include?(current_status)
        raise Error, "Cannot perform this action: client is #{current_status} (expected one of: #{from.join(", ")})"
      end

      Client.transaction do
        client.update!(status: to)
        ClientRefreshToken.where(client_id: client.id).delete_all if revoke_tokens
      end

      client.reload
    end
  end
end
