module CoachApp
  class ClientsController < BaseController
    def index
      render_success(Clients.list(current_coach))
    end

    def show
      render_success(Clients.detail(current_coach, params[:id]))
    end

    def mark_seen
      Notifications.mark_seen(current_coach)
      render_success({})
    end
  end
end
