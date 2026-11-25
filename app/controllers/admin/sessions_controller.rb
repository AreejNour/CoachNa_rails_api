module Admin
  class SessionsController < BaseController
    skip_before_action :require_admin, only: %i[new create]

    def new; end

    def create
      admin = AdminUser.find_by(email: params[:email].to_s.downcase.strip)
      if admin&.authenticate(params[:password].to_s)
        reset_session
        session[:admin_id] = admin.id
        redirect_to admin_root_path
      else
        flash.now[:alert] = "Wrong email or password."
        render :new
      end
    end

    def destroy
      reset_session
      redirect_to admin_login_path
    end
  end
end
