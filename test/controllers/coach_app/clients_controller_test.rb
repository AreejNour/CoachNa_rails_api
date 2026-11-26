require "test_helper"

class CoachApp::ClientsControllerTest < ActionDispatch::IntegrationTest
  setup { @coach = Coach.create!(phone: uniq_phone, password_hash: "h", full_name: "Coach") }

  def uniq_phone = "+20#{SecureRandom.random_number(10**10).to_s.rjust(10, '0')}"
  def auth = { "Authorization" => "Bearer #{CoachApp::AccessToken.sign(@coach.id)}" }
  def data = response.parsed_body["data"]

  def make_client(name = "Client")
    Client.create!(phone: uniq_phone, password_hash: "h", full_name: name)
  end

  def make_sub(client, coach: @coach)
    pkg = coach.coach_packages.create!(name: "P", price_piastres: 1000, duration_days: 30, includes: [ "x" ])
    Subscription.create!(
      client: client, coach: coach, package_id: pkg.id, status: "awaiting_plan",
      price_piastres: 1000, commission_percent: 15, commission_piastres: 150,
      starts_at: Time.current, ends_at: 30.days.from_now
    )
  end

  def new_note(coach, subscription_id)
    Notification.create!(
      recipient_type: "coach", recipient_id: coach.id, type: "new_client",
      title: "t", body: "b", data: { "subscriptionId" => subscription_id }
    )
  end

  test "every route needs a token" do
    get "/coach/clients"
    assert_response :unauthorized
    get "/coach/clients/x"
    assert_response :unauthorized
    post "/coach/clients/mark-seen"
    assert_response :unauthorized
    get "/coach/notifications/unread-count"
    assert_response :unauthorized
  end

  test "index returns the contract list and newCount" do
    sub = make_sub(make_client("Aya"))
    new_note(@coach, sub.id)

    get "/coach/clients", headers: auth
    assert_response :ok
    assert_equal %w[clientId fullName isNew questionnaireSubmitted since status subscriptionId],
                 data["clients"].first.keys.sort
    assert_equal 1, data["newCount"]
    assert data["clients"].first["isNew"]
  end

  test "show returns the detail keys" do
    sub = make_sub(make_client("Aya"))

    get "/coach/clients/#{sub.id}", headers: auth
    assert_response :ok
    assert_equal %w[client health questionnaire], data.keys.sort
    assert_equal "Aya", data["client"]["fullName"]
  end

  test "another coach's subscription id returns 404" do
    other = Coach.create!(phone: uniq_phone, password_hash: "h", full_name: "Other")
    theirs = make_sub(make_client("Theirs"), coach: other)

    get "/coach/clients/#{theirs.id}", headers: auth
    assert_response :not_found
  end

  test "mark-seen clears the unread count" do
    sub = make_sub(make_client("Aya"))
    new_note(@coach, sub.id)

    get "/coach/notifications/unread-count", headers: auth
    assert_equal 1, data["count"]
    post "/coach/clients/mark-seen", headers: auth
    assert_response :ok
    get "/coach/notifications/unread-count", headers: auth
    assert_equal 0, data["count"]
  end

  %w[checkout_open pending_payment payment_failed].each do |status|
    test "a #{status} subscription is not listed, not counted, and its detail is 404" do
      unpaid = make_sub(make_client("Unpaid"))
      unpaid.update!(status: status)
      new_note(@coach, unpaid.id)

      get "/coach/clients", headers: auth
      assert_response :ok
      assert_empty data["clients"]
      assert_equal 0, data["newCount"]

      get "/coach/clients/#{unpaid.id}", headers: auth
      assert_response :not_found
    end
  end

  def photo_question
    questionnaire = @coach.questionnaire || @coach.create_questionnaire!(title: "Q")
    questionnaire.questionnaire_questions.create!(type: "photo", label: "Front", required: true, position: 1)
  end

  def photo_answer(subscription, question, key: "questionnaire/c/#{SecureRandom.uuid}.png")
    QuestionnaireAnswer.create!(subscription_id: subscription.id, question_id: question.id, answer: { "photo" => true }, photo_storage_key: key)
  end

  PNG_BYTES = "\x89PNG\r\n\x1a\n".b

  test "detail shows photo: true and no answer for a photo answer" do
    sub = make_sub(make_client)
    q = photo_question
    photo_answer(sub, q)
    get "/coach/clients/#{sub.id}", headers: auth
    item = data["questionnaire"]["questions"].first
    assert_equal "photo", item["type"]
    assert_nil item["answer"]
    assert_equal true, item["photo"]
  end

  test "detail shows photo: false for an unanswered photo question" do
    sub = make_sub(make_client)
    photo_question
    get "/coach/clients/#{sub.id}", headers: auth
    assert_equal false, data["questionnaire"]["questions"].first["photo"]
  end

  test "a paid subscription's photo answer streams back" do
    sub = make_sub(make_client)
    q = photo_question
    key = "questionnaire/c/#{SecureRandom.uuid}.png"
    Storage.current.put(key, PNG_BYTES, mime_type: "image/png")
    photo_answer(sub, q, key: key)
    get "/coach/clients/#{sub.id}/answers/#{q.id}/photo", headers: auth
    assert_response :ok
    assert_includes response.media_type, "image/png"
    assert_equal PNG_BYTES, response.body.b
  end

  %w[checkout_open pending_payment payment_failed].each do |status|
    test "a #{status} subscription's photo is 404" do
      sub = make_sub(make_client)
      q = photo_question
      key = "questionnaire/c/#{SecureRandom.uuid}.png"
      Storage.current.put(key, PNG_BYTES, mime_type: "image/png")
      photo_answer(sub, q, key: key)
      sub.update!(status: status)
      get "/coach/clients/#{sub.id}/answers/#{q.id}/photo", headers: auth
      assert_response :not_found
    end
  end

  test "another coach's subscription photo is 404" do
    other = Coach.create!(phone: uniq_phone, password_hash: "h", full_name: "Other")
    sub = make_sub(make_client, coach: other)
    q = photo_question
    photo_answer(sub, q)
    get "/coach/clients/#{sub.id}/answers/#{q.id}/photo", headers: auth
    assert_response :not_found
  end

  test "a question without a photo is 404" do
    sub = make_sub(make_client)
    q = photo_question
    get "/coach/clients/#{sub.id}/answers/#{q.id}/photo", headers: auth
    assert_response :not_found
  end
end
