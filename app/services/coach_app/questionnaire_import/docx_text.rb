module CoachApp
  module QuestionnaireImport
    # Plain text of a .docx: paragraphs one per line, table rows joined with " | ".
    module DocxText
      ENTRY = "word/document.xml".freeze
      MAX_XML_BYTES = 50_000_000
      W = { "w" => "http://schemas.openxmlformats.org/wordprocessingml/2006/main" }.freeze

      def self.call(bytes)
        xml = read_entry(bytes)
        doc = Nokogiri::XML(xml) { |config| config.nonet.strict }
        body = doc.at_xpath("//w:body", W)
        return "" unless body

        blocks(body).flat_map { |node| lines(node) }.join("\n")
      rescue Zip::Error, Zlib::Error, EOFError, Nokogiri::XML::SyntaxError
        raise ApiError.new(400, Source::UNSUPPORTED)
      end

      def self.entry?(bytes)
        found = false
        Zip::File.open_buffer(StringIO.new(bytes)) { |zip| found = !zip.find_entry(ENTRY).nil? }
        found
      rescue Zip::Error, Zlib::Error, EOFError
        false
      end

      # Checks the declared size first so a zip bomb is never inflated.
      def self.read_entry(bytes)
        xml = nil
        Zip::File.open_buffer(StringIO.new(bytes)) do |zip|
          entry = zip.find_entry(ENTRY) || raise(ApiError.new(400, Source::UNSUPPORTED))
          raise ApiError.new(400, ImportFile::TOO_LARGE) if entry.size > MAX_XML_BYTES

          xml = entry.get_input_stream.read(MAX_XML_BYTES + 1).to_s
        end
        raise ApiError.new(400, ImportFile::TOO_LARGE) if xml.bytesize > MAX_XML_BYTES

        xml
      end
      private_class_method :read_entry

      # Child blocks in order, looking inside content controls (w:sdt).
      def self.blocks(parent)
        parent.element_children.flat_map do |node|
          node.name == "sdt" ? blocks(node.at_xpath("w:sdtContent", W) || node.document.create_element("x")) : [ node ]
        end
      end

      def self.lines(node)
        case node.name
        when "p" then [ paragraph(node) ]
        when "tbl" then node.xpath("w:tr", W).map { |row| row.xpath("w:tc", W).map { |cell| cell_text(cell) }.join(" | ") }
        else []
        end
      end
      private_class_method :blocks, :lines

      def self.paragraph(node) = node.xpath(".//w:t", W).map(&:text).join

      def self.cell_text(cell) = blocks(cell).select { |n| n.name == "p" }.map { |p| paragraph(p) }.join(" ")
      private_class_method :paragraph, :cell_text
    end
  end
end
