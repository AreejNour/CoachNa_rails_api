module Admin
  # Base for the server-rendered admin panel: session auth + views + CSRF.
  # Intentionally NOT ApplicationController (that is ActionController::API, JSON-only).
  class BaseController < ActionController::Base
    layout "admin"
    helper ::AdminHelper
    protect_from_forgery with: :exception
    before_action :require_admin

    helper_method :current_admin

    private

    def current_admin
      return @current_admin if defined?(@current_admin)

      @current_admin = session[:admin_id] && AdminUser.find_by(id: session[:admin_id])
    end

    def require_admin
      redirect_to admin_login_path unless current_admin
    end
  end
end
