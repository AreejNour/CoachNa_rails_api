module Admin
  # Promo codes (step 1: CoachNa-funded codes). List with active / inactive / expired filters, create
  # and edit with a non-blocking "CoachNa loses money" check (Admin::PromoLossCheck), and switch off.
  # There is no delete: subscriptions keep pointing at the codes they used.
  #
  # The form posts money in EGP (a fixed value, the discount cap, the minimum price); the table keeps
  # piastres. Two extra submit buttons re-render the form without saving: `preview` (run the loss
  # check) and `search_clients` (look up clients for the allow-list, as the Clients page does).
  class PromoCodesController < BaseController
    CLIENT_SEARCH_LIMIT = 20

    before_action :load_code, only: %i[show edit update deactivate]

    def index
      @filter = params[:filter].presence_in(PromoCode::FILTERS)
      @codes = PromoCode.includes(:created_by_admin).for_filter(@filter).order(created_at: :desc).to_a
      @uses = PromoCode.paid_use_counts(@codes.map(&:id))
    end

    def show
      @uses = PromoCode.paid_use_counts([ @code.id ])[@code.id].to_i
      @loss = Admin::PromoLossCheck.call(@code)
      @allowed_clients = Client.where(id: @code.promo_code_clients.select(:client_id)).order(:full_name)
    end

    def new
      @code = PromoCode.new(kind: "percent", active: true)
      prepare_form
    end

    def create
      @code = PromoCode.new(funded_by: "platform", created_by_admin_id: current_admin.id)
      @code.assign_attributes(code_attributes)
      save_or_rerender(:new)
    end

    def edit
      prepare_form
    end

    def update
      @code.assign_attributes(code_attributes)
      save_or_rerender(:edit)
    end

    def deactivate
      # A column write: switching off must work even if the code no longer passes today's rules
      # (e.g. a fixed value above what the current packages allow).
      @code.update_columns(active: false, updated_at: Time.current)
      redirect_to admin_promo_code_path(@code), notice: "Promo code #{@code.code} switched off."
    end

    private

    def load_code
      @code = PromoCode.find(params[:id])
    end

    def save_or_rerender(template)
      if params[:preview].present? || params[:search_clients].present?
        @loss = Admin::PromoLossCheck.call(@code) if params[:preview].present?
        prepare_form(submitted: true)
        return render(template)
      end

      saved = PromoCode.transaction do
        next false unless @code.save

        @code.replace_clients!(selected_client_ids)
        true
      end

      if saved
        redirect_to admin_promo_code_path(@code), notice: "Promo code #{@code.code} saved."
      else
        prepare_form(submitted: true)
        render template, status: :unprocessable_entity
      end
    end

    def form_params
      params.fetch(:promo_code, {}).permit(
        :code, :kind, :value, :max_discount_egp, :min_price_egp, :restrict_coach_id, :restrict_package_id,
        :min_duration_days, :max_duration_days, :new_patients_only, :starts_at, :ends_at, :max_uses,
        :active, :client_q, client_ids: []
      )
    end

    # The model's attributes from the form. funded_by and the owner are never taken from it, and the
    # code text only on create (it is read-only afterwards).
    def code_attributes
      p = form_params
      attrs = {
        kind: p[:kind],
        value: p[:kind] == "fixed" ? egp_to_piastres(p[:value]) : p[:value].presence,
        max_discount_piastres: egp_to_piastres(p[:max_discount_egp]),
        min_price_piastres: egp_to_piastres(p[:min_price_egp]),
        restrict_coach_id: p[:restrict_coach_id].presence,
        restrict_package_id: p[:restrict_package_id].presence,
        min_duration_days: p[:min_duration_days].presence,
        max_duration_days: p[:max_duration_days].presence,
        new_patients_only: p[:new_patients_only] == "1",
        starts_at: cairo_time(p[:starts_at]),
        ends_at: cairo_time(p[:ends_at]),
        max_uses: p[:max_uses].presence,
        active: p[:active] == "1"
      }
      @code.persisted? ? attrs : attrs.merge(code: p[:code])
    end

    # A datetime-local value ("2026-12-01T00:00") read as Cairo time. Blank -> nil.
    def cairo_time(text)
      text.presence && PromoCode::TIME_ZONE.parse(text)
    end

    # "12.5" -> 1250. Blank -> nil. Anything unparseable is passed through so validation rejects it.
    def egp_to_piastres(text)
      return nil if text.blank?

      (BigDecimal(text.to_s.strip) * 100).round.to_i
    rescue ArgumentError
      text
    end

    # 1250 -> "12.50", 10000 -> "100". nil stays nil.
    def piastres_to_egp(piastres)
      return nil if piastres.nil?

      (piastres % 100).zero? ? (piastres / 100).to_s : format("%.2f", piastres / 100.0)
    end

    def selected_client_ids
      if params[:promo_code]&.key?(:client_ids)
        Client.where(id: form_params[:client_ids].to_a.compact_blank).pluck(:id)
      elsif @code.persisted?
        @code.promo_code_clients.pluck(:client_id)
      else
        []
      end
    end

    # What the form shows: what was typed when re-rendering, else the saved code (money in EGP).
    def prepare_form(submitted: false)
      @form = submitted ? form_params.to_h.symbolize_keys : saved_form_values
      ids = selected_client_ids
      @selected_clients = Client.where(id: ids).order(:full_name).to_a
      @client_q = form_params[:client_q].to_s.strip
      @client_results =
        if params[:search_clients].present? && @client_q.present?
          Client.search(@client_q).where.not(id: ids).order(:full_name).limit(CLIENT_SEARCH_LIMIT).to_a
        else
          []
        end
      # The pickers offer approved coaches and active packages, plus whatever this code is already
      # restricted to (a coach since suspended, a package since switched off), so saving the form
      # never silently drops a restriction and widens the code.
      coach_ids = [ @code.restrict_coach_id, @code.restrict_coach_id_in_database ].compact
      package_ids = [ @code.restrict_package_id, @code.restrict_package_id_in_database ].compact
      @coaches = Coach.where(status: "approved").or(Coach.where(id: coach_ids)).order(:full_name)
      @packages = CoachPackage.where(is_active: true).or(CoachPackage.where(id: package_ids))
                              .includes(:coach).order(:price_piastres)
    end

    def saved_form_values
      c = @code
      piastres_to_egp = method(:piastres_to_egp)
      {
        code: c.code, kind: c.kind,
        value: c.fixed? ? piastres_to_egp.call(c.value) : c.value,
        max_discount_egp: piastres_to_egp.call(c.max_discount_piastres),
        min_price_egp: piastres_to_egp.call(c.min_price_piastres),
        restrict_coach_id: c.restrict_coach_id, restrict_package_id: c.restrict_package_id,
        min_duration_days: c.min_duration_days, max_duration_days: c.max_duration_days,
        new_patients_only: c.new_patients_only ? "1" : "0",
        starts_at: c.starts_at&.in_time_zone(PromoCode::TIME_ZONE)&.strftime("%Y-%m-%dT%H:%M"),
        ends_at: c.ends_at&.in_time_zone(PromoCode::TIME_ZONE)&.strftime("%Y-%m-%dT%H:%M"),
        max_uses: c.max_uses, active: c.active ? "1" : "0"
      }
    end
  end
end
