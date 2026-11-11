# A question in a coach's questionnaire, on the Node-owned `questionnaire_questions` table.
# `type` is a plain column (the question type), not Rails STI — so inheritance is turned off.
class QuestionnaireQuestion < ApplicationRecord
  self.inheritance_column = nil

  belongs_to :questionnaire
end
