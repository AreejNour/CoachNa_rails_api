module CoachApp
  class QuestionnaireImportsController < BaseController
    def create
      result = QuestionnaireImport.call(
        current_coach, file: params[:file], text: params[:text], language: params[:language]
      )
      render_success(result)
    end
  end
end
