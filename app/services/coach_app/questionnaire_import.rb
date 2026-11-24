module CoachApp
  # Reads a coach's questionnaire (PDF, Word, photo or pasted text) into questions for the coach
  # to review. Nothing is saved here: the app saves what the coach keeps through bulk create.
  module QuestionnaireImport
    UNREADABLE = "couldn't read a questionnaire in this file".freeze
    LANGUAGES = %w[ar en].freeze

    # No usable answer from the model (refusal, cut off, not JSON).
    class Unreadable < StandardError; end

    # The model could not be reached (no key, network, API error).
    class Unavailable < StandardError; end

    # Returns { questions:, skipped:, truncated: }.
    def self.call(coach, file:, text:, language:)
      source = Source.from(file: file, text: text)
      language = LANGUAGES.include?(language) ? language : "en"
      labels = Questions.list(coach).map(&:label)
      raw = Reader.call(source, existing_labels: labels, language: language)
      normalized = Normalizer.call(raw, language: language)
      raise ApiError.new(422, UNREADABLE) if normalized[:questions].empty? && normalized[:skipped].empty?

      normalized
    rescue Unreadable => e
      Rails.logger.warn("questionnaire import unreadable: #{e.message}")
      raise ApiError.new(422, UNREADABLE)
    rescue Unavailable => e
      Rails.logger.error("questionnaire import reader unavailable: #{e.message}")
      raise ApiError.new(502, "couldn't reach the questionnaire reader, try again")
    end
  end
end
