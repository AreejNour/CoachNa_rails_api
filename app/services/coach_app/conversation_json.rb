module CoachApp
  # A conversation as a row in the coach's chat list: the client, last activity, a short preview,
  # the coach's unread count, and whether the chat is still open.
  module ConversationJson
    def self.list_item(conversation, unread_count)
      subscription = conversation.subscription
      {
        id: conversation.id,
        subscriptionId: subscription.id,
        client: { id: subscription.client_id, fullName: subscription.client.full_name },
        lastMessageAt: conversation.last_message_at&.iso8601,
        lastMessagePreview: preview(conversation),
        unreadCount: unread_count,
        state: Chat.open?(subscription) ? "open" : "closed"
      }
    end

    # The newest message in a line: its text, or a marker for a photo-only message.
    def self.preview(conversation)
      last = conversation.messages.order(sent_at: :desc, id: :desc).first
      return nil unless last

      last.body.presence || (last.photo? ? "صورة" : nil)
    end
    private_class_method :preview
  end
end
