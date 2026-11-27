require "test_helper"

class Admin::PromoCodesControllerTest < ActionDispatch::IntegrationTest
  @@seq = 0

  WARNING = "CoachNa loses money on 1 package(s) with this code (worst case EGP 270.00)".freeze

  setup do
    @admin = AdminUser.create!(email: "team@coachna.app", name: "Team Lead", password: "Secret123")
    # One 20% coach with an EGP 900 package: a 50% code loses 45000 - 18000 = 27000 on it.
    @coach = Coach.create!(full_name: "Mona Coach", phone: uniq_phone, password_hash: "h",
                           status: "approved", commission_percent: 20)
    @pkg = CoachPackage.create!(coach: @coach, name: "Gold Plan", price_piastres: 90_000,
                                duration_days: 30, includes: {})
  end

  def sign_in
    post "/admin/login", params: { email: "team@coachna.app", password: "Secret123" }
  end

  def uniq_phone
    @@seq += 1
    format("+20124%07d", @@seq)
  end

  def make_code(attrs = {})
    PromoCode.create!({ code: "SUMMER50", kind: "percent", value: 50, funded_by: "platform",
                        created_by_admin_id: @admin.id }.merge(attrs))
  end

  def form_params(attrs = {})
    { promo_code: { code: "summer50", kind: "percent", value: "50", active: "1" }.merge(attrs) }
  end

  # ---------------------------------------------------------------------------
  # Auth
  # ---------------------------------------------------------------------------

  test "every page requires sign-in" do
    code = make_code
    get admin_promo_codes_path
    assert_redirected_to "/admin/login"
    get new_admin_promo_code_path
    assert_redirected_to "/admin/login"
    get admin_promo_code_path(code)
    assert_redirected_to "/admin/login"
    get edit_admin_promo_code_path(code)
    assert_redirected_to "/admin/login"
    post admin_promo_codes_path, params: form_params(code: "OTHER")
    assert_redirected_to "/admin/login"
    patch admin_promo_code_path(code), params: form_params(value: "10")
    assert_redirected_to "/admin/login"
    post deactivate_admin_promo_code_path(code)
    assert_redirected_to "/admin/login"
    assert_equal 1, PromoCode.count
    assert code.reload.active
  end

  # ---------------------------------------------------------------------------
  # List
  # ---------------------------------------------------------------------------

  test "index lists codes with kind, value, uses and creator" do
    sign_in
    code = make_code(max_uses: 100)
    client = Client.create!(full_name: "Payer", phone: uniq_phone, password_hash: "h")
    sub = Subscription.create!(client: client, coach: @coach, package_id: @pkg.id, status: "active",
                               price_piastres: 90_000, commission_percent: 20, commission_piastres: -27_000,
                               discount_piastres: 45_000, promo_code_id: code.id,
                               starts_at: Time.current, ends_at: 30.days.from_now)
    Payment.create!(client_id: client.id, purpose: "subscription", subscription_id: sub.id,
                    amount_piastres: 45_000, provider: "simulated", status: "paid", paid_at: Time.current)

    get admin_promo_codes_path
    assert_response :ok
    assert_includes @response.body, "SUMMER50"
    assert_includes @response.body, "50%"
    assert_includes @response.body, "1 / 100"
    assert_includes @response.body, "Team Lead"
    assert_includes @response.body, "Promo codes"
  end

  test "index filters by active, inactive and expired" do
    sign_in
    make_code(code: "LIVECODE")
    make_code(code: "OFFCODE", active: false)
    make_code(code: "OLDCODE", starts_at: 10.days.ago, ends_at: 1.day.ago)

    get admin_promo_codes_path(filter: "expired")
    assert_includes @response.body, "OLDCODE"
    assert_not_includes @response.body, "LIVECODE"
    assert_not_includes @response.body, "OFFCODE"

    get admin_promo_codes_path(filter: "inactive")
    assert_includes @response.body, "OFFCODE"
    assert_not_includes @response.body, "LIVECODE"

    get admin_promo_codes_path(filter: "active")
    assert_includes @response.body, "LIVECODE"
    assert_not_includes @response.body, "OLDCODE"
  end

  test "the sidebar links to promo codes" do
    sign_in
    get admin_root_path
    assert_includes @response.body, admin_promo_codes_path
  end

  # ---------------------------------------------------------------------------
  # Create
  # ---------------------------------------------------------------------------

  test "new renders the form" do
    sign_in
    get new_admin_promo_code_path
    assert_response :ok
    assert_includes @response.body, "New promo code"
    assert_includes @response.body, "Gold Plan"
  end

  test "create saves an upcased, platform-funded code owned by the signed-in admin" do
    sign_in
    assert_difference -> { PromoCode.count }, 1 do
      post admin_promo_codes_path, params: form_params(funded_by: "coach")
    end
    code = PromoCode.last
    assert_redirected_to admin_promo_code_path(code)
    assert_equal "SUMMER50", code.code
    assert_equal "platform", code.funded_by
    assert_equal @admin.id, code.created_by_admin_id
    assert code.active
  end

  test "form dates are Cairo time" do
    sign_in
    post admin_promo_codes_path, params: form_params(starts_at: "2026-12-01T00:00", ends_at: "2026-12-31T23:59")
    code = PromoCode.find_by!(code: "SUMMER50")
    assert_equal Time.utc(2026, 11, 30, 22, 0), code.starts_at
    assert_equal Time.utc(2026, 12, 31, 21, 59), code.ends_at

    get edit_admin_promo_code_path(code)
    assert_includes @response.body, 'value="2026-12-01T00:00"'
    assert_includes @response.body, "(Cairo time)"
  end

  test "create converts EGP money fields to piastres" do
    sign_in
    post admin_promo_codes_path, params: form_params(code: "FLAT", kind: "fixed", value: "100",
                                                    min_price_egp: "500")
    code = PromoCode.find_by!(code: "FLAT")
    assert_equal 10_000, code.value
    assert_equal 50_000, code.min_price_piastres

    post admin_promo_codes_path, params: form_params(code: "CAPPED", value: "30", max_discount_egp: "200")
    assert_equal 20_000, PromoCode.find_by!(code: "CAPPED").max_discount_piastres
  end

  test "create saves restrictions and the allow-list" do
    sign_in
    a = Client.create!(full_name: "Allowed Ann", phone: uniq_phone, password_hash: "h")
    post admin_promo_codes_path, params: form_params(
      restrict_coach_id: @coach.id, restrict_package_id: @pkg.id, min_duration_days: "30",
      max_duration_days: "90", max_uses: "5", new_patients_only: "1", client_ids: [ a.id ],
    )
    code = PromoCode.find_by!(code: "SUMMER50")
    assert_equal @coach.id, code.restrict_coach_id
    assert_equal @pkg.id, code.restrict_package_id
    assert_equal 30, code.min_duration_days
    assert_equal 90, code.max_duration_days
    assert_equal 5, code.max_uses
    assert code.new_patients_only
    assert_equal [ a.id ], code.promo_code_clients.pluck(:client_id)
  end

  test "create re-renders with errors when invalid" do
    sign_in
    assert_no_difference -> { PromoCode.count } do
      post admin_promo_codes_path, params: form_params(code: "x!", value: "150")
    end
    assert_response :unprocessable_entity
    assert_includes @response.body, "New promo code"
  end

  test "saving a code that can lose money shows the warning" do
    sign_in
    post admin_promo_codes_path, params: form_params
    follow_redirect!
    assert_includes @response.body, WARNING
  end

  test "no warning when the code cannot lose money" do
    sign_in
    post admin_promo_codes_path, params: form_params(value: "10")
    follow_redirect!
    assert_not_includes @response.body, "CoachNa loses money"
  end

  test "preview shows the warning without saving" do
    sign_in
    assert_no_difference -> { PromoCode.count } do
      post admin_promo_codes_path, params: form_params.merge(preview: "1")
    end
    assert_response :ok
    assert_includes @response.body, WARNING
  end

  test "searching clients in the form lists matches by name or phone without saving" do
    sign_in
    Client.create!(full_name: "Layla Hassan", phone: "+201119998877", password_hash: "h")
    Client.create!(full_name: "Omar Said", phone: uniq_phone, password_hash: "h")

    assert_no_difference -> { PromoCode.count } do
      post admin_promo_codes_path, params: form_params(client_q: "Layla").merge(search_clients: "1")
    end
    assert_response :ok
    assert_includes @response.body, "Layla Hassan"
    assert_not_includes @response.body, "Omar Said"

    post admin_promo_codes_path, params: form_params(client_q: "9998877").merge(search_clients: "1")
    assert_includes @response.body, "Layla Hassan"
  end

  # ---------------------------------------------------------------------------
  # Show / edit / update / deactivate
  # ---------------------------------------------------------------------------

  test "show renders the code" do
    sign_in
    code = make_code(value: 10)
    get admin_promo_code_path(code)
    assert_response :ok
    assert_includes @response.body, "SUMMER50"
    assert_includes @response.body, "Team Lead"
  end

  test "edit and update change the rules but never the code text" do
    sign_in
    code = make_code(value: 10)
    get edit_admin_promo_code_path(code)
    assert_response :ok
    assert_includes @response.body, "SUMMER50"
    assert_not_includes @response.body, 'name="promo_code[code]"'

    patch admin_promo_code_path(code), params: form_params(value: "15", code: "RENAMED")
    assert_redirected_to admin_promo_code_path(code)
    code.reload
    assert_equal 15, code.value
    assert_equal "SUMMER50", code.code
    assert_equal @admin.id, code.created_by_admin_id
  end

  test "update replaces the allow-list" do
    sign_in
    code = make_code(value: 10)
    a = Client.create!(full_name: "Ann", phone: uniq_phone, password_hash: "h")
    b = Client.create!(full_name: "Bob", phone: uniq_phone, password_hash: "h")
    code.promo_code_clients.create!(client_id: a.id)

    patch admin_promo_code_path(code), params: form_params(value: "10", client_ids: [ b.id ])
    assert_equal [ b.id ], code.reload.promo_code_clients.pluck(:client_id)
  end

  test "preview on edit does not save" do
    sign_in
    code = make_code(value: 10)
    a = Client.create!(full_name: "Ann", phone: uniq_phone, password_hash: "h")

    patch admin_promo_code_path(code), params: form_params(value: "50", client_ids: [ a.id ]).merge(preview: "1")
    assert_response :ok
    assert_includes @response.body, WARNING
    assert_equal 10, code.reload.value
    assert_empty code.promo_code_clients
  end

  test "update with errors re-renders the form" do
    sign_in
    code = make_code(value: 10)
    patch admin_promo_code_path(code), params: form_params(value: "120")
    assert_response :unprocessable_entity
    assert_equal 10, code.reload.value
  end

  test "deactivate switches the code off and keeps it" do
    sign_in
    code = make_code
    post deactivate_admin_promo_code_path(code)
    assert_redirected_to admin_promo_code_path(code)
    assert_not code.reload.active
    assert PromoCode.exists?(code.id)
  end

  test "deactivate works even when the code no longer passes today's rules" do
    sign_in
    code = make_code(kind: "fixed", value: 80_000)
    @pkg.update!(price_piastres: 50_000) # 80000 is now above the 49000 maximum
    post deactivate_admin_promo_code_path(code)
    assert_not code.reload.active
  end

  test "editing keeps a restriction to an inactive package and a non-approved coach" do
    sign_in
    @coach.update!(status: "suspended")
    @pkg.update!(is_active: false)
    code = make_code(value: 10, restrict_coach_id: @coach.id, restrict_package_id: @pkg.id)

    get edit_admin_promo_code_path(code)
    assert_response :ok
    assert_match(/<option value="#{@coach.id}" selected>Mona Coach \(suspended\)/, @response.body)
    assert_match(/<option value="#{@pkg.id}" data-coach-id="#{@coach.id}" selected>.*Gold Plan.*\(inactive\)/m, @response.body)

    # The browser posts back what the form selected.
    patch admin_promo_code_path(code), params: form_params(value: "15", restrict_coach_id: @coach.id,
                                                          restrict_package_id: @pkg.id)
    assert_redirected_to admin_promo_code_path(code)
    code.reload
    assert_equal 15, code.value
    assert_equal @coach.id, code.restrict_coach_id
    assert_equal @pkg.id, code.restrict_package_id
  end

  test "an unknown coach or package id is a form error, not a crash" do
    sign_in
    assert_no_difference -> { PromoCode.count } do
      post admin_promo_codes_path, params: form_params(restrict_coach_id: SecureRandom.uuid)
    end
    assert_response :unprocessable_entity

    assert_no_difference -> { PromoCode.count } do
      post admin_promo_codes_path, params: form_params(restrict_package_id: SecureRandom.uuid)
    end
    assert_response :unprocessable_entity
  end

  test "unknown client ids in the allow-list are dropped" do
    sign_in
    a = Client.create!(full_name: "Real Ann", phone: uniq_phone, password_hash: "h")
    post admin_promo_codes_path, params: form_params(client_ids: [ a.id, SecureRandom.uuid ])
    code = PromoCode.find_by!(code: "SUMMER50")
    assert_redirected_to admin_promo_code_path(code)
    assert_equal [ a.id ], code.promo_code_clients.pluck(:client_id)
  end

  test "create saves uses per patient, or none when blank" do
    sign_in
    post admin_promo_codes_path, params: form_params(code: "THREE", max_uses_per_client: "3")
    assert_equal 3, PromoCode.find_by!(code: "THREE").max_uses_per_client
    post admin_promo_codes_path, params: form_params(code: "NOLIMIT", max_uses_per_client: "")
    assert_nil PromoCode.find_by!(code: "NOLIMIT").max_uses_per_client
  end

  test "new and edit show the uses per patient value" do
    sign_in
    get new_admin_promo_code_path
    assert_select "input[name='promo_code[max_uses_per_client]'][value='1']"
    code = make_code
    get edit_admin_promo_code_path(code)
    assert_select "input[name='promo_code[max_uses_per_client]'][value='1']"
    code.update!(max_uses_per_client: nil)
    get edit_admin_promo_code_path(code)
    assert_select "input[name='promo_code[max_uses_per_client]'][value='']"
  end

  test "package options carry their coach id for the coach filter" do
    sign_in
    get new_admin_promo_code_path
    assert_select "select#promo_code_restrict_package_id option[value='#{@pkg.id}'][data-coach-id='#{@coach.id}']"
  end

  test "index and show display the per-patient limit" do
    sign_in
    one = make_code
    none = make_code(code: "FREEFORALL", max_uses_per_client: nil)
    get admin_promo_codes_path
    assert_select "th", text: "Per patient"
    assert_select "tr", text: /SUMMER50.*\b1\b/m
    assert_select "tr", text: /FREEFORALL.*∞/m
    get admin_promo_code_path(none)
    assert_select ".field", text: /Uses per patient\s*∞/
    get admin_promo_code_path(one)
    assert_select ".field", text: /Uses per patient\s*1/
  end

  test "there is no delete" do
    sign_in
    code = make_code
    delete admin_promo_code_path(code)
    assert PromoCode.exists?(code.id)
  end
end
