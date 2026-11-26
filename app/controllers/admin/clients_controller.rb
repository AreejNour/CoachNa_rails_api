module Admin
  # Clients management (M37b): an all-clients list with status filter + search, a detail page,
  # and the suspend / reactivate / deactivate account actions (via Admin::ClientDecision).
  class ClientsController < BaseController
    STATUSES = %w[active suspended deactivated].freeze

    def index
      @status = params[:status].presence_in(STATUSES)
      @query  = params[:q].to_s.strip

      @counts  = Client.group(:status).count
      @clients = Client.for_status(@status).search(@query).order(created_at: :desc)
    end

    def show
      @client = Client.includes(:client_health_profile, subscriptions: [ :coach, :coach_package ]).find(params[:id])
      @profile = @client.client_health_profile
    end

    def suspend
      client = Client.find(params[:id])
      decision(client, "Client suspended.") { Admin::ClientDecision.suspend!(client: client) }
    end

    def reactivate
      client = Client.find(params[:id])
      decision(client, "Client reactivated.") { Admin::ClientDecision.reactivate!(client: client) }
    end

    def deactivate
      client = Client.find(params[:id])
      decision(client, "Client deactivated.") { Admin::ClientDecision.deactivate!(client: client) }
    end

    private

    def decision(client, notice)
      yield
      flash[:notice] = notice
    rescue Admin::ClientDecision::Error => e
      flash[:alert] = e.message
    ensure
      redirect_to admin_client_path(client)
    end
  end
end
