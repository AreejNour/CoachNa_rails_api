# The `promo_codes` table is owned by the Node API (migration 0026), which checks and prices codes at
# checkout. The admin panel creates and edits CoachNa-funded (`platform`) codes here. Coach-funded
# codes come in a later step. Money is integer piastres.
class PromoCode < ApplicationRecord
  KINDS = %w[percent fixed].freeze
  MIN_PAYABLE_PIASTRES = 1000
  MIN_FIXED_PIASTRES = 100
  FILTERS = %w[active inactive expired].freeze

  belongs_to :created_by_admin, class_name: "AdminUser", optional: true
  belongs_to :restrict_coach, class_name: "Coach", optional: true
  belongs_to :restrict_package, class_name: "CoachPackage", optional: true
  has_many :promo_code_clients
  has_many :subscriptions

  before_validation { self.code = code.to_s.strip.upcase if code }

  validates :code, presence: true, uniqueness: { case_sensitive: false }
  validates :code, format: { with: /\A[A-Z0-9]{3,20}\z/, message: "must be 3-20 letters or digits" }, allow_blank: true
  validates :kind, inclusion: { in: KINDS }
  validates :value, numericality: { only_integer: true }
  validates :funded_by, inclusion: { in: %w[platform], message: "must be platform" }
  validates :created_by_admin_id, presence: true
  validates :max_discount_piastres, :min_price_piastres, :max_uses,
            numericality: { only_integer: true, greater_than: 0 }, allow_nil: true
  validates :min_duration_days, :max_duration_days,
            numericality: { only_integer: true, greater_than: 0 }, allow_nil: true
  validate :value_in_range
  validate :max_discount_only_for_percent
  validate :duration_range
  validate :date_range
  validate :package_matches_coach
  validate :restrictions_exist

  scope :expired_now, -> { where(ends_at: ..Time.current) }
  scope :for_filter, lambda { |filter|
    case filter
    when "active" then where(active: true).where("ends_at IS NULL OR ends_at > ?", Time.current)
    when "inactive" then where(active: false)
    when "expired" then expired_now
    else all
    end
  }

  # { promo_code_id => number of subscriptions with that code whose payment is paid } (a "use").
  def self.paid_use_counts(ids)
    Subscription.where(promo_code_id: ids)
                .joins(:payments).where(payments: { status: "paid" })
                .group(:promo_code_id).distinct.count(:id)
  end

  def self.max_active_package_price
    CoachPackage.where(is_active: true).maximum(:price_piastres)
  end

  def percent? = kind == "percent"
  def fixed? = kind == "fixed"

  def expired?(now = Time.current) = ends_at.present? && ends_at <= now

  # Replaces the allow-list with exactly these client ids.
  def replace_clients!(client_ids)
    ids = Array(client_ids).compact_blank.uniq
    promo_code_clients.where.not(client_id: ids).delete_all
    (ids - promo_code_clients.pluck(:client_id)).each { |id| promo_code_clients.create!(client_id: id) }
  end

  private

  def value_in_range
    return unless value.is_a?(Integer)

    if percent?
      errors.add(:value, "must be a percent from 1 to 99") unless value.between?(1, 99)
    elsif fixed?
      if value < MIN_FIXED_PIASTRES
        errors.add(:value, "must be at least EGP 1")
      elsif (max = self.class.max_active_package_price) && value > max - MIN_PAYABLE_PIASTRES
        errors.add(:value, "must leave at least EGP 10 on the most expensive active package " \
                           "(at most EGP #{(max - MIN_PAYABLE_PIASTRES) / 100.0})")
      end
    end
  end

  def max_discount_only_for_percent
    errors.add(:max_discount_piastres, "is only for percent codes") if max_discount_piastres && !percent?
  end

  def duration_range
    return unless min_duration_days && max_duration_days

    errors.add(:min_duration_days, "must not be more than the maximum") if min_duration_days > max_duration_days
  end

  def restrictions_exist
    errors.add(:restrict_coach_id, "is not a known coach") if restrict_coach_id.present? && restrict_coach.nil?
    errors.add(:restrict_package_id, "is not a known package") if restrict_package_id.present? && restrict_package.nil?
  end

  def package_matches_coach
    return unless restrict_coach_id.present? && restrict_package

    errors.add(:restrict_package_id, "must belong to the chosen coach") if restrict_package.coach_id != restrict_coach_id
  end

  def date_range
    return unless starts_at && ends_at

    errors.add(:ends_at, "must be after the start") unless starts_at < ends_at
  end
end
