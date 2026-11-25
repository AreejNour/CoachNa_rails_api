module Admin
  # Read-only money overview (M37): CoachNa-wide income/commission/owed totals + a per-coach breakdown.
  class MoneyController < BaseController
    def index
      @overview = MoneyOverview.call
    end
  end
end
