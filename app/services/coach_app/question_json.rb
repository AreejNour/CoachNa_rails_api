module CoachApp
  module QuestionJson
    def self.call(question)
      {
        id: question.id,
        type: question.type,
        label: question.label,
        options: question.options,
        required: question.required,
        position: question.position
      }
    end
  end
end
