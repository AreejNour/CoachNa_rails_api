require "anthropic"

module CoachApp
  module PlanImport
    # The only class that touches the network. Sends the PDF to Claude and returns the raw plan
    # hash (shape in SCHEMA) for the Normalizer; trusts nothing in it.
    module Reader
      MODEL = :"claude-opus-5-5"
      MAX_TOKENS = 64_000
      # Per attempt in the SDK, so no retries: the answer (or 502) must come before the app's 120 s.
      TIMEOUT_SECONDS = 100
      MAX_RETRIES = 0
      ITEM_KINDS = %w[food macro portion text].freeze
      UNITS = %w[g ml piece tbsp tsp cup].freeze
      SLOTS = %w[breakfast lunch dinner snack].freeze
      MACROS = %w[protein carbs fat].freeze
      PORTION_GROUPS = %w[carb protein fat fruit dairy vegetable].freeze

      def self.nullable(type, **rest) = { type: [ type, "null" ], **rest }

      ITEM = {
        type: "object", additionalProperties: false,
        required: %w[kind foodId quantity unit preparation macro grams portionGroup portionCount text sourceLine doubt],
        properties: {
          kind: { type: "string", enum: ITEM_KINDS },
          foodId: nullable("string"),
          quantity: nullable("number"),
          unit: { type: [ "string", "null" ], enum: UNITS + [ nil ] },
          preparation: nullable("string"),
          macro: { type: [ "string", "null" ], enum: MACROS + [ nil ] },
          grams: nullable("number"),
          portionGroup: { type: [ "string", "null" ], enum: PORTION_GROUPS + [ nil ] },
          portionCount: nullable("number"),
          text: nullable("string"),
          sourceLine: { type: "string" },
          doubt: nullable("string")
        }
      }.freeze

      SCHEMA = {
        type: "object", additionalProperties: false, required: %w[tips options],
        properties: {
          tips: nullable("string"),
          options: {
            type: "array",
            items: {
              type: "object", additionalProperties: false, required: %w[label meals],
              properties: {
                label: { type: "string" },
                meals: {
                  type: "array",
                  items: {
                    type: "object", additionalProperties: false, required: %w[title slot items],
                    properties: {
                      title: { type: "string" },
                      slot: { type: [ "string", "null" ], enum: SLOTS + [ nil ] },
                      items: { type: "array", items: ITEM }
                    }
                  }
                }
              }
            }
          }
        }
      }.freeze

      INSTRUCTIONS = <<~TEXT.freeze
        You read a nutrition coach's meal plan PDF and return it as structured data. The plan is
        usually written in the CoachNa template, in Arabic, English or both. Arabic text in PDFs
        can be extracted reversed by other tools; read the pages as a person would.

        Template: an optional TIPS / ملاحظات section (return it as "tips"); then OPTION 1, OPTION 2...
        (خيار ١...), one per page, each a day or a menu choice; each option holds meals (MEAL 1 /
        وجبة ١, Breakfast, Snack... any name); each meal holds lines, one item per line or joined
        by "+". The amount comes first. Return every option, meal and line in the order written.

        Every line becomes one item with exactly one kind:
        - food: a specific food with an amount, e.g. "150g chicken breast (cooked)". Set foodId to
          the id of the matching food in the list below, quantity, unit, and preparation
          ("cooked", "raw", "boiled"...) when the line says so.
        - macro: grams of a macro, e.g. "+ 30g protein". Set macro (protein, carbs or fat) and grams.
        - portion: a count of portions, e.g. "+ 1 carb". Set portionGroup (carb, protein, fat,
          fruit, dairy, vegetable; map Arabic equivalents) and portionCount.
        - text: anything else, e.g. "any snack below 150 kcal", or a line you cannot match.
          Put the line's words in text.

        Allowed units: g, ml, piece, tbsp, tsp, cup. Use piece, tbsp, tsp or cup only when the food's
        householdUnit is that unit. Otherwise use g or ml.

        Rules:
        - Never invent a foodId. Use only ids from the foods list. If no food matches, use kind text
          with foodId null and put the original line in text.
        - Set unused fields to null. Always copy the original line into sourceLine.
        - If a line offers alternatives ("1 tuna or 150 g fish"), use the first as the item and
          describe the other in doubt.
        - If you are unsure of a food match, an amount or a unit, still give your best reading and
          explain in doubt (one short sentence). Leave doubt null when sure.
        - Ignore pages and sections that are not the plan: recipes, FAQs, branding, cover pages,
          contact details and client details. If the file has no plan, return options: [].
        - A meal's slot is breakfast, lunch, dinner or snack when its name says so, otherwise null.
        - Never output anything except the JSON.

        The coach's foods (JSON lines: id, nameEn, nameAr, group, weightBasis, householdUnit):
      TEXT

      # foods: Food records visible to the coach. Returns a Hash (the model's answer, untrusted).
      # Raises Unreadable when there is no usable answer, Unavailable when there is none at all.
      def self.call(pdf_bytes, foods)
        key = ENV["ANTHROPIC_API_KEY"].to_s
        raise Unavailable, "ANTHROPIC_API_KEY is not set" if key.empty?

        message = client(key).beta.messages.stream(
          model: MODEL,
          max_tokens: MAX_TOKENS,
          thinking: { type: :adaptive },
          output_config: { effort: :medium, format: { type: :json_schema, schema: SCHEMA } },
          betas: [ :"server-side-fallback-2026-07-01" ],
          fallbacks: :default,
          system_: [
            { type: "text", text: INSTRUCTIONS + food_lines(foods), cache_control: { type: "ephemeral" } }
          ],
          messages: [ { role: "user", content: [
            { type: "document", source: { type: "base64", media_type: "application/pdf",
                                          data: Base64.strict_encode64(pdf_bytes) } },
            { type: "text", text: "Read this plan." }
          ] } ]
        ).accumulated_message
        parse(message)
      rescue Anthropic::Errors::Error => e
        raise Unavailable, e.class.name # class only: messages can quote request or response data
      end

      def self.client(key)
        Anthropic::Client.new(api_key: key, timeout: TIMEOUT_SECONDS, max_retries: MAX_RETRIES)
      end

      # Errors here must never carry model output or PDF text: they are logged.
      def self.parse(message)
        reason = message.stop_reason
        raise Unreadable, "stop_reason #{reason}" unless reason == :end_turn

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
        raise Unreadable, "output was not JSON"
      end

      def self.food_lines(foods)
        foods.map do |f|
          { id: f.id, nameEn: f.name_en, nameAr: f.name_ar, group: f.group,
            weightBasis: f.weight_basis, householdUnit: f.household_unit }.to_json
        end.join("\n")
      end
    end
  end
end
