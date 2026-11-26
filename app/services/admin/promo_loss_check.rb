module Admin
  # Can a CoachNa-funded code cost CoachNa more than it earns? Over every active package of an
  # approved coach (what the API sells) the code can
  # apply to (coach / package restriction, minimum price, duration range, and still leaving EGP 10 to
  # pay), compares the discount (cap applied) with CoachNa's commission on that package: the coach's
  # own rate, or the platform default. Mirrors CoachNa_api/src/promo/evaluate.ts. Works on an unsaved
  # code too, so the form can preview it. Not blocking: the admin decides.
  module PromoLossCheck
    def self.call(promo_code)
      packages = PromoCode.sellable_packages
      packages = packages.where(coach_id: promo_code.restrict_coach_id) if promo_code.restrict_coach_id.present?
      packages = packages.where(id: promo_code.restrict_package_id) if promo_code.restrict_package_id.present?
      packages = packages.where(price_piastres: promo_code.min_price_piastres..) if promo_code.min_price_piastres
      packages = packages.where(duration_days: promo_code.min_duration_days..) if promo_code.min_duration_days
      packages = packages.where(duration_days: ..promo_code.max_duration_days) if promo_code.max_duration_days

      default = Rails.configuration.x.platform_commission_percent
      losses = packages.pluck(:price_piastres, Arel.sql("coaches.commission_percent")).filter_map do |price, pct|
        discount = discount_for(promo_code, price)
        next if discount.nil? || price - discount < PromoCode::MIN_PAYABLE_PIASTRES

        commission = (BigDecimal(price) * (pct || default) / 100).round(half: :up).to_i
        discount - commission if discount > commission
      end

      { affected_count: losses.size, worst_loss_piastres: losses.max || 0 }
    end

    def self.discount_for(promo_code, price)
      return nil unless promo_code.value.is_a?(Integer)

      if promo_code.percent?
        discount = price * promo_code.value / 100
        promo_code.max_discount_piastres ? [ discount, promo_code.max_discount_piastres ].min : discount
      elsif promo_code.fixed?
        promo_code.value
      end
    end
    private_class_method :discount_for
  end
end
