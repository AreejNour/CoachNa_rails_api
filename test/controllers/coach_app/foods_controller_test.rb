require "test_helper"

class CoachApp::FoodsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @coach = Coach.create!(phone: "+201012349001", password_hash: "h", full_name: "Sara")
    @other = Coach.create!(phone: "+201012349002", password_hash: "h", full_name: "Other")
    @global = Food.create!(name_ar: "أرز عالمي", name_en: "Global Rice", group: "carb",
                           protein_per_100: 2.7, carbs_per_100: 28, fat_per_100: 0.3,
                           weight_basis: "cooked")
  end

  def auth = { "Authorization" => "Bearer #{CoachApp::AccessToken.sign(@coach.id)}" }
  def data = response.parsed_body["data"]

  def body(over = {})
    {
      nameAr: "زبدة لوز",
      nameEn: "Almond Butter",
      group: "fat",
      proteinPer100: 21,
      carbsPer100: 20,
      fatPer100: 55,
      weightBasis: "as_is",
      householdUnit: "ملعقة",
      gramsPerUnit: 16
    }.merge(over)
  end

  test "every route needs a token" do
    get "/coach/foods"
    assert_response :unauthorized
    post "/coach/foods", params: body, as: :json
    assert_response :unauthorized
  end

  test "create returns the food with derived kcal and isCustom" do
    post "/coach/foods", params: body, headers: auth, as: :json
    assert_response :created
    assert_equal "Almond Butter", data["nameEn"]
    assert_equal 4 * 21 + 4 * 20 + 9 * 55, data["kcalPer100"]
    assert data["isCustom"]
    assert_equal "ملعقة", data["householdUnit"]
  end

  test "list returns global foods and own customs, not another coach's" do
    post "/coach/foods", params: body(nameEn: "Mine"), headers: auth, as: :json
    @other.foods.create!(name_ar: "سر", name_en: "Theirs", group: "fat", protein_per_100: 1,
                         carbs_per_100: 1, fat_per_100: 1, weight_basis: "as_is", is_active: true)

    get "/coach/foods", headers: auth
    assert_response :ok
    names = data["foods"].map { |f| f["nameEn"] }
    assert_includes names, "Global Rice"
    assert_includes names, "Mine"
    refute_includes names, "Theirs"
  end

  test "update changes a field; delete soft-deletes and drops from the list" do
    post "/coach/foods", params: body(nameEn: "Editable"), headers: auth, as: :json
    id = data["id"]

    patch "/coach/foods/#{id}", params: { nameEn: "Edited" }, headers: auth, as: :json
    assert_response :ok
    assert_equal "Edited", data["nameEn"]

    delete "/coach/foods/#{id}", headers: auth
    assert_response :ok
    get "/coach/foods", headers: auth
    refute_includes data["foods"].map { |f| f["id"] }, id
  end

  test "another coach's food id is 404; a global food cannot be edited by a coach" do
    theirs = @other.foods.create!(name_ar: "س", name_en: "T", group: "fat", protein_per_100: 1,
                                  carbs_per_100: 1, fat_per_100: 1, weight_basis: "as_is", is_active: true)
    patch "/coach/foods/#{theirs.id}", params: { nameEn: "Hacked" }, headers: auth, as: :json
    assert_response :not_found
    patch "/coach/foods/#{@global.id}", params: { nameEn: "Hacked" }, headers: auth, as: :json
    assert_response :not_found
    assert_equal "T", theirs.reload.name_en
  end

  test "a bad body is a 400 (macro out of range, unknown group, unpaired household unit)" do
    post "/coach/foods", params: body(proteinPer100: 200), headers: auth, as: :json
    assert_response :bad_request
    post "/coach/foods", params: body(group: "snacks"), headers: auth, as: :json
    assert_response :bad_request
    post "/coach/foods", params: body(householdUnit: "ملعقة", gramsPerUnit: nil), headers: auth, as: :json
    assert_response :bad_request
  end
end
