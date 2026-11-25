module Admin
  # Read-only subscriptions overview (M36): a searchable, status-filterable list and a detail page.
  class SubscriptionsController < BaseController
    # Lifecycle statuses, mirroring coaches_api/src/db/schema/subscriptions.ts. Drives the filter.
    STATUSES = %w[pending_payment awaiting_questionnaire awaiting_plan active ended cancelled payment_failed].freeze

    def index
      @q = params[:q]
      @status = params[:status]
      @subscriptions = Subscription.includes(:client, :coach, :coach_package)
                                   .for_status(@status)
                                   .search(@q)
                                   .order(created_at: :desc)
    end
  end
end
