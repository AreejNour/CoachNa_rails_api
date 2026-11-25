# The `admins` table is Rails-owned (the admin panel); it is not part of the Node API.
# Named AdminUser so the `Admin::` controller namespace does not collide with the model.
class AdminUser < ApplicationRecord
  self.table_name = "admins"

  has_secure_password

  before_validation :normalize_email

  validates :email, presence: true, uniqueness: { case_sensitive: false }
  validates :name, presence: true

  # Seed the first admin from env vars (wrapped by the `admin:create` rake task).
  def self.create_from_env!
    email = ENV["ADMIN_EMAIL"].to_s.strip
    password = ENV["ADMIN_PASSWORD"].to_s
    raise ArgumentError, "ADMIN_EMAIL and ADMIN_PASSWORD are required" if email.empty? || password.empty?
    raise "an admin with #{email} already exists" if exists?(email: email.downcase)

    create!(email: email, password: password, name: ENV["ADMIN_NAME"].presence || "Admin")
  end

  private

  def normalize_email
    self.email = email.to_s.downcase.strip if email
  end
end
