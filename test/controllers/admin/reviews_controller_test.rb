require "test_helper"

class Admin::ReviewsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @admin = AdminUser.create!(email: "team@coachna.app", name: "Team", password: "Secret123")
  end

  def sign_in
    post "/admin/login", params: { email: "team@coachna.app", password: "Secret123" }
  end

  def make_coach(phone)
    Coach.create!(full_name: "Coach Name", phone: phone, password_hash: "h", status: "approved")
  end

  def make_client(phone)
    Client.create!(phone: phone, password_hash: "h", full_name: "Client Name")
  end

  def make_review(coach:, client:, rating:, status:, body: "Great coach!")
    CoachReview.create!(coach: coach, client: client, rating: rating, status: status, body: body)
  end

  def make_photo(review, kind: "before", storage_key: "photos/before.jpg", status: "pending")
    ReviewPhoto.create!(review_id: review.id, kind: kind, storage_key: storage_key,
                        status: status, consent_given_at: Time.current)
  end

  # ── index ────────────────────────────────────────────────────────────────────

  test "index lists pending reviews and excludes visible and rejected" do
    sign_in
    coach  = make_coach("+201000000080")
    client = make_client("+201000000081")

    pending_review  = make_review(coach: coach, client: client, rating: 4, status: "pending",  body: "Pending body")
    _visible_review = make_review(coach: coach, client: client, rating: 5, status: "visible",  body: "Visible body")
    _rejected_review = make_review(coach: coach, client: client, rating: 2, status: "rejected", body: "Rejected body")

    get admin_reviews_path
    assert_response :ok
    assert_includes @response.body, "Pending body"
    assert_not_includes @response.body, "Visible body"
    assert_not_includes @response.body, "Rejected body"
    assert_includes @response.body, "Coach Name"
    assert_includes @response.body, "4"
  end

  test "index shows an empty state when no pending reviews" do
    sign_in
    get admin_reviews_path
    assert_response :ok
    assert_includes @response.body, "No reviews"
  end

  test "index redirects to login when not signed in" do
    get admin_reviews_path
    assert_redirected_to "/admin/login"
  end

  # ── show ─────────────────────────────────────────────────────────────────────

  test "show renders the review rating, body, and photo links" do
    sign_in
    coach  = make_coach("+201000000082")
    client = make_client("+201000000083")
    review = make_review(coach: coach, client: client, rating: 3, status: "pending", body: "Show body")
    photo  = make_photo(review, storage_key: "photos/x.jpg")

    get admin_review_path(review)
    assert_response :ok
    assert_includes @response.body, "Show body"
    assert_includes @response.body, "3"
    # photo link must be present
    assert_includes @response.body, admin_review_photo_path(review, photo)
  end

  test "show redirects to login when not signed in" do
    coach  = make_coach("+201000000084")
    client = make_client("+201000000085")
    review = make_review(coach: coach, client: client, rating: 5, status: "pending")
    get admin_review_path(review)
    assert_redirected_to "/admin/login"
  end

  # ── photo ─────────────────────────────────────────────────────────────────────

  test "photo returns bytes with Cache-Control: no-store for a signed-in admin" do
    sign_in
    coach  = make_coach("+201000000086")
    client = make_client("+201000000087")
    review = make_review(coach: coach, client: client, rating: 4, status: "pending")
    photo  = make_photo(review, storage_key: "photos/shot.jpg")

    swap_method(Storage.current, :download_url, ->(_key, _ttl) { nil }) do
      swap_method(Storage.current, :read, ->(_key) { "IMG" }) do
        get admin_review_photo_path(review, photo)
      end
    end

    assert_response :ok
    assert_equal "no-store", @response.headers["Cache-Control"]
    assert_equal "IMG", @response.body
  end

  test "photo redirects to login when not signed in" do
    coach  = make_coach("+201000000088")
    client = make_client("+201000000089")
    review = make_review(coach: coach, client: client, rating: 4, status: "pending")
    photo  = make_photo(review, storage_key: "photos/shot.jpg")
    get admin_review_photo_path(review, photo)
    assert_redirected_to "/admin/login"
  end
end
