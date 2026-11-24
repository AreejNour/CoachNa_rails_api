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

  test "content-control blocks come out in document order at body and cell level" do
    sdt = ->(inner) { "<w:sdt><w:sdtPr/><w:sdtContent>#{inner}</w:sdtContent></w:sdt>" }
    cell_sdt = "<w:tbl><w:tr><w:tc>#{sdt.call(DocxBuilder.paragraph("InCell"))}</w:tc></w:tr></w:tbl>"
    body = DocxBuilder.paragraph("Before") + sdt.call(DocxBuilder.paragraph("Q1") + DocxBuilder.paragraph("Q2")) +
           cell_sdt + DocxBuilder.paragraph("After")
    assert_equal "Before\nQ1\nQ2\nInCell\nAfter", call(DocxBuilder.build(body))
  end

  test "truncated zip bytes raise a 400 not a zlib or eof error" do
    bytes = DocxBuilder.build(DocxBuilder.paragraph("hello " * 500))
    [ 0.3, 0.5, 0.8 ].each do |f|
      cut = bytes[0, (bytes.bytesize * f).to_i]
      assert_equal false, CoachApp::QuestionnaireImport::DocxText.entry?(cut)
      assert_equal 400, assert_raises(ApiError) { call(cut) }.status
    end
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
