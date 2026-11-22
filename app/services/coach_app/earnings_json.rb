module CoachApp
  # The coach's earnings summary plus a per-subscription breakdown, newest paid first.
  module EarningsJson
    def self.call(payments)
      items = payments.map { |payment| item(payment) }
      {
        summary: {
          grossPiastres: items.sum { |i| i[:grossPiastres] },
          commissionPiastres: items.sum { |i| i[:commissionPiastres] },
          netPiastres: items.sum { |i| i[:netPiastres] },
          subscriptionCount: items.size
        },
        items: items
      }
    end

    def self.item(payment)
      sub = payment.subscription
      gross = payment.amount_piastres
      commission = sub.commission_piastres
      {
        id: payment.id,
        clientFirstName: sub.client.full_name.to_s.split.first || "",
        packageName: sub.coach_package&.name,
        paidAt: payment.paid_at&.iso8601,
        grossPiastres: gross,
        commissionPiastres: commission,
        netPiastres: gross - commission
      }
    end
  end
end
