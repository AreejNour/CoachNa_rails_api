module CoachApp
  # The one rule for which of a coach's subscriptions the coach app may reach. An unpaid
  # subscription (not yet paid, or failed) does not exist for the coach.
  module Subscriptions
    # checkout_open: the card form was opened, nothing submitted or paid. pending_payment: awaiting
    # Paymob. payment_failed: an attempt that never became a client.
    UNPAID_STATUSES = %w[checkout_open pending_payment payment_failed].freeze

    def self.visible_to_coach(coach)
      coach.subscriptions.where.not(status: UNPAID_STATUSES)
    end
  end
end
