module CoachApp
  # Reads a coach's questionnaire (PDF, Word, photo or pasted text) into questions.
  module QuestionnaireImport
    # No usable answer from the model (refusal, cut off, not JSON).
    class Unreadable < StandardError; end

    # The model could not be reached (no key, network, API error).
    class Unavailable < StandardError; end
  end
end
