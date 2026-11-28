require "test_helper"

class AdminHelperTest < ActionView::TestCase
  include AdminHelper

  def coach(status) = Coach.new(id: SecureRandom.uuid, status: status)
  def client(status) = Client.new(id: SecureRandom.uuid, status: status)

  test "coach_actions for pending_review" do
    a = coach_actions(coach("pending_review"))
    assert_equal %i[approve request_changes reject], a.map { |x| x[:key] }
    assert_equal %i[commission reason reason], a.map { |x| x[:input] }
  end

  test "coach_actions for approved, suspended, rejected" do
    assert_equal %i[suspend deactivate], coach_actions(coach("approved")).map { |x| x[:key] }
    assert_equal %i[reactivate deactivate], coach_actions(coach("suspended")).map { |x| x[:key] }
    assert_equal [], coach_actions(coach("rejected"))
  end

  test "coach_actions offers a set-password email only for approved or suspended coaches with an email" do
    with_email = Coach.new(id: SecureRandom.uuid, status: "approved", email: "a@example.com")
    item = coach_actions(with_email).find { |x| x[:key] == :send_password_email }
    assert_equal "Send set-password email", item[:label]
    assert_nil item[:input]
    assert_includes coach_actions(Coach.new(id: SecureRandom.uuid, status: "suspended", email: "a@example.com")).map { |x| x[:key] }, :send_password_email
    assert_not_includes coach_actions(coach("approved")).map { |x| x[:key] }, :send_password_email
    assert_not_includes coach_actions(Coach.new(id: SecureRandom.uuid, status: "rejected", email: "a@example.com")).map { |x| x[:key] }, :send_password_email
  end

  test "coach deactivate is danger" do
    d = coach_actions(coach("approved")).find { |x| x[:key] == :deactivate }
    assert d[:danger]
    assert_not coach_actions(coach("approved")).first[:danger]
  end

  test "client_actions" do
    a = client_actions(client("active"))
    assert_equal %i[suspend deactivate], a.map { |x| x[:key] }
    assert_equal [ nil, nil ], a.map { |x| x[:input] }
    assert a.last[:confirm].present?
    assert_equal %i[reactivate deactivate], client_actions(client("suspended")).map { |x| x[:key] }
    assert_equal [], client_actions(client("deactivated"))
  end

  test "action_menu partial renders items, dialogs and empty states" do
    c = coach("pending_review")
    html = render(partial: "admin/shared/action_menu",
                  locals: { actions: coach_actions(c), record_id: c.id, return_to: "/admin?x=1", trigger: :button })
    assert_includes html, "Actions ▾"
    assert_includes html, %(id="action-#{c.id}-approve")
    assert_includes html, %(name="commission")
    assert_includes html, %(value="/admin?x=1")

    d = coach("approved")
    html = render(partial: "admin/shared/action_menu",
                  locals: { actions: coach_actions(d), record_id: d.id, return_to: "/admin", trigger: :dots })
    assert_includes html, "This cannot be undone."
    assert_includes html, "btn danger"

    empty = coach("rejected")
    html = render(partial: "admin/shared/action_menu",
                  locals: { actions: [], record_id: empty.id, return_to: "/admin", trigger: :button })
    assert_includes html, "No actions for this status"
    assert_equal "", render(partial: "admin/shared/action_menu",
                  locals: { actions: [], record_id: "x", return_to: "/admin", trigger: :dots }).strip
  end
end
