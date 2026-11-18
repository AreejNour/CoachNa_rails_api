module CoachApp
  module PlanImport
    # Turns the reader's untrusted raw hash into the PlanInput wire shape (string keys, camelCase).
    # Anything doubtful is kept but carries an importFlag the coach must clear before publishing;
    # anything PlanInput could not accept becomes a flagged text line. Pure: no network, no writes.
    class Normalizer
      UNITS = %w[g ml piece tbsp tsp cup].freeze
      MAX_OPTIONS = 5
      MAX_MEALS = 30
      MAX_ITEMS = 30
      FLAG_MAX = PlanInput::IMPORT_FLAG_MAX
      UNMATCHED = "Couldn't match a food — pick one".freeze
      CHECK_AMOUNT = "Check this amount".freeze
      TOO_LONG = "Plan was longer than CoachNa allows — check the rest".freeze
      UNREADABLE = "(unreadable line)".freeze
      UNREADABLE_FLAG = "Couldn't read this line — check it".freeze

      def self.call(raw, visible_foods)
        new(visible_foods).call(raw)
      end

      def initialize(visible_foods)
        @visible = visible_foods
      end

      def call(raw)
        raw = {} unless raw.is_a?(Hash)
        raw = raw.deep_stringify_keys
        all = hashes(raw["options"])
        kept = all.first(MAX_OPTIONS)
        options = kept.each_with_index.map { |o, i| option(o, i) }
        options.compact!
        flag_last_item(options.last) if all.length > MAX_OPTIONS && options.any?
        { notes: clean(raw["tips"], PlanInput::NOTES_PLAN_MAX), options: options,
          flag_count: options.sum { |o| o["meals"].sum { |m| m["components"].count { |c| c["importFlag"] } } } }
      end

      private

      def option(raw, index)
        all = hashes(raw["meals"])
        meals = all.first(MAX_MEALS).each_with_index.filter_map { |m, i| meal(m, i) }
        return nil if meals.empty?

        meals.each_with_index do |m, i|
          m["position"] = i
          m["title"] ||= "Meal #{i + 1}"
        end
        option = { "label" => clean(raw["label"], PlanInput::LABEL_MAX) || "Option #{index + 1}",
                   "notes" => nil, "meals" => meals }
        flag_last_item(option) if all.length > MAX_MEALS
        option
      end

      def meal(raw, index)
        all = usable_items(raw["items"])
        items = all.first(MAX_ITEMS).map { |i| item(i) }
        return nil if items.empty?

        items.last["importFlag"] = join_flags(items.last["importFlag"], TOO_LONG) if all.length > MAX_ITEMS
        slot = PlanInput::SLOTS.include?(raw["slot"]) ? raw["slot"] : nil
        { "slot" => slot, "position" => index,
          "title" => clean(raw["title"], PlanInput::TITLE_MAX),
          "notes" => nil, "components" => items }
      end

      def flag_last_item(option)
        last = option["meals"].last["components"].last
        last["importFlag"] = join_flags(last["importFlag"], TOO_LONG)
      end

      # Hash entries pass through; a non-blank string becomes a flagged text line; the rest is skipped.
      def usable_items(value)
        return [] unless value.is_a?(Array)

        value.filter_map do |v|
          if v.is_a?(Hash) then v
          elsif clean(v, 1) then { "kind" => "text", "text" => v, "_from_string" => true }
          end
        end
      end

      # `flags` holds system flags only; the model's doubt is added last and trimmed to fit.
      def item(raw)
        flags = []
        built = case raw["kind"]
        when "food" then food_item(raw, flags)
        when "macro" then macro_item(raw, flags)
        when "portion" then portion_item(raw, flags)
        end
        built ||= text_item(raw, flags)
        built["importFlag"] = combine(flags, clean(raw["doubt"], FLAG_MAX))
        built
      end

      def combine(flags, doubt)
        system = flags.join("; ")
        return doubt if system.empty?

        room = FLAG_MAX - system.length - 2
        full = doubt && room > 0 ? "#{system}; #{doubt.slice(0, room)}" : system
        full.slice(0, FLAG_MAX)
      end

      def food_item(raw, flags)
        food = @visible[raw["foodId"]]
        unit = raw["unit"]
        qty = raw["quantity"]
        unless food && UNITS.include?(unit) && (%w[g ml].include?(unit) || unit == food.household_unit)
          flags.unshift(UNMATCHED) if food.nil?
          flags.unshift("Couldn't read the unit — check this line") if food && !UNITS.include?(unit)
          flags.unshift("Unit doesn't fit this food — check this line") if food && UNITS.include?(unit)
          return nil
        end
        unless number?(qty) && qty >= PlanInput::QTY_MIN && qty <= PlanInput::QTY_MAX
          flags.unshift(CHECK_AMOUNT)
          return nil
        end
        sane = %w[g ml].include?(unit) ? qty.between?(1, 2000) : qty.between?(0.25, 20)
        flags << CHECK_AMOUNT unless sane
        { "kind" => "food", "foodId" => raw["foodId"], "quantity" => qty, "unit" => unit,
          "preparation" => clean(raw["preparation"], PlanInput::PREP_MAX), "macro" => nil,
          "macroGrams" => nil, "portionGroup" => nil, "portionCount" => nil, "freeText" => nil }
      end

      def macro_item(raw, flags)
        grams = raw["grams"]
        unless PlanInput::MACROS.include?(raw["macro"]) && number?(grams) && grams > 0 &&
               grams <= PlanInput::MACRO_GRAMS_MAX
          flags.unshift(CHECK_AMOUNT)
          return nil
        end
        flags << CHECK_AMOUNT unless grams.between?(1, 200)
        { "kind" => "macro", "foodId" => nil, "quantity" => nil, "unit" => nil, "preparation" => nil,
          "macro" => raw["macro"], "macroGrams" => grams, "portionGroup" => nil,
          "portionCount" => nil, "freeText" => nil }
      end

      def portion_item(raw, flags)
        count = raw["portionCount"]
        unless PlanInput::PORTION_GROUPS.include?(raw["portionGroup"]) && number?(count) && count > 0 &&
               count <= PlanInput::PORTION_COUNT_MAX
          flags.unshift(CHECK_AMOUNT)
          return nil
        end
        flags << CHECK_AMOUNT unless count.between?(0.25, 20)
        { "kind" => "portion", "foodId" => nil, "quantity" => nil, "unit" => nil, "preparation" => nil,
          "macro" => nil, "macroGrams" => nil, "portionGroup" => raw["portionGroup"],
          "portionCount" => count, "freeText" => nil }
      end

      def text_item(raw, flags)
        text = clean(raw["sourceLine"], PlanInput::FREE_TEXT_MAX) || clean(raw["text"], PlanInput::FREE_TEXT_MAX)
        text = clean(raw["text"], PlanInput::FREE_TEXT_MAX) if raw["_from_string"]
        # Anything we invented or replaced (unknown kind, blank text, bare string) must be checked.
        flags << UNREADABLE_FLAG if flags.empty? && (raw["kind"] != "text" || text.nil? || raw["_from_string"])
        { "kind" => "text", "foodId" => nil, "quantity" => nil, "unit" => nil, "preparation" => nil,
          "macro" => nil, "macroGrams" => nil, "portionGroup" => nil, "portionCount" => nil,
          "freeText" => text || UNREADABLE }
      end

      def number?(value) = value.is_a?(Numeric) && value.finite?

      def hashes(value) = value.is_a?(Array) ? value.select { |v| v.is_a?(Hash) } : []

      # Trimmed, valid-encoding, null-free string cut to max; nil when nothing usable is left.
      def clean(value, max)
        return nil unless value.is_a?(String) && value.valid_encoding?

        text = value.delete("\0").strip
        text.empty? ? nil : text.slice(0, max)
      end

      def join_flags(existing, extra)
        return extra unless existing

        "#{existing.slice(0, FLAG_MAX - extra.length - 2)}; #{extra}"
      end
    end
  end
end
