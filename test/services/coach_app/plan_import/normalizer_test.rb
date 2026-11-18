require "test_helper"

class CoachApp::PlanImport::NormalizerTest < ActiveSupport::TestCase
  setup do
    @coach = Coach.create!(phone: "+201012349001", password_hash: "h", full_name: "Coach A")
    @other = Coach.create!(phone: "+201012349002", password_hash: "h", full_name: "Coach B")
    @bread = Food.create!(name_ar: "خبز", name_en: "Toast", group: "carb", protein_per_100: 9,
                          carbs_per_100: 49, fat_per_100: 3, weight_basis: "raw",
                          household_unit: "piece", grams_per_unit: 30)
    @potato = Food.create!(name_ar: "بطاطس", name_en: "Potato", group: "carb", protein_per_100: 2,
                           carbs_per_100: 17, fat_per_100: 0.1, weight_basis: "cooked")
    @chicken = Food.create!(name_ar: "دجاج", name_en: "Chicken", group: "protein", protein_per_100: 27,
                            carbs_per_100: 0, fat_per_100: 3, weight_basis: "cooked")
    @foreign = Food.create!(name_ar: "س", name_en: "Secret", group: "carb", protein_per_100: 1,
                            carbs_per_100: 1, fat_per_100: 1, weight_basis: "raw", owner_coach_id: @other.id)
    @visible = CoachApp::Foods.visible_by_id(@coach)
  end

  def run_norm(raw)
    out = CoachApp::PlanImport::Normalizer.call(raw, @visible)
    # Must be accepted unchanged by the real validator.
    if out[:options].any?
      CoachApp::PlanInput.validate({ "notes" => out[:notes], "options" => out[:options] }.deep_stringify_keys, @visible)
    end
    out
  end

  def raw_with(items, over = {})
    { "tips" => nil, "options" => [ { "label" => "A", "meals" => [
      { "title" => "M", "slot" => "lunch", "items" => items.map { |i| { "kind" => "food" }.merge(i) } }.merge(over)
    ] } ] }
  end

  def first_item(out) = out[:options][0]["meals"][0]["components"][0]

  test "clean plan has zero flags and maps to wire shape" do
    raw = raw_with([
      { "foodId" => @bread.id, "quantity" => 2, "unit" => "piece", "sourceLine" => "2 toast" },
      { "foodId" => @potato.id, "quantity" => 120, "unit" => "g", "preparation" => "cooked" },
      { "foodId" => @chicken.id, "quantity" => 100, "unit" => "g" }
    ])
    out = run_norm(raw)
    assert_equal 0, out[:flag_count]
    assert_equal "food", first_item(out)["kind"]
    assert_equal "lunch", out[:options][0]["meals"][0]["slot"]
    assert_equal 0, out[:options][0]["meals"][0]["position"]
  end

  test "unknown food id becomes flagged text" do
    out = run_norm(raw_with([ { "foodId" => SecureRandom.uuid, "quantity" => 5, "unit" => "g", "sourceLine" => "mystery" } ]))
    c = first_item(out)
    assert_equal "text", c["kind"]
    assert_equal "mystery", c["freeText"]
    assert_nil c["foodId"]
    assert_includes c["importFlag"], "Couldn't match a food"
    assert_equal 1, out[:flag_count]
  end

  test "another coach's custom food becomes flagged text" do
    out = run_norm(raw_with([ { "foodId" => @foreign.id, "quantity" => 5, "unit" => "g", "sourceLine" => "theirs" } ]))
    assert_equal "text", first_item(out)["kind"]
    assert_nil first_item(out)["foodId"]
    assert first_item(out)["importFlag"]
  end

  test "bad unit becomes flagged text" do
    out = run_norm(raw_with([ { "foodId" => @potato.id, "quantity" => 1, "unit" => "bucket", "sourceLine" => "1 bucket potato" } ]))
    assert_equal "text", first_item(out)["kind"]
    assert first_item(out)["importFlag"]
  end

  test "unit the food cannot convert becomes flagged text" do
    out = run_norm(raw_with([ { "foodId" => @potato.id, "quantity" => 1, "unit" => "cup", "sourceLine" => "1 cup" } ]))
    assert_equal "text", first_item(out)["kind"]
    assert first_item(out)["importFlag"]
  end

  test "quantity 15000 g is kept as food but flagged" do
    out = run_norm(raw_with([ { "foodId" => @potato.id, "quantity" => 15_000, "unit" => "g" } ]))
    assert_equal "food", first_item(out)["kind"]
    assert_equal "Check this amount", first_item(out)["importFlag"]
  end

  test "unit quantity out of range is flagged" do
    out = run_norm(raw_with([ { "foodId" => @bread.id, "quantity" => 40, "unit" => "piece" } ]))
    assert_equal "food", first_item(out)["kind"]
    assert_equal "Check this amount", first_item(out)["importFlag"]
  end

  test "zero or absurd quantity falls back to flagged text still valid" do
    [ 0, -3, nil, "5", 1_000_000 ].each do |q|
      out = run_norm(raw_with([ { "foodId" => @potato.id, "quantity" => q, "unit" => "g", "sourceLine" => "line" } ]))
      assert_equal "text", first_item(out)["kind"]
      assert first_item(out)["importFlag"]
    end
  end

  test "macro grams out of 1-200 flagged, invalid ones become text" do
    macro = ->(g) { { "kind" => "macro", "macro" => "protein", "grams" => g, "sourceLine" => "30g protein" } }
    assert_nil first_item(run_norm(raw_with([ macro.call(30) ])))["importFlag"]
    out = run_norm(raw_with([ macro.call(500) ]))
    assert_equal "macro", first_item(out)["kind"]
    assert_equal 500, first_item(out)["macroGrams"]
    assert first_item(out)["importFlag"]
    out = run_norm(raw_with([ macro.call(0) ]))
    assert_equal "text", first_item(out)["kind"]
    assert_equal "30g protein", first_item(out)["freeText"]
    assert first_item(out)["importFlag"]
    assert_equal "text", first_item(run_norm(raw_with([ macro.call(9000) ])))["kind"]
  end

  test "portion count 40 is flagged and stays valid" do
    p = ->(n) { { "kind" => "portion", "portionGroup" => "carb", "portionCount" => n, "sourceLine" => "x portions" } }
    out = run_norm(raw_with([ p.call(40) ]))
    assert first_item(out)["importFlag"]
    assert_equal 1, out[:flag_count]
    out = run_norm(raw_with([ p.call(0.1) ]))
    assert_equal "portion", first_item(out)["kind"]
    assert first_item(out)["importFlag"]
    out = run_norm(raw_with([ p.call(2) ]))
    assert_equal "portion", first_item(out)["kind"]
    assert_nil first_item(out)["importFlag"]
    assert_equal 2, first_item(out)["portionCount"]
  end

  test "text item maps text to freeText and bad kind falls back" do
    out = run_norm(raw_with([ { "kind" => "text", "text" => "any vegetables", "sourceLine" => "veg" } ]))
    assert_equal "veg", first_item(out)["freeText"]
    out = run_norm(raw_with([ { "kind" => "wat", "sourceLine" => "x" } ]))
    assert_equal "text", first_item(out)["kind"]
  end

  test "invented or replaced lines are always flagged" do
    cases = [ { "kind" => "wat", "sourceLine" => "x" }, {}, { "kind" => "text", "text" => "  " } ]
    cases.each do |item|
      out = run_norm({ "options" => [ { "meals" => [ { "items" => [ item ] } ] } ] })
      assert_equal "text", first_item(out)["kind"]
      assert first_item(out)["importFlag"], item.inspect
      assert_equal 1, out[:flag_count]
    end
  end

  test "string item becomes flagged text, other junk skipped" do
    out = run_norm({ "options" => [ { "meals" => [ { "items" => [ "2 eggs", 5, nil, "  " ] } ] } ] })
    comps = out[:options][0]["meals"][0]["components"]
    assert_equal 1, comps.length
    assert_equal "2 eggs", comps[0]["freeText"]
    assert comps[0]["importFlag"]
    assert_equal 1, out[:flag_count]
    assert_empty run_norm({ "options" => [ { "meals" => [ { "items" => [ 5 ] } ] } ] })[:options]
    long = run_norm({ "options" => [ { "meals" => [ { "items" => [ "e" * 400 ] } ] } ] })
    assert_equal 200, long[:options][0]["meals"][0]["components"][0]["freeText"].length
  end

  test "long doubt is trimmed so system flags survive" do
    out = run_norm(raw_with([ { "foodId" => @potato.id, "quantity" => 15_000, "unit" => "g", "doubt" => "d" * 400 } ]))
    flag = first_item(out)["importFlag"]
    assert_operator flag.length, :<=, 300
    assert_includes flag, "Check this amount"
  end

  test "freeText is truncated to 200" do
    out = run_norm(raw_with([ { "kind" => "text", "sourceLine" => "a" * 500 } ]))
    assert_equal 200, first_item(out)["freeText"].length
  end

  test "doubt flags a clean item and is truncated to 300" do
    out = run_norm(raw_with([ { "foodId" => @potato.id, "quantity" => 100, "unit" => "g", "doubt" => "d" * 400 } ]))
    assert_equal "food", first_item(out)["kind"]
    assert_equal 300, first_item(out)["importFlag"].length
  end

  test "defaults, slot filtering and drop of empty meals/options" do
    raw = { "options" => [
      { "label" => nil, "meals" => [
        { "title" => nil, "slot" => "brunch", "items" => [ { "kind" => "text", "sourceLine" => "tea" } ] },
        { "title" => "Empty", "items" => [] },
        { "title" => nil, "slot" => "snack", "items" => [ { "kind" => "text", "sourceLine" => "nuts" } ] }
      ] },
      { "label" => "Empty option", "meals" => [ { "title" => "x", "items" => [] } ] },
      { "label" => "Real", "meals" => [ { "items" => [ { "kind" => "text", "sourceLine" => "z" } ] } ] }
    ], "tips" => "Drink water" }
    out = run_norm(raw)
    assert_equal "Drink water", out[:notes]
    assert_equal [ "Option 1", "Real" ], out[:options].map { |o| o["label"] }
    meals = out[:options][0]["meals"]
    assert_equal [ "Meal 1", "Meal 2" ], meals.map { |m| m["title"] }
    assert_equal [ nil, "snack" ], meals.map { |m| m["slot"] }
    assert_equal [ 0, 1 ], meals.map { |m| m["position"] }
    assert_equal "Meal 1", out[:options][1]["meals"][0]["title"]
  end

  test "too many items, meals and options keep first N and flag the last kept item" do
    text = { "kind" => "text", "sourceLine" => "t" }
    out = run_norm(raw_with(Array.new(31) { text.dup }))
    comps = out[:options][0]["meals"][0]["components"]
    assert_equal 30, comps.length
    assert_equal "Plan was longer than CoachNa allows — check the rest", comps.last["importFlag"]
    assert_nil comps.first["importFlag"]

    meals = Array.new(31) { { "title" => "m", "items" => [ text ] } }
    out = run_norm({ "options" => [ { "label" => "A", "meals" => meals } ] })
    assert_equal 30, out[:options][0]["meals"].length
    assert out[:options][0]["meals"].last["components"].last["importFlag"]
    assert_equal 1, out[:flag_count]

    options = Array.new(6) { |i| { "label" => "O#{i}", "meals" => [ { "title" => "m", "items" => [ text ] } ] } }
    out = run_norm({ "options" => options })
    assert_equal 5, out[:options].length
    assert out[:options].last["meals"].last["components"].last["importFlag"]
    assert_equal 1, out[:flag_count]
  end

  test "garbage input does not raise" do
    assert_equal [], CoachApp::PlanImport::Normalizer.call(nil, @visible)[:options]
    assert_equal [], CoachApp::PlanImport::Normalizer.call({ "options" => "x" }, @visible)[:options]
  end
end
