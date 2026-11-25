require "test_helper"

class SubscriptionTest < ActiveSupport::TestCase
  @@seq = 0

  def uniq_phone
    @@seq += 1
    format("+20100%07d", @@seq)
  end

  def make_subscription(client_name:, coach_name:, client_phone: nil, status: "active")
    coach  = Coach.create!(full_name: coach_name, phone: uniq_phone, password_hash: "h", status: "approved")
    client = Client.create!(full_name: client_name, phone: client_phone || uniq_phone, password_hash: "h")
    pkg    = CoachPackage.create!(coach: coach, name: "Plan", price_piastres: 50_000,
                                  duration_days: 30, includes: {})
    Subscription.create!(client: client, coach: coach, package_id: pkg.id, status: status,
                         price_piastres: 50_000, commission_percent: 10, commission_piastres: 5_000,
                         starts_at: Time.current, ends_at: 30.days.from_now)
  end

  test "for_status returns only the matching status" do
    active = make_subscription(client_name: "Active Amy", coach_name: "Coach A", status: "active")
    make_subscription(client_name: "Ended Ed", coach_name: "Coach B", status: "ended")

    assert_equal [ active.id ], Subscription.for_status("active").pluck(:id)
  end

  test "for_status is a no-op when blank" do
    make_subscription(client_name: "Active Amy", coach_name: "Coach A", status: "active")
    make_subscription(client_name: "Ended Ed", coach_name: "Coach B", status: "ended")

    assert_equal 2, Subscription.for_status(nil).count
    assert_equal 2, Subscription.for_status("").count
  end

  test "for_status returns none for an unknown status" do
    make_subscription(client_name: "Active Amy", coach_name: "Coach A", status: "active")

    assert_equal 0, Subscription.for_status("bogus").count
  end

  test "search matches a client full name" do
    layla = make_subscription(client_name: "Layla Hassan", coach_name: "Coach A")
    make_subscription(client_name: "Omar Said", coach_name: "Coach B")

    assert_equal [ layla.id ], Subscription.search("Layla").pluck(:id)
  end

  test "search matches a client phone fragment" do
    target = make_subscription(client_name: "Phone Pat", coach_name: "Coach A", client_phone: "+201119998877")
    make_subscription(client_name: "Other Olive", coach_name: "Coach B")

    assert_includes Subscription.search("9998877").pluck(:id), target.id
    assert_not_includes Subscription.search("9998877").pluck(:id), Subscription.where.not(id: target.id).first&.id
  end

  test "search matches a coach full name" do
    target = make_subscription(client_name: "Client C", coach_name: "Mona Specialist")
    make_subscription(client_name: "Client D", coach_name: "Other Coach")

    assert_equal [ target.id ], Subscription.search("Mona").pluck(:id)
  end

  test "search is a no-op when blank" do
    make_subscription(client_name: "Client C", coach_name: "Coach A")
    make_subscription(client_name: "Client D", coach_name: "Coach B")

    assert_equal 2, Subscription.search(nil).count
    assert_equal 2, Subscription.search("").count
  end

  test "search escapes ILIKE wildcards in the term" do
    literal = make_subscription(client_name: "50% Off", coach_name: "Coach A")
    other   = make_subscription(client_name: "Regular Rita", coach_name: "Coach B")

    ids = Subscription.search("50%").pluck(:id)
    assert_includes ids, literal.id
    assert_not_includes ids, other.id
  end

  test "payments returns the subscription's payments" do
    sub = make_subscription(client_name: "Paid Pam", coach_name: "Coach A")
    payment = Payment.create!(client_id: sub.client_id, purpose: "subscription", subscription_id: sub.id,
                              amount_piastres: 50_000, provider: "simulated", status: "paid",
                              paid_at: Time.current)

    assert_equal [ payment.id ], sub.payments.pluck(:id)
  end
end
