require "test_helper"

class CoachApp::PackagesTest < ActiveSupport::TestCase
  setup do
    @coach = Coach.create!(phone: "+201012345720", password_hash: "h", full_name: "Sara")
  end

  def valid_attrs(over = {})
    {
      "name" => "Weight loss — 1 month",
      "description" => "A month of guidance.",
      "pricePiastres" => 50_000,
      "durationDays" => 30,
      "includes" => [ "Weekly plan updates", "Chat support" ]
    }.merge(over)
  end

  test "create stores piastres, duration, includes and is active" do
    package = CoachApp::Packages.create!(@coach, valid_attrs)
    assert_equal 50_000, package.price_piastres
    assert_equal 30, package.duration_days
    assert_equal [ "Weekly plan updates", "Chat support" ], package.includes
    assert package.is_active
    assert_equal @coach.id, package.coach_id
  end

  test "create trims the name and includes items" do
    package = CoachApp::Packages.create!(@coach, valid_attrs("name" => "  Plan  ", "includes" => [ " Chat " ]))
    assert_equal "Plan", package.name
    assert_equal [ "Chat" ], package.includes
  end

  test "list returns only the coach's active packages, newest first" do
    old = CoachApp::Packages.create!(@coach, valid_attrs("name" => "Old"))
    old.update!(created_at: 1.day.ago)
    new = CoachApp::Packages.create!(@coach, valid_attrs("name" => "New"))
    other = Coach.create!(phone: "+201012345721", password_hash: "h", full_name: "Other")
    CoachApp::Packages.create!(other, valid_attrs("name" => "Theirs"))
    CoachApp::Packages.soft_delete!(@coach, CoachApp::Packages.create!(@coach, valid_attrs("name" => "Gone")).id)

    names = CoachApp::Packages.list(@coach).map(&:name)
    assert_equal [ "New", "Old" ], names
  end

  test "update changes fields" do
    package = CoachApp::Packages.create!(@coach, valid_attrs)
    CoachApp::Packages.update!(@coach, package.id, { "name" => "Renamed", "pricePiastres" => 70_000 })
    package.reload
    assert_equal "Renamed", package.name
    assert_equal 70_000, package.price_piastres
    assert_equal 30, package.duration_days
  end

  test "soft delete deactivates the row but keeps it" do
    package = CoachApp::Packages.create!(@coach, valid_attrs)
    CoachApp::Packages.soft_delete!(@coach, package.id)
    assert_not package.reload.is_active
    assert_empty CoachApp::Packages.list(@coach)
  end

  test "another coach's package is not found for update or delete" do
    other = Coach.create!(phone: "+201012345722", password_hash: "h", full_name: "Other")
    package = CoachApp::Packages.create!(other, valid_attrs)
    assert_raises(ApiError) { CoachApp::Packages.update!(@coach, package.id, { "name" => "X" }) }
    assert_raises(ApiError) { CoachApp::Packages.soft_delete!(@coach, package.id) }
    assert other.coach_packages.first.is_active
  end

  test "a soft-deleted package cannot be edited" do
    package = CoachApp::Packages.create!(@coach, valid_attrs)
    CoachApp::Packages.soft_delete!(@coach, package.id)
    assert_raises(ApiError) { CoachApp::Packages.update!(@coach, package.id, { "name" => "X" }) }
  end

  test "create rejects bad input" do
    bad = [
      { "name" => "" },
      { "name" => "x" * 81 },
      { "description" => "x" * 2001 },
      { "pricePiastres" => 0 },
      { "pricePiastres" => -1 },
      { "pricePiastres" => 199.99 },
      { "pricePiastres" => 100_000_01 },
      { "durationDays" => 0 },
      { "durationDays" => 366 },
      { "includes" => [] },
      { "includes" => Array.new(21, "x") },
      { "includes" => [ "" ] },
      { "includes" => [ "x" * 121 ] },
      { "includes" => "not an array" }
    ]
    bad.each do |over|
      assert_raises(ApiError, "expected #{over.inspect} to be rejected") do
        CoachApp::Packages.create!(@coach, valid_attrs(over))
      end
    end
  end

  test "description may be cleared to null" do
    package = CoachApp::Packages.create!(@coach, valid_attrs)
    CoachApp::Packages.update!(@coach, package.id, { "description" => "" })
    assert_nil package.reload.description
  end

  test "an empty patch is rejected" do
    package = CoachApp::Packages.create!(@coach, valid_attrs)
    assert_raises(ApiError) { CoachApp::Packages.update!(@coach, package.id, {}) }
  end
end
