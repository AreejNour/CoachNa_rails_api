module CoachApp
  # The profile fields a coach may change, checked and named for the table. Only these five keys
  # are ever read, so status, commission and the like can't be set through this route.
  module ProfileParams
    BIO_MAX = 2000
    YEARS_MAX = 80

    def self.parse(params)
      attributes = {}
      attributes[:full_name] = Input.full_name(params[:fullName]) if params.key?(:fullName)
      attributes[:email] = Input.email(params[:email]) if params.key?(:email)
      attributes[:bio] = Input.trimmed(params[:bio], max: BIO_MAX) if params.key?(:bio)
      attributes[:specialties] = specialties(params[:specialties]) if params.key?(:specialties)
      attributes[:years_experience] = years(params[:yearsExperience]) if params.key?(:yearsExperience)
      Input.invalid! if attributes.empty?
      attributes
    end

    def self.specialties(value)
      Input.invalid! unless value.is_a?(Array) && value.all? { |key| Coach::SPECIALTIES.include?(key) }
      value.uniq
    end
    private_class_method :specialties

    def self.years(value)
      Input.invalid! unless value.is_a?(Integer) && value.between?(0, YEARS_MAX)
      value
    end
    private_class_method :years
  end
end
