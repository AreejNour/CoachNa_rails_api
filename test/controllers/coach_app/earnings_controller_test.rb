require "test_helper"

class CoachApp::EarningsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @coach = Coach.create!(phone: "+201012349001", password_hash: "h", full_name: "Coach Mona")
  end

  def auth = { "Authorization" => "Bearer #{CoachApp::AccessToken.sign(@coach.id)}" }
  def data = response.parsed_body["data"]

  def make_client(n, name)
    Client.create!(phone: "+2010123491#{n.to_s.rjust(2, "0")}", password_hash: "h", full_name: name)
  end

  def make_sub(client, price:, commission:, coach: @coach, plan_name: "plan", package_id: nil)
    package_id ||= coach.coach_packages.create!(name: plan_name, price_piastres: price,
                                                duration_days: 30, includes: [ "x" ]).id
    now = Time.current
    Subscription.create!(client_id: client.id, coach_id: coach.id, package_id: package_id, status: "active",
                         price_piastres: price, commission_percent: 10, commission_piastres: commission,
                         starts_at: now - 1.day, ends_at: now + 30.days)
  end

  def pay(sub, status: "paid", at: Time.current, amount: nil)
    Payment.create!(client_id: sub.client_id, purpose: "subscription", subscription_id: sub.id,
                    amount_piastres: amount || sub.price_piastres, provider: "simulated",
                    status: status, paid_at: (status == "paid" ? at : nil))
  end

  test "needs a token" do
    get "/coach/earnings"
    assert_response :unauthorized
  end

  test "coach with no paid subscriptions gets a zeroed summary and empty list" do
    get "/coach/earnings", headers: auth
    assert_response :ok
    assert_equal({ "grossPiastres" => 0, "commissionPiastres" => 0, "netPiastres" => 0, "subscriptionCount" => 0 },
                 data["summary"])
    assert_equal [], data["items"]
  end

  test "sums paid subscription payments, newest first, net = gross - stored commission" do
    a = make_sub(make_client(1, "Nour Hassan"), price: 100_000, commission: 15_000, plan_name: "3-month")
    b = make_sub(make_client(2, "Omar Ali"), price: 50_000, commission: 5_000, plan_name: "1-month")
    pay(a, at: 2.days.ago)
    pay(b, at: 1.hour.ago)

    get "/coach/earnings", headers: auth
    assert_response :ok
    assert_equal({ "grossPiastres" => 150_000, "commissionPiastres" => 20_000, "netPiastres" => 130_000,
                   "subscriptionCount" => 2 }, data["summary"])
    assert_equal %w[Omar Nour], data["items"].map { |i| i["clientFirstName"] }
    first = data["items"].first
    assert_equal 50_000, first["grossPiastres"]
    assert_equal 5_000, first["commissionPiastres"]
    assert_equal 45_000, first["netPiastres"]
    assert_equal "1-month", first["packageName"]
  end

  test "excludes pending, failed and refunded payments and subscriptions with no payment" do
    paid = make_sub(make_client(1, "Paid Pam"), price: 40_000, commission: 4_000)
    pay(paid)
    pay(make_sub(make_client(2, "Pending Peter"), price: 40_000, commission: 4_000), status: "pending")
    pay(make_sub(make_client(3, "Failed Fay"), price: 40_000, commission: 4_000), status: "failed")
    pay(make_sub(make_client(4, "Refund Ray"), price: 40_000, commission: 4_000), status: "refunded")
    make_sub(make_client(5, "Unpaid Uma"), price: 40_000, commission: 4_000)

    get "/coach/earnings", headers: auth
    assert_equal 1, data["summary"]["subscriptionCount"]
    assert_equal %w[Paid], data["items"].map { |i| i["clientFirstName"] }
    assert_equal 40_000, data["summary"]["grossPiastres"]
  end

  test "uses the subscription's copied commission, not the coach's current rate" do
    sub = make_sub(make_client(1, "Nour Hassan"), price: 30_000, commission: 9_000)
    pay(sub)

    get "/coach/earnings", headers: auth
    assert_equal 9_000, data["items"].first["commissionPiastres"]
    assert_equal 21_000, data["items"].first["netPiastres"]
  end

  test "another coach's paid payments never appear" do
    other = Coach.create!(phone: "+201012349002", password_hash: "h", full_name: "Other")
    pay(make_sub(make_client(1, "Theirs Tom"), price: 99_000, commission: 9_000, coach: other))

    get "/coach/earnings", headers: auth
    assert_equal 0, data["summary"]["subscriptionCount"]
    assert_equal [], data["items"]
  end

  test "shows the client first name and still names a soft-deleted (archived) package" do
    client = make_client(1, "Nour Hassan")
    pkg = @coach.coach_packages.create!(name: "archived plan", price_piastres: 20_000, duration_days: 30,
                                        includes: [ "x" ])
    sub = make_sub(client, price: 20_000, commission: 2_000, package_id: pkg.id)
    pay(sub)
    pkg.update!(is_active: false) # a coach "deletes" a package by archiving it; the row (and name) stay

    get "/coach/earnings", headers: auth
    item = data["items"].first
    assert_equal "Nour", item["clientFirstName"]
    assert_equal "archived plan", item["packageName"]
    assert_equal 18_000, item["netPiastres"]
  end
  def promo(funded_by)
    admin = AdminUser.find_by(email: "promo@coachna.app") ||
            AdminUser.create!(email: "promo@coachna.app", name: "Promo", password: "Secret123")
    code = PromoCode.create!(code: "CODE#{funded_by.upcase}", kind: "percent", value: 50, funded_by: "platform",
                             created_by_admin_id: admin.id)
    code.update_column(:funded_by, funded_by)
    code
  end

  test "a CoachNa-funded code looks like a normal sale to the coach" do
    plain = make_sub(make_client(1, "Nour Hassan"), price: 50_000, commission: 5_000)
    pay(plain, at: 2.days.ago)
    # EGP 900 at 20%, 50% CoachNa code: paid 45000, stored commission 18000 - 45000 = -27000.
    sub = make_sub(make_client(2, "Omar Ali"), price: 90_000, commission: -27_000)
    sub.update!(promo_code_id: promo("platform").id, discount_piastres: 45_000)
    pay(sub, amount: 45_000, at: 1.hour.ago)

    get "/coach/earnings", headers: auth
    item = data["items"].first
    assert_equal 90_000, item["grossPiastres"]
    assert_equal 18_000, item["commissionPiastres"]
    assert_equal 72_000, item["netPiastres"]
    assert_equal({ "grossPiastres" => 140_000, "commissionPiastres" => 23_000, "netPiastres" => 117_000,
                   "subscriptionCount" => 2 }, data["summary"])
  end

  test "a coach-funded code keeps the real numbers" do
    # EGP 900 at 20%, 50% coach code: paid 45000, commission unchanged 18000.
    sub = make_sub(make_client(1, "Nour Hassan"), price: 90_000, commission: 18_000)
    sub.update!(promo_code_id: promo("coach").id, discount_piastres: 45_000)
    pay(sub, amount: 45_000)

    get "/coach/earnings", headers: auth
    item = data["items"].first
    assert_equal 45_000, item["grossPiastres"]
    assert_equal 18_000, item["commissionPiastres"]
    assert_equal 27_000, item["netPiastres"]
    assert_equal({ "grossPiastres" => 45_000, "commissionPiastres" => 18_000, "netPiastres" => 27_000,
                   "subscriptionCount" => 1 }, data["summary"])
  end
end
