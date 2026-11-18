module CoachApp
  # The authoring shape of a plan: options → meals → components, structural only. Macros and
  # swaps are the Node client read's job; the coach app computes its live readout from the foods
  # list. `preloaded` is a {meal_id => [components]} / etc. built once to avoid N+1.
  module PlanJson
    def self.call(plan)
      {
        id: plan.id,
        version: plan.version,
        status: plan.status,
        notes: plan.notes,
        publishedAt: plan.published_at&.iso8601,
        options: plan.plan_options.map { |o| option(o) }
      }
    end

    def self.option(option)
      {
        id: option.id,
        position: option.position,
        label: option.label,
        notes: option.notes,
        meals: option.plan_meals.sort_by { |m| [ m.position, m.id ] }.map { |m| meal(m) }
      }
    end

    def self.meal(meal)
      {
        id: meal.id,
        slot: meal.slot,
        position: meal.position,
        title: meal.title,
        notes: meal.notes,
        components: meal.plan_meal_components.map { |c| component(c) }
      }
    end

    def self.component(component)
      food = component.food
      {
        id: component.id,
        position: component.position,
        kind: component.kind,
        food: food && { id: food.id, nameAr: food.name_ar, nameEn: food.name_en, group: food.group },
        quantity: component.quantity&.to_s,
        unit: component.unit,
        preparation: component.preparation,
        macro: component.macro,
        macroGrams: component.macro_grams&.to_f,
        portionGroup: component.portion_group,
        portionCount: component.portion_count&.to_f,
        freeText: component.free_text,
        importFlag: component.import_flag
      }
    end
  end
end
