# The public page a coach created by an admin uses to choose their own password. No admin
# session: the signed, expiring, single-use token in the URL is the credential.
class CoachPasswordController < ActionController::Base
  layout "coach_password"
  protect_from_forgery with: :exception
  before_action :no_store

  def edit
    @coach = Admin::CoachPasswordSetup.verify(params[:token])
    render_expired unless @coach
  end

  def update
    @coach = Admin::CoachPasswordSetup.verify(params[:token])
    return render_expired unless @coach

    password = params[:password].to_s
    if password.length < CoachApp::Input::PASSWORD_MIN
      return form_error("Password must be at least #{CoachApp::Input::PASSWORD_MIN} characters.",
                        "يجب ألا تقل كلمة المرور عن #{CoachApp::Input::PASSWORD_MIN} أحرف.")
    end
    unless password == params[:password_confirmation].to_s
      return form_error("Passwords do not match.", "كلمتا المرور غير متطابقتين.")
    end

    if Admin::CoachPasswordSetup.set_password!(params[:token], password, params[:password_confirmation].to_s)
      render :done
    else
      render_expired
    end
  end

  private

  def form_error(en, ar)
    @error_en = en
    @error_ar = ar
    render :edit, status: :unprocessable_entity
  end

  def render_expired
    render :expired, status: :gone
  end

  def no_store
    response.headers["Cache-Control"] = "no-store"
    response.headers["Referrer-Policy"] = "no-referrer"
  end
end
