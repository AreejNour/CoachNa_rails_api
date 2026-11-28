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

  @@client_seq = 0
  def make_client(name)
    @@client_seq += 1
    Client.create!(full_name: name, phone: format("+20199%07d", @@client_seq), password_hash: "h")
  end

  def sub(coach, client, status:, starts_at: Time.current)
    pkg = CoachPackage.create!(coach: coach, name: "Plan", price_piastres: 50_000,
                               duration_days: 30, includes: {})
    Subscription.create!(client: client, coach: coach, package_id: pkg.id, status: status,
                         price_piastres: 50_000, commission_percent: 10, commission_piastres: 5_000,
                         starts_at: starts_at, ends_at: starts_at + 30.days)
  end

  test "index lists coaches of every status by default" do
    sign_in
    make_coach("Pending Pat", "pending_review", "+201000000001")
    make_coach("Approved Amy", "approved", "+201000000002")
    make_coach("Incomplete Ian", "incomplete", "+201000000003")

    get "/admin"
    assert_response :ok
    assert_includes @response.body, "Pending Pat"
    assert_includes @response.body, "Approved Amy"
    assert_includes @response.body, "Incomplete Ian"
  end

  test "index filters by status param" do
    sign_in
    make_coach("Pending Pat", "pending_review", "+201000000001")
    make_coach("Approved Amy", "approved", "+201000000002")

    get "/admin", params: { status: "approved" }
    assert_response :ok
    assert_includes @response.body, "Approved Amy"
    assert_not_includes @response.body, "Pending Pat"
  end

  test "index filters by search query across name and phone" do
    sign_in
    make_coach("Pending Pat", "pending_review", "+201000000001")
    make_coach("Approved Amy", "approved", "+201000000002")

    get "/admin", params: { q: "Amy" }
    assert_response :ok
    assert_includes @response.body, "Approved Amy"
    assert_not_includes @response.body, "Pending Pat"
  end

  test "index shows an empty state when there are no coaches" do
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

  test "show for pending_review coach has a page menu with dialogs and no Admin actions card" do
    sign_in
    coach = make_coach("Pending Pat", "pending_review", "+201000000040")
    get admin_coach_path(coach)
    assert_response :ok
    assert_select ".page-head .action-menu" do
      assert_select "button.action-item", text: "Approve"
      assert_select "button.action-item", text: "Request changes"
      assert_select "button.action-item", text: "Reject"
    end
    assert_select "dialog#action-#{coach.id}-approve input[name=commission]"
    assert_select "dialog#action-#{coach.id}-reject textarea[name=reason]"
    assert_select "h2", text: "Admin actions", count: 0
    assert_not_includes @response.body, "Reactivate"
  end

  test "show for approved coach menu offers Suspend and Deactivate but not Approve" do
    sign_in
    coach = make_coach("Active Coach", "approved", "+201000000041")
    get admin_coach_path(coach)
    assert_response :ok
    assert_select ".page-head .action-menu button.action-item", text: "Suspend"
    assert_select ".page-head .action-menu button.action-item", text: "Deactivate"
    assert_select "dialog#action-#{coach.id}-deactivate", text: /This cannot be undone/
    assert_not_includes @response.body, admin_approve_coach_path(coach)
    assert_not_includes @response.body, "Reactivate"
  end

  test "show for rejected coach menu says no actions" do
    sign_in
    coach = make_coach("Rejected Ray", "rejected", "+201000000042")
    get admin_coach_path(coach)
    assert_select ".page-head .action-menu", text: /No actions for this status/
  end

  test "dialog fields have labels associated with inputs" do
    sign_in
    coach = make_coach("Pending Pat", "pending_review", "+201000000043")
    get admin_coach_path(coach)
    assert_select "label[for=action-#{coach.id}-approve-field]"
    assert_select "input#action-#{coach.id}-approve-field"
    assert_select "label[for=action-#{coach.id}-reject-field]"
    assert_select "textarea#action-#{coach.id}-reject-field"
  end

  test "index rows each get their own menu with the full path as return_to" do
    sign_in
    a = make_coach("Approved Amy", "approved", "+201000000044")
    b = make_coach("Approved Bob", "approved", "+201000000045")
    r = make_coach("Rejected Ray", "rejected", "+201000000046")
    get admin_root_path(status: "approved", q: "Approved")
    assert_response :ok
    assert_select "tbody tr .action-menu", count: 2
    assert_select "dialog#action-#{a.id}-suspend"
    assert_select "dialog#action-#{b.id}-suspend"
    assert_select "dialog#action-#{a.id}-suspend input[name=return_to][value=?]", request.fullpath
    assert_includes request.fullpath, "status=approved"
    assert_includes request.fullpath, "q=Approved"

    get admin_root_path
    assert_select "tr", text: /Rejected Ray/ do
      assert_select ".action-menu", count: 0
    end
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

  # ---------------------------------------------------------------------------
  # Profile + Clients tabs
  # ---------------------------------------------------------------------------

  test "coach show defaults to the profile tab" do
    sign_in
    coach = make_coach("Approved Amy", "approved", "+201000000070")
    get admin_coach_path(coach)
    assert_response :ok
    assert_includes @response.body, "Application"
  end

  test "clients tab lists only active clients by default, each name linked" do
    sign_in
    coach = make_coach("Approved Amy", "approved", "+201000000071")
    live = make_client("Live Lara"); sub(coach, live, status: "active")
    ended = make_client("Ended Ed"); sub(coach, ended, status: "ended")

    get admin_coach_path(coach, tab: "clients")
    assert_response :ok
    assert_includes @response.body, "Live Lara"
    assert_includes @response.body, admin_client_path(live)
    assert_not_includes @response.body, "Ended Ed"
  end

  test "clients tab filter=all shows every client" do
    sign_in
    coach = make_coach("Approved Amy", "approved", "+201000000072")
    live = make_client("Live Lara"); sub(coach, live, status: "active")
    ended = make_client("Ended Ed"); sub(coach, ended, status: "ended")

    get admin_coach_path(coach, tab: "clients", filter: "all")
    assert_response :ok
    assert_includes @response.body, "Live Lara"
    assert_includes @response.body, "Ended Ed"
  end

  test "clients tab empty state for a coach with no clients" do
    sign_in
    coach = make_coach("Approved Amy", "approved", "+201000000073")
    get admin_coach_path(coach, tab: "clients")
    assert_response :ok
    assert_includes @response.body, "No active clients"
  end

  test "unknown tab falls back to profile" do
    sign_in
    coach = make_coach("Approved Amy", "approved", "+201000000074")
    get admin_coach_path(coach, tab: "bogus")
    assert_response :ok
    assert_includes @response.body, "Application"
  end

  test "out-of-range page does not error" do
    sign_in
    coach = make_coach("Approved Amy", "approved", "+201000000075")
    sub(coach, make_client("Live Lara"), status: "active")
    get admin_coach_path(coach, tab: "clients", page: "999")
    assert_response :ok
  end

  test "action follows a safe return_to" do
    sign_in
    coach = make_coach("Amy", "approved", "+201000000091")
    post admin_suspend_coach_path(coach), params: { reason: "x", return_to: "/admin?status=approved" }
    assert_redirected_to "/admin?status=approved"
  end

  test "action ignores an unsafe return_to" do
    sign_in
    coach = make_coach("Amy", "approved", "+201000000092")
    post admin_suspend_coach_path(coach), params: { reason: "x", return_to: "https://evil.example/x" }
    assert_redirected_to admin_coach_path(coach)
    coach2 = make_coach("Bo", "approved", "+201000000093")
    post admin_suspend_coach_path(coach2), params: { reason: "x", return_to: "//evil.example" }
    assert_redirected_to admin_coach_path(coach2)
  end

  test "failed action flashes alert and returns to return_to" do
    sign_in
    coach = make_coach("Pat", "pending_review", "+201000000094")
    post admin_approve_coach_path(coach), params: { commission: "", return_to: "/admin" }
    assert_redirected_to "/admin"
    assert flash[:alert].present?
  end
end
