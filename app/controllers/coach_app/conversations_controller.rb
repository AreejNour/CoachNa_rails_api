module CoachApp
  class ConversationsController < BaseController
    def index
      render_success(Chat.list(current_coach))
    end

    def messages
      render_success(Chat.messages(current_coach, params[:id], before: params[:before]))
    end

    def read
      render_success(Chat.mark_read!(current_coach, params[:id]))
    end

    def send_message
      message = Chat.send_text!(current_coach, params[:id], body: params[:body], client_ref: params[:clientRef])
      render_success(message, status: :created)
    end

    def send_photo
      message = Chat.send_photo!(current_coach, params[:id], params[:photo], client_ref: params[:clientRef])
      render_success(message, status: :created)
    end

    def photo
      download = Chat.photo(current_coach, params[:id], params[:message_id])
      response.headers["Cache-Control"] = "no-store"
      if download[:url]
        redirect_to download[:url], allow_other_host: true
      else
        send_data download[:bytes], type: download[:mime], disposition: "inline"
      end
    end
  end
end
