module Admin
  # Approves or rejects a pending coach review (admin moderation action).
  # Mirrors the Node `decideReview` in coaches_api/src/reviews/decide-review.ts:
  #   - Runs in one transaction; row-locks the review and coach before mutating.
  #   - Guards against double-decision (409 in Node → Error here).
  #   - Syncs review_photos status to match the review status.
  #   - approve! recomputes the coach aggregate rating.
  #   - reject! deletes photo files from storage AFTER the transaction commits;
  #     storage errors are logged and never re-raised.
  module ReviewDecision
    class Error < StandardError; end

    # Approve a pending review: marks it visible and recomputes the coach rating.
    def self.approve!(review:, admin:)
      CoachReview.transaction do
        locked = decide!(review: review, admin: admin, new_status: "visible")
        Coach.lock.find(locked.coach_id)
        Admin::CoachRating.recompute(locked.coach_id)
      end
      # approve! never deletes storage files
    end

    # Reject a pending review: marks it rejected and deletes its photo files.
    def self.reject!(review:, admin:)
      storage_keys = []

      CoachReview.transaction do
        locked = decide!(review: review, admin: admin, new_status: "rejected")
        storage_keys = ReviewPhoto.where(review_id: locked.id).pluck(:storage_key)
      end

      # After transaction commits, delete each file; errors are logged, never raised.
      storage_keys.each do |key|
        begin
          Storage.current.delete(key)
        rescue => e
          Rails.logger.error("Admin::ReviewDecision: failed to delete storage key #{key}: #{e.message}")
        end
      end
    end

    # ── private helper ────────────────────────────────────────────────────────

    # Shared steps 1–3: re-lock the review row, guard against double-decision,
    # update status/decided_at/decided_by, update all photo statuses.
    # Must be called inside a transaction. Returns the locked review record.
    def self.decide!(review:, admin:, new_status:)
      locked = CoachReview.lock.find(review.id)

      unless locked.status == "pending"
        raise Error, "review already #{locked.status}"
      end

      locked.update!(
        status:     new_status,
        decided_at: Time.current,
        decided_by: admin.id
      )

      ReviewPhoto.where(review_id: locked.id).update_all(status: new_status)

      locked
    end
    private_class_method :decide!
  end
end
