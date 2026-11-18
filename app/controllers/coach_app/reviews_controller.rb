module CoachApp
  class ReviewsController < BaseController
    def index
      render_success(Reviews.list(current_coach))
    end

    def photo
      download = Reviews.photo(current_coach, params[:id])
      response.headers["Cache-Control"] = "no-store"
      if download[:url]
        redirect_to download[:url], allow_other_host: true
      else
        send_data download[:bytes], type: download[:mime], disposition: "inline"
      end
    end
  end
end
