module CoachApp
  # Transactional outbox: write the row inside the caller's transaction, publish after the commit.
  # An unpublished row is re-published by the Node worker's sweeper, so a failed publish is safe.
  module Outbox
    def self.enqueue!(kind:, payload:)
      OutboxMessage.create!(kind: kind, payload: payload).id
    end

    def self.publish_after_commit(ids)
      OutboxMessage.where(id: Array(ids)).find_each do |row|
        QueuePublisher.publish(routing_key: row.kind, body: { outboxId: row.id }.to_json)
        row.update_columns(published_at: Time.current)
      rescue StandardError => error
        Rails.logger.error("[outbox] publish failed for #{row.id}: #{error.class}")
      end
    rescue StandardError => error
      Rails.logger.error("[outbox] publish failed: #{error.class}")
    end
  end
end
