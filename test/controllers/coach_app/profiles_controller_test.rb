require "test_helper"

class CoachApp::ProfilesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @coach = Coach.create!(phone: "+201012345690", password_hash: "x", full_name: "Sara Adel", email: "sara@example.com")
  end

  def patch_profile(body = {}, token: CoachApp::AccessToken.sign(@coach.id), **fields)
    patch "/coach/profile", params: body.merge(fields), as: :json, headers: token ? { "Authorization" => "Bearer #{token}" } : {}
  end

  def returned = response.parsed_body["data"]["coach"]

  def assert_failure(status, message)
    assert_response status
    assert_equal({ "success" => false, "error" => message }, response.parsed_body)
  end

  test "updates every field and returns the camelCase coach" do
    patch_profile(
      fullName: "Sara A.", email: "new@example.com", bio: "Clinical nutritionist",
      specialties: %w[weight_loss womens_health], yearsExperience: 8
    )

    assert_response :ok
    assert_equal "Sara A.", returned["fullName"]
    assert_equal "new@example.com", returned["email"]
    assert_equal "Clinical nutritionist", returned["bio"]
    assert_equal %w[weight_loss womens_health], returned["specialties"]
    assert_equal 8, returned["yearsExperience"]
    @coach.reload
    assert_equal [ "Sara A.", "new@example.com", "Clinical nutritionist", %w[weight_loss womens_health], 8 ],
      [ @coach.full_name, @coach.email, @coach.bio, @coach.specialties, @coach.years_experience ]
  end

  test "the response never contains the password hash or commission" do
    patch_profile(bio: "Hi")

    assert_response :ok
    assert_no_match(/password|commission/i, response.body)
  end

  test "a partial update leaves other fields alone" do
    patch_profile(bio: "Hi")

    assert_response :ok
    @coach.reload
    assert_equal [ "Hi", "Sara Adel", "sara@example.com" ], [ @coach.bio, @coach.full_name, @coach.email ]
  end

  test "updated_at changes" do
    before = @coach.reload.updated_at
    travel 1.minute do
      patch_profile(bio: "Hi")
    end

    assert_operator @coach.reload.updated_at, :>, before
  end

  test "Arabic text is kept" do
    patch_profile(bio: "أخصائية تغذية", fullName: "سارة عادل")

    assert_equal "أخصائية تغذية", returned["bio"]
    assert_equal "سارة عادل", returned["fullName"]
  end

  test "bio and fullName are trimmed" do
    patch_profile(bio: "  Hi  ", fullName: "  Sara  ")

    assert_equal [ "Hi", "Sara" ], [ returned["bio"], returned["fullName"] ]
  end

  test "text fields that are blank, too long or not text are refused" do
    [
      { bio: "   " }, { bio: "" }, { bio: nil }, { bio: 5 }, { bio: "a" * 2001 }, { bio: "a\u0000b" },
      { fullName: "   " }, { fullName: nil }, { fullName: "a" * 101 }
    ].each do |body|
      patch_profile(body)

      assert_failure :bad_request, "validation failed"
    end
    assert_nil @coach.reload.bio
  end

  test "the longest allowed bio and name are accepted" do
    patch_profile(bio: "a" * 2000, fullName: "b" * 100)

    assert_response :ok
  end

  test "yearsExperience must be a whole number from 0 to 80" do
    [ -1, 81, 5.5, "5", nil, true, 2**40 ].each do |years|
      patch_profile(yearsExperience: years)

      assert_failure :bad_request, "validation failed"
    end
    [ 0, 80 ].each do |years|
      patch_profile(yearsExperience: years)

      assert_response :ok
      assert_equal years, returned["yearsExperience"]
    end
  end

  test "an unknown specialty and non-list values are refused" do
    [ %w[weight_loss flying], "weight_loss", 5, nil, [ 5 ], [ { a: 1 } ] ].each do |specialties|
      patch_profile(specialties: specialties)

      assert_failure :bad_request, "validation failed"
    end
    assert_equal [], @coach.reload.specialties
  end

  test "duplicate specialties are removed and an empty list is accepted" do
    patch_profile(specialties: %w[sports sports general])
    assert_equal %w[sports general], returned["specialties"]

    patch_profile(specialties: [])
    assert_response :ok
    assert_equal [], returned["specialties"]
  end

  test "a bad or empty email is refused" do
    [ "not-an-email", "", nil, 5 ].each do |email|
      patch_profile(email: email)

      assert_failure :bad_request, "validation failed"
    end
  end

  test "a taken email is 409, and keeping your own is fine" do
    Coach.create!(phone: "+201012345691", password_hash: "x", full_name: "Other", email: "taken@example.com")

    patch_profile(email: "taken@example.com")
    assert_failure :conflict, "email already registered"

    patch_profile(email: "sara@example.com")
    assert_response :ok
  end

  test "an empty body is refused" do
    patch_profile({})

    assert_failure :bad_request, "validation failed"
  end

  test "a body with only protected fields is refused and changes nothing" do
    patch_profile(status: "approved", commissionPercent: 1, averageRating: 5, phone: "+201000000000")

    assert_failure :bad_request, "validation failed"
    @coach.reload
    assert_equal [ "incomplete", nil, nil, "+201012345690" ], [ @coach.status, @coach.commission_percent, @coach.average_rating, @coach.phone ]
  end

  test "protected fields beside a real change are ignored" do
    patch_profile(bio: "Hi", status: "approved", commissionPercent: 1, passwordHash: "stolen", reviewCount: 99)

    assert_response :ok
    @coach.reload
    assert_equal [ "Hi", "incomplete", nil, "x", 0 ], [ @coach.bio, @coach.status, @coach.commission_percent, @coach.password_hash, @coach.review_count ]
  end

  %w[pending_review approved suspended deactivated].each do |status|
    test "a coach who is #{status} can't edit" do
      @coach.update!(status: status)
      patch_profile(bio: "Hi")

      assert_failure :conflict, "profile not editable in current state"
      assert_nil @coach.reload.bio
    end
  end

  %w[incomplete rejected].each do |status|
    test "a coach who is #{status} can edit" do
      @coach.update!(status: status)
      patch_profile(bio: "Hi")

      assert_response :ok
    end
  end

  test "no token is 401" do
    patch_profile({ bio: "Hi" }, token: nil)

    assert_failure :unauthorized, "unauthorized"
  end

  test "another coach's profile can't be touched" do
    other = Coach.create!(phone: "+201012345692", password_hash: "x", full_name: "Other")
    patch_profile({ bio: "Mine" }, token: CoachApp::AccessToken.sign(other.id))

    assert_response :ok
    assert_nil @coach.reload.bio
    assert_equal "Mine", other.reload.bio
  end
end
