require "test_helper"

class CoachApp::QuestionnaireImport::ReaderTest < ActiveSupport::TestCase
  Message = Struct.new(:stop_reason, :content)
  Block = Struct.new(:type, :text)
  Reader = CoachApp::QuestionnaireImport::Reader
  Source = CoachApp::QuestionnaireImport::Source
  Unreadable = CoachApp::QuestionnaireImport::Unreadable
  EMPTY = '{"questions":[],"skipped":[]}'.freeze

  def parse(msg) = CoachApp::ClaudeJson.parse(msg, Unreadable)
  def answer(reason, text) = Message.new(reason, [ Block.new(:text, text) ])

  def params(source, labels: [], language: "en")
    CoachApp::ClaudeJson.request_params(
      system: Reader::INSTRUCTIONS, schema: Reader::SCHEMA, max_tokens: Reader::MAX_TOKENS,
      content: Reader.send(:content, source, labels, language)
    )
  end

  test "parse returns the JSON of a finished answer" do
    assert_equal({ "questions" => [], "skipped" => [] }, parse(answer(:end_turn, EMPTY)))
  end

  test "parse refuses a refusal, a cut-off answer and non-JSON" do
    assert_raises(Unreadable) { parse(answer(:refusal, "")) }
    assert_raises(Unreadable) { parse(answer(:max_tokens, '{"questions":')) }
    assert_raises(Unreadable) { parse(answer(:end_turn, "sorry")) }
  end

  test "after a mid-stream fallback the text after the fallback block wins" do
    msg = Message.new(:end_turn, [ Block.new(:text, '{"questions":[{"x'), Block.new(:fallback, nil), Block.new(:text, EMPTY) ])
    assert_equal({ "questions" => [], "skipped" => [] }, parse(msg))
  end

  test "a fallback block with only the earlier text falls back to all text" do
    msg = Message.new(:end_turn, [ Block.new(:text, '{"questions":[],'), Block.new(:fallback, nil), Block.new(:text, '"skipped":[]}') ])
    assert_equal({ "questions" => [], "skipped" => [] }, parse(msg))
  end

  test "unparseable output raises without quoting the model's text" do
    error = assert_raises(Unreadable) { parse(answer(:end_turn, "Do you have diabetes Ali Hassan {")) }
    assert_no_match(/Ali|Hassan|diabetes/, error.message)
  end

  test "the request asks for the opus model with medium effort and fallbacks" do
    p = params(Source.new(kind: :pdf, bytes: "%PDF-".b, media_type: "application/pdf"))
    assert_equal :"claude-opus-5-5", p[:model]
    assert_equal :medium, p[:output_config][:effort]
    assert_equal :default, p[:fallbacks]
    assert_equal "ephemeral", p[:system_].first[:cache_control][:type]
    assert_equal "document", p[:messages].first[:content].first[:type]
  end

  test "the system text carries no per-request value" do
    a = params(Source.new(kind: :text, text: "x"), labels: [ "Secret Coach Question" ], language: "ar")
    b = params(Source.new(kind: :text, text: "x"), labels: [], language: "en")
    assert_equal a[:system_], b[:system_]
    assert_no_match(/Secret Coach Question|\{coach_language\}|\{existing_labels\}/, a[:system_].first[:text])
  end

  test "an image source gives an image block" do
    block = params(Source.new(kind: :image, bytes: "png".b, media_type: "image/png"))[:messages].first[:content].first
    assert_equal "image", block[:type]
    assert_equal "image/png", block[:source][:media_type]
    assert_equal Base64.strict_encode64("png"), block[:source][:data]
  end

  test "a text source gives a text document block" do
    block = params(Source.new(kind: :text, text: "Q1"))[:messages].first[:content].first
    assert_equal({ type: "document", source: { type: "text", media_type: "text/plain", data: "Q1" } }, block)
  end

  test "the user text names the language and the existing questions" do
    src = Source.new(kind: :text, text: "x")
    assert_includes params(src, labels: [ "A?", "B?" ], language: "ar")[:messages].first[:content].last[:text],
                    "Coach language: Arabic\nExisting questions:\nA?\nB?\nConvert this questionnaire."
    assert_includes params(src)[:messages].first[:content].last[:text], "Coach language: English\nExisting questions:\n(none)\n"
  end

  test "no API key raises Unavailable" do
    original = ENV.delete("ANTHROPIC_API_KEY")
    assert_raises(CoachApp::QuestionnaireImport::Unavailable) do
      Reader.call(Source.new(kind: :text, text: "x"), existing_labels: [], language: "en")
    end
  ensure
    ENV["ANTHROPIC_API_KEY"] = original if original
  end

  test "an SDK error becomes Unavailable carrying only its class" do
    err = Anthropic::Errors::APIConnectionError.new(url: URI("https://x.test"))
    streamer = Object.new
    streamer.define_singleton_method(:stream) { |**| raise err }
    fake = Struct.new(:beta).new(Struct.new(:messages).new(streamer))
    original = CoachApp::ClaudeJson.method(:client)
    CoachApp::ClaudeJson.define_singleton_method(:client) { |_key| fake }
    begin
      ENV["ANTHROPIC_API_KEY"] = "k"
      raised = assert_raises(CoachApp::QuestionnaireImport::Unavailable) do
        Reader.call(Source.new(kind: :text, text: "x"), existing_labels: [], language: "en")
      end
      assert_equal err.class.name, raised.message
    ensure
      CoachApp::ClaudeJson.define_singleton_method(:client, original)
      ENV.delete("ANTHROPIC_API_KEY")
    end
  end

  test "the request body the SDK builds accepts the schema" do
    body = Anthropic::Models::Beta::MessageCreateParams.dump_request(params(Source.new(kind: :text, text: "x"))).first
    assert_equal :json_schema, body[:output_config][:format][:type]
  end
end
