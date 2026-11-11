# A client's answer to one question, on the Node-owned `questionnaire_answers` table. Rails reads
# these to show a coach what their client answered.
class QuestionnaireAnswer < ApplicationRecord
  belongs_to :subscription
  belongs_to :questionnaire_question, foreign_key: :question_id, inverse_of: false
end
