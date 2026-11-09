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

  test "an Egyptian number written without the leading 0 is valid" do
    assert_equal "+201001234567", CoachApp::PhoneNumber.normalize("1001234567", "EG")
  end

  # Other countries use the country's general pattern, because the full check refused
  # nearly half of the foreign numbers Node accepts.
  [
    [ "93873684", "KW", "+96593873684" ],
    [ "0769206663", "JO", "+962769206663" ],
    [ "0590721725", "AE", "+971590721725" ],
    [ "0523067910", "SA", "+966523067910" ]
  ].each do |number, country, expected|
    test "a foreign number Node accepts is accepted: #{number} #{country}" do
      assert_equal expected, CoachApp::PhoneNumber.normalize(number, country)
    end
  end

  [ [ "12", "KW" ], [ "123", "SA" ], [ "01012345678", "SA" ] ].each do |number, country|
    test "an impossible foreign number is refused: #{number} #{country}" do
      assert_nil CoachApp::PhoneNumber.normalize(number, country)
    end
  end

  test "Egypt's strict check still applies when another country is selected" do
    assert_nil CoachApp::PhoneNumber.normalize("+201612345678", "SA")
  end

  test "countries lists codes with their calling codes, sorted" do
    countries = CoachApp::PhoneNumber.countries

    assert_includes countries, { country: "EG", callingCode: "20" }
    assert_includes countries, { country: "SA", callingCode: "966" }
    assert_equal countries.map { |c| c[:country] }.sort, countries.map { |c| c[:country] }
    assert(countries.all? { |c| c[:country].match?(/\A[A-Z]{2}\z/) && c[:callingCode].match?(/\A\d+\z/) })
  end

  test "every listed country is accepted" do
    CoachApp::PhoneNumber.countries.each do |country|
      assert_equal country[:country], CoachApp::Input.country(country[:country])
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
