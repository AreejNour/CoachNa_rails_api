module CoachApp
  # Read a coach's subscribers from the shared database: the client list, and one client's health
  # profile and questionnaire answers. Everything is reached through the coach's own subscriptions,
  # so a coach only ever sees their own clients.
  module Clients
    CURRENT_STATUSES = %w[awaiting_questionnaire awaiting_plan active].freeze

    def self.list(coach)
      subscriptions = Subscriptions.visible_to_coach(coach)
                           .where(status: CURRENT_STATUSES)
                           .order(created_at: :desc)
                           .includes(:client)
      new_ids = unread_new_client_subscription_ids(coach)
      clients = subscriptions.map { |s| ClientJson.list_item(s, is_new: new_ids.include?(s.id)) }
      { clients: clients, newCount: clients.count { |c| c[:isNew] } }
    end

    def self.detail(coach, subscription_id)
      subscription = Subscriptions.visible_to_coach(coach).find_by(id: subscription_id) ||
        raise(ApiError.new(404, "client not found"))
      health = ClientHealthProfile.find_by(client_id: subscription.client_id)
      ClientJson.detail(subscription, health, answered_questions(coach, subscription))
    end

    # A client's photo answer, only through a subscription the coach can see (never an unpaid one):
    # a signed URL, or the bytes. Same shape as Chat.photo.
    def self.answer_photo(coach, subscription_id, question_id)
      subscription = Subscriptions.visible_to_coach(coach).find_by(id: subscription_id)
      answer = subscription && coach.questionnaire&.questionnaire_questions&.find_by(id: question_id)&.then do |question|
        QuestionnaireAnswer.find_by(subscription_id: subscription.id, question_id: question.id)
      end
      raise ApiError.new(404, "not found") unless answer&.photo_storage_key

      key = answer.photo_storage_key
      url = Storage.current.download_url(key, 300)
      { mime: photo_mime(key), url: url, bytes: url ? nil : Storage.current.read(key) }
    rescue Storage::NotFound, Storage::InvalidKey
      raise ApiError.new(404, "not found")
    end

    # The answer row keeps no MIME type; the key's extension (jpg/jpeg/png only) says which it is.
    def self.photo_mime(key)
      File.extname(key).casecmp?(".png") ? "image/png" : "image/jpeg"
    end
    private_class_method :photo_mime

    # Each of the coach's questions paired with this subscription's answer, in position order.
    # An archived question is kept only if the client answered it, so the coach still sees the answer.
    def self.answered_questions(coach, subscription)
      questionnaire = coach.questionnaire
      return [] unless questionnaire

      answers = QuestionnaireAnswer.where(subscription_id: subscription.id).index_by(&:question_id)
      questionnaire.questionnaire_questions.order(:position).filter_map do |question|
        answer = answers[question.id]
        next if question.is_archived && answer.nil?

        { question: question, answer: answer&.answer, photo_storage_key: answer&.photo_storage_key }
      end
    end
    private_class_method :answered_questions

    def self.unread_new_client_subscription_ids(coach)
      Notification
        .where(recipient_type: "coach", recipient_id: coach.id, type: "new_client", read_at: nil)
        .pluck(Arel.sql("data->>'subscriptionId'"))
        .compact
        .to_set
    end
    private_class_method :unread_new_client_subscription_ids
  end
end
