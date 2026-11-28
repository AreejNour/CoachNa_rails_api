require "test_helper"

class Admin::CoachPasswordSetupTest < ActiveSupport::TestCase
  setup do
    CoachApp::QueuePublisher.adapter = CoachApp::QueuePublisher::TestAdapter.new
    @coach = Coach.create!(full_name: "Mona Coach", phone: "+201001234567", email: "mona@example.com",
                           password_hash: CoachApp::Password.digest("random-initial"), status: "approved",
                           specialties: [ "weight_loss" ])
  end

  teardown { CoachApp::QueuePublisher.adapter = nil }

  test "verify returns the coach for a fresh token and nil after the password is set" do
    token = Admin::CoachPasswordSetup.token_for(@coach)
    assert_equal @coach, Admin::CoachPasswordSetup.verify(token)
    assert Admin::CoachPasswordSetup.set_password!(token, "newpass123", "newpass123")
    assert_nil Admin::CoachPasswordSetup.verify(token)
    assert_nil Admin::CoachPasswordSetup.set_password!(token, "other12345", "other12345")
  end

  test "verify rejects nil, blank and tokens for other purposes" do
    assert_nil Admin::CoachPasswordSetup.verify(nil)
    assert_nil Admin::CoachPasswordSetup.verify("")
    other = Rails.application.message_verifier(:other).generate([ @coach.id, "x" ])
    assert_nil Admin::CoachPasswordSetup.verify(other)
  end

  test "send_email! queues coach_account_created with a link" do
    Admin::CoachPasswordSetup.send_email!(@coach)
    payload = OutboxMessage.where(kind: "email").sole.payload
    assert_equal "coach_account_created", payload["template"]
    assert_equal "mona@example.com", payload["to"]
    assert_includes payload["data"]["link"], "/coach-password/"
  end

  test "send_email! refuses a coach without an email" do
    @coach.update!(email: nil)
    assert_raises(ArgumentError) { Admin::CoachPasswordSetup.send_email!(@coach) }
  end
end
