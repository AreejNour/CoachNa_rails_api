require "test_helper"

class Admin::CoachClientsQueryTest < ActiveSupport::TestCase
  @@seq = 0
  def nxt; @@seq += 1; end
  def uniq_phone; format("+20100%07d", nxt); end

  def make_coach(name = "Coach")
    Coach.create!(full_name: name, phone: uniq_phone, password_hash: "h", status: "approved")
  end

  def make_client(name)
    Client.create!(full_name: name, phone: uniq_phone, password_hash: "h")
  end

  def sub(coach, client, status:, starts_at: Time.current)
    pkg = CoachPackage.create!(coach: coach, name: "Plan", price_piastres: 50_000,
                               duration_days: 30, includes: {})
    Subscription.create!(client: client, coach: coach, package_id: pkg.id, status: status,
                         price_piastres: 50_000, commission_percent: 10, commission_piastres: 5_000,
                         starts_at: starts_at, ends_at: starts_at + 30.days)
  end

  test "active filter keeps only clients with a live subscription to this coach" do
    coach = make_coach
    live  = make_client("Live Lara"); sub(coach, live, status: "active")
    ended = make_client("Ended Ed");  sub(coach, ended, status: "ended")

    result = Admin::CoachClientsQuery.call(coach: coach, filter: "active")

    assert_equal [ "Live Lara" ], result.rows.map { |r| r.client.full_name }
    assert_equal 1, result.total
  end

  test "all filter returns every distinct client of the coach" do
    coach = make_coach
    live  = make_client("Live Lara"); sub(coach, live, status: "active")
    ended = make_client("Ended Ed");  sub(coach, ended, status: "ended")

    result = Admin::CoachClientsQuery.call(coach: coach, filter: "all")

    assert_equal [ "Ended Ed", "Live Lara" ], result.rows.map { |r| r.client.full_name }
    assert_equal 2, result.total
  end

  test "a client with multiple subs to the coach appears once with the latest status and date" do
    coach = make_coach
    cli = make_client("Repeat Rae")
    sub(coach, cli, status: "ended", starts_at: 90.days.ago)
    sub(coach, cli, status: "active", starts_at: 2.days.ago)

    result = Admin::CoachClientsQuery.call(coach: coach, filter: "all")

    assert_equal 1, result.rows.length
    assert_equal "active", result.rows.first.latest_status
    assert_in_delta 2.days.ago.to_f, result.rows.first.latest_started_at.to_f, 5
  end

  test "excludes clients of other coaches" do
    coach = make_coach("Mine")
    other = make_coach("Other")
    mine  = make_client("Mine Mia");   sub(coach, mine, status: "active")
    theirs = make_client("Their Tom"); sub(other, theirs, status: "active")

    result = Admin::CoachClientsQuery.call(coach: coach, filter: "all")

    assert_equal [ "Mine Mia" ], result.rows.map { |r| r.client.full_name }
  end

  test "paginates: total counts all, rows are limited to the page window" do
    coach = make_coach
    3.times { |i| sub(coach, make_client(format("Client %02d", i)), status: "active") }

    result = Admin::CoachClientsQuery.call(coach: coach, filter: "all", page: 1, per_page: 2)

    assert_equal 3, result.total
    assert_equal 2, result.rows.length
    assert_equal 2, result.total_pages
    assert_equal 1, result.page
  end

  test "out-of-range page clamps into range" do
    coach = make_coach
    sub(coach, make_client("Only One"), status: "active")

    result = Admin::CoachClientsQuery.call(coach: coach, filter: "all", page: 999, per_page: 25)

    assert_equal 1, result.page
    assert_equal 1, result.rows.length
  end
end
