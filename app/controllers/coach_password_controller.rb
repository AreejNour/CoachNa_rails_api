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

    password = params[:password]
    confirmation = params[:password_confirmation]
    unless password.is_a?(String) && confirmation.is_a?(String)
      return form_error("Enter and confirm your password.", "أدخل كلمة المرور وأكّدها.")
    end
    if password.include?("\0")
      return form_error("Password contains an invalid character.", "كلمة المرور تحتوي على رمز غير صالح.")
    end
    if password.length < CoachApp::Input::PASSWORD_MIN
      return form_error("Password must be at least #{CoachApp::Input::PASSWORD_MIN} characters.",
                        "يجب ألا تقل كلمة المرور عن #{CoachApp::Input::PASSWORD_MIN} أحرف.")
    end
    unless password == confirmation
      return form_error("Passwords do not match.", "كلمتا المرور غير متطابقتين.")
    end

    if Admin::CoachPasswordSetup.set_password!(params[:token], password, confirmation)
      render :done
    else
      render_expired
    end
  rescue ApiError
    form_error("Password is invalid.", "كلمة المرور غير صالحة.")
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
