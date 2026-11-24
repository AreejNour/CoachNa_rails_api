require "test_helper"
require_relative "docx_builder"

class CoachApp::QuestionnaireImport::SourceTest < ActiveSupport::TestCase
  PNG = "\x89PNG\r\n\x1a\n".b
  JPEG = "\xFF\xD8\xFF".b
  UNSUPPORTED = "use a PDF, Word (.docx), JPG or PNG file".freeze

  def from(file: nil, text: nil) = CoachApp::QuestionnaireImport::Source.from(file: file, text: text)
  def upload(bytes) = StringIO.new(bytes)

  def assert_rejected(message)
    error = assert_raises(ApiError) { yield }
    assert_equal 400, error.status
    assert_equal message, error.message if message
  end

  test "a pdf keeps its bytes" do
    bytes = "%PDF-1.4\n".b + "x" * 100
    source = from(file: upload(bytes))
    assert_equal :pdf, source.kind
    assert_equal "application/pdf", source.media_type
    assert_equal bytes, source.bytes
  end

  test "a pdf over 60 pages is refused" do
    bytes = "%PDF-1.4\n".b + ("<< /Type /Page >>\n" * 61)
    assert_rejected("pdf has more than 60 pages") { from(file: upload(bytes)) }
  end

  test "a 21 MB pdf is too large" do
    assert_rejected("file too large") { from(file: upload("%PDF-".b + "x" * 21_000_000)) }
  end

  test "an 11 MB docx is too large but an 11 MB pdf is not" do
    assert_rejected("file too large") { from(file: upload("PK\x03\x04".b + "x" * 11_000_000)) }
    assert_equal :pdf, from(file: upload("%PDF-".b + "x" * 11_000_000)).kind
  end

  test "the type comes from the bytes, not the name" do
    file = upload(PNG + "data")
    file.define_singleton_method(:original_filename) { "x.pdf" }
    source = from(file: file)
    assert_equal :image, source.kind
    assert_equal "image/png", source.media_type
  end

  test "jpeg bytes become image/jpeg" do
    source = from(file: upload(JPEG + "data"))
    assert_equal :image, source.kind
    assert_equal "image/jpeg", source.media_type
  end

  test "a 6 MB image is too large" do
    assert_rejected("file too large") { from(file: upload(PNG + "x" * 6_000_000)) }
  end

  test "an old .doc is refused" do
    assert_rejected(UNSUPPORTED) { from(file: upload("\xD0\xCF\x11\xE0".b + "x" * 50)) }
  end

  test "unknown bytes are refused" do
    assert_rejected(UNSUPPORTED) { from(file: upload("hello world")) }
  end

  test "a zip without word/document.xml is refused" do
    assert_rejected(UNSUPPORTED) { from(file: upload(DocxBuilder.zip("a.txt" => "hi"))) }
  end

  test "a docx becomes text" do
    source = from(file: upload(DocxBuilder.build(DocxBuilder.paragraph("Goal?"))))
    assert_equal :text, source.kind
    assert_equal "Goal?", source.text
  end

  test "pasted text becomes text" do
    source = from(text: "  What is your goal?  ")
    assert_equal :text, source.kind
    assert_equal "What is your goal?", source.text
  end

  test "pasted text of 20,000 characters is accepted and 20,001 is refused" do
    assert_equal 20_000, from(text: "a" * 20_000).text.length
    assert_rejected(nil) { from(text: "a" * 20_001) }
  end

  test "pasted text with a NUL byte or invalid UTF-8 is refused" do
    assert_rejected(nil) { from(text: "a\0b") }
    assert_rejected(nil) { from(text: "a\xFFb".dup.force_encoding("UTF-8")) }
  end

  test "both, neither or blank text is refused" do
    msg = "send a file or text"
    assert_rejected(msg) { from }
    assert_rejected(msg) { from(file: upload(PNG), text: "hi") }
    assert_rejected(msg) { from(text: "  \n ") }
  end
end
