module CoachApp
  # Stand-in: writes the code to the log, like the Node API's console driver. A real SMS provider
  # replaces this before launch (docs/temporary-code-to-remove.md).
  module OtpSender
    def self.deliver(phone, code)
      Rails.logger.info("[otp] code for #{phone}: #{code}")
    end
  end
end
