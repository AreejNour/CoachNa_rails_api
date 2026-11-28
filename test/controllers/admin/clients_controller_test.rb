require "test_helper"

class Admin::ClientsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @admin = AdminUser.create!(email: "team@coachna.app", name: "Team", password: "Secret123")
  end

  def sign_in
    post "/admin/login", params: { email: "team@coachna.app", password: "Secret123" }
  end

  def make_client(name, status, phone, email: nil)
    Client.create!(full_name: name, phone: phone, email: email, password_hash: "h", status: status)
  end

  # ---------------------------------------------------------------------------
  # Index: list, filter, search
  # ---------------------------------------------------------------------------

  test "index lists clients of every status by default" do
    sign_in
    make_client("Active Ann", "active", "+201000000301")
    make_client("Suspended Sue", "suspended", "+201000000302")
    make_client("Deactivated Dan", "deactivated", "+201000000303")

    get "/admin/clients"
    assert_response :ok
    assert_includes @response.body, "Active Ann"
    assert_includes @response.body, "Suspended Sue"
    assert_includes @response.body, "Deactivated Dan"
  end

  test "index filters by status param" do
    sign_in
    make_client("Active Ann", "active", "+201000000301")
    make_client("Suspended Sue", "suspended", "+201000000302")

    get "/admin/clients", params: { status: "suspended" }
    assert_response :ok
    assert_includes @response.body, "Suspended Sue"
    assert_not_includes @response.body, "Active Ann"
  end

  test "index searches by name, phone, and email" do
    sign_in
    make_client("Active Ann", "active", "+201000000301", email: "ann@example.com")
    make_client("Other Guy", "active", "+201000000399", email: "guy@example.com")

    get "/admin/clients", params: { q: "ann@example" }
    assert_response :ok
    assert_includes @response.body, "Active Ann"
    assert_not_includes @response.body, "Other Guy"
  end

  test "index escapes ILIKE wildcards in the search term" do
    sign_in
    make_client("Plain Pat", "active", "+201000000301")

    # A bare "%" must match literally (no client has it), so the plain client is excluded.
    get "/admin/clients", params: { q: "%" }
    assert_response :ok
    assert_not_includes @response.body, "Plain Pat"
  end

  test "index redirects to login when not signed in" do
    get "/admin/clients"
    assert_redirected_to "/admin/login"
  end

  # ---------------------------------------------------------------------------
  # Show: identity + health profile + subscriptions
  # ---------------------------------------------------------------------------

  def make_subscription_for(client)
    coach = Coach.create!(full_name: "Mona Coach", phone: "+201000000401", password_hash: "h", status: "approved")
    pkg = CoachPackage.create!(coach: coach, name: "Gold Plan", price_piastres: 50_000, duration_days: 30, includes: {})
    Subscription.create!(client: client, coach: coach, package_id: pkg.id, status: "active",
                         price_piastres: 50_000, commission_percent: 10, commission_piastres: 5_000,
                         starts_at: Time.current, ends_at: 30.days.from_now)
  end

  test "show renders identity, health profile, and subscriptions" do
    sign_in
    client = make_client("Active Ann", "active", "+201000000301", email: "ann@example.com")
    ClientHealthProfile.create!(client_id: client.id, date_of_birth: Date.new(1990, 5, 1),
                                gender: "female", weight_kg: 68.5, goal: "weight_loss")
    make_subscription_for(client)

    get admin_client_path(client)
    assert_response :ok
    assert_includes @response.body, "Active Ann"
    assert_includes @response.body, "weight_loss"
    assert_includes @response.body, "Mona Coach"
  end

  test "show renders a no-health-profile message when absent" do
    sign_in
    client = make_client("Active Ann", "active", "+201000000301")

    get admin_client_path(client)
    assert_response :ok
    assert_includes @response.body, "No health profile yet"
  end

  # ---------------------------------------------------------------------------
  # Status actions
  # ---------------------------------------------------------------------------

  test "suspend sets an active client to suspended and flashes a notice" do
    sign_in
    client = make_client("Active Ann", "active", "+201000000301")
    post admin_suspend_client_path(client)
    assert_redirected_to admin_client_path(client)
    follow_redirect!
    assert_includes @response.body, "Client suspended."
    assert_equal "suspended", client.reload.status
  end

  test "reactivate sets a suspended client to active" do
    sign_in
    client = make_client("Suspended Sue", "suspended", "+201000000302")
    post admin_reactivate_client_path(client)
    assert_redirected_to admin_client_path(client)
    assert_equal "active", client.reload.status
  end

  test "deactivate sets an active client to deactivated" do
    sign_in
    client = make_client("Active Ann", "active", "+201000000301")
    post admin_deactivate_client_path(client)
    assert_redirected_to admin_client_path(client)
    assert_equal "deactivated", client.reload.status
  end

  test "invalid transition flashes an alert and leaves status unchanged" do
    sign_in
    client = make_client("Deactivated Dan", "deactivated", "+201000000303")
    post admin_suspend_client_path(client)
    assert_redirected_to admin_client_path(client)
    follow_redirect!
    assert_includes @response.body, "Cannot perform this action"
    assert_equal "deactivated", client.reload.status
  end

  test "suspend without sign in redirects to login and changes nothing" do
    client = make_client("Active Ann", "active", "+201000000301")
    post admin_suspend_client_path(client)
    assert_redirected_to "/admin/login"
    assert_equal "active", client.reload.status
  end

  test "reactivate without sign in redirects to login and changes nothing" do
    client = make_client("Suspended Sue", "suspended", "+201000000302")
    post admin_reactivate_client_path(client)
    assert_redirected_to "/admin/login"
    assert_equal "suspended", client.reload.status
  end

  test "deactivate without sign in redirects to login and changes nothing" do
    client = make_client("Active Ann", "active", "+201000000301")
    post admin_deactivate_client_path(client)
    assert_redirected_to "/admin/login"
    assert_equal "active", client.reload.status
  end

  test "show for active client has a page menu with Suspend and Deactivate and no Admin actions card" do
    sign_in
    client = make_client("Active Ann", "active", "+201000000301")
    get admin_client_path(client)
    assert_response :ok
    assert_select ".page-head .action-menu button.action-item", text: "Suspend"
    assert_select ".page-head .action-menu button.action-item", text: "Deactivate"
    assert_select ".page-head .action-menu form[action=?][onsubmit*=confirm]", admin_deactivate_client_path(client)
    assert_includes @response.body, "This cannot be undone."
    assert_select "h2", text: "Admin actions", count: 0
    assert_not_includes @response.body, "Reactivate"
  end

  test "show page uses a single-column detail layout" do
    sign_in
    c = make_client("Solo Sol", "active", "+201000000361")
    get admin_client_path(c)
    assert_select ".detail.single"
  end

  test "show for suspended client menu offers Reactivate and Deactivate" do
    sign_in
    client = make_client("Suspended Sue", "suspended", "+201000000302")
    get admin_client_path(client)
    assert_select ".page-head .action-menu button.action-item", text: "Reactivate"
    assert_select ".page-head .action-menu button.action-item", text: "Deactivate"
  end

  test "show for deactivated client menu says no actions" do
    sign_in
    client = make_client("Deactivated Dan", "deactivated", "+201000000303")
    get admin_client_path(client)
    assert_select ".page-head .action-menu", text: /No actions for this status/
  end

  test "index rows get menus for active and suspended clients, none for deactivated" do
    sign_in
    a = make_client("Active Ann", "active", "+201000000311")
    s = make_client("Suspended Sue", "suspended", "+201000000312")
    make_client("Deactivated Dan", "deactivated", "+201000000313")
    get admin_clients_path(q: "a")
    assert_response :ok
    assert_includes request.fullpath, "q=a"
    assert_select "form[action=?] input[name=return_to][value=?]", admin_suspend_client_path(a), request.fullpath
    get admin_clients_path
    assert_select "tbody tr .action-menu", count: 2
    assert_select ".card.table-card"
    assert_select "tbody tr .action-dots[aria-label=?]", "Actions for Active Ann"
    assert_select "tbody tr .action-dots[aria-label=?]", "Actions for Suspended Sue"
    assert_select "form[action=?] input[name=return_to][value=?]", admin_suspend_client_path(a), request.fullpath
    assert_select "form[action=?]", admin_reactivate_client_path(s)
    assert_select "tr", text: /Deactivated Dan/ do
      assert_select ".action-menu", count: 0
    end
  end

  test "show hides checkout_open and replaced subscriptions" do
    sign_in
    client = make_client("Busy Bea", "active", "+201000000351")
    make = lambda do |coach_name, phone, status|
      coach = Coach.create!(full_name: coach_name, phone: phone, password_hash: "h", status: "approved")
      pkg = CoachPackage.create!(coach: coach, name: "Plan", price_piastres: 50_000, duration_days: 30, includes: {})
      Subscription.create!(client: client, coach: coach, package_id: pkg.id, status: status,
                           price_piastres: 50_000, commission_percent: 10, commission_piastres: 5_000,
                           starts_at: Time.current, ends_at: 30.days.from_now)
    end
    make.call("Ended Coach", "+201000000352", "ended")
    replaced = make.call("Replaced Coach", "+201000000353", "cancelled")
    Payment.create!(client_id: client.id, purpose: "subscription", subscription_id: replaced.id,
                    amount_piastres: 50_000, provider: "paymob", status: "failed", failure_reason: "replaced")
    make.call("Open Coach", "+201000000354", "checkout_open")

    get admin_client_path(client)
    assert_includes @response.body, "Ended Coach"
    assert_not_includes @response.body, "Replaced Coach"
    assert_not_includes @response.body, "Open Coach"
  end

  test "suspend follows a safe return_to" do
    sign_in
    client = make_client("Ann Active", "active", "+201000000391")
    post admin_suspend_client_path(client), params: { return_to: "/admin/clients?q=ann" }
    assert_redirected_to "/admin/clients?q=ann"
  end
end
