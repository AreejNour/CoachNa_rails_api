module CoachApp
  # Validates and normalizes an authoring payload into a tree of plain hashes ready to insert:
  #   { notes:, options: [ { label:, notes:, meals: [ { slot:, position:, title:, notes:,
  #     components: [ { food_id:, quantity:, unit:, preparation:, free_text: } ] } ] } ] }
  # Mirrors the Node plan-input schema and publishPlan's food/unit guards so Rails-published plans
  # read back identically through Node's getMyPlan.
  module PlanInput
    SLOTS = %w[breakfast lunch dinner snack].freeze
    NOTES_PLAN_MAX = 4000
    NOTES_MAX = 2000
    LABEL_MAX = 100
    TITLE_MAX = 200
    PREP_MAX = 200
    FREE_TEXT_MAX = 200
    QTY_MIN = 0.01
    QTY_MAX = 99_999.99

    # `visible` is a {food_id => Food} map of what the coach may reference (CoachApp::Foods.visible_by_id).
    def self.validate(attrs, visible)
      Input.invalid! unless attrs.is_a?(ActionController::Parameters) || attrs.is_a?(Hash)

      options = array(attrs["options"], 1, 5) { |o| option(o, visible) }
      { notes: optional_notes(attrs["notes"], NOTES_PLAN_MAX), options: options }
    end

    def self.option(o, visible)
      Input.invalid! unless o.is_a?(ActionController::Parameters) || o.is_a?(Hash)
      {
        label: Input.trimmed(o["label"], max: LABEL_MAX),
        notes: optional_notes(o["notes"], NOTES_MAX),
        meals: array(o["meals"], 1, 30) { |m| meal(m, visible) }
      }
    end
    private_class_method :option

    def self.meal(m, visible)
      Input.invalid! unless m.is_a?(ActionController::Parameters) || m.is_a?(Hash)
      {
        slot: enum(m["slot"], SLOTS),
        position: non_negative_int(m["position"]),
        title: Input.trimmed(m["title"], max: TITLE_MAX),
        notes: optional_notes(m["notes"], NOTES_MAX),
        components: array(m["components"], 1, 30) { |c| component(c, visible) }
      }
    end
    private_class_method :meal

    def self.component(c, visible)
      Input.invalid! unless c.is_a?(ActionController::Parameters) || c.is_a?(Hash)
      food_id = c["foodId"]

      if food_id.nil?
        # Free-text component: free text only, nothing else.
        Input.invalid! if c["quantity"] || c["unit"] || c["preparation"]
        { food_id: nil, quantity: nil, unit: nil, preparation: nil,
          free_text: Input.trimmed(c["freeText"], max: FREE_TEXT_MAX) }
      else
        Input.invalid! if c["freeText"]
        food = visible[food_id] || raise(ApiError.new(400, "unknown food in plan"))
        unit = c["unit"]
        # Only units we can convert to grams, so Node's read-time macro maths never throws.
        unless unit == "g" || unit == "ml" || unit == food.household_unit
          raise ApiError.new(400, "unit not usable for this food")
        end
        { food_id: food_id, quantity: quantity(c["quantity"]), unit: unit,
          preparation: optional_trim(c["preparation"], PREP_MAX), free_text: nil }
      end
    end
    private_class_method :component

    def self.array(value, min, max)
      Input.invalid! unless value.is_a?(Array) && value.length.between?(min, max)
      value.map { |item| yield item }
    end
    private_class_method :array

    def self.enum(value, allowed)
      Input.invalid! unless allowed.include?(value)
      value
    end
    private_class_method :enum

    def self.non_negative_int(value)
      Input.invalid! unless value.is_a?(Integer) && value >= 0
      value
    end
    private_class_method :non_negative_int

    def self.quantity(value)
      Input.invalid! unless value.is_a?(Numeric) && value >= QTY_MIN && value <= QTY_MAX
      format("%.2f", value)
    end
    private_class_method :quantity

    def self.optional_notes(value, max)
      return nil if value.nil? || value == ""

      Input.trimmed(value, max: max)
    end
    private_class_method :optional_notes

    def self.optional_trim(value, max)
      return nil if value.nil? || value == ""

      Input.trimmed(value, max: max)
    end
    private_class_method :optional_trim
  end
end
