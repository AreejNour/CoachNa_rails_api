module CoachApp
  # For routes that need a signed-in coach.
  class BaseController < ApplicationController
    before_action :require_coach!

    private

    attr_reader :current_coach

    def require_coach!
      header = request.headers["Authorization"].to_s
      coach_id = AccessToken.verify(header.delete_prefix("Bearer ")) if header.start_with?("Bearer ")
      @current_coach = Coach.find_by(id: coach_id) if coach_id
      raise ApiError.new(401, "unauthorized") unless current_coach
    end
  end
end
