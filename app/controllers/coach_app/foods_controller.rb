module CoachApp
  class FoodsController < BaseController
    def index
      render_success({ foods: Foods.list(current_coach).map { |f| FoodJson.call(f) } })
    end

    def create
      render_success(FoodJson.call(Foods.create_custom!(current_coach, params)), status: :created)
    end

    def update
      render_success(FoodJson.call(Foods.update_custom!(current_coach, params[:id], params)))
    end

    def destroy
      Foods.soft_delete!(current_coach, params[:id])
      render_success({})
    end
  end
end
