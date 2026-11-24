module CoachApp
  # File checks both importers make before reading a file. Messages and limits that differ per
  # feature stay with the feature.
  module ImportFile
    TOO_LARGE = "file too large".freeze
    PDF_MAGIC = "%PDF-".b
    MAX_PAGES = 60

    # The file's bytes, once it is a readable upload within max_bytes.
    def self.read(file, max_bytes:, not_a_file:)
      raise ApiError.new(400, not_a_file) unless file.respond_to?(:read) && file.respond_to?(:size)
      raise ApiError.new(400, TOO_LARGE) if file.size > max_bytes

      file.read.to_s.b
    end

    def self.pdf?(bytes) = bytes.start_with?(PDF_MAGIC)

    def self.check_pdf_pages!(bytes)
      raise ApiError.new(400, "pdf has more than #{MAX_PAGES} pages") if page_count(bytes) > MAX_PAGES
    end

    # Cheap and dependency-free: counts page objects (not the /Pages tree). Pages hidden in
    # compressed object streams are not seen, so this can undercount; the API caps pages too.
    def self.page_count(bytes)
      bytes.scan(%r{/Type\s*/Page(?![A-Za-z])}n).size
    end
  end
end
