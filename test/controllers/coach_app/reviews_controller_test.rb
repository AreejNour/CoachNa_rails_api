require "test_helper"

class CoachApp::ReviewsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @coach = Coach.create!(phone: "+201012348001", password_hash: "h", full_name: "Coach Mona")
  end

  def auth = { "Authorization" => "Bearer #{CoachApp::AccessToken.sign(@coach.id)}" }
  def data = response.parsed_body["data"]

  def make_client(n, name)
    Client.create!(phone: "+20101234810#{n}", password_hash: "h", full_name: name)
  end

  def make_sub(coach, client, plan_name)
    pkg = coach.coach_packages.create!(name: plan_name, price_piastres: 1000, duration_days: 30, includes: [ "x" ])
    now = Time.current
    Subscription.create!(client_id: client.id, coach_id: coach.id, package_id: pkg.id, status: "active",
                         price_piastres: 1000, commission_percent: 10, commission_piastres: 100,
                         starts_at: now - 1.day, ends_at: now + 30.days)
  end

  def review(client, at, coach: @coach, rating: 5, body: "great", status: "visible", sub: nil)
    CoachReview.create!(coach_id: coach.id, client_id: client.id, subscription_id: sub&.id, rating: rating,
                        body: body, status: status, created_at: at)
  end

  def photo(rev, kind, status: "visible")
    ReviewPhoto.create!(review_id: rev.id, kind: kind, storage_key: "k/#{SecureRandom.hex(4)}",
                        consent_given_at: Time.current, status: status)
  end

  test "needs a token" do
    get "/coach/reviews"
    assert_response :unauthorized
  end

  test "coach with no reviews gets a null average and empty list" do
    get "/coach/reviews", headers: auth
    assert_response :ok
    assert_nil data["summary"]["averageRating"]
    assert_equal 0, data["summary"]["reviewCount"]
    assert_equal [], data["reviews"]
  end

  test "returns only visible reviews newest first with summary, plan name and visible photos" do
    @coach.update_columns(average_rating: 4.5, review_count: 2)
    c1 = make_client(1, "Nour Hassan")
    c2 = make_client(2, "Omar Ali")
    old = review(c1, 3.days.ago, rating: 4, sub: make_sub(@coach, c1, "3-month plan"))
    recent = review(c2, 1.day.ago, rating: 5, body: nil)
    review(make_client(3, "Pending Pat"), 2.hours.ago, status: "pending")
    review(make_client(4, "Hidden Hal"), 2.hours.ago, status: "hidden")
    after = photo(recent, "after")
    before = photo(recent, "before")
    photo(old, "before", status: "pending")

    other = Coach.create!(phone: "+201012348002", password_hash: "h", full_name: "Other")
    review(c1, 1.hour.ago, coach: other, body: "not mine")

    get "/coach/reviews", headers: auth
    assert_response :ok
    assert_equal({ "averageRating" => 4.5, "reviewCount" => 2 }, data["summary"])
    assert_equal [ recent.id, old.id ], data["reviews"].map { |r| r["id"] }

    r = data["reviews"][0]
    assert_nil r["body"]
    assert_nil r["planName"]
    assert_equal "Omar", r["reviewerFirstName"]
    assert_equal 5, r["rating"]
    assert_equal recent.created_at.iso8601, r["createdAt"]
    assert_equal [ { "id" => before.id, "kind" => "before", "url" => "/coach/reviews/photos/#{before.id}" },
                   { "id" => after.id, "kind" => "after", "url" => "/coach/reviews/photos/#{after.id}" } ], r["photos"]

    r = data["reviews"][1]
    assert_equal "great", r["body"]
    assert_equal "3-month plan", r["planName"]
    assert_equal [], r["photos"]
  end

  test "first name ignores extra whitespace" do
    review(make_client(1, "  Nour   Hassan  "), 1.day.ago)
    get "/coach/reviews", headers: auth
    assert_equal "Nour", data["reviews"][0]["reviewerFirstName"]
  end
end
