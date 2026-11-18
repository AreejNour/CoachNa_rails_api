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
