require "test_helper"

class CoachApp::QuestionnaireImportControllerTest < ActionDispatch::IntegrationTest
  UNREADABLE = "couldn't read a questionnaire in this file".freeze

  setup do
    @coach = Coach.create!(phone: "+201012349501", password_hash: "h", full_name: "Coach Mona")
    @reads = []
  end

  def auth = { "Authorization" => "Bearer #{CoachApp::AccessToken.sign(@coach.id)}" }
  def data = response.parsed_body["data"]

  def raw_answer
    { "questions" => [
      { "type" => "text", "label" => "What is your goal?", "required" => true },
      { "type" => "single_choice", "label" => "Training days?", "options" => [ "3", "4" ] }
    ], "skipped" => [] }
  end

  def import(params: { text: "1. What is your goal?" }, headers: auth)
    post "/coach/questionnaire/import", params: params, headers: headers
  end

  def stubbing_reader(result = nil, raises: nil, &test)
    reader = lambda do |source, **kw|
      @reads << [ source, kw ]
      raise raises if raises

      result
    end
    original = CoachApp::QuestionnaireImport::Reader.method(:call)
    CoachApp::QuestionnaireImport::Reader.define_singleton_method(:call) { |source, **kw| reader.call(source, **kw) }
    test.call
  ensure
    CoachApp::QuestionnaireImport::Reader.define_singleton_method(:call, original)
  end

  def upload(bytes, name)
    Rack::Test::UploadedFile.new(StringIO.new(bytes), "application/octet-stream", true, original_filename: name)
  end

  test "pasted text answers normalized questions and saves nothing" do
    stubbing_reader(raw_answer) { import(params: { text: "1. What is your goal?", language: "ar" }) }
    assert_response :success
    assert_equal [ "What is your goal?", "Training days?" ], data["questions"].map { |q| q["label"] }
    assert_equal [ { "label" => "3" }, { "label" => "4" } ], data["questions"][1]["options"]
    assert_equal [], data["skipped"]
    assert_equal false, data["truncated"]
    assert_equal 0, QuestionnaireQuestion.count
    source, kw = @reads.first
    assert_equal :text, source.kind
    assert_equal "ar", kw[:language]
    assert_equal [], kw[:existing_labels]
  end

  test "the reader is given the coach's existing labels and unknown languages become en" do
    post "/coach/questionnaire/questions", params: { type: "text", label: "Age?" }, headers: auth, as: :json
    stubbing_reader(raw_answer) { import(params: { text: "x", language: "fr" }) }
    assert_equal [ "Age?" ], @reads.first[1][:existing_labels]
    assert_equal "en", @reads.first[1][:language]
  end

  test "a hostile answer is cleaned and nothing is saved" do
    hostile = { "evil" => 1, "questions" => [
      { "type" => "bogus", "label" => "Bad type" },
      { "type" => "text", "label" => "L" * 300, "admin" => true, "extra" => { "a" => 1 } }
    ] }
    stubbing_reader(hostile) { import }
    assert_response :success
    assert_equal 1, data["questions"].size
    assert_operator data["questions"][0]["label"].length, :<=, CoachApp::Questions::LABEL_MAX
    assert_not data["questions"][0].key?("admin")
    assert_equal 0, QuestionnaireQuestion.count
  end

  test "unreadable answers 422" do
    stubbing_reader(raises: CoachApp::QuestionnaireImport::Unreadable.new("cut off")) { import }
    assert_response :unprocessable_entity
    assert_equal UNREADABLE, response.parsed_body["error"]
  end

  test "unavailable reader answers 502" do
    stubbing_reader(raises: CoachApp::QuestionnaireImport::Unavailable.new("no key")) { import }
    assert_response :bad_gateway
    assert_equal "couldn't reach the questionnaire reader, try again", response.parsed_body["error"]
  end

  test "zero questions after cleaning answers 422" do
    stubbing_reader({ "questions" => [ { "type" => "bogus", "label" => "x" } ] }) { import }
    assert_response :unprocessable_entity
    assert_equal UNREADABLE, response.parsed_body["error"]
  end

  test "a .doc upload answers 400" do
    stubbing_reader(raw_answer) { import(params: { file: upload("\xD0\xCF\x11\xE0old word".b, "q.doc") }) }
    assert_response :bad_request
    assert_empty @reads
  end

  test "both file and text answer 400" do
    stubbing_reader(raw_answer) do
      import(params: { text: "hi", file: upload("%PDF-1.4\n".b, "q.pdf") })
    end
    assert_response :bad_request
    assert_empty @reads
  end

  test "signed out answers 401" do
    post "/coach/questionnaire/import", params: { text: "hi" }
    assert_response :unauthorized
  end
end
