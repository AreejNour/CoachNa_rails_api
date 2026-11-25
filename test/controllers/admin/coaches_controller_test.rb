require "test_helper"

class Admin::CoachesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @admin = AdminUser.create!(email: "team@coachna.app", name: "Team", password: "Secret123")
  end

  def sign_in
    post "/admin/login", params: { email: "team@coachna.app", password: "Secret123" }
  end

  def make_coach(name, status, phone, submitted: Time.current)
    Coach.create!(full_name: name, phone: phone, password_hash: "h", status: status,
                  specialties: [ "weight_loss" ], profile_submitted_at: submitted)
  end

  test "index lists pending_review coaches and excludes other statuses" do
    sign_in
    make_coach("Pending Pat", "pending_review", "+201000000001")
    make_coach("Approved Amy", "approved", "+201000000002")
    make_coach("Incomplete Ian", "incomplete", "+201000000003")

    get "/admin"
    assert_response :ok
    assert_includes @response.body, "Pending Pat"
    assert_not_includes @response.body, "Approved Amy"
    assert_not_includes @response.body, "Incomplete Ian"
  end

  test "index shows an empty state when none are pending" do
    sign_in
    get "/admin"
    assert_response :ok
    assert_includes @response.body, "No coaches"
  end

  test "index redirects to login when not signed in" do
    get "/admin"
    assert_redirected_to "/admin/login"
  end

  def make_document(coach, type, mime)
    coach.coach_documents.create!(type: type, storage_key: "k-#{type}", mime_type: mime, size_bytes: 1)
  end

  test "show displays the coach profile and its documents" do
    sign_in
    coach = make_coach("Pending Pat", "pending_review", "+201000000009")
    coach.update!(bio: "Clinical nutritionist", years_experience: 7)
    make_document(coach, "profile_photo", "image/jpeg")

    get admin_coach_path(coach)
    assert_response :ok
    assert_includes @response.body, "Pending Pat"
    assert_includes @response.body, "Clinical nutritionist"
    assert_includes @response.body, "profile_photo"
  end

  test "document streams the bytes with no-store for a signed-in admin" do
    sign_in
    coach = make_coach("Pending Pat", "pending_review", "+201000000010")
    doc = make_document(coach, "certificate", "application/pdf")

    swap_method(CoachApp::Documents, :download, ->(_doc) { { bytes: "PDFBYTES" } }) do
      get admin_coach_document_path(coach, doc)
    end
    assert_response :ok
    assert_equal "no-store", @response.headers["Cache-Control"]
    assert_equal "PDFBYTES", @response.body
  end

  test "show redirects to login when not signed in" do
    coach = make_coach("Pending Pat", "pending_review", "+201000000011")
    get admin_coach_path(coach)
    assert_redirected_to "/admin/login"
  end

  # ---------------------------------------------------------------------------
  # Decision actions
  # ---------------------------------------------------------------------------

  test "approve sets coach to approved with commission" do
    sign_in
    coach = make_coach("Pending Pat", "pending_review", "+201000000020")
    post admin_approve_coach_path(coach), params: { commission: "15" }
    assert_redirected_to admin_coach_path(coach)
    coach.reload
    assert_equal "approved", coach.status
    assert_equal 15.0, coach.commission_percent
  end

  test "request_changes sets coach to incomplete with rejection_reason" do
    sign_in
    coach = make_coach("Pending Pat", "pending_review", "+201000000021")
    post admin_request_changes_coach_path(coach), params: { reason: "Missing certificate" }
    assert_redirected_to admin_coach_path(coach)
    coach.reload
    assert_equal "incomplete", coach.status
    assert_equal "Missing certificate", coach.rejection_reason
  end

  test "reject sets coach to rejected with rejection_reason" do
    sign_in
    coach = make_coach("Pending Pat", "pending_review", "+201000000022")
    post admin_reject_coach_path(coach), params: { reason: "Does not qualify" }
    assert_redirected_to admin_coach_path(coach)
    coach.reload
    assert_equal "rejected", coach.status
    assert_equal "Does not qualify", coach.rejection_reason
  end

  test "suspend sets approved coach to suspended" do
    sign_in
    coach = make_coach("Approved Amy", "approved", "+201000000023")
    post admin_suspend_coach_path(coach), params: { reason: "Policy violation" }
    assert_redirected_to admin_coach_path(coach)
    coach.reload
    assert_equal "suspended", coach.status
  end

  test "reactivate sets suspended coach to approved" do
    sign_in
    coach = make_coach("Suspended Sam", "suspended", "+201000000024")
    post admin_reactivate_coach_path(coach), params: { reason: "Issue resolved" }
    assert_redirected_to admin_coach_path(coach)
    coach.reload
    assert_equal "approved", coach.status
  end

  test "deactivate sets approved coach to deactivated" do
    sign_in
    coach = make_coach("Approved Amy", "approved", "+201000000025")
    post admin_deactivate_coach_path(coach), params: { reason: "Account closed" }
    assert_redirected_to admin_coach_path(coach)
    coach.reload
    assert_equal "deactivated", coach.status
  end

  test "invalid transition flashes alert and leaves status unchanged" do
    sign_in
    coach = make_coach("Pending Pat", "pending_review", "+201000000026")
    post admin_suspend_coach_path(coach), params: { reason: "Some reason" }
    assert_redirected_to admin_coach_path(coach)
    follow_redirect!
    assert_includes @response.body, "Cannot perform this action"
    coach.reload
    assert_equal "pending_review", coach.status
  end

  test "approve without sign in redirects to login and changes nothing" do
    coach = make_coach("Pending Pat", "pending_review", "+201000000030")
    post admin_approve_coach_path(coach), params: { commission: "15" }
    assert_redirected_to "/admin/login"
    coach.reload
    assert_equal "pending_review", coach.status
  end

  test "request_changes without sign in redirects to login and changes nothing" do
    coach = make_coach("Pending Pat", "pending_review", "+201000000031")
    post admin_request_changes_coach_path(coach), params: { reason: "Missing cert" }
    assert_redirected_to "/admin/login"
    coach.reload
    assert_equal "pending_review", coach.status
  end

  test "reject without sign in redirects to login and changes nothing" do
    coach = make_coach("Pending Pat", "pending_review", "+201000000032")
    post admin_reject_coach_path(coach), params: { reason: "Does not qualify" }
    assert_redirected_to "/admin/login"
    coach.reload
    assert_equal "pending_review", coach.status
  end

  test "suspend without sign in redirects to login and changes nothing" do
    coach = make_coach("Approved Amy", "approved", "+201000000033")
    post admin_suspend_coach_path(coach), params: { reason: "Policy" }
    assert_redirected_to "/admin/login"
    coach.reload
    assert_equal "approved", coach.status
  end

  test "reactivate without sign in redirects to login and changes nothing" do
    coach = make_coach("Suspended Sam", "suspended", "+201000000034")
    post admin_reactivate_coach_path(coach), params: { reason: "Resolved" }
    assert_redirected_to "/admin/login"
    coach.reload
    assert_equal "suspended", coach.status
  end

  test "deactivate without sign in redirects to login and changes nothing" do
    coach = make_coach("Approved Amy", "approved", "+201000000035")
    post admin_deactivate_coach_path(coach), params: { reason: "Closed" }
    assert_redirected_to "/admin/login"
    coach.reload
    assert_equal "approved", coach.status
  end

  # ---------------------------------------------------------------------------
  # View: decision panel shows correct controls per status
  # ---------------------------------------------------------------------------

  test "show for pending_review coach displays Approve, Request changes, Reject but not Suspend" do
    sign_in
    coach = make_coach("Pending Pat", "pending_review", "+201000000040")
    get admin_coach_path(coach)
    assert_response :ok
    assert_includes @response.body, "Approve"
    assert_includes @response.body, "Request changes"
    assert_includes @response.body, "Reject"
    assert_not_includes @response.body, "Suspend"
    assert_not_includes @response.body, "Reactivate"
  end

  test "show for approved coach displays Suspend and Deactivate but not Approve" do
    sign_in
    coach = make_coach("Active Coach", "approved", "+201000000041")
    get admin_coach_path(coach)
    assert_response :ok
    assert_includes @response.body, "Suspend"
    assert_includes @response.body, "Deactivate"
    assert_not_includes @response.body, "Approve"
    assert_not_includes @response.body, "Reactivate"
  end

  # ---------------------------------------------------------------------------
  # I1: terminal-action confirm guard (onsubmit= with confirm()
  # ---------------------------------------------------------------------------

  test "show for pending_review coach reject form carries onsubmit confirm guard" do
    sign_in
    coach = make_coach("Pending Pat", "pending_review", "+201000000050")
    get admin_coach_path(coach)
    assert_response :ok
    assert_match(/onsubmit=.*confirm\(/, @response.body)
  end

  test "show for approved coach deactivate form carries onsubmit confirm guard" do
    sign_in
    coach = make_coach("Active Coach", "approved", "+201000000051")
    get admin_coach_path(coach)
    assert_response :ok
    assert_match(/onsubmit=.*confirm\(/, @response.body)
  end

  # ---------------------------------------------------------------------------
  # M3: per-action flash messages
  # ---------------------------------------------------------------------------

  test "approve flashes 'Coach approved.'" do
    sign_in
    coach = make_coach("Pending Pat", "pending_review", "+201000000060")
    post admin_approve_coach_path(coach), params: { commission: "10" }
    assert_redirected_to admin_coach_path(coach)
    follow_redirect!
    assert_includes @response.body, "Coach approved."
  end
end
