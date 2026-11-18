require "test_helper"

class CoachApp::PlanImportReaderTest < ActiveSupport::TestCase
  Message = Struct.new(:stop_reason, :content)
  Block = Struct.new(:type, :text)
  Reader = CoachApp::PlanImport::Reader

  def answer(reason, text) = Message.new(reason, [ Block.new(:text, text) ])

  test "parse returns the JSON of a finished answer" do
    assert_equal({ "tips" => nil, "options" => [] }, Reader.parse(answer(:end_turn, '{"tips":null,"options":[]}')))
  end

  test "parse refuses a refusal, a cut-off answer and non-JSON" do
    assert_raises(CoachApp::PlanImport::Unreadable) { Reader.parse(answer(:refusal, "")) }
    assert_raises(CoachApp::PlanImport::Unreadable) { Reader.parse(answer(:max_tokens, '{"tips":')) }
    assert_raises(CoachApp::PlanImport::Unreadable) { Reader.parse(answer(:end_turn, "sorry")) }
  end

  test "after a mid-stream fallback the text after the fallback block wins" do
    msg = Message.new(:end_turn, [ Block.new(:text, '{"tips":"partial'), Block.new(:fallback, nil),
                                   Block.new(:text, '{"tips":null,"options":[]}') ])
    assert_equal({ "tips" => nil, "options" => [] }, Reader.parse(msg))
  end

  test "a fallback block with only the earlier text falls back to all text" do
    msg = Message.new(:end_turn, [ Block.new(:text, '{"tips":null,'), Block.new(:fallback, nil),
                                   Block.new(:text, '"options":[]}') ])
    assert_equal({ "tips" => nil, "options" => [] }, Reader.parse(msg))
  end

  test "unparseable output raises without quoting the model's text" do
    error = assert_raises(CoachApp::PlanImport::Unreadable) { Reader.parse(answer(:end_turn, "Client Ali Hassan 90kg {")) }
    assert_no_match(/Ali|Hassan/, error.message)
  end

  test "the client is built with no retries and a timeout under the app's 120 s" do
    seen = nil
    original = Anthropic::Client.method(:new)
    Anthropic::Client.define_singleton_method(:new) { |**kw| seen = kw; :client }
    begin
      Reader.client("k")
    ensure
      Anthropic::Client.define_singleton_method(:new, original)
    end
    assert_equal 0, seen[:max_retries]
    assert_operator seen[:timeout], :<=, 100
  end

  test "an SDK error becomes Unavailable carrying only its class" do
    [ Anthropic::Errors::APIConnectionError.new(url: URI("https://x.test")),
      Anthropic::Errors::APITimeoutError.new(url: URI("https://x.test")) ].each do |err|
      streamer = Object.new
      streamer.define_singleton_method(:stream) { |**| raise err }
      fake = Struct.new(:beta).new(Struct.new(:messages).new(streamer))
      original = Reader.method(:client)
      Reader.define_singleton_method(:client) { |_key| fake }
      begin
        ENV["ANTHROPIC_API_KEY"] = "k"
        raised = assert_raises(CoachApp::PlanImport::Unavailable) { Reader.call("%PDF-".b, []) }
        assert_equal err.class.name, raised.message
      ensure
        Reader.define_singleton_method(:client, original)
        ENV.delete("ANTHROPIC_API_KEY")
      end
    end
  end

  test "the request body the SDK builds carries the schema, fallbacks and a cached system prefix" do
    body = Anthropic::Models::Beta::MessageCreateParams.dump_request(
      max_tokens: 1, model: Reader::MODEL, messages: [ { role: "user", content: "x" } ],
      system_: [ { type: "text", text: "t", cache_control: { type: "ephemeral" } } ],
      output_config: { effort: :medium, format: { type: :json_schema, schema: Reader::SCHEMA } },
      betas: [ :"server-side-fallback-2026-07-01" ], fallbacks: :default
    ).first
    assert_equal :json_schema, body[:output_config][:format][:type]
    assert_equal :default, body[:fallbacks]
    assert_equal "ephemeral", body[:system].first[:cache_control][:type]
  end

  test "food_lines lists the fields the prompt promises" do
    food = Food.new(name_en: "Rice", name_ar: "أرز", group: "carb", weight_basis: "cooked", household_unit: "cup")
    food.id = "0b0e0c1e-1111-4222-8333-444455556666"
    line = JSON.parse(Reader.food_lines([ food ]))
    assert_equal({ "id" => "0b0e0c1e-1111-4222-8333-444455556666", "nameEn" => "Rice", "nameAr" => "أرز", "group" => "carb",
                   "weightBasis" => "cooked", "householdUnit" => "cup" }, line)
  end
end
