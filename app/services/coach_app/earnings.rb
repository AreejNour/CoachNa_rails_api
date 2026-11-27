module CoachApp
  # The coach's earnings (Milestone 24): income from their clients' PAID subscription payments, with
  # CoachNa's commission (copied onto each subscription at purchase) and the coach's net share.
  # Read-only: nothing here authors or moderates. Unpaid/pending/failed/refunded payments don't count.
  module Earnings
    def self.summary(coach)
      payments = Payment.where(purpose: "subscription", status: "paid")
                        .joins(:subscription).where(subscriptions: { coach_id: coach.id })
                        .includes(subscription: [ :client, :coach_package, :promo_code ])
                        .order(paid_at: :desc, id: :desc)
      EarningsJson.call(payments)
    end
  end
end
