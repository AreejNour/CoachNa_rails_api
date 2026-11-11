module CoachApp
  # The coach's in-app notifications on the shared `notifications` table (written by Node). For
  # Milestone 20 the only kind is new_client; mark_seen clears those when the coach opens the list.
  module Notifications
    def self.unread_count(coach)
      Notification.where(recipient_type: "coach", recipient_id: coach.id, read_at: nil).count
    end

    def self.mark_seen(coach)
      Notification
        .where(recipient_type: "coach", recipient_id: coach.id, type: "new_client", read_at: nil)
        .update_all(read_at: Time.current)
      nil
    end
  end
end
