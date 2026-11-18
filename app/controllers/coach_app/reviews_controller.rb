module CoachApp
  class ReviewsController < BaseController
    def index
      render_success(Reviews.list(current_coach))
    end
  end
end
