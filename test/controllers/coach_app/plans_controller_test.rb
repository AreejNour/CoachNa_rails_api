require "test_helper"

class CoachApp::PlansControllerTest < ActionDispatch::IntegrationTest
  setup do
    @coach = Coach.create!(phone: "+201012348001", password_hash: "h", full_name: "Coach Mona")
    @client = Client.create!(phone: "+201012348101", password_hash: "h", full_name: "Client")
    @package = @coach.coach_packages.create!(name: "P", price_piastres: 50_000, duration_days: 30, includes: [ "x" ])
    @rice = Food.create!(name_ar: "أرز", name_en: "Rice", group: "carb", protein_per_100: 2.7,
                         carbs_per_100: 28, fat_per_100: 0.3, weight_basis: "cooked")
    @sub = make_sub("awaiting_plan")
  end

  # Each subscription gets its own client: a client may have only one current subscription.
  def make_sub(status, client: @client)
    now = Time.current
    Subscription.create!(client_id: client.id, coach_id: @coach.id, package_id: @package.id,
                         status: status, price_piastres: 50_000, commission_percent: 10,
                         commission_piastres: 5000, starts_at: now, ends_at: now + 30.days)
  end

  def another_client
    @client_seq = (@client_seq || 0) + 1
    Client.create!(phone: format("+2010123482%02d", @client_seq), password_hash: "h", full_name: "C#{@client_seq}")
  end

  def auth = { "Authorization" => "Bearer #{CoachApp::AccessToken.sign(@coach.id)}" }
  def data = response.parsed_body["data"]

  def plan_body(over = {})
    {
      notes: "Drink water.",
      options: [
        {
          label: "Day 1",
          meals: [
            { slot: "breakfast", position: 1, title: "Oats",
              components: [ { foodId: @rice.id, quantity: 80, unit: "g" }, { freeText: "coffee" } ] },
            { slot: "lunch", position: 1, title: "Lunch",
              components: [ { foodId: @rice.id, quantity: 150, unit: "g", preparation: "boiled" } ] }
          ]
        }
      ]
    }.merge(over)
  end

  def publish(sub = @sub, over = {})
    post "/coach/subscriptions/#{sub.id}/plan/publish", params: plan_body(over), headers: auth, as: :json
  end

  test "every route needs a token" do
    get "/coach/subscriptions/#{@sub.id}/plan"
    assert_response :unauthorized
    post "/coach/subscriptions/#{@sub.id}/plan/publish", params: plan_body, as: :json
    assert_response :unauthorized
  end

  test "publish creates version 1, moves the subscription to active and writes a plan_ready notification" do
    publish
    assert_response :ok
    assert_equal 1, data["plan"]["version"]
    assert_equal "published", data["plan"]["status"]
    assert_equal "active", @sub.reload.status

    plan = Plan.find(data["plan"]["id"])
    assert_equal 1, plan.plan_options.count
    meals = plan.plan_options.first.plan_meals.order(:slot)
    assert_equal %w[breakfast lunch], meals.pluck(:slot).sort
    breakfast = meals.find { |m| m.slot == "breakfast" }
    comps = breakfast.plan_meal_components.order(:position)
    assert_equal [ @rice.id, nil ], comps.map(&:food_id)
    assert_equal [ nil, "coffee" ], comps.map(&:free_text)

    note = Notification.find_by(recipient_type: "client", recipient_id: @client.id, type: "plan_ready")
    assert note
    assert_equal "خطتك جاهزة", note.title
    assert_equal({ "subscriptionId" => @sub.id, "planId" => plan.id }, note.data)
  end

  test "publish enqueues one plan push for the client, published after commit" do
    CoachApp::QueuePublisher.adapter = CoachApp::QueuePublisher::TestAdapter.new
    publish

    rows = OutboxMessage.where(kind: "push")
    assert_equal 1, rows.count
    assert_equal(
      { "recipient" => { "type" => "client", "id" => @client.id },
        "title" => { "ar" => "خطتك جاهزة", "en" => "Your plan is ready" },
        "body" => { "ar" => "نشر #{@coach.full_name} خطتك. افتحها لترى وجبات اليوم.",
                    "en" => "#{@coach.full_name} published your plan. Open it to see today's meals." },
        "data" => { "screen" => "plan" } },
      rows.first.payload,
    )
    assert_equal 1, CoachApp::QueuePublisher.adapter.published.size
  ensure
    CoachApp::QueuePublisher.adapter = nil
  end

  test "a second publish pushes the updated title" do
    publish
    publish(@sub, notes: "v2")

    titles = OutboxMessage.where(kind: "push").order(:created_at).map { |r| r.payload["title"]["en"] }
    assert_equal [ "Your plan is ready", "Your plan was updated" ], titles
  end

  test "a failure writing the notification leaves no push row" do
    swap_method(Notification, :create!, ->(*) { raise "boom" }) do
      publish
    end
    assert_equal 0, OutboxMessage.count
  end

  test "a second publish replaces the first (version 2) and the notification says updated" do
    publish
    first_id = data["plan"]["id"]
    publish(@sub, notes: "v2")
    assert_response :ok
    assert_equal 2, data["plan"]["version"]
    assert_equal "replaced", Plan.find(first_id).status
    assert_equal 1, Plan.where(subscription_id: @sub.id, status: "published").count
    assert_equal "تم تحديث خطتك",
                 Notification.where(recipient_id: @client.id, type: "plan_ready").order(:created_at).last.title
  end

  test "save draft upserts a single hidden draft and show returns it" do
    put "/coach/subscriptions/#{@sub.id}/plan/draft", params: plan_body, headers: auth, as: :json
    assert_response :ok
    assert_equal "draft", data["plan"]["status"]
    put "/coach/subscriptions/#{@sub.id}/plan/draft", params: plan_body(notes: "edited"), headers: auth, as: :json
    assert_equal 1, Plan.where(subscription_id: @sub.id, status: "draft").count

    get "/coach/subscriptions/#{@sub.id}/plan", headers: auth
    assert_equal "edited", data["plan"]["notes"]
    assert_equal "draft", data["plan"]["status"]
    # The client sees nothing until publish: no published plan, no notification.
    assert_equal 0, Plan.where(subscription_id: @sub.id, status: "published").count
    assert_nil Notification.find_by(recipient_id: @client.id, type: "plan_ready")
  end

  test "409 when the subscription is not ready or expired" do
    early = make_sub("awaiting_questionnaire", client: another_client)
    post "/coach/subscriptions/#{early.id}/plan/publish", params: plan_body, headers: auth, as: :json
    assert_response :conflict

    late = make_sub("awaiting_plan", client: another_client)
    late.update!(ends_at: 1.second.ago)
    post "/coach/subscriptions/#{late.id}/plan/publish", params: plan_body, headers: auth, as: :json
    assert_response :conflict
    assert_equal 0, Plan.where(subscription_id: late.id).count
  end

  test "400 for a foreign food, a bad unit, and a malformed component" do
    other = Coach.create!(phone: "+201012348777", password_hash: "h", full_name: "O")
    foreign = other.foods.create!(name_ar: "x", name_en: "x", group: "carb", protein_per_100: 1,
                                  carbs_per_100: 1, fat_per_100: 1, weight_basis: "cooked", is_active: true)
    publish(@sub, options: [ { label: "D", meals: [ { slot: "lunch", position: 1, title: "x",
      components: [ { foodId: foreign.id, quantity: 100, unit: "g" } ] } ] } ])
    assert_response :bad_request

    publish(@sub, options: [ { label: "D", meals: [ { slot: "lunch", position: 1, title: "x",
      components: [ { foodId: @rice.id, quantity: 100, unit: "piece" } ] } ] } ])
    assert_response :bad_request

    publish(@sub, options: [ { label: "D", meals: [ { slot: "lunch", position: 1, title: "x",
      components: [ {} ] } ] } ])
    assert_response :bad_request
    assert_equal 0, Plan.where(subscription_id: @sub.id).count
  end

  test "another coach's subscription is 404" do
    other = Coach.create!(phone: "+201012348888", password_hash: "h", full_name: "O")
    token = { "Authorization" => "Bearer #{CoachApp::AccessToken.sign(other.id)}" }
    post "/coach/subscriptions/#{@sub.id}/plan/publish", params: plan_body, headers: token, as: :json
    assert_response :not_found
  end

  def kinds_body(extra = {})
    plan_body(options: [ { label: "D", meals: [
      { slot: nil, position: 1, title: "Meal 1", components: [
        { kind: "food", foodId: @rice.id, quantity: 80, unit: "g", importFlag: extra[:flag] },
        { kind: "macro", macro: "protein", macroGrams: 30 },
        { kind: "portion", portionGroup: "carb", portionCount: 2 },
        { kind: "portion", portionGroup: "vegetable", portionCount: 1 },
        { kind: "text", freeText: "tea" }
      ] }
    ] } ])
  end

  def comps(plan_id)
    Plan.find(plan_id).plan_options.first.plan_meals.first.plan_meal_components.order(:position)
  end

  test "draft with every kind round-trips with exact wire fields and a null slot" do
    put "/coach/subscriptions/#{@sub.id}/plan/draft", params: kinds_body, headers: auth, as: :json
    assert_response :ok
    get "/coach/subscriptions/#{@sub.id}/plan", headers: auth
    meal = data["plan"]["options"][0]["meals"][0]
    assert_nil meal["slot"]
    c = meal["components"]
    assert_equal %w[food macro portion portion text], c.map { |x| x["kind"] }
    assert_equal %w[id position kind food quantity unit preparation macro macroGrams portionGroup portionCount freeText importFlag].sort,
                 c[0].keys.sort
    assert_equal [ "protein", 30.0 ], [ c[1]["macro"], c[1]["macroGrams"] ]
    assert_equal [ "carb", 2.0, nil ], [ c[2]["portionGroup"], c[2]["portionCount"], c[2]["macroGrams"] ]
    assert_equal "tea", c[4]["freeText"]
  end

  test "a component without kind is inferred" do
    put "/coach/subscriptions/#{@sub.id}/plan/draft", params: plan_body, headers: auth, as: :json
    assert_response :ok
    kinds = data["plan"]["options"][0]["meals"].flat_map { |m| m["components"].map { |x| x["kind"] } }
    assert_equal %w[food food text], kinds.sort
  end

  test "draft keeps importFlag" do
    put "/coach/subscriptions/#{@sub.id}/plan/draft", params: kinds_body(flag: "check qty"), headers: auth, as: :json
    assert_response :ok
    assert_equal "check qty", data["plan"]["options"][0]["meals"][0]["components"][0]["importFlag"]
  end

  test "publish with a flagged line is 409 and writes nothing" do
    assert_no_difference "Plan.count" do
      post "/coach/subscriptions/#{@sub.id}/plan/publish", params: kinds_body(flag: "?"), headers: auth, as: :json
    end
    assert_response :conflict
    assert_equal "plan has unchecked lines", response.parsed_body["error"]
    assert_equal "awaiting_plan", @sub.reload.status
  end

  test "publish snapshots portion grams from standard and from coach sizes" do
    post "/coach/subscriptions/#{@sub.id}/plan/publish", params: kinds_body, headers: auth, as: :json
    assert_response :ok
    c = comps(data["plan"]["id"])
    assert_equal 60, c[2].macro_grams.to_i
    assert_nil c[3].macro_grams
    assert_equal 30, c[1].macro_grams.to_i

    CoachPortionSize.create!(coach_id: @coach.id, group: "carb", grams_of_macro: 25)
    post "/coach/subscriptions/#{@sub.id}/plan/publish", params: kinds_body, headers: auth, as: :json
    assert_response :ok
    assert_equal 50, comps(data["plan"]["id"])[2].macro_grams.to_i
  end

  test "draft leaves portion macro_grams null" do
    put "/coach/subscriptions/#{@sub.id}/plan/draft", params: kinds_body, headers: auth, as: :json
    assert_nil comps(data["plan"]["id"])[2].macro_grams
  end

  test "400 for malformed kinds" do
    bad = lambda do |comp|
      put "/coach/subscriptions/#{@sub.id}/plan/draft", headers: auth, as: :json,
          params: plan_body(options: [ { label: "D", meals: [ { position: 1, title: "M", components: [ comp ] } ] } ])
      assert_response :bad_request, comp.inspect
    end
    bad.call({ kind: "macro", macro: "protein", macroGrams: 30, foodId: @rice.id })
    bad.call({ kind: "macro", macro: "sugar", macroGrams: 30 })
    bad.call({ kind: "macro", macro: "fat", macroGrams: 5001 })
    bad.call({ kind: "macro", macro: "fat", macroGrams: 0 })
    bad.call({ kind: "macro", macro: "fat", macroGrams: 0.004 })
    bad.call({ kind: "portion", portionGroup: "carb", portionCount: 0.004 })
    bad.call({ kind: "portion", portionGroup: "carb", portionCount: 21 })
    bad.call({ kind: "portion", portionGroup: "carb", portionCount: 0 })
    bad.call({ kind: "portion", portionGroup: "nuts", portionCount: 1 })
    bad.call({ kind: "text", freeText: "x", importFlag: "y" * 301 })
    bad.call({ kind: "bogus", freeText: "x" })
  end

  %w[checkout_open pending_payment payment_failed].each do |status|
  test "a #{status} subscription's plan is 404 to read, save and publish" do
    unpaid = make_sub(status, client: another_client)

    get "/coach/subscriptions/#{unpaid.id}/plan", headers: auth
    assert_response :not_found
    put "/coach/subscriptions/#{unpaid.id}/plan/draft", params: plan_body, headers: auth, as: :json
    assert_response :not_found
    publish(unpaid)
    assert_response :not_found
    assert_equal 0, Plan.where(subscription_id: unpaid.id).count
  end
  end
end
