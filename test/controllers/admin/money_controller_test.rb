require "test_helper"

class Admin::MoneyControllerTest < ActionDispatch::IntegrationTest
  @@seq = 0

  setup do
    AdminUser.create!(email: "team@coachna.app", name: "Team", password: "Secret123")
  end

  def sign_in
    post "/admin/login", params: { email: "team@coachna.app", password: "Secret123" }
  end

  def uniq_phone
    @@seq += 1
    format("+20100%07d", @@seq)
  end

  def paid_sub(coach_name:, gross:, commission:)
    coach  = Coach.create!(full_name: coach_name, phone: uniq_phone, password_hash: "h", status: "approved")
    client = Client.create!(full_name: "Client #{@@seq}", phone: uniq_phone, password_hash: "h")
    pkg    = CoachPackage.create!(coach: coach, name: "Plan", price_piastres: gross,
                                  duration_days: 30, includes: {})
    sub = Subscription.create!(client: client, coach: coach, package_id: pkg.id, status: "active",
                               price_piastres: gross, commission_percent: 10, commission_piastres: commission,
                               starts_at: Time.current, ends_at: 30.days.from_now)
    Payment.create!(client_id: client.id, purpose: "subscription", subscription_id: sub.id,
                    amount_piastres: gross, provider: "simulated", status: "paid", paid_at: Time.current)
  end

  test "index shows the coach, gross, net and CoachNa commission" do
    sign_in
    paid_sub(coach_name: "Mona Coach", gross: 50_000, commission: 5_000)

    get admin_money_path
    assert_response :ok
    assert_includes @response.body, "Mona Coach"
    assert_includes @response.body, "EGP 500.00"  # gross income
    assert_includes @response.body, "EGP 450.00"  # net owed to coach
    assert_includes @response.body, "EGP 50.00"   # CoachNa commission
  end

  test "index shows an empty state when there are no paid subscriptions" do
    sign_in
    get admin_money_path
    assert_response :ok
    assert_includes @response.body, "No paid subscriptions yet."
  end

  test "index redirects to login when not signed in" do
    get admin_money_path
    assert_redirected_to "/admin/login"
  end
end
