module CoachApp
  # Phone numbers as canonical E.164, matching the Node API's normalizePhone.
  module PhoneNumber
    ARABIC_DIGITS = "٠١٢٣٤٥٦٧٨٩۰۱۲۳۴۵۶۷۸۹"
    ASCII_DIGITS = "01234567890123456789"

    def self.normalize(input, country)
      return unless input.is_a?(String) && input.valid_encoding? && !input.include?("\0")

      phone = Phonelib.parse(ascii_digits(input), country)
      phone.e164 if phone.valid?
    end

    # Arabic keyboards type these digits, and Node's library accepts them.
    def self.ascii_digits(text)
      text.tr(ARABIC_DIGITS, ASCII_DIGITS)
    end
  end
end
