module CoachApp
  class ProfilesController < BaseController
    def update
      attributes = ProfileParams.parse(params)
      unless Coach::EDITABLE_STATUSES.include?(current_coach.status)
        raise ApiError.new(409, "profile not editable in current state")
      end

      current_coach.update!(attributes)
      render_success({ coach: CoachJson.call(current_coach) })
    rescue ActiveRecord::RecordNotUnique
      raise ApiError.new(409, "email already registered")
    end
  end
end
