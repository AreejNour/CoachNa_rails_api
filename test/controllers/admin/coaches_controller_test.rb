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
end
