# The `questionnaires` table is shared with the Node API, which reads a coach's questions into the
# client app's questionnaire. Rails owns building and editing the questions; there is one per coach.
class Questionnaire < ApplicationRecord
  belongs_to :coach
  has_many :questionnaire_questions
end
