require "test_helper"

class CoachApp::ConversationJsonTest < ActiveSupport::TestCase
  setup do
    @coach = Coach.create!(phone: uniq_phone, password_hash: "h", full_name: "Coach")
    @client = Client.create!(phone: uniq_phone, password_hash: "h", full_name: "Nour Hassan")
    @sub = make_sub
    @conv = Conversation.create!(subscription_id: @sub.id, last_message_at: Time.current)
  end

  def uniq_phone = "+20#{SecureRandom.random_number(10**10).to_s.rjust(10, '0')}"

  def make_sub
    pkg = @coach.coach_packages.create!(name: "P", price_piastres: 1000, duration_days: 30, includes: [ "x" ])
    now = Time.current
    Subscription.create!(client_id: @client.id, coach_id: @coach.id, package_id: pkg.id, status: "active",
                         price_piastres: 1000, commission_percent: 10, commission_piastres: 100,
                         starts_at: now - 1.day, ends_at: now + 30.days)
  end

  def msg(sender_type, body, at)
    sender_id = sender_type == "coach" ? @coach.id : @client.id
    Message.create!(conversation_id: @conv.id, sender_type: sender_type, sender_id: sender_id,
                    body: body, sent_at: at)
  end

  test "lastMessageSenderType is the newest message's sender when the coach replied last" do
    msg("client", "hi", 2.minutes.ago)
    msg("coach", "reply", 1.minute.ago)
    assert_equal "coach", CoachApp::ConversationJson.list_item(@conv, 0)[:lastMessageSenderType]
  end

  test "lastMessageSenderType reflects a client newest message" do
    msg("coach", "reply", 2.minutes.ago)
    msg("client", "thanks", 1.minute.ago)
    assert_equal "client", CoachApp::ConversationJson.list_item(@conv, 0)[:lastMessageSenderType]
  end

  test "lastMessageSenderType is nil when there are no messages" do
    assert_nil CoachApp::ConversationJson.list_item(@conv, 0)[:lastMessageSenderType]
  end
end
