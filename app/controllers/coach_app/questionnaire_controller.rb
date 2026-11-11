module CoachApp
  class QuestionnaireController < BaseController
    def index
      render_success({ questions: Questions.list(current_coach).map { |q| QuestionJson.call(q) } })
    end

    def create
      render_success(QuestionJson.call(Questions.create!(current_coach, params)), status: :created)
    end

    def update
      render_success(QuestionJson.call(Questions.update!(current_coach, params[:id], params)))
    end

    def destroy
      Questions.archive!(current_coach, params[:id])
      render_success({})
    end
  end
end
