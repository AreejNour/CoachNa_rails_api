module CoachApp
  class PortionSizesController < BaseController
    def show
      render_success(payload)
    end

    def update
      entries = parse_entries
      CoachPortionSize.transaction do
        entries.each do |group, grams|
          row = CoachPortionSize.find_by(coach_id: current_coach.id, group: group)
          if grams == Portions::STANDARD[group]
            row&.destroy!
          elsif row
            row.update!(grams_of_macro: grams)
          else
            CoachPortionSize.create!(coach_id: current_coach.id, group: group, grams_of_macro: grams)
          end
        end
      end
      render_success(payload)
    end

    private

    def payload
      sizes = Portions.sizes_for(current_coach)
      { sizes: Portions::STANDARD.keys.map do |group|
        { group: group, gramsOfMacro: sizes[group], macro: Portions::MACRO[group],
          isStandard: sizes[group] == Portions::STANDARD[group] }
      end }
    end

    # Validates the whole body first so a bad entry writes nothing.
    def parse_entries
      list = params[:sizes]
      raise ApiError.new(400, "sizes must be a list") unless list.is_a?(Array)

      entries = list.map do |item|
        raise ApiError.new(400, "invalid size") unless item.respond_to?(:key?)

        group = item[:group]
        grams = item[:gramsOfMacro]
        raise ApiError.new(400, "unknown group") unless group.is_a?(String) && Portions::STANDARD.key?(group)
        raise ApiError.new(400, "gramsOfMacro must be a number from 1 to 200") unless grams.is_a?(Numeric) && grams.between?(1, 200)

        [ group, grams.to_f ]
      end
      raise ApiError.new(400, "duplicate group") if entries.map(&:first).uniq.size != entries.size

      entries
    end
  end
end
