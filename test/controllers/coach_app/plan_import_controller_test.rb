require "test_helper"

class CoachApp::PlanImportControllerTest < ActionDispatch::IntegrationTest
  PDF = "%PDF-1.4\n<< /Type /Catalog >>\n<< /Type /Pages /Count 1 >>\n<< /Type /Page >>\n%%EOF".b
  JPEG = "\xFF\xD8\xFF\xE0JFIF".b

  setup do
    @coach = Coach.create!(phone: "+201012349001", password_hash: "h", full_name: "Coach Mona")
    @other = Coach.create!(phone: "+201012349002", password_hash: "h", full_name: "Coach Other")
    @client = Client.create!(phone: "+201012349101", password_hash: "h", full_name: "Client")
    @package = @coach.coach_packages.create!(name: "P", price_piastres: 50_000, duration_days: 30, includes: [ "x" ])
    @rice = Food.create!(name_ar: "أرز", name_en: "Rice", group: "carb", protein_per_100: 2.7,
                         carbs_per_100: 28, fat_per_100: 0.3, weight_basis: "cooked")
    now = Time.current
    @sub = Subscription.create!(client_id: @client.id, coach_id: @coach.id, package_id: @package.id,
                                status: "awaiting_plan", price_piastres: 50_000, commission_percent: 10,
                                commission_piastres: 5000, starts_at: now, ends_at: now + 30.days)
    @stored = []
    @reads = []
    @storage = Storage.current
  end

  def auth = { "Authorization" => "Bearer #{CoachApp::AccessToken.sign(@coach.id)}" }
  def data = response.parsed_body["data"]

  def raw_plan
    { "tips" => "Drink water.",
      "options" => [ { "label" => "Option 1", "meals" => [
        { "title" => "Breakfast", "slot" => "breakfast", "items" => [
          { "kind" => "food", "foodId" => @rice.id, "quantity" => 100, "unit" => "g", "sourceLine" => "100g rice" },
          { "kind" => "food", "foodId" => "nope", "quantity" => 5, "unit" => "g", "sourceLine" => "5g mystery" }
        ] }
      ] } ] }
  end

  def import(bytes: PDF, type: "application/pdf", sub: @sub.id, headers: auth, **extra)
    file = Rack::Test::UploadedFile.new(StringIO.new(bytes), type, true, original_filename: "plan.pdf")
    post "/coach/subscriptions/#{sub}/plan/import", params: { pdf: file, **extra }, headers: headers
  end

  def stubbing_reader(result = nil, raises: nil, &test)
    reader = lambda do |bytes, foods|
      @reads << [ bytes, foods ]
      raise raises if raises

      result
    end
    with_stub(CoachApp::PlanImport::Reader, :call, reader, &test)
  end

  # Minitest 6 has no Object#stub; swap the singleton method for the block's duration.
  def with_stub(target, name, impl)
    original = target.method(name)
    target.define_singleton_method(name) { |*args| impl.call(*args) }
    yield
  ensure
    target.define_singleton_method(name, original)
  end

  def stored_files = Dir.glob(File.join(Storage.local_dir, "plan-imports", @sub.id.to_s, "*.pdf"))

  teardown { FileUtils.rm_rf(File.join(Storage.local_dir, "plan-imports")) }

  test "happy path saves a flagged draft and returns flagCount" do
    stubbing_reader(raw_plan) { import }
    assert_response :created
    assert_equal 1, data["flagCount"]
    assert_equal "draft", data["plan"]["status"]
    assert_equal "Drink water.", data["plan"]["notes"]
    comps = data["plan"]["options"][0]["meals"][0]["components"]
    assert_equal "food", comps[0]["kind"]
    assert_equal "text", comps[1]["kind"]
    assert_equal 1, Plan.where(subscription_id: @sub.id, status: "draft").count
    assert_equal 1, stored_files.size, "the PDF is kept on success"
    assert_equal PDF, @reads.first[0].b
  end

  test "the reader is given the coach's visible foods only" do
    Food.create!(name_ar: "س", name_en: "Secret", group: "carb", protein_per_100: 1, carbs_per_100: 1,
                 fat_per_100: 1, weight_basis: "raw", owner_coach_id: @other.id)
    stubbing_reader(raw_plan) { import }
    names = @reads.first[1].map(&:name_en)
    assert_includes names, "Rice"
    assert_not_includes names, "Secret"
  end

  test "existing draft gives 409 unless replaceDraft is true" do
    stubbing_reader(raw_plan) { import }
    stubbing_reader(raw_plan) { import }
    assert_response :conflict
    assert_equal "draft exists", response.parsed_body["error"]
    assert_equal 1, stored_files.size, "the refused upload is not kept"
    assert_equal 1, @reads.size, "the reader is not called when a draft blocks"

    stubbing_reader(raw_plan) { import(replaceDraft: "true") }
    assert_response :created
    assert_equal 1, Plan.where(subscription_id: @sub.id, status: "draft").count
  end

  test "a JPEG renamed .pdf is 400 and nothing is stored" do
    stubbing_reader(raw_plan) { import(bytes: JPEG) }
    assert_response :bad_request
    assert_empty stored_files
    assert_empty @reads
  end

  test "missing file is 400" do
    post "/coach/subscriptions/#{@sub.id}/plan/import", headers: auth
    assert_response :bad_request
  end

  test "over 20 MB is 400" do
    stubbing_reader(raw_plan) { import(bytes: PDF + ("0" * 20_000_001)) }
    assert_response :bad_request
    assert_empty @reads
  end

  test "over 60 pages is 400" do
    pages = "<< /Type /Page /Parent 1 0 R >>\n" * 61
    stubbing_reader(raw_plan) { import(bytes: "%PDF-1.4\n<< /Type /Pages /Count 61 >>\n#{pages}".b) }
    assert_response :bad_request
    assert_match(/60 pages/, response.parsed_body["error"])
    assert_empty @reads
  end

  test "exactly 60 pages is accepted" do
    pages = "<< /Type /Page >>\n" * 60
    stubbing_reader(raw_plan) { import(bytes: "%PDF-1.4\n<< /Type /Pages >>\n#{pages}".b) }
    assert_response :created
  end

  test "a refusal is 422, saves no draft and deletes the stored file" do
    stubbing_reader(raises: CoachApp::PlanImport::Unreadable.new("refusal")) do
      import
    end
    assert_response :unprocessable_entity
    assert_equal "couldn't read a plan in this file", response.parsed_body["error"]
    assert_equal 0, Plan.where(subscription_id: @sub.id).count
    assert_empty stored_files
  end

  test "no options after normalizing is 422, no draft, file deleted" do
    stubbing_reader({ "tips" => "x", "options" => [] }) { import }
    assert_response :unprocessable_entity
    assert_equal "couldn't read a plan in this file", response.parsed_body["error"]
    assert_equal 0, Plan.where(subscription_id: @sub.id).count
    assert_empty stored_files
  end

  test "malformed reader output is 422" do
    stubbing_reader("not a hash") { import }
    assert_response :unprocessable_entity
    assert_empty stored_files
  end

  test "an API failure is 502, no draft, file deleted" do
    stubbing_reader(raises: CoachApp::PlanImport::Unavailable.new("boom")) do
      import
    end
    assert_response :bad_gateway
    assert_equal 0, Plan.where(subscription_id: @sub.id).count
    assert_empty stored_files
  end

  test "a save error deletes the stored file and keeps the existing draft" do
    with_stub(CoachApp::Plans, :save_draft!, ->(*) { raise ActiveRecord::RecordInvalid }) do
      stubbing_reader(raw_plan) { import }
    end
    assert_response :internal_server_error
    assert_empty stored_files
  end

  test "another coach's subscription is 404 and nothing is read or stored" do
    other_headers = { "Authorization" => "Bearer #{CoachApp::AccessToken.sign(@other.id)}" }
    stubbing_reader(raw_plan) { import(headers: other_headers) }
    assert_response :not_found
    assert_empty @reads
    assert_empty stored_files
  end

  test "no token is 401" do
    stubbing_reader(raw_plan) { import(headers: {}) }
    assert_response :unauthorized
  end

  test "a missing API key is 502 from the real reader, not a crash" do
    original = ENV.delete("ANTHROPIC_API_KEY")
    import
    assert_response :bad_gateway
    assert_empty stored_files
  ensure
    ENV["ANTHROPIC_API_KEY"] = original if original
  end

  test "a pending_payment subscription is 404 and nothing is read or stored" do
    @sub.update!(status: "pending_payment")
    stubbing_reader(raw_plan) { import }
    assert_response :not_found
    assert_empty @reads
    assert_empty stored_files
  end
end
