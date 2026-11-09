# The `coach_documents` table is shared with the Node API, which serves profile photos to clients.
class CoachDocument < ApplicationRecord
  # The `type` column holds the kind of document, not a Ruby class.
  self.inheritance_column = nil

  REQUIRED_SINGLE = %w[profile_photo national_id_front national_id_back].freeze
  CERTIFICATE = "certificate".freeze
  TYPES = (REQUIRED_SINGLE + [ CERTIFICATE ]).freeze
  MAX_CERTIFICATES = 10

  belongs_to :coach
end
