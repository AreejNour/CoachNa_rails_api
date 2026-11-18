module CoachApp
  # The coach side of the chat (Milestone 22), reading/writing the shared conversations/messages
  # tables. A coach only reaches their own clients' conversations (through their subscriptions).
  # Coach unread = client messages sent after the coach's read cursor (conversations.coach_last_read_at).
  module Chat
    PAGE_SIZE = 50
    MAX_BODY = 2000
    UUID = /\A[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}\z/

    # The coach writes a text message, replicating Node's sendCoachMessage transactionally:
    # lock the conversation row, verify ownership + chat open, insert the message, bump
    # last_message_at, and collapse-or-insert the client's new_message notification. A `client_ref`
    # makes a retried send idempotent (the shared (conversation_id, client_ref) unique index).
    def self.send_text!(coach, conversation_id, body:, client_ref: nil, now: Time.current)
      text = body.to_s.strip
      raise ApiError.new(400, "validation failed") if text.empty? || text.length > MAX_BODY
      raise ApiError.new(400, "validation failed") if client_ref.present? && !client_ref.match?(UUID)

      Conversation.transaction do
        # FOR UPDATE on the conversation row: serialises the notification collapse below.
        conversation = Conversation.lock.find_by(id: conversation_id)
        subscription = conversation&.subscription
        raise ApiError.new(404, "conversation not found") unless subscription&.coach_id == coach.id
        raise ApiError.new(409, "chat closed") unless open?(subscription, now)

        if client_ref.present?
          existing = conversation.messages.find_by(client_ref: client_ref)
          return MessageJson.call(existing, conversation.id) if existing
        end

        message = conversation.messages.create!(
          sender_type: "coach", sender_id: coach.id, body: text,
          client_ref: client_ref.presence, sent_at: now,
        )
        conversation.update!(last_message_at: now)
        collapse_client_notification!(conversation, subscription, coach, text)
        MessageJson.call(message, conversation.id)
      end
    end

    PHOTO_MAGIC = { "image/jpeg" => "\xFF\xD8\xFF".b, "image/png" => "\x89PNG".b }.freeze
    PHOTO_EXT = { "image/jpeg" => "jpg", "image/png" => "png" }.freeze

    # The coach sends a photo message. Same validation as the Node client photo path (jpeg/png by
    # magic bytes, size cap), stored in the shared attachment storage under the same key shape, then
    # the same lock / bump / collapse as a text message.
    def self.send_photo!(coach, conversation_id, file, client_ref: nil, now: Time.current)
      mime = check_photo!(file)
      raise ApiError.new(400, "validation failed") if client_ref.present? && !client_ref.match?(UUID)

      Conversation.transaction do
        conversation = Conversation.lock.find_by(id: conversation_id)
        subscription = conversation&.subscription
        raise ApiError.new(404, "conversation not found") unless subscription&.coach_id == coach.id
        raise ApiError.new(409, "chat closed") unless open?(subscription, now)

        if client_ref.present?
          existing = conversation.messages.find_by(client_ref: client_ref)
          return MessageJson.call(existing, conversation.id) if existing
        end

        id = SecureRandom.uuid
        key = "chat/#{conversation.id}/#{id}.#{PHOTO_EXT.fetch(mime)}"
        Storage.current.put(key, file.read, mime_type: mime)
        begin
          message = conversation.messages.create!(
            id: id, sender_type: "coach", sender_id: coach.id,
            attachment_key: key, attachment_mime: mime, client_ref: client_ref.presence, sent_at: now,
          )
        rescue StandardError
          begin
            Storage.current.delete(key)
          rescue StandardError
            nil
          end
          raise
        end
        conversation.update!(last_message_at: now)
        collapse_client_notification!(conversation, subscription, coach, "صورة")
        MessageJson.call(message, conversation.id)
      end
    end

    # A photo of a message in one of the coach's conversations: a signed URL, or the bytes.
    def self.photo(coach, conversation_id, message_id)
      conversation = find_owned!(coach, conversation_id)
      message = conversation.messages.find_by(id: message_id)
      raise ApiError.new(404, "not found") unless message&.attachment_key

      url = Storage.current.download_url(message.attachment_key, 300)
      { mime: message.attachment_mime, url: url, bytes: url ? nil : Storage.current.read(message.attachment_key) }
    rescue Storage::NotFound, Storage::InvalidKey
      raise ApiError.new(404, "not found")
    end

    def self.check_photo!(file)
      raise ApiError.new(400, "validation failed") unless file.respond_to?(:read) && file.respond_to?(:content_type)

      mime = file.content_type.to_s.split(";").first.to_s.strip.downcase
      raise ApiError.new(400, "unsupported file type") unless PHOTO_MAGIC.key?(mime)
      raise ApiError.new(400, "file too large") if file.size > ENV.fetch("UPLOAD_MAX_BYTES", 8_000_000).to_i

      magic = PHOTO_MAGIC.fetch(mime)
      head = file.read(magic.bytesize).to_s.b
      file.rewind
      raise ApiError.new(400, "file content does not match its type") unless head == magic

      mime
    end
    private_class_method :check_photo!

    # At most one unread `new_message` toward the client per conversation (serialised by the row
    # lock the caller holds). Mirrors Node recordClientNotification + the collapse check.
    def self.collapse_client_notification!(conversation, subscription, coach, preview)
      unread = Notification
        .where(recipient_type: "client", recipient_id: subscription.client_id, type: "new_message", read_at: nil)
        .where("data->>'conversationId' = ?", conversation.id)
        .exists?
      return if unread

      Notification.create!(
        recipient_type: "client", recipient_id: subscription.client_id, type: "new_message",
        title: coach.full_name, body: preview[0, 100],
        data: { "conversationId" => conversation.id, "subscriptionId" => subscription.id },
      )
    end
    private_class_method :collapse_client_notification!

    # The coach's conversations, most recent activity first, with an unread count and preview.
    def self.list(coach)
      conversations =
        Conversation
          .joins(:subscription)
          .where(subscriptions: { coach_id: coach.id })
          .includes(subscription: :client)
          .order(Arel.sql("conversations.last_message_at DESC NULLS LAST"))
          .to_a
      { conversations: conversations.map { |c| ConversationJson.list_item(c, unread_count(c)) } }
    end

    # One conversation's messages, newest-page first then returned oldest→newest; keyset-paginated
    # by `before` (a message id) like the client read. Ownership-checked.
    def self.messages(coach, conversation_id, before: nil)
      conversation = find_owned!(coach, conversation_id)
      scope = conversation.messages.order(sent_at: :desc, id: :desc)
      if before.present?
        cursor = conversation.messages.find_by(id: before) || raise(ApiError.new(404, "not found"))
        scope = scope.where("(messages.sent_at, messages.id) < (?, ?)", cursor.sent_at, cursor.id)
      end
      rows = scope.limit(PAGE_SIZE + 1).to_a
      has_more = rows.size > PAGE_SIZE
      page = rows.first(PAGE_SIZE).reverse
      {
        messages: page.map { |m| MessageJson.call(m, conversation.id) },
        hasMore: has_more,
        unreadCount: unread_count(conversation),
      }
    end

    # Mark every client message read for the coach by advancing the read cursor.
    def self.mark_read!(coach, conversation_id, now = Time.current)
      conversation = find_owned!(coach, conversation_id)
      conversation.update!(coach_last_read_at: now)
      { readAt: now.iso8601 }
    end

    def self.find_owned!(coach, conversation_id)
      Conversation
        .joins(:subscription)
        .where(subscriptions: { coach_id: coach.id })
        .find_by(id: conversation_id) || raise(ApiError.new(404, "conversation not found"))
    end

    # Client messages the coach hasn't read: those sent after the cursor (all of them if never read).
    def self.unread_count(conversation)
      scope = conversation.messages.where(sender_type: "client")
      cursor = conversation.coach_last_read_at
      scope = scope.where("messages.sent_at > ?", cursor) if cursor
      scope.count
    end

    # A chat is open while the subscription is active and not past its end (mirrors Node isChatOpen).
    def self.open?(subscription, now = Time.current)
      subscription.status == "active" && subscription.ends_at > now
    end
  end
end
