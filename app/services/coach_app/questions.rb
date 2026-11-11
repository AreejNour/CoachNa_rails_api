module CoachApp
  # Build, edit, list and archive the questions in a coach's questionnaire. A coach has at most one
  # questionnaire (created on the first question); every question is reached through it, so a coach
  # only ever touches their own. The `questionnaires` and `questionnaire_questions` tables are shared
  # with the Node API, which reads non-archived questions, in position order, for the client app.
  module Questions
    TYPES = %w[text number single_choice multi_choice yes_no date].freeze
    CHOICE_TYPES = %w[single_choice multi_choice].freeze
    LABEL_MAX = 200
    OPTIONS_MIN = 2
    OPTIONS_MAX = 20
    OPTION_LABEL_MAX = 120
    DEFAULT_TITLE = "New client questionnaire"

    def self.list(coach)
      questionnaire = coach.questionnaire
      return [] unless questionnaire

      questionnaire.questionnaire_questions.where(is_archived: false).order(:position).to_a
    end

    def self.create!(coach, attrs)
      type = valid_type(attrs["type"])
      label = Input.trimmed(attrs["label"], max: LABEL_MAX)
      required = valid_required(attrs.key?("required") ? attrs["required"] : true)
      options = valid_options(attrs["options"], type)

      questionnaire = coach.questionnaire || coach.create_questionnaire!(title: DEFAULT_TITLE)
      position = questionnaire.questionnaire_questions.maximum(:position).to_i + 1
      questionnaire.questionnaire_questions.create!(
        type: type, label: label, required: required, options: options, position: position
      )
    end

    # A PATCH touches only the keys present, and never the type (changing it would strand answers).
    # An empty patch is itself invalid.
    def self.update!(coach, id, attrs)
      question = find_owned!(coach, id)
      changes = {}
      changes[:label] = Input.trimmed(attrs["label"], max: LABEL_MAX) if attrs.key?("label")
      changes[:required] = valid_required(attrs["required"]) if attrs.key?("required")
      changes[:options] = valid_options(attrs["options"], question.type) if attrs.key?("options")
      Input.invalid! if changes.empty?

      question.update!(changes)
      question
    end

    def self.archive!(coach, id)
      find_owned!(coach, id).update!(is_archived: true)
      nil
    end

    def self.find_owned!(coach, id)
      question = coach.questionnaire&.questionnaire_questions&.where(is_archived: false)&.find_by(id: id)
      question || raise(ApiError.new(404, "question not found"))
    end

    def self.valid_type(value)
      Input.invalid! unless TYPES.include?(value)
      value
    end
    private_class_method :valid_type

    def self.valid_required(value)
      Input.invalid! unless [ true, false ].include?(value)
      value
    end
    private_class_method :valid_required

    # Choice types need 2–20 options with unique, non-empty labels; other types carry none.
    # Each option keeps the key it was sent with (so a relabel never changes a past answer) and a
    # new option gets a fresh key.
    def self.valid_options(raw, type)
      unless CHOICE_TYPES.include?(type)
        Input.invalid! if raw.present?
        return nil
      end

      Input.invalid! unless raw.is_a?(Array) && raw.length.between?(OPTIONS_MIN, OPTIONS_MAX)
      labels = []
      raw.map do |opt|
        Input.invalid! unless opt.is_a?(Hash) || opt.is_a?(ActionController::Parameters)
        label = Input.trimmed(opt["label"], max: OPTION_LABEL_MAX)
        Input.invalid! if labels.include?(label)
        labels << label
        { "key" => option_key(opt["key"]), "label" => label }
      end
    end
    private_class_method :valid_options

    def self.option_key(value)
      value.is_a?(String) && !value.strip.empty? ? value : "opt_#{SecureRandom.alphanumeric(8).downcase}"
    end
    private_class_method :option_key
  end
end
