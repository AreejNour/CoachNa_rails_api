module Admin
  # An admin creates an approved coach: profile, documents, status history and a welcome email
  # with a link to choose a password, all in one transaction. Applies the coach app's rules.
  module CoachCreation
    class Invalid < StandardError
      attr_reader :errors

      def initialize(errors)
        @errors = Array(errors)
        super(@errors.join(" "))
      end
    end

    REASON = "Created by admin".freeze
    SINGLE_DOCUMENTS = CoachDocument::REQUIRED_SINGLE
    LABELS = { "profile_photo" => "Profile photo", "national_id_front" => "National id front",
               "national_id_back" => "National id back", "certificate" => "Certificate" }.freeze

    def self.call(admin:, params:)
      attrs, files, errors = parse(params)
      errors.concat(duplicates(attrs))
      raise Invalid, errors if errors.any?

      create!(admin, attrs, files)
    end

    # Queues the welcome email. A coach without an email or a link would get a broken message.
    def self.welcome!(coach)
      link = CoachPasswordSetup.link_for(coach)
      data = { firstName: coach.full_name.to_s.split.first, link: link }
      CoachApp::Outbox.enqueue_and_publish_after_commit!(
        kind: "email", payload: { to: coach.email, template: "coach_account_created", data: data }
      )
    end

    def self.create!(admin, attrs, files)
      stored_keys = []
      begin
        coach = Coach.transaction do
          coach = Coach.create!(
            attrs.merge(status: "incomplete", phone_verified_at: Time.current,
                        password_hash: CoachApp::Password.digest(SecureRandom.hex(32)))
          )
          files.each do |type, file|
            stored_keys << CoachApp::Documents.add(coach, type, file).storage_key
          end
          coach.update!(status: "approved", reviewed_at: Time.current, profile_submitted_at: Time.current)
          coach.coach_status_changes.create!(
            admin_id: admin.id, from_status: "incomplete", to_status: "approved",
            reason: REASON, commission_percent: attrs[:commission_percent]
          )
          welcome!(coach)
          coach
        end
        coach.reload
      rescue StandardError => error
        stored_keys.each { |key| delete_file(key) }
        raise translate(error)
      end
    end
    private_class_method :create!

    def self.translate(error)
      case error
      when Invalid then error
      when ApiError then Invalid.new(error.message.to_s.capitalize + ".")
      when ActiveRecord::RecordNotUnique
        Invalid.new(error.message.include?("coaches_email_unique") ? "Email already registered." : "Phone already registered.")
      when ActiveRecord::RecordInvalid then Invalid.new(error.record.errors.full_messages)
      else
        Rails.logger.error("[coach_creation] failed: #{error.class}")
        Invalid.new("Could not create the coach. Please try again.")
      end
    end
    private_class_method :translate

    def self.delete_file(key)
      Storage.current.delete(key)
    rescue StandardError => error
      Rails.logger.error("Could not delete stored file #{key}: #{error.class}")
    end
    private_class_method :delete_file

    # Returns [attributes, [[type, file], ...], errors].
    def self.parse(params)
      errors = []
      attrs = {}
      check(errors, "Full name is invalid.") { attrs[:full_name] = CoachApp::Input.full_name(params[:full_name]) }
      check(errors, "Phone is invalid.") { attrs[:phone] = CoachApp::Input.phone(params[:phone], params[:country]) }
      check(errors, "Email is invalid.") { attrs[:email] = CoachApp::Input.email(params[:email]) }
      check(errors, "Bio is required (up to #{CoachApp::ProfileParams::BIO_MAX} characters).") do
        attrs[:bio] = CoachApp::Input.trimmed(params[:bio], max: CoachApp::ProfileParams::BIO_MAX)
      end
      check(errors, "Years of experience must be a whole number from 0 to #{CoachApp::ProfileParams::YEARS_MAX}.") do
        attrs[:years_experience] = years(params[:years_experience])
      end
      check(errors, "Choose at least one specialty.") { attrs[:specialties] = specialties(params[:specialties]) }
      check(errors, "Commission must be a number from 0 to 100.") { attrs[:commission_percent] = commission(params[:commission]) }

      files = []
      SINGLE_DOCUMENTS.each do |type|
        file = params[type.to_sym]
        if file?(file)
          files << [ type, file ]
        else
          errors << "#{LABELS[type]} is required."
        end
      end
      Array(params[:certificates]).select { |file| file?(file) }.each { |file| files << [ CoachDocument::CERTIFICATE, file ] }
      if files.count { |type, _| type == CoachDocument::CERTIFICATE } > CoachDocument::MAX_CERTIFICATES
        errors << "Too many certificates (at most #{CoachDocument::MAX_CERTIFICATES})."
      end
      files.each do |type, file|
        CoachApp::DocumentUpload.check!(type, file)
      rescue ApiError => error
        errors << "#{LABELS[type]}: #{error.message}."
      end
      [ attrs, files, errors ]
    end
    private_class_method :parse

    def self.duplicates(attrs)
      errors = []
      errors << "Phone already registered." if attrs[:phone] && Coach.exists?(phone: attrs[:phone])
      errors << "Email already registered." if attrs[:email] && Coach.exists?(email: attrs[:email])
      errors
    end
    private_class_method :duplicates

    def self.check(errors, message)
      yield
    rescue ApiError
      errors << message
    end
    private_class_method :check

    def self.file?(value)
      value.respond_to?(:content_type) && value.respond_to?(:read) && value.respond_to?(:size)
    end
    private_class_method :file?

    def self.years(value)
      CoachApp::Input.invalid! unless value.to_s.strip.match?(/\A\d+\z/)
      number = value.to_s.strip.to_i
      CoachApp::Input.invalid! unless number.between?(0, CoachApp::ProfileParams::YEARS_MAX)
      number
    end
    private_class_method :years

    def self.specialties(value)
      list = Array(value).map(&:to_s).reject(&:blank?).uniq
      CoachApp::Input.invalid! if list.empty? || !list.all? { |key| Coach::SPECIALTIES.include?(key) }
      list
    end
    private_class_method :specialties

    def self.commission(value)
      number = Float(value.to_s.strip, exception: false)
      CoachApp::Input.invalid! unless number&.between?(0, 100)
      number
    end
    private_class_method :commission
  end
end
