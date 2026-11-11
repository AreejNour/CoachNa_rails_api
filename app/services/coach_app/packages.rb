module CoachApp
  # Create, edit, list and remove a coach's subscription packages. A package belongs to one coach;
  # a coach only ever reaches their own. Money is integer piastres, matching the shared column and
  # the client app's `pricePiastres`.
  module Packages
    NAME_MAX = 80
    DESCRIPTION_MAX = 2000
    PRICE_MIN = 1
    PRICE_MAX = 100_000_00 # 100,000 EGP, in piastres
    DURATION_MIN = 1
    DURATION_MAX = 365
    INCLUDES_MAX = 20
    INCLUDE_ITEM_MAX = 120

    def self.list(coach)
      coach.coach_packages.where(is_active: true).order(created_at: :desc).to_a
    end

    def self.create!(coach, attrs)
      coach.coach_packages.create!(validated(attrs, partial: false))
    end

    def self.update!(coach, id, attrs)
      package = find_owned!(coach, id)
      package.update!(validated(attrs, partial: true))
      package
    end

    def self.soft_delete!(coach, id)
      find_owned!(coach, id).update!(is_active: false)
      nil
    end

    def self.find_owned!(coach, id)
      coach.coach_packages.where(is_active: true).find_by(id: id) ||
        raise(ApiError.new(404, "package not found"))
    end

    # Builds the validated DB attributes. On create everything is required; on a PATCH only the
    # keys present are touched, and an empty PATCH is itself invalid.
    def self.validated(attrs, partial:)
      out = {}

      if !partial || given?(attrs, "name")
        out[:name] = Input.trimmed(attrs["name"], max: NAME_MAX)
      end

      if !partial || attrs.key?("description")
        out[:description] = valid_description(attrs["description"])
      end

      if !partial || given?(attrs, "pricePiastres")
        out[:price_piastres] = integer_in(attrs["pricePiastres"], PRICE_MIN, PRICE_MAX)
      end

      if !partial || given?(attrs, "durationDays")
        out[:duration_days] = integer_in(attrs["durationDays"], DURATION_MIN, DURATION_MAX)
      end

      if !partial || given?(attrs, "includes")
        out[:includes] = valid_includes(attrs["includes"])
      end

      Input.invalid! if out.empty?
      out
    end
    private_class_method :validated

    def self.given?(attrs, key)
      attrs.key?(key) && !attrs[key].nil?
    end
    private_class_method :given?

    def self.valid_description(value)
      return nil if value.nil? || value == ""

      unless value.is_a?(String) && value.valid_encoding? && !value.include?("\0") && value.length <= DESCRIPTION_MAX
        Input.invalid!
      end
      value
    end
    private_class_method :valid_description

    def self.integer_in(value, min, max)
      Input.invalid! unless value.is_a?(Integer) && value >= min && value <= max
      value
    end
    private_class_method :integer_in

    def self.valid_includes(value)
      Input.invalid! unless value.is_a?(Array) && value.length.between?(1, INCLUDES_MAX)

      value.map do |item|
        Input.invalid! unless item.is_a?(String) && item.valid_encoding? && !item.include?("\0")
        trimmed = item.strip
        Input.invalid! if trimmed.empty? || trimmed.length > INCLUDE_ITEM_MAX
        trimmed
      end
    end
    private_class_method :valid_includes
  end
end
