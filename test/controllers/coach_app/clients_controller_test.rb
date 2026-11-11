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
end
