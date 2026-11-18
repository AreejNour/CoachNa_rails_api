module CoachApp
  class PlansController < BaseController
    def show
      render_success({ plan: Plans.show(current_coach, params[:subscription_id]) })
    end

    def save_draft
      render_success({ plan: Plans.save_draft!(current_coach, params[:subscription_id], params) })
    end

    def publish
      render_success({ plan: Plans.publish!(current_coach, params[:subscription_id], params) })
    end
  end
end
