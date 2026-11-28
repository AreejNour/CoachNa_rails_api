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

    def new
      @form = {}
    end

    def create
      attrs = params[:coach].is_a?(ActionController::Parameters) ? params[:coach] : ActionController::Parameters.new
      @coach = Admin::CoachCreation.call(admin: current_admin, params: attrs)
      redirect_to admin_coach_path(@coach), notice: "Coach created and approved. Setup email sent."
    rescue Admin::CoachCreation::Invalid => e
      @errors = e.errors + [ "Choose the files again." ]
      @form = attrs.respond_to?(:permit) ? attrs.permit(:full_name, :phone, :country, :email, :bio, :years_experience, :commission, :gender, :date_of_birth, specialties: []).to_h : {}
      render :new, status: :unprocessable_entity
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

    # Any status: an admin can give an approved coach a gender and date of birth the coach app can't edit.
    def update_details
      coach = Coach.find(params[:id])
      coach.assign_attributes(gender: params[:gender].presence, date_of_birth: parse_date(params[:date_of_birth]))
      if coach.gender.nil? || coach.date_of_birth.nil?
        flash[:alert] = "Choose a gender and a valid date of birth."
      elsif coach.save
        flash[:notice] = "Coach details saved."
      else
        flash[:alert] = coach.errors.include?(:date_of_birth) ? "Date of birth must be a real date, not in the future, and 18 or older." : coach.errors.full_messages.to_sentence
      end
      redirect_to(safe_admin_return_to(params[:return_to]) || admin_coach_path(coach))
    end

    def send_password_email
      coach = Coach.find(params[:id])
      if coach.email.blank? || !%w[approved suspended].include?(coach.status)
        flash[:alert] = "This coach cannot receive a set-password email."
      else
        Admin::CoachPasswordSetup.send_email!(coach)
        flash[:notice] = "Set-password email sent."
      end
      redirect_to(safe_admin_return_to(params[:return_to]) || admin_coach_path(coach))
    end

    private

    def parse_date(value)
      Date.iso8601(value.to_s) if value.to_s.match?(/\A\d{4}-\d{2}-\d{2}\z/)
    rescue Date::Error
      nil
    end

    def decision(coach, notice)
      yield
      flash[:notice] = notice
    rescue Admin::CoachDecision::Error => e
      flash[:alert] = e.message
    ensure
      redirect_to(safe_admin_return_to(params[:return_to]) || admin_coach_path(coach))
    end
  end
end
