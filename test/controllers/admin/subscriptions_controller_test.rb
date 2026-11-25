require "test_helper"

class Admin::SubscriptionsControllerTest < ActionDispatch::IntegrationTest
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

  def make_subscription(client_name:, coach_name:, client_phone: nil, status: "active")
    coach  = Coach.create!(full_name: coach_name, phone: uniq_phone, password_hash: "h", status: "approved")
    client = Client.create!(full_name: client_name, phone: client_phone || uniq_phone, password_hash: "h")
    pkg    = CoachPackage.create!(coach: coach, name: "Gold Plan", price_piastres: 50_000,
                                  duration_days: 30, includes: {})
    Subscription.create!(client: client, coach: coach, package_id: pkg.id, status: status,
                         price_piastres: 50_000, commission_percent: 10, commission_piastres: 5_000,
                         starts_at: Time.current, ends_at: 30.days.from_now)
  end

  test "index lists subscriptions with client and coach names" do
    sign_in
    make_subscription(client_name: "Layla Hassan", coach_name: "Mona Coach")

    get admin_subscriptions_path
    assert_response :ok
    assert_includes @response.body, "Layla Hassan"
    assert_includes @response.body, "Mona Coach"
  end

  test "index filters by status" do
    sign_in
    make_subscription(client_name: "Active Amy", coach_name: "Coach A", status: "active")
    make_subscription(client_name: "Ended Ed", coach_name: "Coach B", status: "ended")

    get admin_subscriptions_path(status: "active")
    assert_response :ok
    assert_includes @response.body, "Active Amy"
    assert_not_includes @response.body, "Ended Ed"
  end

  test "index searches by client name" do
    sign_in
    make_subscription(client_name: "Layla Hassan", coach_name: "Coach A")
    make_subscription(client_name: "Omar Said", coach_name: "Coach B")

    get admin_subscriptions_path(q: "Layla")
    assert_response :ok
    assert_includes @response.body, "Layla Hassan"
    assert_not_includes @response.body, "Omar Said"
  end

  test "index shows an empty state when there are no subscriptions" do
    sign_in
    get admin_subscriptions_path
    assert_response :ok
    assert_includes @response.body, "No subscriptions"
  end

  test "index redirects to login when not signed in" do
    get admin_subscriptions_path
    assert_redirected_to "/admin/login"
  end
end
