module CoachApp
  # Checks an uploaded file before anything is stored. Same rules and messages as the Node API.
  module DocumentUpload
    IMAGES = %w[image/jpeg image/png].freeze
    MAGIC = {
      "image/jpeg" => "\xFF\xD8\xFF".b,
      "image/png" => "\x89PNG".b,
      "application/pdf" => "%PDF-".b
    }.freeze
    EXTENSIONS = { "image/jpeg" => ".jpg", "image/png" => ".png", "application/pdf" => ".pdf" }.freeze
    NAME_MAX = 255

    # The file's checked type. Only that decides how it's stored; its name and declared
    # type can say anything.
    def self.check!(type, file)
      refuse("unknown document type") unless CoachDocument::TYPES.include?(type)

      mime_type = file.content_type.to_s.split(";").first.to_s.strip.downcase
      refuse("unsupported file type") unless allowed_types(type).include?(mime_type)
      refuse("file too large") if file.size > ENV.fetch("UPLOAD_MAX_BYTES", 8_000_000).to_i
      refuse("file content does not match its type") unless content_matches?(mime_type, file)
      mime_type
    end

    # The name to show the coach: no path, control characters or broken encoding.
    def self.clean_name(name)
      text = name.to_s.dup.force_encoding(Encoding::UTF_8).scrub("")
      base = text.tr("\\", "/").split("/").last.to_s
      base.gsub(/[[:cntrl:]]/, "").strip.last(NAME_MAX).presence
    end

    def self.allowed_types(type)
      type == CoachDocument::CERTIFICATE ? IMAGES + [ "application/pdf" ] : IMAGES
    end
    private_class_method :allowed_types

    def self.content_matches?(mime_type, file)
      magic = MAGIC.fetch(mime_type)
      head = file.read(magic.bytesize).to_s.b
      file.rewind
      head == magic
    end
    private_class_method :content_matches?

    def self.refuse(message)
      raise ApiError.new(400, message)
    end
    private_class_method :refuse
  end
end
