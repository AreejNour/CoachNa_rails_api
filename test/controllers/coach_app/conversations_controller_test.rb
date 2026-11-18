require "test_helper"

class CoachApp::ConversationsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @coach = Coach.create!(phone: "+201012347001", password_hash: "h", full_name: "Coach Mona")
    @client = Client.create!(phone: "+201012347101", password_hash: "h", full_name: "Cl")
    @sub = make_sub(@coach, @client)
    @conv = Conversation.create!(subscription_id: @sub.id, last_message_at: Time.current)
  end

  def make_sub(coach, client, status: "active")
    pkg = coach.coach_packages.create!(name: "P", price_piastres: 1000, duration_days: 30, includes: [ "x" ])
    now = Time.current
    Subscription.create!(client_id: client.id, coach_id: coach.id, package_id: pkg.id, status: status,
                         price_piastres: 1000, commission_percent: 10, commission_piastres: 100,
                         starts_at: now - 1.day, ends_at: now + 30.days)
  end

  def msg(sender_type, sender_id, body, at)
    Message.create!(conversation_id: @conv.id, sender_type: sender_type, sender_id: sender_id,
                    body: body, sent_at: at)
  end

  def auth = { "Authorization" => "Bearer #{CoachApp::AccessToken.sign(@coach.id)}" }
  def data = response.parsed_body["data"]

  test "every route needs a token" do
    get "/coach/conversations"
    assert_response :unauthorized
    get "/coach/conversations/#{@conv.id}/messages"
    assert_response :unauthorized
    post "/coach/conversations/#{@conv.id}/read"
    assert_response :unauthorized
  end

  test "list returns own conversations with preview, unread count and open state, not another coach's" do
    msg("client", @client.id, "hi coach", 2.minutes.ago)
    msg("client", @client.id, "you there?", 1.minute.ago)
    # Another coach's conversation must not appear.
    otherCoach = Coach.create!(phone: "+201012347002", password_hash: "h", full_name: "Other")
    otherClient = Client.create!(phone: "+201012347102", password_hash: "h", full_name: "OC")
    otherSub = make_sub(otherCoach, otherClient)
    Conversation.create!(subscription_id: otherSub.id, last_message_at: Time.current)

    get "/coach/conversations", headers: auth
    assert_response :ok
    assert_equal 1, data["conversations"].length
    row = data["conversations"][0]
    assert_equal @conv.id, row["id"]
    assert_equal "Cl", row["client"]["fullName"]
    assert_equal "you there?", row["lastMessagePreview"]
    assert_equal 2, row["unreadCount"]
    assert_equal "open", row["state"]
  end

  test "messages returns history oldest to newest, with unread count" do
    msg("client", @client.id, "first", 3.minutes.ago)
    msg("coach", @coach.id, "reply", 2.minutes.ago)
    msg("client", @client.id, "thanks", 1.minute.ago)

    get "/coach/conversations/#{@conv.id}/messages", headers: auth
    assert_response :ok
    assert_equal %w[first reply thanks], data["messages"].map { |m| m["body"] }
    assert_equal %w[client coach client], data["messages"].map { |m| m["senderType"] }
    assert_equal 2, data["unreadCount"]
    assert_equal false, data["hasMore"]
  end

  test "read advances the cursor so unread drops to zero, and new client messages count again" do
    msg("client", @client.id, "old", 2.minutes.ago)
    post "/coach/conversations/#{@conv.id}/read", headers: auth
    assert_response :ok
    get "/coach/conversations/#{@conv.id}/messages", headers: auth
    assert_equal 0, data["unreadCount"]

    msg("client", @client.id, "new one", Time.current + 1.second)
    get "/coach/conversations/#{@conv.id}/messages", headers: auth
    assert_equal 1, data["unreadCount"]
  end

  test "another coach's conversation id is 404 for messages and read" do
    other = Coach.create!(phone: "+201012347003", password_hash: "h", full_name: "O")
    token = { "Authorization" => "Bearer #{CoachApp::AccessToken.sign(other.id)}" }
    get "/coach/conversations/#{@conv.id}/messages", headers: token
    assert_response :not_found
    post "/coach/conversations/#{@conv.id}/read", headers: token
    assert_response :not_found
  end

  def client_new_messages
    Notification.where(recipient_type: "client", recipient_id: @client.id, type: "new_message")
  end

  test "send text: 201, bumps last_message_at, records a collapsed client new_message notification" do
    post "/coach/conversations/#{@conv.id}/messages", params: { body: "  hello there  " }, headers: auth, as: :json
    assert_response :created
    assert_equal "hello there", data["body"]
    assert_equal "coach", data["senderType"]

    row = Message.find(data["id"])
    assert_equal @coach.id, row.sender_id
    assert @conv.reload.last_message_at >= row.sent_at - 1

    notes = client_new_messages
    assert_equal 1, notes.count
    assert_equal "Coach Mona", notes.first.title
    assert_equal({ "conversationId" => @conv.id, "subscriptionId" => @sub.id }, notes.first.data)

    # A burst collapses into one unread notification.
    post "/coach/conversations/#{@conv.id}/messages", params: { body: "and again" }, headers: auth, as: :json
    assert_equal 1, client_new_messages.where(read_at: nil).count
    assert_equal 2, Message.where(conversation_id: @conv.id, sender_type: "coach").count
  end

  test "send is 400 for empty/whitespace or an over-long body, writing nothing" do
    post "/coach/conversations/#{@conv.id}/messages", params: { body: "   " }, headers: auth, as: :json
    assert_response :bad_request
    post "/coach/conversations/#{@conv.id}/messages", params: { body: "a" * 2001 }, headers: auth, as: :json
    assert_response :bad_request
    assert_equal 0, Message.where(conversation_id: @conv.id).count
  end

  test "send is 409 when the subscription has ended (chat closed)" do
    @sub.update!(status: "ended", ends_at: 1.second.ago)
    post "/coach/conversations/#{@conv.id}/messages", params: { body: "hi" }, headers: auth, as: :json
    assert_response :conflict
    assert_equal 0, Message.where(conversation_id: @conv.id).count
  end

  test "another coach cannot send to this conversation (404)" do
    other = Coach.create!(phone: "+201012347004", password_hash: "h", full_name: "O2")
    token = { "Authorization" => "Bearer #{CoachApp::AccessToken.sign(other.id)}" }
    post "/coach/conversations/#{@conv.id}/messages", params: { body: "hi" }, headers: token, as: :json
    assert_response :not_found
  end

  test "the same clientRef twice sends one message" do
    ref = "11111111-1111-4111-8111-111111111111"
    post "/coach/conversations/#{@conv.id}/messages", params: { body: "once", clientRef: ref }, headers: auth, as: :json
    first_id = data["id"]
    post "/coach/conversations/#{@conv.id}/messages", params: { body: "once", clientRef: ref }, headers: auth, as: :json
    assert_equal first_id, data["id"]
    assert_equal 1, Message.where(conversation_id: @conv.id, sender_type: "coach").count
  end

  JPEG = "\xFF\xD8\xFF\xE0\x00\x10JFIF".b
  PNG = "\x89PNG\r\n\x1a\n".b

  def photo_upload(bytes: JPEG, content_type: "image/jpeg", name: "a.jpg")
    Rack::Test::UploadedFile.new(StringIO.new(bytes), content_type, true, original_filename: name)
  end

  test "send photo: 201, stored under chat/<conv>/, notifies the client, and streams back" do
    post "/coach/conversations/#{@conv.id}/photo",
         params: { photo: photo_upload(bytes: PNG, content_type: "image/png", name: "a.png") }, headers: auth
    assert_response :created
    assert_nil data["body"]
    assert_match %r{\A/coach/conversations/#{@conv.id}/messages/.+/photo\z}, data["photoUrl"]

    message = Message.find(data["id"])
    assert_equal "coach", message.sender_type
    assert message.attachment_key.start_with?("chat/#{@conv.id}/")
    assert_equal 1, client_new_messages.count

    get data["photoUrl"], headers: auth
    assert_response :ok
    assert_includes response.media_type, "image/png"
  end

  test "a non-image upload is 400 and writes nothing" do
    post "/coach/conversations/#{@conv.id}/photo",
         params: { photo: photo_upload(bytes: "GIF89a".b, content_type: "image/gif", name: "a.gif") }, headers: auth
    assert_response :bad_request
    post "/coach/conversations/#{@conv.id}/photo",
         params: { photo: photo_upload(bytes: JPEG, content_type: "image/png", name: "a.png") }, headers: auth
    assert_response :bad_request
    assert_equal 0, Message.where(conversation_id: @conv.id).count
  end

  test "another coach cannot fetch this conversation's photo (404)" do
    post "/coach/conversations/#{@conv.id}/photo", params: { photo: photo_upload }, headers: auth
    url = data["photoUrl"]
    other = Coach.create!(phone: "+201012347005", password_hash: "h", full_name: "O3")
    token = { "Authorization" => "Bearer #{CoachApp::AccessToken.sign(other.id)}" }
    get url, headers: token
    assert_response :not_found
  end
end
