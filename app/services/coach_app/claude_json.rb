require "anthropic"

module CoachApp
  # The Claude call both importers' readers make (structured JSON out), and reading the JSON out
  # of the finished message. Each reader supplies only its schema, instructions and content.
  module ClaudeJson
    MODEL = :"claude-opus-5-5"
    # Per attempt in the SDK, so no retries: the answer (or 502) must come before the app's 120 s.
    TIMEOUT_SECONDS = 100
    MAX_RETRIES = 0

    # The model answered but there is nothing usable (refusal, cut off, not JSON).
    class Unreadable < StandardError; end
    # The model could not be reached (no key, network, API error).
    class Unavailable < StandardError; end

    def self.nullable(type, **rest) = { type: [ type, "null" ], **rest }

    def self.client(key)
      Anthropic::Client.new(api_key: key, timeout: TIMEOUT_SECONDS, max_retries: MAX_RETRIES)
    end

    # system: the cached instruction text. content: the user message's content blocks.
    # Returns a Hash (the model's answer, untrusted).
    # Raises Unreadable when there is no usable answer, Unavailable when there is none at all.
    def self.call(system:, content:, schema:, max_tokens:)
      key = ENV["ANTHROPIC_API_KEY"].to_s
      raise Unavailable, "ANTHROPIC_API_KEY is not set" if key.empty?

      message = client(key).beta.messages.stream(
        **request_params(system: system, content: content, schema: schema, max_tokens: max_tokens)
      ).accumulated_message
      parse(message, Unreadable)
    rescue Anthropic::Errors::Error => e
      raise Unavailable, e.class.name # class only: messages can quote request or response data
    end

    def self.request_params(system:, content:, schema:, max_tokens:)
      {
        model: MODEL,
        max_tokens: max_tokens,
        thinking: { type: :adaptive },
        output_config: { effort: :medium, format: { type: :json_schema, schema: schema } },
        betas: [ :"server-side-fallback-2026-07-01" ],
        fallbacks: :default,
        system_: [ { type: "text", text: system, cache_control: { type: "ephemeral" } } ],
        messages: [ { role: "user", content: content } ]
      }
    end

    # Runs the block; maps Unreadable to a 422 and Unavailable to a 502 with the given messages.
    # Logs only the error's message, which never carries model output or file text.
    def self.mapping_errors(label, unreadable:, unavailable:)
      yield
    rescue Unreadable => e
      Rails.logger.warn("#{label} unreadable: #{e.message}")
      raise ApiError.new(422, unreadable)
    rescue Unavailable => e
      Rails.logger.error("#{label} reader unavailable: #{e.message}")
      raise ApiError.new(502, unavailable)
    end

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
