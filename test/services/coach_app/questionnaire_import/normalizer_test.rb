require "test_helper"

class CoachApp::QuestionnaireImport::NormalizerTest < ActiveSupport::TestCase
  Normalizer = CoachApp::QuestionnaireImport::Normalizer

  def q(**over) = { "type" => "text", "label" => "Any injuries?", "required" => true, "options" => nil, "doubt" => nil }.merge(over.transform_keys(&:to_s))

  def run_with(questions: [], skipped: [], language: "en")
    Normalizer.call({ "questions" => questions, "skipped" => skipped }, language: language)
  end

  test "a clean question passes through" do
    out = run_with(questions: [ q ])
    assert_equal [ { type: "text", label: "Any injuries?", required: true, options: nil, doubt: nil } ], out[:questions]
    assert_equal false, out[:truncated]
  end

  test "a single_choice with one option becomes text with a doubt" do
    out = run_with(questions: [ q(type: "single_choice", options: [ "Only" ]) ]).fetch(:questions).first
    assert_equal "text", out[:type]
    assert_nil out[:options]
    assert out[:doubt].present?
  end

  test "the doubt note follows the coach language" do
    en = run_with(questions: [ q(type: "multi_choice", options: []) ]).dig(:questions, 0, :doubt)
    ar = run_with(questions: [ q(type: "multi_choice", options: []) ], language: "ar").dig(:questions, 0, :doubt)
    assert_match(/text question/, en)
    assert_match(/\p{Arabic}/, ar)
  end

  test "25 options are cut to 20 with a doubt" do
    out = run_with(questions: [ q(type: "multi_choice", options: (1..25).map { |i| "o#{i}" }) ]).fetch(:questions).first
    assert_equal 20, out[:options].length
    assert out[:doubt].present?
  end

  test "duplicate options are removed ignoring case and spaces" do
    out = run_with(questions: [ q(type: "single_choice", options: [ "Yes", "yes ", "No" ]) ]).fetch(:questions).first
    assert_equal [ { label: "Yes" }, { label: "No" } ], out[:options]
  end

  test "a 250 character label is cut to 200 with a doubt, and a blank label is dropped" do
    out = run_with(questions: [ q(label: "a" * 250), q(label: "   ") ]).fetch(:questions)
    assert_equal 1, out.length
    assert_equal 200, out.first[:label].length
    assert out.first[:doubt].present?
  end

  test "an option label of 130 characters is cut to 120" do
    out = run_with(questions: [ q(type: "single_choice", options: [ "b" * 130, "c" ]) ]).fetch(:questions).first
    assert_equal 120, out[:options].first[:label].length
  end

  test "an unknown type is dropped and a non-boolean required becomes true" do
    out = run_with(questions: [ q(type: "essay"), q(required: "no") ]).fetch(:questions)
    assert_equal 1, out.length
    assert_equal true, out.first[:required]
  end

  test "required false is kept" do
    assert_equal false, run_with(questions: [ q(required: false) ]).dig(:questions, 0, :required)
  end

  test "60 questions give 50 and truncated" do
    out = run_with(questions: Array.new(60) { |i| q(label: "Q#{i}") })
    assert_equal 50, out[:questions].length
    assert_equal true, out[:truncated]
  end

  test "a non-choice type loses its options" do
    assert_nil run_with(questions: [ q(type: "number", options: [ "a", "b" ]) ]).dig(:questions, 0, :options)
  end

  test "a skipped item with a bad reason is dropped; already_in_questionnaire keeps a normalized question" do
    out = run_with(skipped: [
      { "text" => "Weight?", "reason" => "nonsense", "question" => nil },
      { "text" => "Weight?", "reason" => "health_profile", "question" => nil },
      { "text" => "Injuries", "reason" => "already_in_questionnaire", "question" => q(label: "  Injuries? ") }
    ]).fetch(:skipped)
    assert_equal 2, out.length
    assert_equal({ text: "Weight?", reason: "health_profile" }, out.first)
    assert_equal "Injuries?", out.last.dig(:question, :label)
  end

  test "bad input gives empty lists" do
    [ nil, "x", [], {}, { "questions" => "no", "skipped" => 3 } ].each do |raw|
      assert_equal({ questions: [], skipped: [], truncated: false }, Normalizer.call(raw, language: "en"))
    end
  end
end
