module Admin
  class CoachesController < BaseController
    STATUSES = %w[incomplete pending_review approved rejected suspended deactivated].freeze

    # The coaches list: every coach, optionally filtered by status and a name/phone/email
    # search. Defaults to showing those waiting for review first, newest submission first.
    def index
      @status = params[:status].presence_in(STATUSES)
      @query  = params[:q].to_s.strip

      scope = Coach.all
      scope = scope.where(status: @status) if @status
      if @query.present?
        like = "%#{@query}%"
        scope = scope.where("full_name ILIKE :q OR phone ILIKE :q OR email ILIKE :q", q: like)
      end

      @counts  = Coach.group(:status).count
      @coaches = scope.order(Arel.sql("profile_submitted_at DESC NULLS LAST, created_at DESC"))
    end

    def show
      @coach = Coach.find(params[:id])
      @documents = @coach.coach_documents.order(:type)
      @tab = params[:tab] == "clients" ? "clients" : "profile"

      return unless @tab == "clients"

      @client_filter = params[:filter] == "all" ? "all" : "active"
      @clients = Admin::CoachClientsQuery.call(
        coach: @coach, filter: @client_filter, page: params[:page].to_i, per_page: 25,
      )
    end

    # Streams one of a coach's documents (ID/certificate images) for review. No-store, since
    # these are sensitive; only a signed-in admin reaches it (require_admin in the base).
    def document
      coach = Coach.find(params[:id])
      doc = coach.coach_documents.find(params[:document_id])
      download = CoachApp::Documents.download(doc)
      response.headers["Cache-Control"] = "no-store"
      if download[:url]
        redirect_to download[:url], allow_other_host: true
      else
        send_data download[:bytes], type: doc.mime_type, disposition: "inline"
      end
    rescue ActiveRecord::RecordNotFound, ApiError
      head :not_found
    end

    def approve
      coach = Coach.find(params[:id])
      decision(coach, "Coach approved.") { Admin::CoachDecision.approve!(coach: coach, admin: current_admin, commission: params[:commission]) }
    end

    def request_changes
      coach = Coach.find(params[:id])
      decision(coach, "Changes requested.") { Admin::CoachDecision.request_changes!(coach: coach, admin: current_admin, reason: params[:reason]) }
    end

    def reject
      coach = Coach.find(params[:id])
      decision(coach, "Coach rejected.") { Admin::CoachDecision.reject!(coach: coach, admin: current_admin, reason: params[:reason]) }
    end

    def suspend
      coach = Coach.find(params[:id])
      decision(coach, "Coach suspended.") { Admin::CoachDecision.suspend!(coach: coach, admin: current_admin, reason: params[:reason]) }
    end

    def reactivate
      coach = Coach.find(params[:id])
      decision(coach, "Coach reactivated.") { Admin::CoachDecision.reactivate!(coach: coach, admin: current_admin, reason: params[:reason]) }
    end

    def deactivate
      coach = Coach.find(params[:id])
      decision(coach, "Coach deactivated.") { Admin::CoachDecision.deactivate!(coach: coach, admin: current_admin, reason: params[:reason]) }
    end

    private

    def decision(coach, notice)
      yield
      flash[:notice] = notice
    rescue Admin::CoachDecision::Error => e
      flash[:alert] = e.message
    ensure
      redirect_to admin_coach_path(coach)
    end
  end
end
