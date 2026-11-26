module Admin
  # Returns a coach's clients for the admin coach-detail "Clients" tab: one row per distinct
  # client, defaulting to those with a live (paid) subscription to this coach, with that client's
  # latest subscription-with-this-coach status/date, windowed for a hand-rolled pager.
  class CoachClientsQuery
    # "Active" = the client has a subscription with THIS coach that is paid and live. Mirrors
    # coaches_api PAID_STATUSES; excludes pending_payment / ended / cancelled / payment_failed.
    ACTIVE_STATUSES = %w[active awaiting_plan awaiting_questionnaire].freeze

    Result = Struct.new(:rows, :total, :page, :total_pages, keyword_init: true)
    Row    = Struct.new(:client, :latest_status, :latest_started_at, keyword_init: true)

    def self.call(coach:, filter: "active", page: 1, per_page: 25)
      new(coach: coach, filter: filter, page: page, per_page: per_page).call
    end

    def initialize(coach:, filter:, page:, per_page:)
      @coach = coach
      @filter = filter
      @per_page = per_page
      @requested_page = page
    end

    def call
      subs = @coach.subscriptions
      subs = subs.where(status: ACTIVE_STATUSES) if @filter != "all"
      client_ids = subs.distinct.pluck(:client_id)

      total = client_ids.length
      total_pages = [ (total / @per_page.to_f).ceil, 1 ].max
      page = @requested_page.to_i.clamp(1, total_pages)

      page_clients = Client.where(id: client_ids)
                           .order(:full_name)
                           .limit(@per_page)
                           .offset((page - 1) * @per_page)
                           .to_a

      latest = latest_subscriptions_for(page_clients.map(&:id))
      rows = page_clients.map do |client|
        sub = latest[client.id]
        Row.new(client: client, latest_status: sub&.status, latest_started_at: sub&.starts_at)
      end

      Result.new(rows: rows, total: total, page: page, total_pages: total_pages)
    end

    private

    # The newest subscription-with-this-coach per client, keyed by client_id (Postgres DISTINCT ON).
    def latest_subscriptions_for(ids)
      return {} if ids.empty?

      @coach.subscriptions
            .where(client_id: ids)
            .select("DISTINCT ON (client_id) client_id, status, starts_at")
            .order("client_id, starts_at DESC")
            .index_by(&:client_id)
    end
  end
end
