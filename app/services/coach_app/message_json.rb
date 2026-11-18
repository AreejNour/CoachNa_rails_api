module CoachApp
  # One chat message for the coach app. `photoUrl` points at the coach photo endpoint
  # (served in Milestone 22 Plan 4); `readAt` is the client's read of a coach message.
  module MessageJson
    def self.call(message, conversation_id)
      {
        id: message.id,
        senderType: message.sender_type,
        body: message.body,
        photoUrl: message.photo? ? "/coach/conversations/#{conversation_id}/messages/#{message.id}/photo" : nil,
        clientRef: message.client_ref,
        sentAt: message.sent_at.iso8601,
        readAt: message.read_at&.iso8601
      }
    end
  end
end
