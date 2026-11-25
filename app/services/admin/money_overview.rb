module Admin
  # CoachNa's business-wide money picture (Milestone 37): per-coach income, the commission CoachNa
  # earned, and what is owed to each coach — read-only, from PAID subscription payments only.
  # Mirrors the M24 coach-earnings math (CoachApp::Earnings): gross = payments.amount_piastres,
  # commission = the subscription's commission_piastres snapshot, net = gross - commission. A
  # subscription with N paid payments contributes its commission N times (same payment rows as M24).
  module MoneyOverview
    CoachRow = Data.define(:coach_id, :coach_name, :gross_piastres, :commission_piastres,
                           :net_piastres, :subscription_count)
    Totals = Data.define(:gross_piastres, :commission_piastres, :net_piastres,
                         :coach_count, :subscription_count)
    Overview = Data.define(:totals, :coaches)

    def self.call
      rows = Payment.where(purpose: "subscription", status: "paid")
                    .joins(subscription: :coach)
                    .group("coaches.id", "coaches.full_name")
                    .pluck(Arel.sql("coaches.id"),
                           Arel.sql("coaches.full_name"),
                           Arel.sql("SUM(payments.amount_piastres)"),
                           Arel.sql("SUM(subscriptions.commission_piastres)"),
                           Arel.sql("COUNT(*)"))

      coaches = rows.map { |id, name, gross, commission, count|
        gross = gross.to_i
        commission = commission.to_i
        CoachRow.new(coach_id: id, coach_name: name, gross_piastres: gross,
                     commission_piastres: commission, net_piastres: gross - commission,
                     subscription_count: count.to_i)
      }.sort_by { |c| -c.gross_piastres }

      totals = Totals.new(
        gross_piastres: coaches.sum(&:gross_piastres),
        commission_piastres: coaches.sum(&:commission_piastres),
        net_piastres: coaches.sum(&:net_piastres),
        coach_count: coaches.size,
        subscription_count: coaches.sum(&:subscription_count),
      )

      Overview.new(totals: totals, coaches: coaches)
    end
  end
end
