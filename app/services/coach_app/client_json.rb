module CoachApp
  module ClientJson
    def self.list_item(subscription, is_new:)
      {
        subscriptionId: subscription.id,
        clientId: subscription.client_id,
        fullName: subscription.client.full_name,
        status: subscription.status,
        since: subscription.created_at.iso8601,
        questionnaireSubmitted: !subscription.questionnaire_submitted_at.nil?,
        isNew: is_new
      }
    end

    def self.detail(subscription, health, answered)
      {
        client: {
          fullName: subscription.client.full_name,
          status: subscription.status,
          since: subscription.created_at.iso8601,
          questionnaireSubmitted: !subscription.questionnaire_submitted_at.nil?
        },
        health: health && health_json(health),
        questionnaire: { questions: answered.map { |a| question_json(a) } }
      }
    end

    def self.health_json(health)
      {
        dateOfBirth: health.date_of_birth&.to_s,
        gender: health.gender,
        heightCm: health.height_cm&.to_f,
        weightKg: health.weight_kg&.to_f,
        activityLevel: health.activity_level,
        goal: health.goal,
        targetWeightKg: health.target_weight_kg&.to_f,
        allergies: health.allergies,
        avoidedFoods: health.avoided_foods
      }
    end
    private_class_method :health_json

    def self.question_json(answered)
      question = answered[:question]
      {
        id: question.id,
        position: question.position,
        type: question.type,
        label: question.label,
        options: question.options,
        required: question.required,
        answer: answered[:answer]
      }
    end
    private_class_method :question_json
  end
end
