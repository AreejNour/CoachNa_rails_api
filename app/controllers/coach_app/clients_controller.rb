module CoachApp
  class ClientsController < BaseController
    def index
      render_success(Clients.list(current_coach))
    end

    def show
      render_success(Clients.detail(current_coach, params[:id]))
    end

    def answer_photo
      download = Clients.answer_photo(current_coach, params[:id], params[:question_id])
      response.headers["Cache-Control"] = "no-store"
      if download[:url]
        redirect_to download[:url], allow_other_host: true
      else
        send_data download[:bytes], type: download[:mime], disposition: "inline"
      end
    end

    def mark_seen
      Notifications.mark_seen(current_coach)
      render_success({})
    end
  end
end
