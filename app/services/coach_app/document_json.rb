module CoachApp
  # A document as the API shows it. The storage key stays private.
  module DocumentJson
    def self.call(document)
      {
        id: document.id,
        type: document.type,
        originalName: document.original_name,
        mimeType: document.mime_type,
        createdAt: document.created_at.iso8601(3)
      }
    end
  end
end
