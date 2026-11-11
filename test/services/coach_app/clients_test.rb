require "test_helper"

class CoachApp::ClientsTest < ActiveSupport::TestCase
  setup do
    @coach = Coach.create!(phone: uniq_phone, password_hash: "h", full_name: "Coach")
  end

  def uniq_phone
    "+20#{SecureRandom.random_number(10**10).to_s.rjust(10, '0')}"
  end

  def make_client(name = "Client")
    Client.create!(phone: uniq_phone, password_hash: "h", full_name: name)
  end

  def make_package(coach = @coach)
    coach.coach_packages.create!(name: "P", price_piastres: 1000, duration_days: 30, includes: [ "x" ])
  end

  def make_subscription(client, coach: @coach, status: "awaiting_plan", package: nil)
    Subscription.create!(
      client: client, coach: coach, package_id: (package || make_package(coach)).id,
      status: status, price_piastres: 1000, commission_percent: 15, commission_piastres: 150,
      starts_at: Time.current, ends_at: 30.days.from_now
    )
  end

  def new_client_note(coach, subscription_id, read_at: nil)
    Notification.create!(
      recipient_type: "coach", recipient_id: coach.id, type: "new_client",
      title: "New client", body: "b", data: { "subscriptionId" => subscription_id }, read_at: read_at
    )
  end

  test "list returns current subscriptions newest first, not ended or another coach's" do
    aya = make_subscription(make_client("Aya"))
    mona = make_subscription(make_client("Mona"))
    aya.update!(created_at: 1.day.ago)
    make_subscription(make_client("Gone"), status: "ended")
    other = Coach.create!(phone: uniq_phone, password_hash: "h", full_name: "Other")
    make_subscription(make_client("Theirs"), coach: other)

    result = CoachApp::Clients.list(@coach)
    assert_equal [ "Mona", "Aya" ], result[:clients].map { |c| c[:fullName] }
    assert_equal [ mona.id, aya.id ], result[:clients].map { |c| c[:subscriptionId] }
  end

  test "list marks a client new from an unread new_client notification and counts them" do
    sub = make_subscription(make_client("Aya"))
    plain = make_subscription(make_client("Noa"))
    new_client_note(@coach, sub.id)

    result = CoachApp::Clients.list(@coach)
    assert result[:clients].find { |c| c[:subscriptionId] == sub.id }[:isNew]
    assert_not result[:clients].find { |c| c[:subscriptionId] == plain.id }[:isNew]
    assert_equal 1, result[:newCount]
  end

  test "detail returns health facts and answered questions in position order" do
    client = make_client("Aya")
    ClientHealthProfile.create!(client_id: client.id, gender: "female", weight_kg: 70.5, allergies: [ "nuts" ])
    sub = make_subscription(client)
    goal = CoachApp::Questions.create!(@coach, { "type" => "text", "label" => "Goal?" })
    CoachApp::Questions.create!(@coach, { "type" => "text", "label" => "Unanswered" })
    archived_answered = CoachApp::Questions.create!(@coach, { "type" => "text", "label" => "Old answered" })
    archived_blank = CoachApp::Questions.create!(@coach, { "type" => "text", "label" => "Old blank" })
    QuestionnaireAnswer.create!(subscription_id: sub.id, question_id: goal.id, answer: "Lose weight")
    QuestionnaireAnswer.create!(subscription_id: sub.id, question_id: archived_answered.id, answer: "Kept")
    CoachApp::Questions.archive!(@coach, archived_answered.id)
    CoachApp::Questions.archive!(@coach, archived_blank.id)

    detail = CoachApp::Clients.detail(@coach, sub.id)
    assert_equal "female", detail[:health][:gender]
    assert_equal 70.5, detail[:health][:weightKg]
    assert_equal [ "nuts" ], detail[:health][:allergies]

    questions = detail[:questionnaire][:questions]
    labels = questions.map { |q| q[:label] }
    assert_includes labels, "Old answered"      # archived but answered → shown
    assert_includes labels, "Unanswered"        # non-archived, no answer → shown
    assert_not_includes labels, "Old blank"     # archived, no answer → hidden
    assert_equal questions.map { |q| q[:position] }, questions.map { |q| q[:position] }.sort
    assert_equal "Lose weight", questions.find { |q| q[:label] == "Goal?" }[:answer]
    assert_nil questions.find { |q| q[:label] == "Unanswered" }[:answer]
  end

  test "detail for a client with no health profile returns health nil and still lists questions" do
    sub = make_subscription(make_client("Aya"))
    CoachApp::Questions.create!(@coach, { "type" => "text", "label" => "Q" })

    detail = CoachApp::Clients.detail(@coach, sub.id)
    assert_nil detail[:health]
    assert_equal 1, detail[:questionnaire][:questions].length
    assert_equal "Aya", detail[:client][:fullName]
  end

  test "detail raises 404 for a subscription that isn't this coach's" do
    other = Coach.create!(phone: uniq_phone, password_hash: "h", full_name: "Other")
    theirs = make_subscription(make_client("Theirs"), coach: other)
    assert_raises(ApiError) { CoachApp::Clients.detail(@coach, theirs.id) }
  end

  test "mark_seen clears only this coach's unread new_client notifications" do
    other = Coach.create!(phone: uniq_phone, password_hash: "h", full_name: "Other")
    mine = new_client_note(@coach, make_subscription(make_client).id)
    theirs = new_client_note(other, make_subscription(make_client, coach: other).id)

    CoachApp::Notifications.mark_seen(@coach)
    assert_not_nil mine.reload.read_at
    assert_nil theirs.reload.read_at
    assert_equal 0, CoachApp::Notifications.unread_count(@coach)
    assert_equal 1, CoachApp::Notifications.unread_count(other)
  end
end
