# Builds tiny .docx files in memory for the questionnaire-import tests.
module DocxBuilder
  W = "http://schemas.openxmlformats.org/wordprocessingml/2006/main".freeze

  def self.paragraph(text) = "<w:p><w:r><w:t>#{text}</w:t></w:r></w:p>"

  def self.table(rows)
    trs = rows.map do |cells|
      "<w:tr>#{cells.map { |c| "<w:tc>#{paragraph(c)}</w:tc>" }.join}</w:tr>"
    end
    "<w:tbl>#{trs.join}</w:tbl>"
  end

  def self.build(body_xml, entry: "word/document.xml")
    xml = %(<?xml version="1.0" encoding="UTF-8"?><w:document xmlns:w="#{W}"><w:body>#{body_xml}</w:body></w:document>)
    zip(entry => xml)
  end

  def self.zip(entries)
    Zip::OutputStream.write_buffer do |out|
      entries.each do |name, data|
        out.put_next_entry(name)
        out.write(data)
      end
    end.string
  end
end
