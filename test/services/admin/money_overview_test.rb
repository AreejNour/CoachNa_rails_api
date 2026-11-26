require "test_helper"

class Admin::MoneyOverviewTest < ActiveSupport::TestCase
  @@seq = 0

  def uniq_phone
    @@seq += 1
    format("+20100%07d", @@seq)
  end

  def make_coach(name)
    Coach.create!(full_name: name, phone: uniq_phone, password_hash: "h", status: "approved")
  end

  # Creates a subscription for `coach` and a payment against it. Returns the subscription.
  def paid_sub(coach, gross:, commission:, status: "paid", purpose: "subscription")
    client = Client.create!(full_name: "Client #{@@seq}", phone: uniq_phone, password_hash: "h")
    pkg = CoachPackage.create!(coach: coach, name: "Plan", price_piastres: gross,
                               duration_days: 30, includes: {})
    sub = Subscription.create!(client: client, coach: coach, package_id: pkg.id, status: "active",
                               price_piastres: gross, commission_percent: 10, commission_piastres: commission,
                               starts_at: Time.current, ends_at: 30.days.from_now)
    Payment.create!(client_id: client.id, purpose: purpose, subscription_id: sub.id,
                    amount_piastres: gross, provider: "simulated", status: status,
                    paid_at: (status == "paid" ? Time.current : nil))
    sub
  end

  test "rolls up two coaches, income-desc, with CoachNa-wide totals" do
    a = make_coach("Coach A")
    b = make_coach("Coach B")
    paid_sub(a, gross: 50_000, commission: 5_000)
    paid_sub(b, gross: 80_000, commission: 12_000)

    overview = Admin::MoneyOverview.call

    assert_equal [ b.id, a.id ], overview.coaches.map(&:coach_id)
    assert_equal 130_000, overview.totals.gross_piastres
    assert_equal 17_000, overview.totals.commission_piastres
    assert_equal 113_000, overview.totals.net_piastres
    assert_equal 2, overview.totals.coach_count
    assert_equal 2, overview.totals.subscription_count
  end

  test "counts only paid payments" do
    a = make_coach("Coach A")
    paid_sub(a, gross: 50_000, commission: 5_000)
    paid_sub(a, gross: 99_000, commission: 9_000, status: "pending")
    paid_sub(a, gross: 99_000, commission: 9_000, status: "failed")
    paid_sub(a, gross: 99_000, commission: 9_000, status: "refunded")

    overview = Admin::MoneyOverview.call

    assert_equal 50_000, overview.totals.gross_piastres
    assert_equal 5_000, overview.totals.commission_piastres
    assert_equal 1, overview.totals.subscription_count
  end

  test "excludes order payments from the money totals" do
    a = make_coach("Coach A")
    paid_sub(a, gross: 50_000, commission: 5_000)
    # a paid order payment (meal order): purpose order, no subscription
    client = Client.create!(full_name: "Order Olive", phone: uniq_phone, password_hash: "h")
    Payment.create!(client_id: client.id, purpose: "order", order_id: SecureRandom.uuid,
                    amount_piastres: 77_000, provider: "simulated", status: "paid", paid_at: Time.current)

    overview = Admin::MoneyOverview.call

    assert_equal 50_000, overview.totals.gross_piastres
  end

  test "net equals gross minus commission for every entry and the totals" do
    a = make_coach("Coach A")
    b = make_coach("Coach B")
    paid_sub(a, gross: 50_000, commission: 5_000)
    paid_sub(b, gross: 80_000, commission: 12_000)

    overview = Admin::MoneyOverview.call

    overview.coaches.each do |c|
      assert_equal c.gross_piastres - c.commission_piastres, c.net_piastres
    end
    assert_equal overview.totals.gross_piastres - overview.totals.commission_piastres,
                 overview.totals.net_piastres
  end

  test "a coach's row matches their M24 earnings summary" do
    a = make_coach("Coach A")
    paid_sub(a, gross: 50_000, commission: 5_000)
    paid_sub(a, gross: 30_000, commission: 4_000)

    row = Admin::MoneyOverview.call.coaches.find { |c| c.coach_id == a.id }
    m24 = CoachApp::Earnings.summary(a)[:summary]

    assert_equal m24[:grossPiastres], row.gross_piastres
    assert_equal m24[:commissionPiastres], row.commission_piastres
    assert_equal m24[:netPiastres], row.net_piastres
    assert_equal m24[:subscriptionCount], row.subscription_count
  end

  test "empty when there are no paid subscription payments" do
    overview = Admin::MoneyOverview.call

    assert_equal [], overview.coaches
    assert_equal 0, overview.totals.gross_piastres
    assert_equal 0, overview.totals.commission_piastres
    assert_equal 0, overview.totals.net_piastres
    assert_equal 0, overview.totals.coach_count
    assert_equal 0, overview.totals.subscription_count
  end
  test "an admin promo code's negative commission leaves the coach's net at the no-code share" do
    coach = Coach.create!(full_name: "Promo Coach", phone: uniq_phone, password_hash: "h",
                          status: "approved", commission_percent: 20)
    client = Client.create!(full_name: "Promo Client", phone: uniq_phone, password_hash: "h")
    pkg = CoachPackage.create!(coach: coach, name: "Plan", price_piastres: 90_000, duration_days: 30, includes: {})
    admin = AdminUser.create!(email: "promo@coachna.app", name: "Promo", password: "Secret123")
    promo = PromoCode.create!(code: "HALF", kind: "percent", value: 50, funded_by: "platform",
                              created_by_admin_id: admin.id)
    # 50% off EGP 900 at 20%: pays 45000, commission 18000 - 45000 = -27000.
    sub = Subscription.create!(client: client, coach: coach, package_id: pkg.id, status: "active",
                               price_piastres: 90_000, commission_percent: 20, commission_piastres: -27_000,
                               discount_piastres: 45_000, promo_code_id: promo.id,
                               starts_at: Time.current, ends_at: 30.days.from_now)
    Payment.create!(client_id: client.id, purpose: "subscription", subscription_id: sub.id,
                    amount_piastres: 45_000, provider: "simulated", status: "paid", paid_at: Time.current)

    row = Admin::MoneyOverview.call.coaches.find { |c| c.coach_id == coach.id }

    assert_equal 45_000, row.gross_piastres
    assert_equal(-27_000, row.commission_piastres)
    assert_equal 90_000 * 80 / 100, row.net_piastres
    assert_equal CoachApp::Earnings.summary(coach)[:summary][:netPiastres], row.net_piastres
  end
end
