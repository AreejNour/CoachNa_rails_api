module CoachApp
  class ReviewController < BaseController
    def status
      render_success(ReviewStatus.call(current_coach))
    end

    def submit
      render_success(ReviewStatus.submit!(current_coach))
    end
  end
end
