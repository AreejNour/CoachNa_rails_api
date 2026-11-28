# The `coaches` table is shared with the Node API, whose migrations define it.
class Coach < ApplicationRecord
  EDITABLE_STATUSES = %w[incomplete].freeze
  SPECIALTIES = %w[weight_loss muscle_gain diabetes_friendly sports womens_health general].freeze

  GENDERS = %w[male female].freeze
  MIN_AGE = 18
  MIN_BIRTH_YEAR = 1900

  validates :gender, inclusion: { in: GENDERS }, allow_nil: true
  validate :date_of_birth_allowed

  has_many :coach_status_changes
  has_many :coach_documents
  has_many :coach_packages
  has_many :subscriptions
  has_many :coach_reviews
  has_many :foods, foreign_key: :owner_coach_id, inverse_of: :owner_coach
  has_one :questionnaire

  # Whole years old today; nil with no date of birth. A 29 Feb birthday counts from 1 Mar in other years.
  def age(today = Date.current) = self.class.age_on(date_of_birth, today)

  def self.age_on(date, today = Date.current)
    return nil if date.nil?

    today.year - date.year - ((today.month * 100 + today.day) < (date.month * 100 + date.day) ? 1 : 0)
  end

  # True for a real date, not in the future, from 1900, and at least 18 years old today.
  def self.date_of_birth_allowed?(date, today = Date.current)
    date.year >= MIN_BIRTH_YEAR && date <= today && age_on(date, today) >= MIN_AGE
  end

  private

  def date_of_birth_allowed
    return if date_of_birth.nil? || self.class.date_of_birth_allowed?(date_of_birth)

    errors.add(:date_of_birth, :invalid)
  end
end
