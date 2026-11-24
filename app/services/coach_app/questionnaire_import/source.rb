module CoachApp
  module QuestionnaireImport
    # What goes to the reader: a PDF or image as bytes, or text (pasted, or pulled from a Word
    # file). Built from either an uploaded file or pasted text, never both. The file type comes
    # from its bytes, not its name or declared content type.
    class Source < Struct.new(:kind, :bytes, :media_type, :text, keyword_init: true)
      MAX_BYTES = PlanImport::MAX_BYTES
      MAX_DOCX_BYTES = 10_000_000
      MAX_IMAGE_BYTES = 5_000_000
      MAX_TEXT_CHARS = 20_000
      PNG_MAGIC = "\x89PNG\r\n\x1a\n".b
      JPEG_MAGIC = "\xFF\xD8\xFF".b
      ZIP_MAGIC = "PK\x03\x04".b
      UNSUPPORTED = "use a PDF, Word (.docx), JPG or PNG file".freeze
      SEND_ONE = "send a file or text".freeze

      def self.from(file:, text:)
        has_file = !file.nil? && file != ""
        has_text = !text.nil? && !text.to_s.scrub.strip.empty?
        raise ApiError.new(400, SEND_ONE) if has_file == has_text

        has_file ? from_file(file) : from_text(text)
      end

      def self.from_text(text)
        raise ApiError.new(400, "validation failed") unless text.is_a?(String)

        text = text.dup.force_encoding(Encoding::UTF_8)
        raise ApiError.new(400, "validation failed") unless text.valid_encoding? && !text.include?("\0")

        text = text.strip
        raise ApiError.new(400, "text is too long (max #{MAX_TEXT_CHARS} characters)") if text.length > MAX_TEXT_CHARS

        new(kind: :text, text: text)
      end

      def self.from_file(file)
        bytes = ImportFile.read(file, max_bytes: MAX_BYTES, not_a_file: UNSUPPORTED)
        if ImportFile.pdf?(bytes) then pdf(bytes)
        elsif bytes.start_with?(PNG_MAGIC) then image(bytes, "image/png")
        elsif bytes.start_with?(JPEG_MAGIC) then image(bytes, "image/jpeg")
        elsif bytes.start_with?(ZIP_MAGIC) then docx(bytes)
        else raise ApiError.new(400, UNSUPPORTED)
        end
      end

      def self.pdf(bytes)
        ImportFile.check_pdf_pages!(bytes)
        new(kind: :pdf, bytes: bytes, media_type: "application/pdf")
      end

      def self.image(bytes, media_type)
        raise ApiError.new(400, ImportFile::TOO_LARGE) if bytes.bytesize > MAX_IMAGE_BYTES

        new(kind: :image, bytes: bytes, media_type: media_type)
      end

      def self.docx(bytes)
        raise ApiError.new(400, ImportFile::TOO_LARGE) if bytes.bytesize > MAX_DOCX_BYTES
        raise ApiError.new(400, UNSUPPORTED) unless DocxText.entry?(bytes)

        text = DocxText.call(bytes)
        raise ApiError.new(422, QuestionnaireImport::UNREADABLE) if text.gsub(/[\s|]+/, "").empty?

        new(kind: :text, text: text)
      end
      private_class_method :from_text, :from_file, :pdf, :image, :docx
    end
  end
end
