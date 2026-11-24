module CoachApp
  # Reads a coach's questionnaire (PDF, Word, photo or pasted text) into questions for the coach
  # to review. Nothing is saved here: the app saves what the coach keeps through bulk create.
  module QuestionnaireImport
    UNREADABLE = "couldn't read a questionnaire in this file".freeze
    LANGUAGES = %w[ar en].freeze

    Unreadable = ClaudeJson::Unreadable
    Unavailable = ClaudeJson::Unavailable
    UNAVAILABLE = "couldn't reach the questionnaire reader, try again".freeze

    # Returns { questions:, skipped:, truncated: }.
    def self.call(coach, file:, text:, language:)
      ClaudeJson.mapping_errors("questionnaire import", unreadable: UNREADABLE, unavailable: UNAVAILABLE) do
        source = Source.from(file: file, text: text)
        language = LANGUAGES.include?(language) ? language : "en"
        labels = Questions.list(coach).map(&:label)
        raw = Reader.call(source, existing_labels: labels, language: language)
        normalized = Normalizer.call(raw, language: language)
        raise ApiError.new(422, UNREADABLE) if normalized[:questions].empty? && normalized[:skipped].empty?

        normalized
      end
    end
  end
end
