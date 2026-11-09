require "test_helper"

class CoachApp::DocumentUploadTest < ActiveSupport::TestCase
  JPEG = "\xFF\xD8\xFF\xE0jpeg".b
  PNG = "\x89PNG\r\n\x1A\n".b
  PDF = "%PDF-1.7 pdf".b

  FakeFile = Struct.new(:io, :content_type) do
    def size = io.size
    def read(*args) = io.read(*args)
    def rewind = io.rewind
  end

  def file(bytes, type) = FakeFile.new(StringIO.new(bytes), type)

  def assert_refused(message, type, upload)
    error = assert_raises(ApiError) { CoachApp::DocumentUpload.check!(type, upload) }
    assert_equal [ 400, message ], [ error.status, error.message ]
  end

  %w[profile_photo national_id_front national_id_back certificate].each do |type|
    test "#{type} accepts JPEG and PNG" do
      assert_equal "image/jpeg", CoachApp::DocumentUpload.check!(type, file(JPEG, "image/jpeg"))
      assert_equal "image/png", CoachApp::DocumentUpload.check!(type, file(PNG, "image/png"))
    end
  end

  test "only a certificate accepts a PDF" do
    assert_equal "application/pdf", CoachApp::DocumentUpload.check!("certificate", file(PDF, "application/pdf"))
    assert_refused "unsupported file type", "profile_photo", file(PDF, "application/pdf")
    assert_refused "unsupported file type", "national_id_front", file(PDF, "application/pdf")
  end

  test "the type's parameters and case are ignored" do
    assert_equal "image/jpeg", CoachApp::DocumentUpload.check!("certificate", file(JPEG, "IMAGE/JPEG; charset=binary"))
  end

  test "an unknown document type is refused" do
    assert_refused "unknown document type", "chat_photo", file(JPEG, "image/jpeg")
    assert_refused "unknown document type", "../../x", file(JPEG, "image/jpeg")
  end

  test "a GIF and a missing type are refused" do
    assert_refused "unsupported file type", "certificate", file("GIF89a", "image/gif")
    assert_refused "unsupported file type", "certificate", file(JPEG, nil)
  end

  test "a file over the limit is refused, and exactly the limit is accepted" do
    original = ENV["UPLOAD_MAX_BYTES"]
    ENV["UPLOAD_MAX_BYTES"] = JPEG.bytesize.to_s
    assert_equal "image/jpeg", CoachApp::DocumentUpload.check!("certificate", file(JPEG, "image/jpeg"))

    ENV["UPLOAD_MAX_BYTES"] = (JPEG.bytesize - 1).to_s
    assert_refused "file too large", "certificate", file(JPEG, "image/jpeg")
  ensure
    ENV["UPLOAD_MAX_BYTES"] = original
  end

  test "an executable or text file declared as an image is refused" do
    assert_refused "file content does not match its type", "certificate", file("MZ\x90\x00exe".b, "image/jpeg")
    assert_refused "file content does not match its type", "certificate", file("hello", "image/png")
    assert_refused "file content does not match its type", "certificate", file(JPEG, "application/pdf")
  end

  test "an empty file and a 2-byte file are refused, not a crash" do
    assert_refused "file content does not match its type", "certificate", file("", "image/jpeg")
    assert_refused "file content does not match its type", "certificate", file("\xFF\xD8".b, "image/jpeg")
  end

  test "checking leaves the file ready to read from the start" do
    upload = file(JPEG, "image/jpeg")

    CoachApp::DocumentUpload.check!("certificate", upload)

    assert_equal JPEG, upload.read
  end

  test "clean_name keeps only the file's own name" do
    assert_equal "evil.exe", CoachApp::DocumentUpload.clean_name("../../evil.exe")
    assert_equal "evil.exe", CoachApp::DocumentUpload.clean_name("C:\\temp\\evil.exe")
    assert_equal "شهادة.pdf", CoachApp::DocumentUpload.clean_name("شهادة.pdf")
  end

  test "clean_name removes control characters and broken encoding" do
    assert_equal "ab.jpg", CoachApp::DocumentUpload.clean_name("a\u0000b.jpg")
    assert_equal "a.jpg", CoachApp::DocumentUpload.clean_name("a\xFF.jpg")
  end

  test "clean_name shortens long names and gives nil for nothing usable" do
    assert_equal 255, CoachApp::DocumentUpload.clean_name("#{"a" * 500}.jpg").length
    assert_nil CoachApp::DocumentUpload.clean_name(nil)
    assert_nil CoachApp::DocumentUpload.clean_name("  ")
    assert_nil CoachApp::DocumentUpload.clean_name("\u0000")
  end
end
