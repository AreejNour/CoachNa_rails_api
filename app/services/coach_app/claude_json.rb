module CoachApp
  # Reads the JSON out of a finished Claude message. Shared by the importers' readers.
  module ClaudeJson
    # Errors here must never carry model output or file text: they are logged.
    def self.parse(message, error_class)
      reason = message.stop_reason
      raise error_class, "stop_reason #{reason}" unless reason == :end_turn

      # After a mid-stream fallback, the text before the `fallback` block is the declined
      # model's partial answer: read what follows it first, then everything.
      blocks = message.content
      last_fallback = blocks.rindex { |b| b.type == :fallback }
      candidates = []
      candidates << blocks.drop(last_fallback + 1) if last_fallback
      candidates << blocks
      candidates.each do |list|
        text = list.select { |b| b.type == :text }.map(&:text).join
        begin
          return JSON.parse(text)
        rescue JSON::ParserError
          next
        end
      end
      raise error_class, "output was not JSON"
    end
  end
end
