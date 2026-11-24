require "test_helper"
require_relative "docx_builder"

class CoachApp::QuestionnaireImport::DocxTextTest < ActiveSupport::TestCase
  def call(bytes) = CoachApp::QuestionnaireImport::DocxText.call(bytes)

  test "paragraphs come out in order, one per line" do
    bytes = DocxBuilder.build(DocxBuilder.paragraph("First") + DocxBuilder.paragraph("Second"))
    assert_equal "First\nSecond", call(bytes)
  end

  test "table cells come out row by row joined with a pipe, in document order" do
    body = DocxBuilder.paragraph("Before") + DocxBuilder.table([ %w[a b], %w[c d] ]) + DocxBuilder.paragraph("After")
    assert_equal "Before\na | b\nc | d\nAfter", call(DocxBuilder.build(body))
  end

  test "arabic text comes out exactly as stored" do
    q1 = "ما هو هدفك؟"
    q2 = "الوزن"
    body = DocxBuilder.table([ [ q1, q2 ] ]) + DocxBuilder.paragraph(q1)
    out = call(DocxBuilder.build(body))
    assert_equal "#{q1} | #{q2}\n#{q1}", out
    assert_equal Encoding::UTF_8, out.encoding
  end

  test "an empty document returns an empty string" do
    assert_equal "", call(DocxBuilder.build(""))
  end

  test "a document that expands past 50 MB is refused before it is read" do
    big = DocxBuilder.zip("word/document.xml" => "a" * (51 * 1024 * 1024))
    error = assert_raises(ApiError) { call(big) }
    assert_equal 400, error.status
  end
end
