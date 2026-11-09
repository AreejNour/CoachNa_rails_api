require "test_helper"

class CoachApp::ReviewControllerTest < ActionDispatch::IntegrationTest
  ALL_MISSING = %w[about profile_photo national_id_front national_id_back certificate].freeze

  setup { @coach = Coach.create!(phone: "+201012345710", password_hash: "secret-hash", full_name: "Sara") }

  def auth = { "Authorization" => "Bearer #{CoachApp::AccessToken.sign(@coach.id)}" }
  def data = response.parsed_body["data"]
  def status_data = (get("/coach/profile/status", headers: auth); data)
  def submit = post("/coach/profile/submit", headers: auth)

  def add_document(type, key = type)
    @coach.coach_documents.create!(type: type, storage_key: "secret/#{key}", mime_type: "image/jpeg", size_bytes: 1)
  end

  def complete_profile = @coach.update!(bio: "Hi", years_experience: 3, specialties: [ "sports" ])

  def complete_everything
    complete_profile
    CoachDocument::TYPES.each { |type| add_document(type) }
  end

  def assert_failure(status, message)
    assert_response status
    assert_equal({ "success" => false, "error" => message }, response.parsed_body)
  end

  test "a new coach is missing all five, in order" do
    assert_equal ALL_MISSING, status_data["missing"]
  end

  test "status returns the contract's fields" do
    add_document("certificate")

    result = status_data

    assert_equal %w[commissionPercent documents missing rejectionReason status], result.keys.sort
    assert_equal "incomplete", result["status"]
    assert_nil result["rejectionReason"]
    assert_equal "certificate", result["documents"].first["type"]
  end

  test "about stays missing with no bio, no years or no specialties" do
    [ { bio: nil }, { years_experience: nil }, { specialties: [] } ].each do |gap|
      complete_profile
      @coach.update!(gap)

      assert_includes status_data["missing"], "about"
    end
  end

  test "0 years of experience counts" do
    complete_profile
    @coach.update!(years_experience: 0)

    assert_not_includes status_data["missing"], "about"
  end

  test "two certificates don't hide a missing ID" do
    2.times { |n| add_document("certificate", "c#{n}") }

    assert_equal %w[about profile_photo national_id_front national_id_back], status_data["missing"]
  end

  test "commission is a number, or null with none" do
    assert_nil status_data["commissionPercent"]

    @coach.update!(commission_percent: 15)
    assert_equal 15, status_data["commissionPercent"]
    assert_kind_of Numeric, status_data["commissionPercent"]

    @coach.update!(commission_percent: 12.5)
    assert_equal 12.5, status_data["commissionPercent"]
  end

  test "the password hash and storage keys never appear" do
    add_document("certificate")
    get "/coach/profile/status", headers: auth

    assert_no_match(/secret/, response.body)
  end

  test "submit with everything present moves to pending_review" do
    complete_everything
    @coach.update!(rejection_reason: "old")

    submit

    assert_response :ok
    assert_equal({ "success" => true, "data" => { "status" => "pending_review" } }, response.parsed_body)
    @coach.reload
    assert_equal "pending_review", @coach.status
    assert_not_nil @coach.profile_submitted_at
    assert_nil @coach.rejection_reason
  end

  test "submit with something missing is refused and changes nothing" do
    complete_profile
    add_document("profile_photo")

    submit

    assert_response :bad_request
    assert_equal({
      "success" => false, "error" => "missing requirements",
      "missing" => %w[national_id_front national_id_back certificate]
    }, response.parsed_body)
    assert_equal "incomplete", @coach.reload.status
    assert_nil @coach.profile_submitted_at
  end

  test "a rejected coach can submit again, which clears the reason" do
    complete_everything
    @coach.update!(status: "rejected", rejection_reason: "Too blurry")

    submit

    assert_response :ok
    assert_nil @coach.reload.rejection_reason
  end

  %w[pending_review approved suspended deactivated].each do |status|
    test "a coach who is #{status} can't submit" do
      complete_everything
      @coach.update!(status: status)

      submit

      assert_failure :conflict, "profile not submittable in current state"
      assert_equal status, @coach.reload.status
    end
  end

  test "a second submit is refused and doesn't move the submitted time" do
    complete_everything
    submit
    first = @coach.reload.profile_submitted_at

    travel 1.minute do
      submit
    end

    assert_failure :conflict, "profile not submittable in current state"
    assert_equal first, @coach.reload.profile_submitted_at
  end

  test "no token is 401" do
    get "/coach/profile/status"
    assert_failure :unauthorized, "unauthorized"

    post "/coach/profile/submit"
    assert_failure :unauthorized, "unauthorized"
  end
end

class CoachApp::ReviewConcurrencyTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  setup do
    Storage.reset!
    @coach = Coach.create!(phone: "+201012345711", password_hash: "x", full_name: "Sara", bio: "Hi", years_experience: 3, specialties: [ "sports" ])
    CoachDocument::REQUIRED_SINGLE.each do |type|
      @coach.coach_documents.create!(type: type, storage_key: "keep/#{type}", mime_type: "image/jpeg", size_bytes: 1)
    end
  end

  teardown { Coach.where(id: @coach.id).delete_all }

  test "a submit and a removal of the last certificate never leave pending_review with a document missing" do
    5.times do
      @coach.update!(status: "incomplete")
      certificate = @coach.coach_documents.create!(type: "certificate", storage_key: "keep/c", mime_type: "image/jpeg", size_bytes: 1)
      start = Concurrent::CountDownLatch.new(1)
      actions = [
        -> { CoachApp::ReviewStatus.submit!(Coach.find(@coach.id)) },
        -> { CoachApp::Documents.remove(Coach.find(@coach.id), certificate.id) }
      ]
      threads = actions.map do |action|
        Thread.new do
          ActiveRecord::Base.connection_pool.with_connection do
            start.wait
            action.call
          rescue ApiError
            nil
          end
        end
      end
      start.count_down
      threads.each(&:join)

      if @coach.reload.status == "pending_review"
        assert CoachDocument.exists?(certificate.id), "submitted without its certificate"
      end
      @coach.coach_documents.where(type: "certificate").delete_all
    end
  end
end
