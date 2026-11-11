require "test_helper"

class CoachApp::QuestionsTest < ActiveSupport::TestCase
  setup do
    @coach = Coach.create!(phone: "+201012345740", password_hash: "h", full_name: "Sara")
  end

  def text_attrs(over = {})
    { "type" => "text", "label" => "What's your goal?", "required" => true }.merge(over)
  end

  def choice_attrs(over = {})
    {
      "type" => "single_choice",
      "label" => "Pick one",
      "options" => [ { "label" => "Lose weight" }, { "label" => "Gain muscle" } ]
    }.merge(over)
  end

  test "create stores type, label, required and appends position from 1" do
    q1 = CoachApp::Questions.create!(@coach, text_attrs)
    assert_equal "text", q1.type
    assert_equal "What's your goal?", q1.label
    assert q1.required
    assert_equal 1, q1.position

    q2 = CoachApp::Questions.create!(@coach, text_attrs("label" => "Second"))
    assert_equal 2, q2.position
  end

  test "create makes the questionnaire once and reuses it" do
    CoachApp::Questions.create!(@coach, text_attrs)
    CoachApp::Questions.create!(@coach, text_attrs("label" => "Second"))
    assert_equal 1, Questionnaire.where(coach_id: @coach.id).count
  end

  test "create assigns a key to every choice option" do
    q = CoachApp::Questions.create!(@coach, choice_attrs)
    labels = q.options.map { |o| o["label"] }
    keys = q.options.map { |o| o["key"] }
    assert_equal [ "Lose weight", "Gain muscle" ], labels
    assert_equal 2, keys.uniq.length
    assert keys.all? { |k| k.is_a?(String) && !k.empty? }
  end

  test "create trims the label and option labels" do
    q = CoachApp::Questions.create!(@coach, choice_attrs("label" => "  Pick  ", "options" => [ { "label" => " A " }, { "label" => " B " } ]))
    assert_equal "Pick", q.label
    assert_equal [ "A", "B" ], q.options.map { |o| o["label"] }
  end

  test "list returns only the coach's non-archived questions in position order" do
    first = CoachApp::Questions.create!(@coach, text_attrs("label" => "First"))
    second = CoachApp::Questions.create!(@coach, text_attrs("label" => "Second"))
    gone = CoachApp::Questions.create!(@coach, text_attrs("label" => "Gone"))
    CoachApp::Questions.archive!(@coach, gone.id)
    other = Coach.create!(phone: "+201012345741", password_hash: "h", full_name: "Other")
    CoachApp::Questions.create!(other, text_attrs("label" => "Theirs"))

    assert_equal [ first.id, second.id ], CoachApp::Questions.list(@coach).map(&:id)
  end

  test "list is empty for a coach with no questionnaire" do
    assert_empty CoachApp::Questions.list(@coach)
  end

  test "update changes label and required but keeps option keys, minting for new options" do
    q = CoachApp::Questions.create!(@coach, choice_attrs)
    first_key = q.options.first["key"]

    CoachApp::Questions.update!(@coach, q.id, {
      "label" => "Renamed",
      "required" => false,
      "options" => [ { "key" => first_key, "label" => "Lose weight (edited)" }, { "label" => "Maintain" } ]
    })
    q.reload

    assert_equal "Renamed", q.label
    assert_not q.required
    assert_equal first_key, q.options.first["key"]
    assert_equal "Lose weight (edited)", q.options.first["label"]
    assert_not_equal first_key, q.options.last["key"]
    assert_equal "Maintain", q.options.last["label"]
  end

  test "update cannot change the type" do
    q = CoachApp::Questions.create!(@coach, text_attrs)
    CoachApp::Questions.update!(@coach, q.id, { "type" => "number", "label" => "Still text" })
    assert_equal "text", q.reload.type
  end

  test "archive removes it from the list and it cannot be edited again" do
    q = CoachApp::Questions.create!(@coach, text_attrs)
    CoachApp::Questions.archive!(@coach, q.id)
    assert q.reload.is_archived
    assert_empty CoachApp::Questions.list(@coach)
    assert_raises(ApiError) { CoachApp::Questions.update!(@coach, q.id, { "label" => "X" }) }
  end

  test "another coach's question is not found for update or archive" do
    other = Coach.create!(phone: "+201012345742", password_hash: "h", full_name: "Other")
    q = CoachApp::Questions.create!(other, text_attrs)
    assert_raises(ApiError) { CoachApp::Questions.update!(@coach, q.id, { "label" => "X" }) }
    assert_raises(ApiError) { CoachApp::Questions.archive!(@coach, q.id) }
    assert_not q.reload.is_archived
  end

  test "create rejects bad input" do
    bad = [
      text_attrs("label" => ""),
      text_attrs("label" => "x" * 201),
      text_attrs("type" => "unknown"),
      text_attrs("type" => "photo"),
      text_attrs("required" => "yes"),
      choice_attrs("options" => nil),
      choice_attrs("options" => []),
      choice_attrs("options" => [ { "label" => "only one" } ]),
      choice_attrs("options" => Array.new(21) { |i| { "label" => "opt #{i}" } }),
      choice_attrs("options" => [ { "label" => "A" }, { "label" => "" } ]),
      choice_attrs("options" => [ { "label" => "A" }, { "label" => "A" } ]),
      choice_attrs("options" => [ { "label" => "A" }, { "label" => "x" * 121 } ]),
      text_attrs("options" => [ { "label" => "A" }, { "label" => "B" } ])
    ]
    bad.each do |attrs|
      assert_raises(ApiError, "expected #{attrs.inspect} to be rejected") do
        CoachApp::Questions.create!(@coach, attrs)
      end
    end
  end

  test "an empty patch is rejected" do
    q = CoachApp::Questions.create!(@coach, text_attrs)
    assert_raises(ApiError) { CoachApp::Questions.update!(@coach, q.id, {}) }
  end
end
