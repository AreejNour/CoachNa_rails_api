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

  # ── approve ───────────────────────────────────────────────────────────────────

  test "approve transitions a pending review to visible and sets flash notice" do
    sign_in
    coach  = make_coach("+201000000090")
    client = make_client("+201000000091")
    review = make_review(coach: coach, client: client, rating: 5, status: "pending")

    post admin_approve_review_path(review)
    assert_redirected_to admin_review_path(review)
    assert_equal "Review approved.", flash[:notice]
    assert_equal "visible", review.reload.status
    assert_equal 1, coach.reload.review_count
  end

  test "approve on an already-visible review sets flash alert and leaves status unchanged" do
    sign_in
    coach  = make_coach("+201000000092")
    client = make_client("+201000000093")
    review = make_review(coach: coach, client: client, rating: 4, status: "visible")

    post admin_approve_review_path(review)
    assert_redirected_to admin_review_path(review)
    assert_match "already", flash[:alert]
    assert_equal "visible", review.reload.status
  end

  test "approve unauthenticated redirects to login and does not change status" do
    coach  = make_coach("+201000000094")
    client = make_client("+201000000095")
    review = make_review(coach: coach, client: client, rating: 3, status: "pending")

    post admin_approve_review_path(review)
    assert_redirected_to "/admin/login"
    assert_equal "pending", review.reload.status
  end

  # ── reject ────────────────────────────────────────────────────────────────────

  test "reject transitions a pending review to rejected and sets flash notice" do
    sign_in
    coach  = make_coach("+201000000096")
    client = make_client("+201000000097")
    review = make_review(coach: coach, client: client, rating: 2, status: "pending")
    make_photo(review, storage_key: "photos/reject_me.jpg")

    swap_method(Storage.current, :delete, ->(_key) { nil }) do
      post admin_reject_review_path(review)
    end

    assert_redirected_to admin_review_path(review)
    assert_equal "Review rejected.", flash[:notice]
    assert_equal "rejected", review.reload.status
  end

  test "reject on an already-visible review sets flash alert and leaves status unchanged" do
    sign_in
    coach  = make_coach("+201000000098")
    client = make_client("+201000000099")
    review = make_review(coach: coach, client: client, rating: 4, status: "visible")

    post admin_reject_review_path(review)
    assert_redirected_to admin_review_path(review)
    assert_match "already", flash[:alert]
    assert_equal "visible", review.reload.status
  end

  test "reject unauthenticated redirects to login and does not change status" do
    coach  = make_coach("+201000000100")
    client = make_client("+201000000101")
    review = make_review(coach: coach, client: client, rating: 3, status: "pending")

    post admin_reject_review_path(review)
    assert_redirected_to "/admin/login"
    assert_equal "pending", review.reload.status
  end

  # ── view gating ───────────────────────────────────────────────────────────────

  test "show for a pending review includes Approve and Reject controls with confirm" do
    sign_in
    coach  = make_coach("+201000000102")
    client = make_client("+201000000103")
    review = make_review(coach: coach, client: client, rating: 4, status: "pending")

    get admin_review_path(review)
    assert_response :ok
    assert_includes @response.body, admin_approve_review_path(review)
    assert_includes @response.body, admin_reject_review_path(review)
    assert_includes @response.body, "confirm("
    assert_includes @response.body, "onsubmit="
  end

  test "show for a visible review shows no approve/reject controls but shows already line" do
    sign_in
    coach  = make_coach("+201000000104")
    client = make_client("+201000000105")
    review = make_review(coach: coach, client: client, rating: 5, status: "visible")

    get admin_review_path(review)
    assert_response :ok
    assert_not_includes @response.body, admin_approve_review_path(review)
    assert_not_includes @response.body, admin_reject_review_path(review)
    assert_includes @response.body, "Already"
  end
end
