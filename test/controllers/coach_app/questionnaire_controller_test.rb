require "test_helper"

class CoachApp::QuestionnaireControllerTest < ActionDispatch::IntegrationTest
  setup { @coach = Coach.create!(phone: "+201012345750", password_hash: "h", full_name: "Sara") }

  def auth = { "Authorization" => "Bearer #{CoachApp::AccessToken.sign(@coach.id)}" }
  def data = response.parsed_body["data"]

  def body(over = {})
    { type: "text", label: "What's your goal?", required: true }.merge(over)
  end

  def create_question(over = {})
    post "/coach/questionnaire/questions", params: body(over), headers: auth, as: :json
    data
  end

  test "every route needs a token" do
    get "/coach/questionnaire"
    assert_response :unauthorized
    post "/coach/questionnaire/questions", params: body, as: :json
    assert_response :unauthorized
    patch "/coach/questionnaire/questions/x", params: { label: "X" }, as: :json
    assert_response :unauthorized
    delete "/coach/questionnaire/questions/x"
    assert_response :unauthorized
  end

  test "create returns the contract's question" do
    created = create_question
    assert_response :created
    assert_equal %w[id label options position required type], created.keys.sort
    assert_equal "text", created["type"]
    assert_nil created["options"]
    assert_equal 1, created["position"]
  end

  test "create a choice question returns options with keys" do
    created = create_question(type: "single_choice", options: [ { label: "A" }, { label: "B" } ])
    assert_response :created
    assert_equal [ "A", "B" ], created["options"].map { |o| o["label"] }
    assert created["options"].all? { |o| o["key"].present? }
  end

  test "list returns own non-archived questions in position order, not another coach's" do
    create_question(label: "First")
    created = create_question(label: "Second")
    delete "/coach/questionnaire/questions/#{create_question(label: 'Gone')['id']}", headers: auth
    other = Coach.create!(phone: "+201012345751", password_hash: "h", full_name: "Other")
    q = other.create_questionnaire!(title: "t").questionnaire_questions.create!(type: "text", label: "Theirs", position: 1)
    assert q.persisted?

    get "/coach/questionnaire", headers: auth
    assert_response :ok
    assert_equal [ "First", "Second" ], data["questions"].map { |x| x["label"] }
    assert_equal created["id"], data["questions"].last["id"]
  end

  test "update changes a field" do
    created = create_question
    patch "/coach/questionnaire/questions/#{created['id']}", params: { label: "Renamed" }, headers: auth, as: :json
    assert_response :ok
    assert_equal "Renamed", data["label"]
  end

  test "delete archives and it drops from the list" do
    created = create_question
    delete "/coach/questionnaire/questions/#{created['id']}", headers: auth
    assert_response :ok
    get "/coach/questionnaire", headers: auth
    assert_empty data["questions"]
  end

  test "another coach's question id returns 404 and changes nothing" do
    other = Coach.create!(phone: "+201012345752", password_hash: "h", full_name: "Other")
    theirs = other.create_questionnaire!(title: "t").questionnaire_questions.create!(type: "text", label: "Theirs", position: 1)
    patch "/coach/questionnaire/questions/#{theirs.id}", params: { label: "Hacked" }, headers: auth, as: :json
    assert_response :not_found
    delete "/coach/questionnaire/questions/#{theirs.id}", headers: auth
    assert_response :not_found
    assert_equal "Theirs", theirs.reload.label
    assert_not theirs.is_archived
  end

  test "a bad body is a 400 validation failed" do
    post "/coach/questionnaire/questions", params: body(type: "photo"), headers: auth, as: :json
    assert_response :bad_request
    assert_equal({ "success" => false, "error" => "validation failed" }, response.parsed_body)
  end
end
