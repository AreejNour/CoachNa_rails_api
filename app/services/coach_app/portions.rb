module CoachApp
  # Portion sizes: grams of the group's defining macro per one portion. Coaches may override
  # carb/protein/fat/fruit/dairy; vegetable has no size.
  module Portions
    STANDARD = { "carb" => 30.0, "protein" => 30.0, "fat" => 10.0, "fruit" => 15.0, "dairy" => 10.0 }.freeze
    MACRO = { "carb" => "carbs", "protein" => "protein", "fat" => "fat", "fruit" => "carbs",
              "dairy" => "protein", "vegetable" => nil }.freeze

    def self.sizes_for(coach)
      overrides = CoachPortionSize.where(coach_id: coach.id).pluck(:group, :grams_of_macro)
      STANDARD.merge(overrides.to_h { |group, grams| [ group, grams.to_f ] })
    end

    # Grams of the defining macro for `count` portions; nil when the group has no size.
    def self.target_grams(group, count, sizes)
      size = sizes[group]
      size && (count.to_f * size)
    end
  end
end
