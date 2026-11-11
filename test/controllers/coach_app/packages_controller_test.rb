require "test_helper"

class CoachApp::PackagesControllerTest < ActionDispatch::IntegrationTest
  setup { @coach = Coach.create!(phone: "+201012345730", password_hash: "h", full_name: "Sara") }

  def auth = { "Authorization" => "Bearer #{CoachApp::AccessToken.sign(@coach.id)}" }
  def data = response.parsed_body["data"]

  def body(over = {})
    {
      name: "Weight loss — 1 month",
      description: "A month of guidance.",
      pricePiastres: 50_000,
      durationDays: 30,
      includes: [ "Weekly plan updates", "Chat support" ]
    }.merge(over)
  end

  def create_package(over = {})
    post "/coach/packages", params: body(over), headers: auth, as: :json
    data
  end

  test "every route needs a token" do
    get "/coach/packages"
    assert_response :unauthorized
    post "/coach/packages", params: body, as: :json
    assert_response :unauthorized
    patch "/coach/packages/x", params: { name: "X" }, as: :json
    assert_response :unauthorized
    delete "/coach/packages/x"
    assert_response :unauthorized
  end

  test "create returns the contract's package" do
    created = create_package
    assert_response :created
    assert_equal %w[createdAt description durationDays id includes isActive name pricePiastres], created.keys.sort
    assert_equal 50_000, created["pricePiastres"]
    assert_equal [ "Weekly plan updates", "Chat support" ], created["includes"]
    assert created["isActive"]
  end

  test "list returns own active packages newest first, not another coach's" do
    create_package(name: "First")
    create_package(name: "Second")
    other = Coach.create!(phone: "+201012345731", password_hash: "h", full_name: "Other")
    other.coach_packages.create!(name: "Theirs", price_piastres: 1, duration_days: 1, includes: [ "x" ])

    get "/coach/packages", headers: auth
    assert_response :ok
    assert_equal [ "Second", "First" ], data["packages"].map { |p| p["name"] }
  end

  test "update changes a field" do
    created = create_package
    patch "/coach/packages/#{created['id']}", params: { pricePiastres: 70_000 }, headers: auth, as: :json
    assert_response :ok
    assert_equal 70_000, data["pricePiastres"]
  end

  test "delete soft-deletes and it drops from the list" do
    created = create_package
    delete "/coach/packages/#{created['id']}", headers: auth
    assert_response :ok
    get "/coach/packages", headers: auth
    assert_empty data["packages"]
  end

  test "another coach's package id returns 404 and changes nothing" do
    other = Coach.create!(phone: "+201012345732", password_hash: "h", full_name: "Other")
    theirs = other.coach_packages.create!(name: "Theirs", price_piastres: 10, duration_days: 5, includes: [ "x" ])
    patch "/coach/packages/#{theirs.id}", params: { name: "Hacked" }, headers: auth, as: :json
    assert_response :not_found
    delete "/coach/packages/#{theirs.id}", headers: auth
    assert_response :not_found
    assert_equal "Theirs", theirs.reload.name
    assert theirs.is_active
  end

  test "a bad body is a 400 validation failed" do
    post "/coach/packages", params: body(pricePiastres: 0), headers: auth, as: :json
    assert_response :bad_request
    assert_equal({ "success" => false, "error" => "validation failed" }, response.parsed_body)
  end
end
