module CoachApp
  # The coach app's food shape. kcal is derived (Atwater 4/4/9), never stored; `isCustom` marks
  # the coach's own foods (vs the global/admin set).
  module FoodJson
    def self.call(food)
      protein = food.protein_per_100.to_f
      carbs = food.carbs_per_100.to_f
      fat = food.fat_per_100.to_f
      {
        id: food.id,
        nameAr: food.name_ar,
        nameEn: food.name_en,
        group: food.group,
        proteinPer100: food.protein_per_100.to_s,
        carbsPer100: food.carbs_per_100.to_s,
        fatPer100: food.fat_per_100.to_s,
        kcalPer100: (4 * protein + 4 * carbs + 9 * fat).round,
        weightBasis: food.weight_basis,
        householdUnit: food.household_unit,
        gramsPerUnit: food.grams_per_unit&.to_s,
        isCustom: food.owner_coach_id.present?
      }
    end
  end
end
