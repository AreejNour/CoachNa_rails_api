# The `coach_packages` table is shared with the Node API, which reads active packages into the
# client app's coach-detail response. Rails owns create/edit/remove.
class CoachPackage < ApplicationRecord
  belongs_to :coach
end
