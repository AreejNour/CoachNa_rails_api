require "test_helper"

class Admin::PromoLossCheckTest < ActiveSupport::TestCase
  @@seq = 0

  def uniq_phone
    @@seq += 1
    format("+20123%07d", @@seq)
  end

  def make_coach(name, commission)
    Coach.create!(full_name: name, phone: uniq_phone, password_hash: "h", status: "approved",
                  commission_percent: commission)
  end

  def make_package(coach, price, days: 30, active: true)
    CoachPackage.create!(coach: coach, name: "Pkg #{price}", price_piastres: price, duration_days: days,
                         includes: {}, is_active: active)
  end

  def code(attrs = {})
    PromoCode.new({ code: "TEST", kind: "percent", value: 30, funded_by: "platform" }.merge(attrs))
  end

  setup do
    @low = make_coach("Low", 20)   # 20% commission
    @high = make_coach("High", 40) # 40% commission
    @low_pkg = make_package(@low, 90_000)
    @high_pkg = make_package(@high, 90_000)
  end

  # The brief's example used 50%, which beats both 20% and 40%; 30% sits between the two rates
  # so it flags only the 20% coach.
  test "an unrestricted 30% code over 20% and 40% coaches flags only the 20% coach's package" do
    result = Admin::PromoLossCheck.call(code)

    assert_equal 1, result[:affected_count]
    # discount 27000 - commission 18000
    assert_equal 9_000, result[:worst_loss_piastres]
  end

  test "a 50% code beats both coaches and reports the worst case" do
    result = Admin::PromoLossCheck.call(code(value: 50))

    assert_equal 2, result[:affected_count]
    # 20% coach: 45000 - 18000
    assert_equal 27_000, result[:worst_loss_piastres]
  end

  test "the discount cap removes the loss" do
    result = Admin::PromoLossCheck.call(code(max_discount_piastres: 10_000))

    assert_equal 0, result[:affected_count]
    assert_equal 0, result[:worst_loss_piastres]
  end

  test "a package restriction narrows the reach" do
    result = Admin::PromoLossCheck.call(code(value: 50, restrict_package_id: @high_pkg.id))

    assert_equal 1, result[:affected_count]
    assert_equal 9_000, result[:worst_loss_piastres] # 45000 - 36000
  end

  test "a coach restriction narrows the reach" do
    result = Admin::PromoLossCheck.call(code(restrict_coach_id: @high.id))

    assert_equal 0, result[:affected_count]
  end

  test "minimum price narrows the reach" do
    make_package(@low, 200_000)

    result = Admin::PromoLossCheck.call(code(min_price_piastres: 100_000))

    assert_equal 1, result[:affected_count]
    assert_equal 20_000, result[:worst_loss_piastres] # 60000 - 40000
  end

  test "duration range narrows the reach" do
    make_package(@low, 300_000, days: 90)

    result = Admin::PromoLossCheck.call(code(min_duration_days: 90, max_duration_days: 90))

    assert_equal 1, result[:affected_count]
    assert_equal 30_000, result[:worst_loss_piastres] # 90000 - 60000
  end

  test "packages of coaches who are not approved are ignored" do
    @low.update!(status: "suspended")

    assert_equal 0, Admin::PromoLossCheck.call(code)[:affected_count]
  end

  test "inactive packages are ignored" do
    @low_pkg.update!(is_active: false)

    assert_equal 0, Admin::PromoLossCheck.call(code)[:affected_count]
  end

  test "a coach with no commission uses the platform default" do
    none = make_coach("Default", nil)
    make_package(none, 100_000)
    pct = Rails.configuration.x.platform_commission_percent.to_i

    at_default = Admin::PromoLossCheck.call(code(value: pct, restrict_coach_id: none.id))
    above = Admin::PromoLossCheck.call(code(value: pct + 1, restrict_coach_id: none.id))

    assert_equal 0, at_default[:affected_count]
    assert_equal 1, above[:affected_count]
    assert_equal 1_000, above[:worst_loss_piastres] # 1% of 100000
  end

  test "the platform default matches the Node API default of 15%" do
    assert_equal 15, Rails.configuration.x.platform_commission_percent
  end

  test "fixed codes compare the flat amount to each package's commission" do
    result = Admin::PromoLossCheck.call(code(kind: "fixed", value: 20_000))

    assert_equal 1, result[:affected_count]
    assert_equal 2_000, result[:worst_loss_piastres] # 20000 - 18000
  end

  test "packages the code is too big for are not counted (the code cannot apply there)" do
    make_package(@low, 1_500)

    result = Admin::PromoLossCheck.call(code(kind: "fixed", value: 1_000, restrict_coach_id: @low.id))

    # 90000 package: 1000 < 18000, no loss. 1500 package: 1500 - 1000 < 1000, code refused there.
    assert_equal 0, result[:affected_count]
  end
end
