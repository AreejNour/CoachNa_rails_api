module CoachApp
  # The one rule for which of a coach's subscriptions the coach app may reach. A pending_payment
  # subscription is not paid yet (Node confirms it with Paymob), so it does not exist for the coach.
  module Subscriptions
    def self.visible_to_coach(coach)
      coach.subscriptions.where.not(status: "pending_payment")
    end
  end
end
