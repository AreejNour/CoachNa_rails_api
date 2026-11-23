module CoachApp
  # Transactional outbox: write the row inside the caller's transaction, publish after the commit.
  # An unpublished row is re-published by the Node worker's sweeper, so a failed publish is safe.
  module Outbox
    def self.enqueue!(kind:, payload:)
      OutboxMessage.create!(kind: kind, payload: payload).id
    end

    # For callers that publish right after their write: the publish waits for the outermost
    # transaction to commit (or runs now with none open), and never runs on a rollback.
    def self.enqueue_and_publish_after_commit!(kind:, payload:)
      id = enqueue!(kind: kind, payload: payload)
      ActiveRecord.after_all_transactions_commit { publish_after_commit([ id ]) }
      id
    end

    def self.publish_after_commit(ids)
      OutboxMessage.where(id: Array(ids)).find_each do |row|
        QueuePublisher.publish(routing_key: row.kind, body: { outboxId: row.id }.to_json)
        stamp_unless_locked(row.id)
      rescue StandardError => error
        Rails.logger.error("[outbox] publish failed for #{row.id}: #{error.class}")
      end
    rescue StandardError => error
      Rails.logger.error("[outbox] publish failed: #{error.class}")
    end

    # Never wait on the Node worker's row lock (held while it sends): stamp only unlocked,
    # unpublished rows. A locked row is the worker's to stamp.
    def self.stamp_unless_locked(id)
      unlocked = OutboxMessage.where(id: id, published_at: nil).lock("FOR UPDATE SKIP LOCKED").select(:id)
      OutboxMessage.where(id: unlocked).update_all(published_at: Time.current)
    end
    private_class_method :stamp_unless_locked
  end
end
