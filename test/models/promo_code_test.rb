require "test_helper"

class PromoCodeTest < ActiveSupport::TestCase
  @@seq = 0

  setup do
    @admin = AdminUser.create!(email: "team@coachna.app", name: "Team", password: "Secret123")
    @coach = Coach.create!(full_name: "Coach A", phone: uniq_phone, password_hash: "h", status: "approved")
    CoachPackage.create!(coach: @coach, name: "Big", price_piastres: 90_000, duration_days: 30, includes: {})
  end

  def uniq_phone
    @@seq += 1
    format("+20122%07d", @@seq)
  end

  def build(attrs = {})
    PromoCode.new({ code: "SUMMER50", kind: "percent", value: 50, funded_by: "platform",
                    created_by_admin_id: @admin.id }.merge(attrs))
  end

  test "a valid percent code saves" do
    assert build.save
  end

  test "code is upcased before validation" do
    code = build(code: "summer50")
    assert code.valid?
    assert_equal "SUMMER50", code.code
  end

  test "code must be 3 to 20 letters or digits" do
    assert_not build(code: "AB").valid?
    assert_not build(code: "A" * 21).valid?
    assert_not build(code: "SUMMER-50").valid?
    assert_not build(code: "صيف50").valid?
    assert_not build(code: "").valid?
    assert build(code: "ABC").valid?
    assert build(code: "A" * 20).valid?
  end

  test "a blank code shows only can't be blank" do
    code = build(code: "")
    assert_not code.valid?
    assert_equal [ "can't be blank" ], code.errors[:code]
  end

  test "restrictions must point at a real coach and package" do
    assert_not build(restrict_coach_id: SecureRandom.uuid).valid?
    assert_not build(restrict_package_id: SecureRandom.uuid).valid?
  end

  test "code is unique ignoring case" do
    build(code: "SUMMER50").save!
    dupe = build(code: "summer50")
    assert_not dupe.valid?
    assert dupe.errors[:code].any?
  end

  test "kind must be percent or fixed" do
    assert_not build(kind: "free").valid?
    assert_not build(kind: nil).valid?
  end

  test "percent value is 1 to 99" do
    assert_not build(value: 0).valid?
    assert_not build(value: 100).valid?
    assert build(value: 1).valid?
    assert build(value: 99).valid?
  end

  test "fixed value is at least 100 and at most the dearest active package minus 1000" do
    CoachPackage.create!(coach: @coach, name: "Old dear", price_piastres: 500_000, duration_days: 30,
                         includes: {}, is_active: false)
    assert_not build(kind: "fixed", value: 99).valid?
    assert build(kind: "fixed", value: 100).valid?
    assert build(kind: "fixed", value: 89_000).valid?
    assert_not build(kind: "fixed", value: 89_001).valid?
  end

  test "max discount is only allowed on percent codes" do
    assert build(kind: "percent", value: 30, max_discount_piastres: 20_000).valid?
    assert_not build(kind: "fixed", value: 5_000, max_discount_piastres: 20_000).valid?
  end

  test "min duration must not exceed max duration" do
    assert_not build(min_duration_days: 90, max_duration_days: 30).valid?
    assert build(min_duration_days: 90, max_duration_days: 90).valid?
  end

  test "starts_at must be before ends_at when both are set" do
    t = Time.current
    assert_not build(starts_at: t, ends_at: t).valid?
    assert_not build(starts_at: t, ends_at: t - 1.day).valid?
    assert build(starts_at: t, ends_at: t + 1.day).valid?
    assert build(starts_at: t).valid?
  end

  test "a package restriction must belong to the chosen coach" do
    other = Coach.create!(full_name: "Coach B", phone: uniq_phone, password_hash: "h", status: "approved")
    pkg = @coach.coach_packages.first
    assert_not build(restrict_coach_id: other.id, restrict_package_id: pkg.id).valid?
    assert build(restrict_coach_id: @coach.id, restrict_package_id: pkg.id).valid?
    assert build(restrict_package_id: pkg.id).valid?
  end

  test "funded_by is always platform" do
    assert_not build(funded_by: "coach").valid?
  end

  test "created_by_admin_id is required" do
    assert_not build(created_by_admin_id: nil).valid?
  end

  test "filters by active, inactive and expired" do
    live = build(code: "LIVE").tap(&:save!)
    off = build(code: "OFF", active: false).tap(&:save!)
    old = build(code: "OLD", starts_at: 10.days.ago, ends_at: 1.day.ago).tap(&:save!)

    assert_equal [ live ], PromoCode.for_filter("active").to_a
    assert_equal [ off ], PromoCode.for_filter("inactive").to_a
    assert_equal [ old ], PromoCode.for_filter("expired").to_a
    assert_equal 3, PromoCode.for_filter(nil).count
  end

  test "paid uses count only subscriptions with a paid payment" do
    code = build.tap(&:save!)
    pkg = @coach.coach_packages.first
    %w[paid pending failed].each do |status|
      client = Client.create!(full_name: "C", phone: uniq_phone, password_hash: "h")
      sub = Subscription.create!(client: client, coach: @coach, package_id: pkg.id, status: "active",
                                 price_piastres: 90_000, commission_percent: 20, commission_piastres: -27_000,
                                 discount_piastres: 45_000, promo_code_id: code.id,
                                 starts_at: Time.current, ends_at: 30.days.from_now)
      Payment.create!(client_id: client.id, purpose: "subscription", subscription_id: sub.id,
                      amount_piastres: 45_000, provider: "simulated", status: status)
    end

    assert_equal({ code.id => 1 }, PromoCode.paid_use_counts([ code.id ]))
  end
end
