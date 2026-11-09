module CoachApp
  class MeController < BaseController
    def show
      render_success({ coach: CoachJson.call(current_coach) })
    end
  end
end
