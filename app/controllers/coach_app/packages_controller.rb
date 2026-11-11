module CoachApp
  class PackagesController < BaseController
    def index
      render_success(packages: Packages.list(current_coach).map { |p| PackageJson.call(p) })
    end

    def create
      render_success(PackageJson.call(Packages.create!(current_coach, params)), status: :created)
    end

    def update
      render_success(PackageJson.call(Packages.update!(current_coach, params[:id], params)))
    end

    def destroy
      Packages.soft_delete!(current_coach, params[:id])
      render_success({})
    end
  end
end
