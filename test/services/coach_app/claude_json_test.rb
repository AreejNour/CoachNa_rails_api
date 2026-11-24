require "test_helper"

class CoachApp::ClaudeJsonTest < ActiveSupport::TestCase
  Json = CoachApp::ClaudeJson

  test "nullable widens a type with null and keeps extras" do
    assert_equal({ type: [ "array", "null" ], items: { type: "string" } }, Json.nullable("array", items: { type: "string" }))
  end

  test "request_params carries the fixed settings and the caller's parts" do
    p = Json.request_params(system: "sys", content: [ { type: "text", text: "hi" } ], schema: { a: 1 }, max_tokens: 7)
    assert_equal [ Json::MODEL, 7, :adaptive ], [ p[:model], p[:max_tokens], p[:thinking][:type] ]
    assert_equal({ type: :json_schema, schema: { a: 1 } }, p[:output_config][:format])
    assert_equal [ :default, [ :"server-side-fallback-2026-07-01" ] ], [ p[:fallbacks], p[:betas] ]
    assert_equal [ { type: "text", text: "sys", cache_control: { type: "ephemeral" } } ], p[:system_]
    assert_equal [ { role: "user", content: [ { type: "text", text: "hi" } ] } ], p[:messages]
  end

  test "call without an API key raises Unavailable" do
    original = ENV.delete("ANTHROPIC_API_KEY")
    assert_raises(Json::Unavailable) { Json.call(system: "s", content: [], schema: {}, max_tokens: 1) }
  ensure
    ENV["ANTHROPIC_API_KEY"] = original if original
  end

  test "mapping_errors turns Unreadable into 422 and Unavailable into 502 with the given messages" do
    unreadable = assert_raises(ApiError) do
      Json.mapping_errors("x", unreadable: "U", unavailable: "A") { raise Json::Unreadable, "refusal" }
    end
    assert_equal [ 422, "U" ], [ unreadable.status, unreadable.message ]
    unavailable = assert_raises(ApiError) do
      Json.mapping_errors("x", unreadable: "U", unavailable: "A") { raise Json::Unavailable, "boom" }
    end
    assert_equal [ 502, "A" ], [ unavailable.status, unavailable.message ]
    assert_equal :ok, Json.mapping_errors("x", unreadable: "U", unavailable: "A") { :ok }
  end
end
