require "test_helper"

class Admin::CoachPasswordSetupTest < ActiveSupport::TestCase
  setup do
    CoachApp::QueuePublisher.adapter = CoachApp::QueuePublisher::TestAdapter.new
    @coach = Coach.create!(full_name: "Mona Coach", phone: "+201001234567", email: "mona@example.com",
                           password_hash: CoachApp::Password.digest("random-initial"), status: "approved",
                           specialties: [ "weight_loss" ])
  end

  teardown { CoachApp::QueuePublisher.adapter = nil }

  test "link_for uses COACH_PASSWORD_URL_BASE, with a localhost default outside production" do
    with_env("COACH_PASSWORD_URL_BASE" => nil) do
      assert Admin::CoachPasswordSetup.link_for(@coach).start_with?("http://localhost:3003/coach-password/")
    end
    with_env("COACH_PASSWORD_URL_BASE" => "https://api.example.com/") do
      assert Admin::CoachPasswordSetup.link_for(@coach).start_with?("https://api.example.com/coach-password/")
    end
  end

  test "in production a missing COACH_PASSWORD_URL_BASE raises, naming the variable" do
    with_env("COACH_PASSWORD_URL_BASE" => nil) do
      original = Rails.method(:env)
      Rails.define_singleton_method(:env) { ActiveSupport::EnvironmentInquirer.new("production") }
      begin
        error = assert_raises(RuntimeError) { Admin::CoachPasswordSetup.link_for(@coach) }
        assert_includes error.message, "COACH_PASSWORD_URL_BASE"
      ensure
        Rails.define_singleton_method(:env, original)
      end
    end
  end

  test "fingerprint is private" do
    assert_raises(NoMethodError) { Admin::CoachPasswordSetup.fingerprint("x") }
  end

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

  private

  def with_env(vars)
    old = vars.keys.to_h { |k| [ k, ENV[k] ] }
    vars.each { |k, v| v.nil? ? ENV.delete(k) : ENV[k] = v }
    yield
  ensure
    old.each { |k, v| v.nil? ? ENV.delete(k) : ENV[k] = v }
  end
end
