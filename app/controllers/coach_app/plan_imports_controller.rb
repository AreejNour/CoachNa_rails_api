module CoachApp
  class PlanImportsController < BaseController
    def create
      result = PlanImport.call(
        current_coach, params[:subscription_id], params[:pdf],
        replace: params[:replaceDraft].to_s == "true"
      )
      render_success({ plan: result[:plan], flagCount: result[:flag_count] }, status: :created)
    end
  end
end
