require "test_helper"

class AdminTest < ActiveSupport::TestCase
  test "authenticates the right password and rejects a wrong one" do
    admin = AdminUser.create!(email: "a@b.co", name: "A", password: "Secret123")
    assert admin.authenticate("Secret123")
    assert_not admin.authenticate("wrong")
  end

  test "requires an email" do
    admin = AdminUser.new(name: "A", password: "Secret123")
    assert_not admin.valid?
    assert admin.errors[:email].any?
  end

  test "email is unique case-insensitively" do
    AdminUser.create!(email: "a@b.co", name: "A", password: "Secret123")
    dup = AdminUser.new(email: "A@B.co", name: "B", password: "Secret123")
    assert_not dup.valid?
  end

  test "stores a password digest, not the plaintext" do
    admin = AdminUser.create!(email: "c@d.co", name: "C", password: "Secret123")
    assert_not_equal "Secret123", admin.password_digest
    assert admin.password_digest.present?
  end
end
