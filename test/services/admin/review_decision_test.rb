require "test_helper"

class Admin::ReviewDecisionTest < ActiveSupport::TestCase
  # ── helpers ─────────────────────────────────────────────────────────────────

  def make_coach(phone)
    Coach.create!(full_name: "Test Coach", phone: phone, password_hash: "h", status: "approved")
  end

  def make_client(phone)
    Client.create!(phone: phone, password_hash: "h", full_name: "Test Client")
  end

  def make_admin
    AdminUser.create!(name: "Admin", email: "admin_#{SecureRandom.hex(4)}@example.com", password: "password123")
  end

  def make_review(coach:, client:, rating: 5, status: "pending")
    CoachReview.create!(coach: coach, client: client, rating: rating, status: status)
  end

  def make_photo(review, kind, storage_key)
    ReviewPhoto.create!(
      review_id: review.id,
      kind: kind,
      storage_key: storage_key,
      consent_given_at: Time.current,
      status: "pending"
    )
  end

  setup do
    @coach  = make_coach("+201000000080")
    @client = make_client("+201000000081")
    @admin  = make_admin
    @review = make_review(coach: @coach, client: @client, rating: 4)
    @photo1 = make_photo(@review, "before", "photos/before_#{SecureRandom.hex(4)}.jpg")
    @photo2 = make_photo(@review, "after",  "photos/after_#{SecureRandom.hex(4)}.jpg")
  end

  # ── approve! ────────────────────────────────────────────────────────────────

  test "approve! sets review to visible with decided metadata" do
    Admin::ReviewDecision.approve!(review: @review, admin: @admin)

    @review.reload
    assert_equal "visible", @review.status
    assert_equal @admin.id, @review.decided_by
    assert_not_nil @review.decided_at
  end

  test "approve! sets both photos to visible" do
    Admin::ReviewDecision.approve!(review: @review, admin: @admin)

    assert_equal "visible", @photo1.reload.status
    assert_equal "visible", @photo2.reload.status
  end

  test "approve! triggers rating recompute so coach rating reflects the visible review" do
    Admin::ReviewDecision.approve!(review: @review, admin: @admin)

    @coach.reload
    assert_equal 1, @coach.review_count
    assert_equal 4.0, @coach.average_rating.to_f
  end

  test "approve! does NOT call Storage.current.delete" do
    delete_calls = []
    storage_mock = Object.new
    storage_mock.define_singleton_method(:delete) { |key| delete_calls << key }

    swap_method(Storage, :current, -> { storage_mock }) do
      Admin::ReviewDecision.approve!(review: @review, admin: @admin)
    end

    assert_empty delete_calls
  end

  # ── reject! ─────────────────────────────────────────────────────────────────

  test "reject! sets review to rejected with decided metadata" do
    Admin::ReviewDecision.reject!(review: @review, admin: @admin)

    @review.reload
    assert_equal "rejected", @review.status
    assert_equal @admin.id, @review.decided_by
    assert_not_nil @review.decided_at
  end

  test "reject! sets both photos to rejected" do
    Admin::ReviewDecision.reject!(review: @review, admin: @admin)

    assert_equal "rejected", @photo1.reload.status
    assert_equal "rejected", @photo2.reload.status
  end

  test "reject! calls Storage.current.delete once per photo storage_key" do
    delete_calls = []
    storage_mock = Object.new
    storage_mock.define_singleton_method(:delete) { |key| delete_calls << key }

    swap_method(Storage, :current, -> { storage_mock }) do
      Admin::ReviewDecision.reject!(review: @review, admin: @admin)
    end

    expected_keys = [ @photo1.storage_key, @photo2.storage_key ].sort
    assert_equal expected_keys, delete_calls.sort
  end

  test "reject! does NOT recompute coach rating" do
    @coach.update!(review_count: 3, average_rating: 4.7)

    Admin::ReviewDecision.reject!(review: @review, admin: @admin)

    @coach.reload
    assert_equal 3, @coach.review_count
    assert_equal 4.7, @coach.average_rating.to_f
  end

  # ── already decided ──────────────────────────────────────────────────────────

  test "approve! raises Error when review is already visible, message includes status" do
    @review.update!(status: "visible")

    error = assert_raises(Admin::ReviewDecision::Error) do
      Admin::ReviewDecision.approve!(review: @review, admin: @admin)
    end

    assert_includes error.message, "visible"
  end

  test "reject! raises Error when review is already visible, message includes status" do
    @review.update!(status: "visible")

    error = assert_raises(Admin::ReviewDecision::Error) do
      Admin::ReviewDecision.reject!(review: @review, admin: @admin)
    end

    assert_includes error.message, "visible"
  end

  test "approve! raises Error when review is already rejected, message includes status" do
    @review.update!(status: "rejected")

    error = assert_raises(Admin::ReviewDecision::Error) do
      Admin::ReviewDecision.approve!(review: @review, admin: @admin)
    end

    assert_includes error.message, "rejected"
  end

  test "reject! raises Error when review is already rejected, message includes status" do
    @review.update!(status: "rejected")

    error = assert_raises(Admin::ReviewDecision::Error) do
      Admin::ReviewDecision.reject!(review: @review, admin: @admin)
    end

    assert_includes error.message, "rejected"
  end

  test "already decided: approve! does not change photos or call delete" do
    @review.update!(status: "visible")
    delete_calls = []
    storage_mock = Object.new
    storage_mock.define_singleton_method(:delete) { |key| delete_calls << key }

    swap_method(Storage, :current, -> { storage_mock }) do
      assert_raises(Admin::ReviewDecision::Error) do
        Admin::ReviewDecision.approve!(review: @review, admin: @admin)
      end
    end

    assert_equal "pending", @photo1.reload.status
    assert_equal "pending", @photo2.reload.status
    assert_empty delete_calls
  end

  test "already decided: reject! does not change photos or call delete" do
    @review.update!(status: "rejected")
    delete_calls = []
    storage_mock = Object.new
    storage_mock.define_singleton_method(:delete) { |key| delete_calls << key }

    swap_method(Storage, :current, -> { storage_mock }) do
      assert_raises(Admin::ReviewDecision::Error) do
        Admin::ReviewDecision.reject!(review: @review, admin: @admin)
      end
    end

    assert_equal "pending", @photo1.reload.status
    assert_equal "pending", @photo2.reload.status
    assert_empty delete_calls
  end

  # ── no photos ────────────────────────────────────────────────────────────────

  test "reject! on a photoless pending review succeeds with zero delete calls" do
    photoless_review = make_review(coach: @coach, client: @client, rating: 3)
    delete_calls = []
    storage_mock = Object.new
    storage_mock.define_singleton_method(:delete) { |key| delete_calls << key }

    swap_method(Storage, :current, -> { storage_mock }) do
      Admin::ReviewDecision.reject!(review: photoless_review, admin: @admin)
    end

    assert_equal "rejected", photoless_review.reload.status
    assert_empty delete_calls
  end

  # ── storage error non-fatal ──────────────────────────────────────────────────

  test "storage error during reject! is logged and not re-raised; review is still committed" do
    storage_mock = Object.new
    storage_mock.define_singleton_method(:delete) { |_key| raise "S3 connection refused" }

    swap_method(Storage, :current, -> { storage_mock }) do
      # Must not raise
      Admin::ReviewDecision.reject!(review: @review, admin: @admin)
    end

    assert_equal "rejected", @review.reload.status
  end

  # ── rollback on approve! failure ─────────────────────────────────────────────

  test "exception inside approve! rolls back: review stays pending, photos unchanged, rating unchanged" do
    @coach.update!(review_count: 0, average_rating: nil)

    original_recompute = Admin::CoachRating.method(:recompute)
    swap_method(Admin::CoachRating, :recompute, ->(_coach_id) { raise "recompute exploded" }) do
      assert_raises(RuntimeError) do
        Admin::ReviewDecision.approve!(review: @review, admin: @admin)
      end
    end

    assert_equal "pending", @review.reload.status
    assert_equal "pending", @photo1.reload.status
    assert_equal "pending", @photo2.reload.status
    @coach.reload
    assert_nil @coach.average_rating
    assert_equal 0, @coach.review_count
  end
end
