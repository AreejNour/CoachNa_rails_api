require "test_helper"

class CoachApp::PortionSizesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @coach = Coach.create!(phone: "+201012349101", password_hash: "h", full_name: "Sara")
    @other = Coach.create!(phone: "+201012349102", password_hash: "h", full_name: "Other")
  end

  def auth = { "Authorization" => "Bearer #{CoachApp::AccessToken.sign(@coach.id)}" }
  def sizes = response.parsed_body["data"]["sizes"]
  def put_sizes(list) = put("/coach/portion-sizes", params: { sizes: list }, headers: auth, as: :json)

  test "requires a token" do
    get "/coach/portion-sizes"
    assert_response :unauthorized
    put "/coach/portion-sizes", params: { sizes: [] }, as: :json
    assert_response :unauthorized
  end

  test "defaults are standard, in order, with macros" do
    get "/coach/portion-sizes", headers: auth
    assert_response :success
    assert_equal %w[carb protein fat fruit dairy], sizes.map { |s| s["group"] }
    assert_equal %w[carbs protein fat carbs protein], sizes.map { |s| s["macro"] }
    assert_equal [ 30, 30, 10, 15, 10 ], sizes.map { |s| s["gramsOfMacro"] }
    assert(sizes.all? { |s| s["isStandard"] == true })
  end

  test "put overrides a group and get shows it" do
    put_sizes([ { group: "protein", gramsOfMacro: 40 } ])
    assert_response :success
    protein = sizes.find { |s| s["group"] == "protein" }
    assert_equal 40, protein["gramsOfMacro"]
    assert_equal false, protein["isStandard"]
    get "/coach/portion-sizes", headers: auth
    assert_equal 40, sizes.find { |s| s["group"] == "protein" }["gramsOfMacro"]
  end

  test "putting the standard value removes the row" do
    put_sizes([ { group: "protein", gramsOfMacro: 40 } ])
    put_sizes([ { group: "protein", gramsOfMacro: 30 } ])
    assert_equal 0, CoachPortionSize.where(coach_id: @coach.id).count
    assert_equal true, sizes.find { |s| s["group"] == "protein" }["isStandard"]
  end

  test "groups not in the body are untouched" do
    put_sizes([ { group: "fat", gramsOfMacro: 12 } ])
    put_sizes([ { group: "carb", gramsOfMacro: 35 } ])
    assert_equal 12, sizes.find { |s| s["group"] == "fat" }["gramsOfMacro"]
  end

  test "invalid requests are 400 and write nothing" do
    [ [ { group: "vegetable", gramsOfMacro: 10 } ],
      [ { group: "protein", gramsOfMacro: 0 } ],
      [ { group: "protein", gramsOfMacro: 201 } ],
      [ { group: "protein", gramsOfMacro: "40" } ],
      [ { group: "protein", gramsOfMacro: nil } ],
      [ { group: "nope", gramsOfMacro: 10 } ],
      [ { group: "carb", gramsOfMacro: 40 }, { group: "carb", gramsOfMacro: 41 } ],
      [ { group: "fat", gramsOfMacro: 12 }, { group: "protein", gramsOfMacro: 0 } ] ].each do |list|
      put_sizes(list)
      assert_response :bad_request, list.inspect
    end
    assert_equal 0, CoachPortionSize.count
  end

  test "missing sizes is 400" do
    put "/coach/portion-sizes", params: {}, headers: auth, as: :json
    assert_response :bad_request
  end

  test "another coach is unaffected" do
    put_sizes([ { group: "protein", gramsOfMacro: 40 } ])
    assert_equal 0, CoachPortionSize.where(coach_id: @other.id).count
  end
end
