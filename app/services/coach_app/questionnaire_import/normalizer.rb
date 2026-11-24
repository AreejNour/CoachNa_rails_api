module CoachApp
  module QuestionnaireImport
    # Cleans the Reader's untrusted answer into questions the questionnaire accepts. Never raises:
    # anything unusable is dropped, and anything it had to change gets a doubt note for the coach.
    module Normalizer
      REASONS = %w[health_profile already_in_questionnaire].freeze
      DOUBT_MAX = 300
      TEXT_MAX = 1_000
      NOTES = {
        "en" => { few_options: "Fewer than 2 options were found, so this became a text question.",
                  many_options: "Only the first %d options were kept.",
                  long_label: "The question was shortened to fit." },
        "ar" => { few_options: "تم العثور على أقل من خيارين، لذلك أصبح هذا السؤال نصيًا.",
                  many_options: "تم الاحتفاظ بأول %d خيارًا فقط.",
                  long_label: "تم اختصار السؤال ليناسب الحد المسموح." }
      }.freeze

      def self.call(raw, language:)
        raw = {} unless raw.is_a?(Hash)
        notes = NOTES.fetch(language, NOTES["en"])
        questions = list(raw["questions"]).filter_map { |q| question(q, notes) }
        {
          questions: questions.first(Questions::BULK_MAX),
          skipped: list(raw["skipped"]).filter_map { |s| skipped_item(s, notes) },
          truncated: questions.length > Questions::BULK_MAX
        }
      end

      def self.list(value) = value.is_a?(Array) ? value : []

      def self.question(raw, notes)
        return unless raw.is_a?(Hash)

        type = raw["type"]
        label = clean(raw["label"])
        return unless Questions::TYPES.include?(type) && label

        doubts = [ clean(raw["doubt"], max: DOUBT_MAX) ]
        if label.length > Questions::LABEL_MAX
          label = label[0, Questions::LABEL_MAX].rstrip
          doubts << notes[:long_label]
        end
        options = nil
        if Questions::CHOICE_TYPES.include?(type)
          options = options(raw["options"])
          if options.length < Questions::OPTIONS_MIN
            type = "text"
            options = nil
            doubts << notes[:few_options]
          elsif options.length > Questions::OPTIONS_MAX
            options = options.first(Questions::OPTIONS_MAX)
            doubts << format(notes[:many_options], Questions::OPTIONS_MAX)
          end
        end
        { type: type, label: label, required: raw["required"] != false,
          options: options&.map { |o| { label: o } }, doubt: doubts.compact.join(" ").presence }
      end

      def self.options(raw)
        seen = {}
        list(raw).each do |o|
          o = clean(o)
          next unless o

          o = o[0, Questions::OPTION_LABEL_MAX].rstrip
          seen[o.downcase] ||= o
        end
        seen.values
      end

      def self.skipped_item(raw, notes)
        return unless raw.is_a?(Hash) && REASONS.include?(raw["reason"])

        text = clean(raw["text"], max: TEXT_MAX)
        question = raw["reason"] == "already_in_questionnaire" ? question(raw["question"], notes) : nil
        text ||= question&.fetch(:label)
        return unless text

        { text: text, reason: raw["reason"], **(question ? { question: question } : {}) }
      end

      # A trimmed, non-blank String, cut to max when given; nil otherwise.
      def self.clean(value, max: nil)
        return unless value.is_a?(String)

        value = value.scrub.strip
        value = value[0, max].rstrip if max && value.length > max
        value.presence
      end
    end
  end
end
