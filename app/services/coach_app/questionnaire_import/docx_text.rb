module CoachApp
  module QuestionnaireImport
    # Plain text of a .docx: paragraphs one per line, table rows joined with " | ".
    module DocxText
      ENTRY = "word/document.xml".freeze
      NUMBERING = "word/numbering.xml".freeze
      MAX_XML_BYTES = 50_000_000
      W = { "w" => "http://schemas.openxmlformats.org/wordprocessingml/2006/main" }.freeze

      def self.call(bytes)
        xml = read_entry(bytes)
        doc = Nokogiri::XML(xml) { |config| config.nonet.strict }
        body = doc.at_xpath("//w:body", W)
        return "" unless body

        numbering = Numbering.new(read_numbering(bytes))
        blocks(body).flat_map { |node| lines(node, numbering) }.join("\n")
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
      def self.read_entry(bytes, name = ENTRY)
        xml = nil
        Zip::File.open_buffer(StringIO.new(bytes)) do |zip|
          entry = zip.find_entry(name)
          next if entry.nil? && name != ENTRY

          entry || raise(ApiError.new(400, Source::UNSUPPORTED))
          raise ApiError.new(400, ImportFile::TOO_LARGE) if entry.size > MAX_XML_BYTES

          xml = entry.get_input_stream.read(MAX_XML_BYTES + 1).to_s
        end
        raise ApiError.new(400, ImportFile::TOO_LARGE) if xml && xml.bytesize > MAX_XML_BYTES

        xml
      end

      # numbering.xml is optional; a missing or unreadable one just means plain "- " prefixes.
      def self.read_numbering(bytes)
        xml = read_entry(bytes, NUMBERING)
        xml && Nokogiri::XML(xml) { |config| config.nonet.strict }
      rescue Zip::Error, Zlib::Error, EOFError, Nokogiri::XML::SyntaxError
        nil
      end
      private_class_method :read_entry, :read_numbering

      # Child blocks in order, looking inside content controls (w:sdt).
      def self.blocks(parent)
        parent.element_children.flat_map do |node|
          node.name == "sdt" ? blocks(node.at_xpath("w:sdtContent", W) || node.document.create_element("x")) : [ node ]
        end
      end

      def self.lines(node, numbering)
        case node.name
        when "p" then [ numbering.prefix(node) + paragraph(node) ]
        when "tbl" then node.xpath("w:tr", W).map { |row| row.xpath("w:tc", W).map { |cell| cell_text(cell, numbering) }.join(" | ") }
        else []
        end
      end
      private_class_method :blocks, :lines

      def self.paragraph(node) = node.xpath(".//w:t", W).map(&:text).join

      def self.cell_text(cell, numbering)
        blocks(cell).select { |n| n.name == "p" }.map { |p| numbering.prefix(p) + paragraph(p) }.join(" ")
      end
      private_class_method :paragraph, :cell_text

      # Turns w:numPr on a paragraph into "1. ", "a. ", "- " ... keeping one counter per list level.
      class Numbering
        ROMAN = { 1000 => "M", 900 => "CM", 500 => "D", 400 => "CD", 100 => "C", 90 => "XC", 50 => "L",
                  40 => "XL", 10 => "X", 9 => "IX", 5 => "V", 4 => "IV", 1 => "I" }.freeze

        def initialize(doc)
          @doc = doc
          @counters = Hash.new { |h, k| h[k] = {} }
        end

        def prefix(paragraph)
          num_pr = paragraph.at_xpath("w:pPr/w:numPr", W)
          return "" unless num_pr

          num_id = num_pr.at_xpath("w:numId/@w:val", W)&.value.to_s
          return "" if num_id == "0"

          level = num_pr.at_xpath("w:ilvl/@w:val", W)&.value.to_i
          fmt, start = format_for(num_id, level)
          return "- " unless fmt

          counters = @counters[num_id]
          counters.delete_if { |l, _| l > level }
          counters[level] = counters.key?(level) ? counters[level] + 1 : start
          label(fmt, counters[level])
        end

        private

        def format_for(num_id, level)
          return unless @doc

          num_id = num_id.gsub(/\D/, "")
          abstract = @doc.at_xpath("//w:num[@w:numId='#{num_id}']/w:abstractNumId/@w:val", W)&.value.to_s.gsub(/\D/, "")
          lvl = @doc.at_xpath("//w:abstractNum[@w:abstractNumId='#{abstract}']/w:lvl[@w:ilvl='#{level}']", W)
          return unless lvl

          [ lvl.at_xpath("w:numFmt/@w:val", W)&.value, (lvl.at_xpath("w:start/@w:val", W)&.value || 1).to_i ]
        end

        def label(fmt, n)
          n = n.clamp(1, 3999)
          case fmt
          when "decimal" then "#{n}. "
          when "lowerLetter" then "#{letters(n)}. "
          when "upperLetter" then "#{letters(n).upcase}. "
          when "lowerRoman" then "#{roman(n).downcase}. "
          when "upperRoman" then "#{roman(n)}. "
          else "- "
          end
        end

        def letters(n)
          s = +""
          while n > 0
            n -= 1
            s.prepend(("a".ord + n % 26).chr)
            n /= 26
          end
          s
        end

        def roman(n)
          ROMAN.reduce(+"") do |out, (value, sym)|
            out << sym * (n / value)
            n %= value
            out
          end
        end
      end
    end
  end
end
