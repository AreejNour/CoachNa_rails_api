require "test_helper"

class Admin::CoachCreationTest < ActiveSupport::TestCase
  PNG = "\x89PNG\r\n\x1A\n".b
  PDF = "%PDF-1.7 pdf".b

  setup do
    @admin = AdminUser.create!(name: "Admin", email: "admin_#{SecureRandom.hex(4)}@example.com", password: "password123")
    CoachApp::QueuePublisher.adapter = CoachApp::QueuePublisher::TestAdapter.new
  end

  teardown { CoachApp::QueuePublisher.adapter = nil }

  def upload(bytes, type, name)
    Rack::Test::UploadedFile.new(StringIO.new(bytes), type, true, original_filename: name)
  end

  def params(overrides = {})
    {
      full_name: "Mona Coach", phone: "1001234567", country: "EG", email: "mona@example.com",
      bio: "Ten years of coaching.", years_experience: "5", specialties: [ "weight_loss" ],
      profile_photo: upload(PNG, "image/png", "me.png"),
      national_id_front: upload(PNG, "image/png", "front.png"),
      national_id_back: upload(PNG, "image/png", "back.png"),
      certificates: [ upload(PDF, "application/pdf", "cert.pdf") ],
      commission: "20"
    }.merge(overrides)
  end

  def stored_files
    dir = Storage.local_dir
    Dir.glob(File.join(dir, "coaches", "**", "*")).select { |path| File.file?(path) }
  end

  test "creates an approved coach with documents, history and a welcome email" do
    coach = Admin::CoachCreation.call(admin: @admin, params: params)

    coach.reload
    assert_equal "approved", coach.status
    assert_equal 20, coach.commission_percent
    assert_equal "+201001234567", coach.phone
    assert_not_nil coach.phone_verified_at
    assert_not_nil coach.reviewed_at
    assert_not_nil coach.profile_submitted_at
    assert_equal 4, coach.coach_documents.count
    # "about" stays until the admin form takes gender and date of birth (a later task).
    assert_equal [ "about" ], CoachApp::ReviewStatus.missing(coach, coach.coach_documents.to_a)

    change = coach.coach_status_changes.sole
    assert_equal [ "incomplete", "approved", "Created by admin", @admin.id ],
                 [ change.from_status, change.to_status, change.reason, change.admin_id ]
    assert_equal 20, change.commission_percent

    row = OutboxMessage.where(kind: "email").sole
    assert_equal "coach_account_created", row.payload["template"]
    assert_equal "mona@example.com", row.payload["to"]
    assert row.payload["data"]["link"].start_with?("http://localhost:3003/coach-password/")
    assert_equal "Mona", row.payload["data"]["firstName"]
  end

  test "the coach cannot log in with any password until they set one" do
    coach = Admin::CoachCreation.call(admin: @admin, params: params)

    assert_not CoachApp::Password.verify("", coach.password_hash)
    assert_not CoachApp::Password.verify("password123", coach.password_hash)
  end

  test "a missing ID back is refused and leaves no coach and no files" do
    before = stored_files.size
    error = assert_raises(Admin::CoachCreation::Invalid) do
      Admin::CoachCreation.call(admin: @admin, params: params(national_id_back: nil))
    end

    assert_includes error.errors.join(" "), "National id back"
    assert_equal 0, Coach.count
    assert_equal before, stored_files.size
  end

  test "a failure after files are stored removes the coach and the stored files" do
    before = stored_files.size
    swap_method(Admin::CoachCreation, :welcome!, ->(_coach) { raise "queue down" }) do
      assert_raises(Admin::CoachCreation::Invalid) { Admin::CoachCreation.call(admin: @admin, params: params) }
    end

    assert_equal 0, Coach.count
    assert_equal 0, CoachDocument.count
    assert_equal before, stored_files.size
  end

  test "a duplicate phone and a duplicate email are friendly errors" do
    Coach.create!(full_name: "Old", phone: "+201001234567", email: "mona@example.com", password_hash: "h")

    error = assert_raises(Admin::CoachCreation::Invalid) { Admin::CoachCreation.call(admin: @admin, params: params) }

    assert_includes error.errors, "Phone already registered."
    assert_includes error.errors, "Email already registered."
    assert_equal 1, Coach.count
  end

  test "collects every field problem" do
    error = assert_raises(Admin::CoachCreation::Invalid) do
      Admin::CoachCreation.call(admin: @admin, params: params(full_name: "", phone: "abc", email: "nope", bio: "",
                                                              years_experience: "x", specialties: [], commission: "150"))
    end

    assert_operator error.errors.size, :>=, 7
    assert_equal 0, Coach.count
  end

  test "an unexpected failure logs the class and a truncated, scrubbed message" do
    logged = StringIO.new
    old = Rails.logger
    Rails.logger = ActiveSupport::Logger.new(logged)
    boom = RuntimeError.new("kaboom #{'$2a$04$' + 'a' * 50} #{'x' * 400}")
    original = Admin::CoachCreation.method(:welcome!)
    Admin::CoachCreation.define_singleton_method(:welcome!) { |_coach| raise boom }
    begin
      assert_raises(Admin::CoachCreation::Invalid) { Admin::CoachCreation.call(admin: @admin, params: params) }
    ensure
      Admin::CoachCreation.define_singleton_method(:welcome!, original)
    end
    line = logged.string.lines.find { |l| l.include?("[coach_creation] failed") }
    assert_includes line, "RuntimeError: kaboom"
    assert_not_includes line, "$2a$"
    assert_operator line.length, :<, 320
  ensure
    Rails.logger = old
  end
end
