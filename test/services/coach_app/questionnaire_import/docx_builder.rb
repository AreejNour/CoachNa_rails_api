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

  def self.build(body_xml, entry: "word/document.xml", numbering: nil)
    xml = %(<?xml version="1.0" encoding="UTF-8"?><w:document xmlns:w="#{W}"><w:body>#{body_xml}</w:body></w:document>)
    entries = { entry => xml }
    entries["word/numbering.xml"] = numbering if numbering
    zip(entries)
  end

  def self.numbered(text, num_id, ilvl = 0)
    %(<w:p><w:pPr><w:numPr><w:ilvl w:val="#{ilvl}"/><w:numId w:val="#{num_id}"/></w:numPr></w:pPr><w:r><w:t>#{text}</w:t></w:r></w:p>)
  end

  # levels: { num_id => [[fmt, start], ...] } one abstractNum per num_id (same id).
  def self.numbering(levels)
    abstracts = levels.map do |id, lvls|
      inner = lvls.each_with_index.map do |(fmt, start), i|
        %(<w:lvl w:ilvl="#{i}"><w:start w:val="#{start}"/><w:numFmt w:val="#{fmt}"/></w:lvl>)
      end.join
      %(<w:abstractNum w:abstractNumId="#{id}">#{inner}</w:abstractNum>)
    end.join
    nums = levels.keys.map { |id| %(<w:num w:numId="#{id}"><w:abstractNumId w:val="#{id}"/></w:num>) }.join
    %(<?xml version="1.0" encoding="UTF-8"?><w:numbering xmlns:w="#{W}">#{abstracts}#{nums}</w:numbering>)
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
