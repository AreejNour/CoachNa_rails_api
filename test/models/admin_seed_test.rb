require "test_helper"

class AdminSeedTest < ActiveSupport::TestCase
  def with_env(email:, password:, name: nil)
    ENV["ADMIN_EMAIL"] = email
    ENV["ADMIN_PASSWORD"] = password
    ENV["ADMIN_NAME"] = name
    yield
  ensure
    ENV.delete("ADMIN_EMAIL")
    ENV.delete("ADMIN_PASSWORD")
    ENV.delete("ADMIN_NAME")
  end

  test "creates one admin from the env vars" do
    with_env(email: "team@coachna.app", password: "Secret123", name: "Team") do
      assert_difference -> { AdminUser.count }, 1 do
        admin = AdminUser.create_from_env!
        assert_equal "team@coachna.app", admin.email
      end
    end
  end

  test "refuses a duplicate email and creates nothing" do
    AdminUser.create!(email: "team@coachna.app", name: "T", password: "Secret123")
    with_env(email: "team@coachna.app", password: "Secret123") do
      assert_no_difference -> { AdminUser.count } do
        assert_raises(RuntimeError) { AdminUser.create_from_env! }
      end
    end
  end

  test "requires both env vars" do
    with_env(email: "team@coachna.app", password: "") do
      assert_raises(ArgumentError) { AdminUser.create_from_env! }
    end
  end
end
