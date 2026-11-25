require "test_helper"

class Admin::CoachRatingTest < ActiveSupport::TestCase
  def make_coach(phone)
    Coach.create!(full_name: "A", phone: phone, password_hash: "h", status: "approved")
  end

  def make_client(phone)
    Client.create!(phone: phone, password_hash: "h", full_name: "Test Client")
  end

  setup do
    @coach  = make_coach("+201000000070")
    @client = make_client("+201000000071")
  end

  def review(coach: @coach, client: @client, rating:, status:)
    CoachReview.create!(coach: coach, client: client, rating: rating, status: status)
  end

  # ── case 1: three visible reviews (5,4,4) → avg 4.333… rounds to 4.3 ──────
  test "three visible reviews: average_rating 4.3, review_count 3" do
    review(rating: 5, status: "visible")
    review(rating: 4, status: "visible")
    review(rating: 4, status: "visible")

    Admin::CoachRating.recompute(@coach.id)

    @coach.reload
    assert_equal 3, @coach.review_count
    assert_equal 4.3, @coach.average_rating.to_f
  end

  # ── case 2: two visible reviews (5,4) → avg 4.5 (rounding boundary) ────────
  test "two visible reviews: average_rating 4.5, review_count 2" do
    review(rating: 5, status: "visible")
    review(rating: 4, status: "visible")

    Admin::CoachRating.recompute(@coach.id)

    @coach.reload
    assert_equal 2, @coach.review_count
    assert_equal 4.5, @coach.average_rating.to_f
  end

  # ── case 3: only non-visible reviews → average_rating nil, count 0 ──────────
  test "no visible reviews: average_rating nil, review_count 0" do
    review(rating: 5, status: "pending")
    review(rating: 4, status: "rejected")
    review(rating: 3, status: "hidden")

    Admin::CoachRating.recompute(@coach.id)

    @coach.reload
    assert_nil @coach.average_rating
    assert_equal 0, @coach.review_count
  end

  # ── case 4: visible review for another coach is excluded ────────────────────
  test "other coach visible review does not affect this coach" do
    other_coach  = make_coach("+201000000072")
    other_client = make_client("+201000000073")
    review(coach: other_coach, client: other_client, rating: 5, status: "visible")

    # @coach has no visible reviews
    Admin::CoachRating.recompute(@coach.id)

    @coach.reload
    assert_nil @coach.average_rating
    assert_equal 0, @coach.review_count
  end
end
