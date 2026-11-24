module CoachApp
  # Reads a coach's plan PDF into a draft: stores the file, asks Claude to read it, runs the
  # answer through the Normalizer, saves it with Plans.save_draft!. Any failure saves nothing
  # and deletes the stored file; on success the PDF stays, private to the coach.
  module PlanImport
    MAX_BYTES = 20_000_000
    UNREADABLE = "couldn't read a plan in this file".freeze

    Unreadable = ClaudeJson::Unreadable
    Unavailable = ClaudeJson::Unavailable
    UNAVAILABLE = "couldn't reach the plan reader, try again".freeze

    # Returns { plan:, flag_count: }.
    def self.call(coach, subscription_id, file, replace:)
      subscription = Subscriptions.visible_to_coach(coach).find_by(id: subscription_id) ||
                     raise(ApiError.new(404, "client not found"))
      bytes = checked_bytes(file)
      if !replace && Plan.exists?(subscription_id: subscription.id, status: "draft")
        raise ApiError.new(409, "draft exists")
      end

      key = "plan-imports/#{subscription.id}/#{SecureRandom.uuid}.pdf"
      Storage.current.put(key, bytes, mime_type: "application/pdf")
      begin
        read_and_save(coach, subscription, bytes)
      rescue StandardError
        delete_file(key)
        raise
      end
    end

    def self.read_and_save(coach, subscription, bytes)
      ClaudeJson.mapping_errors("plan import", unreadable: UNREADABLE, unavailable: UNAVAILABLE) do
        foods = Foods.visible_by_id(coach)
        raw = Reader.call(bytes, foods.values)
        normalized = Normalizer.call(raw, foods)
        raise ApiError.new(422, UNREADABLE) if normalized[:options].empty?

        attrs = { "notes" => normalized[:notes], "options" => normalized[:options] }
        { plan: Plans.save_draft!(coach, subscription.id, attrs), flag_count: normalized[:flag_count] }
      end
    end
    private_class_method :read_and_save

    def self.checked_bytes(file)
      bytes = ImportFile.read(file, max_bytes: MAX_BYTES, not_a_file: "pdf is required")
      raise ApiError.new(400, "file content does not match its type") unless ImportFile.pdf?(bytes)

      ImportFile.check_pdf_pages!(bytes)
      bytes
    end
    private_class_method :checked_bytes

    def self.delete_file(key)
      Storage.current.delete(key)
    rescue StandardError => e
      Rails.logger.error("plan import: couldn't delete #{key}: #{e.class}")
    end
    private_class_method :delete_file
  end
end
