module CoachApp
  class EarningsController < BaseController
    def show
      render_success(Earnings.summary(current_coach))
    end
  end
end
