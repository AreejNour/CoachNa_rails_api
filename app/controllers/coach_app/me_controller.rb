module CoachApp
  class MeController < BaseController
    def show
      render_success({ coach: CoachJson.call(current_coach) })
    end

    # Allowed in every status: the email is for notifications, not part of the reviewed profile.
    def update_email
      current_coach.update!(email: Input.email(params[:email]))
      render_success({ coach: CoachJson.call(current_coach) })
    rescue ActiveRecord::RecordNotUnique
      raise ApiError.new(409, "email already registered")
    end
  end
end
