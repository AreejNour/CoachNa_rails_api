require "test_helper"

class CoachApp::ReviewsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @coach = Coach.create!(phone: "+201012348001", password_hash: "h", full_name: "Coach Mona")
  end

  def auth = { "Authorization" => "Bearer #{CoachApp::AccessToken.sign(@coach.id)}" }
  def data = response.parsed_body["data"]

  def make_client(n, name)
    Client.create!(phone: "+2010123481#{n.to_s.rjust(2, "0")}", password_hash: "h", full_name: name)
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

  def photo(rev, kind, status: "visible", key: "k/#{SecureRandom.hex(4)}")
    ReviewPhoto.create!(review_id: rev.id, kind: kind, storage_key: key,
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

  test "first name is an empty string for a whitespace-only full_name" do
    client = make_client(1, "Nour")
    client.update_column(:full_name, "   ")
    review(client, 1.day.ago)
    get "/coach/reviews", headers: auth
    assert_equal "", data["reviews"][0]["reviewerFirstName"]
  end

  test "reviews sharing a created_at are ordered by id descending" do
    at = 2.days.ago
    a = review(make_client(1, "Nour"), at)
    b = review(make_client(2, "Omar"), at)
    get "/coach/reviews", headers: auth
    assert_equal [ b.id, a.id ].sort.reverse, data["reviews"].map { |r| r["id"] }
  end

  JPEG_BYTES = "\xFF\xD8\xFF\xE0\x00\x10JFIF".b

  def stored_photo(rev, kind: "before", ext: "jpg", status: "visible", bytes: JPEG_BYTES)
    key = "reviews/#{rev.id}/#{SecureRandom.hex(4)}.#{ext}"
    Storage.current.put(key, bytes, mime_type: "application/octet-stream")
    photo(rev, kind, status: status, key: key)
  end

  def visible_review(coach: @coach, status: "visible")
    @n = (@n || 10) + 1
    review(make_client(@n, "Nour Hassan"), 1.day.ago, coach: coach, status: status)
  end

  test "photo needs a token" do
    get "/coach/reviews/photos/#{SecureRandom.uuid}"
    assert_response :unauthorized
  end

  test "serves a visible photo of a visible review with its bytes, type and no-store" do
    p = stored_photo(visible_review)
    get "/coach/reviews/photos/#{p.id}", headers: auth
    assert_response :ok
    assert_equal JPEG_BYTES, response.body.b
    assert_includes response.media_type, "image/jpeg"
    assert_equal "no-store", response.headers["Cache-Control"]
  end

  test "infers the content type from the key extension" do
    { "png" => "image/png", "webp" => "image/webp", "jpeg" => "image/jpeg", "bin" => "application/octet-stream" }.each do |ext, mime|
      rev = visible_review
      get "/coach/reviews/photos/#{stored_photo(rev, ext: ext).id}", headers: auth
      assert_response :ok
      assert_equal mime, response.media_type
    end
  end

  test "a photo url from the list fetches successfully" do
    stored_photo(visible_review)
    get "/coach/reviews", headers: auth
    url = data["reviews"][0]["photos"][0]["url"]
    get url, headers: auth
    assert_response :ok
    assert_equal JPEG_BYTES, response.body.b
  end

  test "photo is 404 when pending, hidden, on a non-visible review, another coach's, unknown, or file missing" do
    rev = visible_review
    other = Coach.create!(phone: "+201012348003", password_hash: "h", full_name: "Other")
    missing = photo(visible_review, "after", key: "reviews/gone/none.jpg")
    ids = [ stored_photo(rev, status: "pending").id,
            stored_photo(rev, kind: "after", status: "hidden").id,
            stored_photo(visible_review(status: "pending")).id,
            stored_photo(visible_review(status: "hidden")).id,
            stored_photo(visible_review(coach: other)).id,
            SecureRandom.uuid,
            missing.id ]
    ids.each do |id|
      get "/coach/reviews/photos/#{id}", headers: auth
      assert_response :not_found, "expected 404 for #{id}"
    end
  end
end
