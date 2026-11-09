require "test_helper"

class CoachApp::PhoneNumberTest < ActiveSupport::TestCase
  # Expected values come from running the Node API's normalizePhone (libphonenumber-js).
  [
    [ "01012345678", "EG", "+201012345678" ],
    [ "+201012345678", "EG", "+201012345678" ],
    [ "00201012345678", "EG", "+201012345678" ],
    [ "010 1234-5678", "EG", "+201012345678" ],
    [ "٠١٠١٢٣٤٥٦٧٨", "EG", "+201012345678" ],
    [ "+966501234567", "EG", "+966501234567" ],
    [ "0501234567", "SA", "+966501234567" ],
    [ "123", "EG", nil ],
    [ "01012345678", "SA", nil ]
  ].each do |input, country, expected|
    test "normalize(#{input.inspect}, #{country}) is #{expected.inspect}" do
      if expected.nil?
        assert_nil CoachApp::PhoneNumber.normalize(input, country)
      else
        assert_equal expected, CoachApp::PhoneNumber.normalize(input, country)
      end
    end
  end

  %w[01012345678 01112345678 01212345678 01512345678].each do |number|
    test "every Egyptian mobile prefix is valid: #{number}" do
      assert_equal "+2#{number}", CoachApp::PhoneNumber.normalize(number, "EG")
    end
  end

  # Stricter than Node on purpose: Node's small phone data accepts these, and a code could
  # never reach them. Real Egyptian mobiles matched Node 720 out of 720 when compared.
  [
    [ "01612345678", "an unassigned prefix" ],
    [ "0101234567", "one digit short" ]
  ].each do |number, reason|
    test "an impossible Egyptian mobile is refused: #{reason}" do
      assert_nil CoachApp::PhoneNumber.normalize(number, "EG")
    end
  end

  test "input that is not a usable string is nil rather than an error" do
    [ nil, 1012345678, [ "01012345678" ], { "a" => 1 }, "", "   ", "\xFF\xFE", "0101234\u00005678" ].each do |input|
      assert_nil CoachApp::PhoneNumber.normalize(input, "EG"), "expected nil for #{input.inspect}"
    end
  end

  test "ascii_digits converts Arabic-Indic and Eastern Arabic digits and leaves the rest" do
    assert_equal "0123456789", CoachApp::PhoneNumber.ascii_digits("٠١٢٣٤٥٦٧٨٩")
    assert_equal "0123456789", CoachApp::PhoneNumber.ascii_digits("۰۱۲۳۴۵۶۷۸۹")
    assert_equal "+20 ab", CoachApp::PhoneNumber.ascii_digits("+٢٠ ab")
  end
end
