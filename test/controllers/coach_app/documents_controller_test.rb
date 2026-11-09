require "test_helper"

class CoachApp::DocumentsControllerTest < ActionDispatch::IntegrationTest
  JPEG = "\xFF\xD8\xFF\xE0one".b
  JPEG_TWO = "\xFF\xD8\xFF\xE0two".b
  PDF = "%PDF-1.7 pdf".b
  KEY = %r{\Acoaches/\h{8}-\h{4}-\h{4}-\h{4}-\h{12}/}

  class FailingStorage
    def put(*, **) = raise("storage is down")
  end

  class RedirectingStorage
    def download_url(key, ttl) = "https://files.example.com/#{key}?ttl=#{ttl}"
  end

  setup do
    Storage.reset!
    FileUtils.rm_rf(Storage.local_dir)
    @coach = Coach.create!(phone: "+201012345700", password_hash: "x", full_name: "Sara")
  end

  teardown { Storage.reset! }

  def auth(coach = @coach) = { "Authorization" => "Bearer #{CoachApp::AccessToken.sign(coach.id)}" }

  def upload(type: "certificate", bytes: JPEG, content_type: "image/jpeg", name: "a.jpg", coach: @coach)
    file = Rack::Test::UploadedFile.new(StringIO.new(bytes), content_type, true, original_filename: name)
    post "/coach/profile/documents", params: { type: type, file: file }, headers: auth(coach)
  end

  def data = response.parsed_body["data"]
  def stored = Dir.glob(File.join(Storage.local_dir, "**/*")).select { |path| File.file?(path) }

  def assert_failure(status, message)
    assert_response status
    assert_equal({ "success" => false, "error" => message }, response.parsed_body)
  end

  test "upload stores the file and returns the contract's Document" do
    upload(type: "profile_photo")

    assert_response :created
    document = CoachDocument.find(data["id"])
    assert_equal %w[createdAt id mimeType originalName type], data.keys.sort
    assert_equal [ "profile_photo", "a.jpg", "image/jpeg" ], data.values_at("type", "originalName", "mimeType")
    assert_equal data["createdAt"], document.created_at.iso8601(3)
    assert_equal JPEG.bytesize, document.size_bytes
    assert_match %r{\Acoaches/#{@coach.id}/profile_photo/\h{8}-\h{4}-\h{4}-\h{4}-\h{12}\.jpg\z}, document.storage_key
    assert_equal JPEG, Storage.current.read(document.storage_key)
  end

  test "the response never reveals the storage key" do
    upload

    assert_no_match(/coaches\/|storage/i, response.body)
  end

  test "a PNG and a PDF get extensions from their checked type, not their names" do
    upload(bytes: "\x89PNG\r\n".b, content_type: "image/png", name: "photo.exe")
    assert_match(/\.png\z/, CoachDocument.find(data["id"]).storage_key)

    upload(bytes: PDF, content_type: "application/pdf", name: "shell.php")
    assert_match(/\.pdf\z/, CoachDocument.find(data["id"]).storage_key)
  end

  test "a hostile file name stays in the coach's folder and loses its path" do
    upload(name: "../../evil.exe")

    assert_response :created
    assert_equal "evil.exe", data["originalName"]
    document = CoachDocument.find(data["id"])
    assert_match KEY, document.storage_key
    assert_match(/\.jpg\z/, document.storage_key)
    assert(stored.all? { |path| path.start_with?(Storage.local_dir) })
  end

  test "a 500-character name is shortened, not a 500" do
    upload(name: "#{"a" * 500}.jpg")

    assert_response :created
    assert_equal 255, data["originalName"].length
  end

  test "a second profile photo replaces the first" do
    upload(type: "profile_photo", bytes: JPEG)
    first_key = CoachDocument.find(data["id"]).storage_key

    upload(type: "profile_photo", bytes: JPEG_TWO)

    assert_response :created
    assert_equal 1, @coach.coach_documents.where(type: "profile_photo").count
    assert_raises(Storage::NotFound) { Storage.current.read(first_key) }
    assert_equal JPEG_TWO, Storage.current.read(CoachDocument.find(data["id"]).storage_key)
    assert_equal 1, stored.size
  end

  test "certificates add up to 10, and the eleventh is refused and not stored" do
    10.times do
      upload
      assert_response :created
    end

    upload

    assert_failure :bad_request, "too many certificates"
    assert_equal 10, @coach.coach_documents.count
    assert_equal 10, stored.size
  end

  test "another coach's documents don't count toward the limit or get replaced" do
    other = Coach.create!(phone: "+201012345701", password_hash: "x", full_name: "Other")
    upload(type: "profile_photo", coach: other)
    upload(type: "profile_photo")

    assert_equal 1, other.coach_documents.count
    assert_equal 1, @coach.coach_documents.count
  end

  test "a missing type, a missing file and a file sent as text are validation failed" do
    post "/coach/profile/documents", params: { type: "certificate" }, headers: auth
    assert_failure :bad_request, "validation failed"

    file = Rack::Test::UploadedFile.new(StringIO.new(JPEG), "image/jpeg", true, original_filename: "a.jpg")
    post "/coach/profile/documents", params: { file: file }, headers: auth
    assert_failure :bad_request, "validation failed"

    post "/coach/profile/documents", params: { type: "certificate", file: "not a file" }, headers: auth
    assert_failure :bad_request, "validation failed"
  end

  test "a broken multipart body is a 400 in the envelope" do
    post "/coach/profile/documents",
      params: "--xxx\r\nContent-Disposition: form-data; name=\"file\"; filename=\"a.jpg\"\r\nContent-Ty",
      headers: auth.merge("CONTENT_TYPE" => "multipart/form-data; boundary=xxx")

    assert_failure :bad_request, "validation failed"
  end

  test "the file checks reach the route with their messages" do
    upload(bytes: "MZ\x90exe".b)

    assert_failure :bad_request, "file content does not match its type"
    assert_empty stored
  end

  test "if the database write fails, the new file is deleted and the old document kept" do
    upload(type: "profile_photo", bytes: JPEG)
    old = CoachDocument.find(data["id"])
    failing = ->(_record) { raise "database is down" }
    CoachDocument.before_create(failing)

    upload(type: "profile_photo", bytes: JPEG_TWO)

    assert_failure :internal_server_error, "internal error"
    assert CoachDocument.exists?(old.id)
    assert_equal JPEG, Storage.current.read(old.storage_key)
    assert_equal 1, stored.size
  ensure
    CoachDocument.skip_callback(:create, :before, failing)
  end

  test "if the storage write fails, nothing changes and the response is a 500" do
    upload(type: "profile_photo")
    old = CoachDocument.find(data["id"])
    Storage.instance_variable_set(:@current, FailingStorage.new)

    upload(type: "profile_photo", bytes: JPEG_TWO)

    assert_failure :internal_server_error, "internal error"
    assert CoachDocument.exists?(old.id)
  end

  %w[pending_review approved suspended deactivated].each do |status|
    test "a coach who is #{status} can't upload or delete" do
      document = @coach.coach_documents.create!(type: "certificate", storage_key: "k", mime_type: "image/jpeg", size_bytes: 1)
      @coach.update!(status: status)

      upload
      assert_failure :conflict, "documents locked in current state"

      delete "/coach/profile/documents/#{document.id}", headers: auth
      assert_failure :conflict, "documents locked in current state"

      assert CoachDocument.exists?(document.id)
      assert_empty stored
    end
  end

  %w[incomplete rejected].each do |status|
    test "a coach who is #{status} can upload and delete" do
      @coach.update!(status: status)

      upload
      assert_response :created

      delete "/coach/profile/documents/#{data["id"]}", headers: auth
      assert_response :ok
    end
  end

  test "delete removes the row and the file" do
    upload
    id = data["id"]

    delete "/coach/profile/documents/#{id}", headers: auth

    assert_response :ok
    assert_equal({ "success" => true, "data" => {} }, response.parsed_body)
    assert_not CoachDocument.exists?(id)
    assert_empty stored
  end

  test "file returns the bytes and type, and is never cached" do
    upload(bytes: PDF, content_type: "application/pdf", name: "c.pdf")

    get "/coach/profile/documents/#{data["id"]}/file", headers: auth

    assert_response :ok
    assert_equal PDF, response.body.b
    assert_match %r{\Aapplication/pdf}, response.headers["Content-Type"]
    assert_equal "no-store", response.headers["Cache-Control"]
    assert_equal "nosniff", response.headers["X-Content-Type-Options"]
  end

  test "on S3, file redirects to the signed URL and isn't cached" do
    document = @coach.coach_documents.create!(type: "certificate", storage_key: "coaches/x/a.jpg", mime_type: "image/jpeg", size_bytes: 1)
    Storage.instance_variable_set(:@current, RedirectingStorage.new)

    get "/coach/profile/documents/#{document.id}/file", headers: auth

    assert_response :found
    assert_equal "https://files.example.com/coaches/x/a.jpg?ttl=300", response.headers["Location"]
    assert_equal "no-store", response.headers["Cache-Control"]
  end

  test "a file missing from storage is 404" do
    document = @coach.coach_documents.create!(type: "certificate", storage_key: "coaches/missing.jpg", mime_type: "image/jpeg", size_bytes: 1)

    get "/coach/profile/documents/#{document.id}/file", headers: auth

    assert_failure :not_found, "document not found"
  end

  test "another coach's document is 404 and nothing changes" do
    other = Coach.create!(phone: "+201012345702", password_hash: "x", full_name: "Other")
    upload(coach: other)
    id = data["id"]

    get "/coach/profile/documents/#{id}/file", headers: auth
    assert_failure :not_found, "document not found"

    delete "/coach/profile/documents/#{id}", headers: auth
    assert_failure :not_found, "document not found"

    assert CoachDocument.exists?(id)
    assert_equal 1, stored.size
  end

  test "an id that isn't a UUID is 404" do
    get "/coach/profile/documents/not-a-uuid/file", headers: auth
    assert_failure :not_found, "document not found"

    delete "/coach/profile/documents/not-a-uuid", headers: auth
    assert_failure :not_found, "document not found"
  end

  test "a client's token and no token are 401" do
    post "/coach/profile/documents"
    assert_failure :unauthorized, "unauthorized"

    delete "/coach/profile/documents/x"
    assert_failure :unauthorized, "unauthorized"

    get "/coach/profile/documents/x/file"
    assert_failure :unauthorized, "unauthorized"
  end
end

class CoachApp::DocumentsConcurrencyTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  JPEG = "\xFF\xD8\xFF\xE0one".b

  FakeFile = Struct.new(:bytes) do
    def content_type = "image/jpeg"
    def original_filename = "a.jpg"
    def size = bytes.bytesize
    def io = (@io ||= StringIO.new(bytes))
    def read(*args) = io.read(*args)
    def rewind = io.rewind
  end

  setup do
    Storage.reset!
    FileUtils.rm_rf(Storage.local_dir)
    @coach = Coach.create!(phone: "+201012345703", password_hash: "x", full_name: "Sara")
  end

  teardown do
    Coach.where(id: @coach.id).delete_all
    FileUtils.rm_rf(Storage.local_dir)
  end

  def stored = Dir.glob(File.join(Storage.local_dir, "**/*")).select { |path| File.file?(path) }

  def in_threads(count)
    start = Concurrent::CountDownLatch.new(1)
    threads = count.times.map do
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          start.wait
          yield
        rescue ApiError => error
          error.status
        end
      end
    end
    start.count_down
    threads.map(&:value)
  end

  test "two simultaneous profile photos leave one row and one file" do
    results = in_threads(2) { CoachApp::Documents.add(Coach.find(@coach.id), "profile_photo", FakeFile.new(JPEG)) }

    assert_not_includes results, 500
    assert_equal 1, @coach.coach_documents.count
    assert_equal [ @coach.coach_documents.first.storage_key ], stored.map { |path| path.delete_prefix("#{Storage.local_dir}/") }
  end

  test "simultaneous certificates can't pass the limit" do
    9.times { |n| @coach.coach_documents.create!(type: "certificate", storage_key: "k#{n}", mime_type: "image/jpeg", size_bytes: 1) }

    results = in_threads(3) { CoachApp::Documents.add(Coach.find(@coach.id), "certificate", FakeFile.new(JPEG)) }

    assert_equal 10, @coach.coach_documents.count
    assert_equal 2, results.count(400), results.inspect
    assert_equal 1, stored.size
  end
end
