module CoachApp
  # The foods a coach can use in a plan: the shared global set plus the coach's own custom foods.
  # Macros are per 100 g/ml. A coach only ever edits or removes their own foods. Removal is a
  # soft delete (is_active=false) because a published plan may reference the row (FK is RESTRICT).
  module Foods
    GROUPS = %w[carb protein fat fruit vegetable dairy free].freeze
    WEIGHT_BASES = %w[cooked raw as_is].freeze
    NAME_MAX = 200
    UNIT_MAX = 40

    def self.list(coach)
      Food
        .where(is_active: true)
        .where("owner_coach_id IS NULL OR owner_coach_id = ?", coach.id)
        .order(:group, :name_ar)
        .to_a
    end

    # The ids a coach may reference in a plan, as a Set, for input validation.
    def self.visible_by_id(coach)
      Food.where(is_active: true)
          .where("owner_coach_id IS NULL OR owner_coach_id = ?", coach.id)
          .index_by(&:id)
    end

    def self.create_custom!(coach, attrs)
      coach.foods.create!(validated(attrs, partial: false).merge(is_active: true))
    end

    def self.update_custom!(coach, id, attrs)
      food = find_owned!(coach, id)
      food.update!(validated(attrs, partial: true))
      food
    end

    def self.soft_delete!(coach, id)
      find_owned!(coach, id).update!(is_active: false)
      nil
    end

    def self.find_owned!(coach, id)
      coach.foods.where(is_active: true).find_by(id: id) ||
        raise(ApiError.new(404, "food not found"))
    end
    private_class_method :find_owned!

    # Builds validated DB attributes. On create everything required; on PATCH only present keys,
    # and an empty PATCH is invalid. householdUnit and gramsPerUnit are paired (both or neither).
    def self.validated(attrs, partial:)
      out = {}

      out[:name_ar] = Input.trimmed(attrs["nameAr"], max: NAME_MAX) if !partial || given?(attrs, "nameAr")
      out[:name_en] = Input.trimmed(attrs["nameEn"], max: NAME_MAX) if !partial || given?(attrs, "nameEn")
      out[:group] = enum(attrs["group"], GROUPS) if !partial || given?(attrs, "group")
      out[:protein_per_100] = macro(attrs["proteinPer100"]) if !partial || given?(attrs, "proteinPer100")
      out[:carbs_per_100] = macro(attrs["carbsPer100"]) if !partial || given?(attrs, "carbsPer100")
      out[:fat_per_100] = macro(attrs["fatPer100"]) if !partial || given?(attrs, "fatPer100")
      out[:weight_basis] = enum(attrs["weightBasis"], WEIGHT_BASES) if !partial || given?(attrs, "weightBasis")

      if !partial || attrs.key?("householdUnit") || attrs.key?("gramsPerUnit")
        unit, grams = household(attrs["householdUnit"], attrs["gramsPerUnit"])
        out[:household_unit] = unit
        out[:grams_per_unit] = grams
      end

      Input.invalid! if out.empty?
      out
    end
    private_class_method :validated

    def self.given?(attrs, key) = attrs.key?(key) && !attrs[key].nil?
    private_class_method :given?

    def self.enum(value, allowed)
      Input.invalid! unless allowed.include?(value)
      value
    end
    private_class_method :enum

    def self.macro(value)
      Input.invalid! unless value.is_a?(Numeric) && value >= 0 && value <= 100
      format("%.2f", value)
    end
    private_class_method :macro

    # A household unit needs a positive grams-per-unit, and vice versa; absent means both nil.
    def self.household(unit, grams)
      return [ nil, nil ] if unit.nil? && grams.nil?

      name = Input.trimmed(unit, max: UNIT_MAX)
      Input.invalid! unless grams.is_a?(Numeric) && grams > 0
      [ name, format("%.2f", grams) ]
    end
    private_class_method :household
  end
end
