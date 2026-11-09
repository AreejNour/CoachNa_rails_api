module CoachApp
  # Phone numbers as canonical E.164. Egypt gets the full check, which matches Node on real mobiles
  # and refuses impossible ones. Other countries get the general pattern for that country, the kind
  # of check Node does: the full check refused nearly half the foreign numbers Node accepts, and
  # refusing a real number would block a real coach.
  module PhoneNumber
    ARABIC_DIGITS = "٠١٢٣٤٥٦٧٨٩۰۱۲۳۴۵۶۷۸۹"
    ASCII_DIGITS = "01234567890123456789"
    COUNTRY_CODE = /\A[A-Z]{2}\z/
    EGYPT_PREFIX = "+20"

    def self.normalize(input, country)
      return unless input.is_a?(String) && input.valid_encoding? && !input.include?("\0")

      phone = Phonelib.parse(ascii_digits(input), country)
      phone.e164 if phone.e164.start_with?(EGYPT_PREFIX) ? phone.valid? : matches_country_pattern?(phone)
    end

    # Every selectable country, for the app's picker. Phonelib also lists non-geographic
    # entries such as "International 800", which aren't countries.
    def self.countries
      Phonelib.phone_data.values
        .select { |data| data[:id].match?(COUNTRY_CODE) }
        .map { |data| { country: data[:id], callingCode: data[:country_code] } }
        .sort_by { |entry| entry[:country] }
    end

    def self.matches_country_pattern?(phone)
      data = Phonelib.phone_data[phone.country]
      return false unless data

      pattern = data.dig(:types, :general_desc, :national_number_pattern)
      national = phone.e164.delete_prefix("+#{data[:country_code]}")
      pattern.present? && national.match?(/\A(?:#{pattern})\z/)
    end
    private_class_method :matches_country_pattern?

    # Arabic keyboards type these digits, and Node's library accepts them.
    def self.ascii_digits(text)
      text.tr(ARABIC_DIGITS, ASCII_DIGITS)
    end
  end
end
