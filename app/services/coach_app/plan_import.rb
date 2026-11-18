module CoachApp
  # Reads a coach's plan PDF into a draft: stores the file, asks Claude to read it, runs the
  # answer through the Normalizer, saves it with Plans.save_draft!. Any failure saves nothing
  # and deletes the stored file; on success the PDF stays, private to the coach.
  module PlanImport
    MAX_BYTES = 20_000_000
    MAX_PAGES = 60
    PDF_MAGIC = "%PDF-".b
    UNREADABLE = "couldn't read a plan in this file".freeze

    # The reader got an answer but there is no plan to use (refusal, cut off, not JSON).
    class Unreadable < StandardError; end
    # The reader could not get an answer (no key, network, API error).
    class Unavailable < StandardError; end

    # Returns { plan:, flag_count: }.
    def self.call(coach, subscription_id, file, replace:)
      subscription = coach.subscriptions.find_by(id: subscription_id) ||
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
      foods = Foods.visible_by_id(coach)
      raw = Reader.call(bytes, foods.values)
      normalized = Normalizer.call(raw, foods)
      raise ApiError.new(422, UNREADABLE) if normalized[:options].empty?

      attrs = { "notes" => normalized[:notes], "options" => normalized[:options] }
      { plan: Plans.save_draft!(coach, subscription.id, attrs), flag_count: normalized[:flag_count] }
    rescue Unreadable => e
      Rails.logger.warn("plan import unreadable: #{e.message}")
      raise ApiError.new(422, UNREADABLE)
    rescue Unavailable => e
      Rails.logger.error("plan import reader unavailable: #{e.message}")
      raise ApiError.new(502, "couldn't reach the plan reader, try again")
    end
    private_class_method :read_and_save

    def self.checked_bytes(file)
      raise ApiError.new(400, "pdf is required") unless file.respond_to?(:read) && file.respond_to?(:size)
      raise ApiError.new(400, "file too large") if file.size > MAX_BYTES

      bytes = file.read.to_s.b
      raise ApiError.new(400, "file content does not match its type") unless bytes.start_with?(PDF_MAGIC)
      raise ApiError.new(400, "pdf has more than #{MAX_PAGES} pages") if page_count(bytes) > MAX_PAGES

      bytes
    end
    private_class_method :checked_bytes

    # Cheap and dependency-free: counts page objects (not the /Pages tree). Pages hidden in
    # compressed object streams are not seen, so this can undercount; the API caps pages too.
    def self.page_count(bytes)
      bytes.scan(%r{/Type\s*/Page(?![A-Za-z])}n).size
    end

    def self.delete_file(key)
      Storage.current.delete(key)
    rescue StandardError => e
      Rails.logger.error("plan import: couldn't delete #{key}: #{e.class}")
    end
    private_class_method :delete_file
  end
end
