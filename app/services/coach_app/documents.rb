module CoachApp
  # A coach's documents. Changes hold a lock on the coach's row, so uploads, removals and
  # submitting for review happen one at a time for each coach.
  module Documents
    DOWNLOAD_TTL_SECONDS = 300

    def self.add(coach, type, file)
      mime_type = DocumentUpload.check!(type, file)
      refuse_unless_editable(coach)

      key = "coaches/#{coach.id}/#{type}/#{SecureRandom.uuid}#{DocumentUpload::EXTENSIONS.fetch(mime_type)}"
      Storage.current.put(key, file.read, mime_type: mime_type)

      replaced_keys = []
      begin
        document = coach.with_lock do
          refuse_unless_editable(coach)
          replaced_keys = make_room(coach, type)
          coach.coach_documents.create!(
            type: type, storage_key: key, mime_type: mime_type, size_bytes: file.size,
            original_name: file.respond_to?(:original_filename) ? DocumentUpload.clean_name(file.original_filename) : nil
          )
        end
      rescue StandardError
        delete_file(key)
        raise
      end
      replaced_keys.each { |old_key| delete_file(old_key) }
      document
    end

    def self.remove(coach, id)
      key = coach.with_lock do
        refuse_unless_editable(coach)
        document = find_owned!(coach, id)
        document.destroy!
        document.storage_key
      end
      delete_file(key)
      nil
    end

    def self.find_owned!(coach, id)
      coach.coach_documents.find_by(id: id) || raise(ApiError.new(404, "document not found"))
    end

    # A signed URL, or the bytes when the storage has no URLs to give.
    def self.download(document)
      url = Storage.current.download_url(document.storage_key, DOWNLOAD_TTL_SECONDS)
      url ? { url: url } : { bytes: Storage.current.read(document.storage_key) }
    rescue Storage::NotFound, Storage::InvalidKey
      raise ApiError.new(404, "document not found")
    end

    def self.make_room(coach, type)
      existing = coach.coach_documents.where(type: type)
      if type == CoachDocument::CERTIFICATE
        raise ApiError.new(400, "too many certificates") if existing.count >= CoachDocument::MAX_CERTIFICATES

        return []
      end
      keys = existing.pluck(:storage_key)
      existing.delete_all
      keys
    end
    private_class_method :make_room

    def self.refuse_unless_editable(coach)
      return if Coach::EDITABLE_STATUSES.include?(coach.status)

      raise ApiError.new(409, "documents locked in current state")
    end
    private_class_method :refuse_unless_editable

    # The database no longer points at this file, so failing to delete it only leaves a stray file.
    def self.delete_file(key)
      Storage.current.delete(key)
    rescue StandardError => error
      Rails.logger.error("Could not delete stored file #{key}: #{error.message}")
    end
    private_class_method :delete_file
  end
end
