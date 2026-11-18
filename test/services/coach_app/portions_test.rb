require "test_helper"

class CoachApp::PortionsTest < ActiveSupport::TestCase
  setup { @coach = Coach.create!(phone: "+201012349001", password_hash: "h", full_name: "Coach P") }

  test "standard sizes" do
    assert_equal({ "carb" => 30.0, "protein" => 30.0, "fat" => 10.0, "fruit" => 15.0, "dairy" => 10.0 },
                 CoachApp::Portions::STANDARD)
  end

  test "sizes_for falls back to standard and applies coach overrides" do
    assert_equal CoachApp::Portions::STANDARD, CoachApp::Portions.sizes_for(@coach)
    CoachPortionSize.create!(coach_id: @coach.id, group: "carb", grams_of_macro: 25)
    sizes = CoachApp::Portions.sizes_for(@coach)
    assert_equal 25.0, sizes["carb"]
    assert_equal 30.0, sizes["protein"]
  end

  test "target_grams multiplies count by size and is nil for vegetables" do
    sizes = CoachApp::Portions::STANDARD
    assert_equal 60.0, CoachApp::Portions.target_grams("carb", 2, sizes)
    assert_equal 22.5, CoachApp::Portions.target_grams("fruit", 1.5, sizes)
    assert_nil CoachApp::Portions.target_grams("vegetable", 3, sizes)
  end

  test "defining macro per group" do
    assert_equal "carbs", CoachApp::Portions::MACRO["fruit"]
    assert_equal "protein", CoachApp::Portions::MACRO["dairy"]
    assert_nil CoachApp::Portions::MACRO["vegetable"]
  end
end
