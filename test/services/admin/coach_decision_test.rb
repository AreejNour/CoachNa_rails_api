require "test_helper"

class Admin::CoachDecisionTest < ActiveSupport::TestCase
  PHONE = "+201099988877"

  setup do
    @admin = AdminUser.create!(email: "admin_decision_test@example.com", password: "secret123", name: "Admin")
    @coach = Coach.create!(phone: PHONE, password_hash: "x", full_name: "Nour Khalil", status: "pending_review")
  end

  # ---------------------------------------------------------------------------
  # approve!
  # ---------------------------------------------------------------------------
  test "approve! moves pending_review to approved, sets commission, clears rejection_reason, sets reviewed_at" do
    @coach.update!(rejection_reason: "old reason")

    Admin::CoachDecision.approve!(coach: @coach, admin: @admin, commission: "20")

    @coach.reload
    assert_equal "approved",  @coach.status
    assert_equal 20.0,        @coach.commission_percent
    assert_nil                @coach.rejection_reason
    assert_not_nil            @coach.reviewed_at
  end

  test "approve! creates one CoachStatusChange audit row with correct fields" do
    assert_difference "CoachStatusChange.count", 1 do
      Admin::CoachDecision.approve!(coach: @coach, admin: @admin, commission: "15")
    end

    change = CoachStatusChange.last
    assert_equal "pending_review", change.from_status
    assert_equal "approved",       change.to_status
    assert_equal @admin.id,        change.admin_id
    assert_equal 15.0,             change.commission_percent.to_f
    assert_nil                     change.reason
  end

  test "approve! enqueues the push and email" do
    @coach.update!(email: "nour@example.com")
    Admin::CoachDecision.approve!(coach: @coach, admin: @admin, commission: "10")

    push = OutboxMessage.find_by!(kind: "push").payload
    assert_equal({ "type" => "coach", "id" => @coach.id }, push["recipient"])
    assert_equal "You're approved", push["title"]["en"]
    assert_equal({ "screen" => "coach_home" }, push["data"])

    email = OutboxMessage.find_by!(kind: "email").payload
    assert_equal "nour@example.com",          email["to"]
    assert_equal "coach_application_approved", email["template"]
    assert_equal "Nour",                       email["data"]["firstName"]
  end

  # ---------------------------------------------------------------------------
  # request_changes!
  # ---------------------------------------------------------------------------
  test "request_changes! moves pending_review to incomplete, sets rejection_reason and reviewed_at" do
    Admin::CoachDecision.request_changes!(coach: @coach, admin: @admin, reason: "Missing certificate")

    @coach.reload
    assert_equal "incomplete",           @coach.status
    assert_equal "Missing certificate",  @coach.rejection_reason
    assert_not_nil                       @coach.reviewed_at
  end

  test "request_changes! creates one audit row with correct fields" do
    assert_difference "CoachStatusChange.count", 1 do
      Admin::CoachDecision.request_changes!(coach: @coach, admin: @admin, reason: "Need better photo")
    end

    change = CoachStatusChange.last
    assert_equal "pending_review",   change.from_status
    assert_equal "incomplete",       change.to_status
    assert_equal @admin.id,          change.admin_id
    assert_equal "Need better photo", change.reason
    assert_nil                        change.commission_percent
  end

  test "request_changes! enqueues the push and email with reason" do
    @coach.update!(email: "nour@example.com")
    Admin::CoachDecision.request_changes!(coach: @coach, admin: @admin, reason: "Blurry photo")

    push = OutboxMessage.find_by!(kind: "push").payload
    assert_equal "Your application needs changes", push["title"]["en"]
    assert_equal({ "screen" => "coach_needs_changes" }, push["data"])

    email = OutboxMessage.find_by!(kind: "email").payload
    assert_equal "coach_application_needs_changes", email["template"]
    assert_equal "Blurry photo",                    email["data"]["reason"]
  end

  # ---------------------------------------------------------------------------
  # reject!
  # ---------------------------------------------------------------------------
  test "reject! moves pending_review to rejected, sets rejection_reason and reviewed_at" do
    Admin::CoachDecision.reject!(coach: @coach, admin: @admin, reason: "Fake certificate")

    @coach.reload
    assert_equal "rejected",          @coach.status
    assert_equal "Fake certificate",  @coach.rejection_reason
    assert_not_nil                    @coach.reviewed_at
  end

  test "reject! creates one audit row with correct fields" do
    assert_difference "CoachStatusChange.count", 1 do
      Admin::CoachDecision.reject!(coach: @coach, admin: @admin, reason: "Not qualified")
    end

    change = CoachStatusChange.last
    assert_equal "pending_review",  change.from_status
    assert_equal "rejected",        change.to_status
    assert_equal @admin.id,         change.admin_id
    assert_equal "Not qualified",   change.reason
    assert_nil                       change.commission_percent
  end

  test "reject! enqueues the push and email with reason" do
    @coach.update!(email: "nour@example.com")
    Admin::CoachDecision.reject!(coach: @coach, admin: @admin, reason: "Not qualified")

    push = OutboxMessage.find_by!(kind: "push").payload
    assert_equal "Your application was declined", push["title"]["en"]

    email = OutboxMessage.find_by!(kind: "email").payload
    assert_equal "coach_application_rejected", email["template"]
    assert_equal "Not qualified",              email["data"]["reason"]
  end

  # ---------------------------------------------------------------------------
  # suspend!
  # ---------------------------------------------------------------------------
  test "suspend! moves approved to suspended, does NOT touch rejection_reason or commission or reviewed_at" do
    @coach.update!(status: "approved", commission_percent: 25, rejection_reason: "preserved", reviewed_at: 1.day.ago)
    original_reviewed_at = @coach.reload.reviewed_at

    Admin::CoachDecision.suspend!(coach: @coach, admin: @admin, reason: "Violation")

    @coach.reload
    assert_equal "suspended",   @coach.status
    assert_equal 25.0,          @coach.commission_percent.to_f
    assert_equal "preserved",   @coach.rejection_reason
    assert_equal original_reviewed_at.to_i, @coach.reviewed_at.to_i
  end

  test "suspend! creates one audit row with correct fields" do
    @coach.update!(status: "approved")

    assert_difference "CoachStatusChange.count", 1 do
      Admin::CoachDecision.suspend!(coach: @coach, admin: @admin, reason: "Violation report")
    end

    change = CoachStatusChange.last
    assert_equal "approved",         change.from_status
    assert_equal "suspended",        change.to_status
    assert_equal @admin.id,          change.admin_id
    assert_equal "Violation report", change.reason
    assert_nil                        change.commission_percent
  end

  test "suspend! enqueues the push and email with reason" do
    @coach.update!(status: "approved", email: "nour@example.com")
    Admin::CoachDecision.suspend!(coach: @coach, admin: @admin, reason: "Terms violation")

    push = OutboxMessage.find_by!(kind: "push").payload
    assert_equal "Your account is suspended", push["title"]["en"]

    email = OutboxMessage.find_by!(kind: "email").payload
    assert_equal "coach_suspended",  email["template"]
    assert_equal "Terms violation",  email["data"]["reason"]
  end

  # ---------------------------------------------------------------------------
  # reactivate!
  # ---------------------------------------------------------------------------
  test "reactivate! moves suspended to approved, does NOT touch rejection_reason or commission or reviewed_at" do
    @coach.update!(status: "suspended", commission_percent: 30, rejection_reason: "kept", reviewed_at: 2.days.ago)
    original_reviewed_at = @coach.reload.reviewed_at

    Admin::CoachDecision.reactivate!(coach: @coach, admin: @admin, reason: "Appeal accepted")

    @coach.reload
    assert_equal "approved",   @coach.status
    assert_equal 30.0,         @coach.commission_percent.to_f
    assert_equal "kept",       @coach.rejection_reason
    assert_equal original_reviewed_at.to_i, @coach.reviewed_at.to_i
  end

  test "reactivate! creates one audit row with correct fields" do
    @coach.update!(status: "suspended")

    assert_difference "CoachStatusChange.count", 1 do
      Admin::CoachDecision.reactivate!(coach: @coach, admin: @admin, reason: "Appeal accepted")
    end

    change = CoachStatusChange.last
    assert_equal "suspended",        change.from_status
    assert_equal "approved",         change.to_status
    assert_equal @admin.id,          change.admin_id
    assert_equal "Appeal accepted",  change.reason
    assert_nil                        change.commission_percent
  end

  test "reactivate! enqueues the push and email with reason" do
    @coach.update!(status: "suspended", email: "nour@example.com")
    Admin::CoachDecision.reactivate!(coach: @coach, admin: @admin, reason: "Appeal OK")

    push = OutboxMessage.find_by!(kind: "push").payload
    assert_equal "Your account is active again", push["title"]["en"]

    email = OutboxMessage.find_by!(kind: "email").payload
    assert_equal "coach_reactivated", email["template"]
    assert_equal "Appeal OK",         email["data"]["reason"]
  end

  # ---------------------------------------------------------------------------
  # deactivate!
  # ---------------------------------------------------------------------------
  test "deactivate! moves approved to deactivated, does NOT touch rejection_reason or commission or reviewed_at" do
    @coach.update!(status: "approved", commission_percent: 18, rejection_reason: "still here", reviewed_at: 3.days.ago)
    original_reviewed_at = @coach.reload.reviewed_at

    Admin::CoachDecision.deactivate!(coach: @coach, admin: @admin, reason: "Closing account")

    @coach.reload
    assert_equal "deactivated",  @coach.status
    assert_equal 18.0,           @coach.commission_percent.to_f
    assert_equal "still here",   @coach.rejection_reason
    assert_equal original_reviewed_at.to_i, @coach.reviewed_at.to_i
  end

  test "deactivate! moves suspended to deactivated" do
    @coach.update!(status: "suspended")
    Admin::CoachDecision.deactivate!(coach: @coach, admin: @admin, reason: "Permanent ban")

    assert_equal "deactivated", @coach.reload.status
  end

  test "deactivate! (from approved) creates one audit row with correct fields" do
    @coach.update!(status: "approved")

    assert_difference "CoachStatusChange.count", 1 do
      Admin::CoachDecision.deactivate!(coach: @coach, admin: @admin, reason: "Closing")
    end

    change = CoachStatusChange.last
    assert_equal "approved",    change.from_status
    assert_equal "deactivated", change.to_status
    assert_equal @admin.id,     change.admin_id
    assert_equal "Closing",     change.reason
    assert_nil                   change.commission_percent
  end

  test "deactivate! enqueues the push and email with reason" do
    @coach.update!(status: "approved", email: "nour@example.com")
    Admin::CoachDecision.deactivate!(coach: @coach, admin: @admin, reason: "Permanent")

    push = OutboxMessage.find_by!(kind: "push").payload
    assert_equal "Your account was deactivated", push["title"]["en"]

    email = OutboxMessage.find_by!(kind: "email").payload
    assert_equal "coach_deactivated", email["template"]
    assert_equal "Permanent",         email["data"]["reason"]
  end

  # ---------------------------------------------------------------------------
  # No-email coach: push + audit still happen, 0 emails
  # ---------------------------------------------------------------------------
  test "approve! with no email: push fires, audit exists, 0 emails" do
    # @coach has no email
    Admin::CoachDecision.approve!(coach: @coach, admin: @admin, commission: "10")

    assert_equal 1, OutboxMessage.where(kind: "push").count
    assert_equal 0, OutboxMessage.where(kind: "email").count
    assert_equal 1, CoachStatusChange.count
  end

  test "request_changes! with no email: push fires, audit exists, 0 emails" do
    Admin::CoachDecision.request_changes!(coach: @coach, admin: @admin, reason: "Missing info")

    assert_equal 1, OutboxMessage.where(kind: "push").count
    assert_equal 0, OutboxMessage.where(kind: "email").count
    assert_equal 1, CoachStatusChange.count
  end

  test "suspend! with no email: push fires, audit exists, 0 emails" do
    @coach.update!(status: "approved")
    Admin::CoachDecision.suspend!(coach: @coach, admin: @admin, reason: "Violation")

    assert_equal 1, OutboxMessage.where(kind: "push").count
    assert_equal 0, OutboxMessage.where(kind: "email").count
    assert_equal 1, CoachStatusChange.count
  end

  # ---------------------------------------------------------------------------
  # Invalid transitions — approve! only allowed from pending_review
  # ---------------------------------------------------------------------------
  %w[incomplete approved rejected suspended deactivated].each do |status|
    test "approve! refuses a coach who is #{status}" do
      @coach.update!(status: status)

      error = assert_raises(Admin::CoachDecision::Error) do
        Admin::CoachDecision.approve!(coach: @coach, admin: @admin, commission: "15")
      end

      assert_includes error.message, status
      assert_equal status,              @coach.reload.status
      assert_equal 0,                   CoachStatusChange.count
      assert_equal 0,                   OutboxMessage.count
    end
  end

  # request_changes! only allowed from pending_review
  %w[incomplete approved rejected suspended deactivated].each do |status|
    test "request_changes! refuses a coach who is #{status}" do
      @coach.update!(status: status)

      error = assert_raises(Admin::CoachDecision::Error) do
        Admin::CoachDecision.request_changes!(coach: @coach, admin: @admin, reason: "reason")
      end

      assert_includes error.message, status
      assert_equal status, @coach.reload.status
      assert_equal 0,      CoachStatusChange.count
      assert_equal 0,      OutboxMessage.count
    end
  end

  # reject! only allowed from pending_review
  %w[incomplete approved rejected suspended deactivated].each do |status|
    test "reject! refuses a coach who is #{status}" do
      @coach.update!(status: status)

      error = assert_raises(Admin::CoachDecision::Error) do
        Admin::CoachDecision.reject!(coach: @coach, admin: @admin, reason: "reason")
      end

      assert_includes error.message, status
      assert_equal status, @coach.reload.status
      assert_equal 0,      CoachStatusChange.count
      assert_equal 0,      OutboxMessage.count
    end
  end

  # suspend! only allowed from approved
  %w[incomplete pending_review rejected suspended deactivated].each do |status|
    test "suspend! refuses a coach who is #{status}" do
      @coach.update!(status: status)

      error = assert_raises(Admin::CoachDecision::Error) do
        Admin::CoachDecision.suspend!(coach: @coach, admin: @admin, reason: "reason")
      end

      assert_includes error.message, status
      assert_equal status, @coach.reload.status
      assert_equal 0,      CoachStatusChange.count
      assert_equal 0,      OutboxMessage.count
    end
  end

  # reactivate! only allowed from suspended
  %w[incomplete pending_review approved rejected deactivated].each do |status|
    test "reactivate! refuses a coach who is #{status}" do
      @coach.update!(status: status)

      error = assert_raises(Admin::CoachDecision::Error) do
        Admin::CoachDecision.reactivate!(coach: @coach, admin: @admin, reason: "reason")
      end

      assert_includes error.message, status
      assert_equal status, @coach.reload.status
      assert_equal 0,      CoachStatusChange.count
      assert_equal 0,      OutboxMessage.count
    end
  end

  # deactivate! only allowed from approved or suspended
  %w[incomplete pending_review rejected deactivated].each do |status|
    test "deactivate! refuses a coach who is #{status}" do
      @coach.update!(status: status)

      error = assert_raises(Admin::CoachDecision::Error) do
        Admin::CoachDecision.deactivate!(coach: @coach, admin: @admin, reason: "reason")
      end

      assert_includes error.message, status
      assert_equal status, @coach.reload.status
      assert_equal 0,      CoachStatusChange.count
      assert_equal 0,      OutboxMessage.count
    end
  end

  # ---------------------------------------------------------------------------
  # Bad input — commission
  # ---------------------------------------------------------------------------
  [ "-1", "101", "abc", "", nil ].each do |commission|
    test "approve! refuses commission #{commission.inspect}" do
      error = assert_raises(Admin::CoachDecision::Error) do
        Admin::CoachDecision.approve!(coach: @coach, admin: @admin, commission: commission)
      end

      assert error.message.present?
      assert_equal "pending_review", @coach.reload.status
      assert_equal 0,                CoachStatusChange.count
      assert_equal 0,                OutboxMessage.count
    end
  end

  # Bad input — reason (all five reason-carrying actions)
  [ nil, "", "   " ].each do |reason|
    test "request_changes! refuses reason #{reason.inspect}" do
      assert_raises(Admin::CoachDecision::Error) do
        Admin::CoachDecision.request_changes!(coach: @coach, admin: @admin, reason: reason)
      end

      assert_equal "pending_review", @coach.reload.status
      assert_equal 0,                CoachStatusChange.count
      assert_equal 0,                OutboxMessage.count
    end

    test "reject! refuses reason #{reason.inspect}" do
      assert_raises(Admin::CoachDecision::Error) do
        Admin::CoachDecision.reject!(coach: @coach, admin: @admin, reason: reason)
      end

      assert_equal "pending_review", @coach.reload.status
      assert_equal 0,                CoachStatusChange.count
      assert_equal 0,                OutboxMessage.count
    end

    test "suspend! refuses reason #{reason.inspect}" do
      @coach.update!(status: "approved")
      assert_raises(Admin::CoachDecision::Error) do
        Admin::CoachDecision.suspend!(coach: @coach, admin: @admin, reason: reason)
      end

      assert_equal "approved", @coach.reload.status
      assert_equal 0,          CoachStatusChange.count
      assert_equal 0,          OutboxMessage.count
    end

    test "reactivate! refuses reason #{reason.inspect}" do
      @coach.update!(status: "suspended")
      assert_raises(Admin::CoachDecision::Error) do
        Admin::CoachDecision.reactivate!(coach: @coach, admin: @admin, reason: reason)
      end

      assert_equal "suspended", @coach.reload.status
      assert_equal 0,           CoachStatusChange.count
      assert_equal 0,           OutboxMessage.count
    end

    test "deactivate! refuses reason #{reason.inspect}" do
      @coach.update!(status: "approved")
      assert_raises(Admin::CoachDecision::Error) do
        Admin::CoachDecision.deactivate!(coach: @coach, admin: @admin, reason: reason)
      end

      assert_equal "approved", @coach.reload.status
      assert_equal 0,          CoachStatusChange.count
      assert_equal 0,          OutboxMessage.count
    end
  end

  # ---------------------------------------------------------------------------
  # Rollback: when the second Outbox.enqueue_and_publish_after_commit! raises,
  # everything is rolled back — no status change, no audit row, no outbox row.
  # ---------------------------------------------------------------------------
  test "approve! rolls back fully when second enqueue raises" do
    @coach.update!(email: "nour@example.com")
    calls = 0
    original = CoachApp::Outbox.method(:enqueue_and_publish_after_commit!)

    swap_method(CoachApp::Outbox, :enqueue_and_publish_after_commit!,
                ->(**kw) { (calls += 1) == 2 ? raise("boom") : original.call(**kw) }) do
      assert_raises(RuntimeError) do
        Admin::CoachDecision.approve!(coach: @coach, admin: @admin, commission: "15")
      end
    end

    assert_equal "pending_review", @coach.reload.status
    assert_equal 0,                CoachStatusChange.count
    assert_equal 0,                OutboxMessage.count
  end

  test "suspend! rolls back fully when second enqueue raises" do
    @coach.update!(status: "approved", email: "nour@example.com")
    calls = 0
    original = CoachApp::Outbox.method(:enqueue_and_publish_after_commit!)

    swap_method(CoachApp::Outbox, :enqueue_and_publish_after_commit!,
                ->(**kw) { (calls += 1) == 2 ? raise("boom") : original.call(**kw) }) do
      assert_raises(RuntimeError) do
        Admin::CoachDecision.suspend!(coach: @coach, admin: @admin, reason: "Violation")
      end
    end

    assert_equal "approved", @coach.reload.status
    assert_equal 0,          CoachStatusChange.count
    assert_equal 0,          OutboxMessage.count
  end
end
