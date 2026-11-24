require "test_helper"

class CoachApp::ImportFileTest < ActiveSupport::TestCase
  File = CoachApp::ImportFile

  def upload(bytes) = StringIO.new(bytes).tap { |io| io.define_singleton_method(:size) { string.bytesize } }

  def assert_400(message, &block)
    error = assert_raises(ApiError, &block)
    assert_equal [ 400, message ], [ error.status, error.message ]
  end

  test "read returns the bytes of an upload within the limit" do
    assert_equal "abc".b, File.read(upload("abc"), max_bytes: 3, not_a_file: "nope")
  end

  test "read refuses a non-file with the caller's message and an oversize file" do
    assert_400("nope") { File.read("text", max_bytes: 3, not_a_file: "nope") }
    assert_400("file too large") { File.read(upload("abcd"), max_bytes: 3, not_a_file: "nope") }
  end

  test "pdf? sniffs the magic and check_pdf_pages! caps the page count" do
    assert File.pdf?("%PDF-1.7".b)
    assert_not File.pdf?("PK".b)
    File.check_pdf_pages!("%PDF-".b + "/Type /Page " * File::MAX_PAGES)
    assert_400("pdf has more than 60 pages") { File.check_pdf_pages!("%PDF-".b + "/Type /Page " * 61) }
  end
end
