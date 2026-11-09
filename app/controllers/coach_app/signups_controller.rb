module CoachApp
  class SignupsController < ApplicationController
    def request_otp
      render_success(Signup.request_otp(phone: params[:phone], country: params[:country]))
    end

    def check_otp
      render_success(Signup.check_code(phone: params[:phone], country: params[:country], code: params[:code]))
    end

    def verify
      data = Signup.verify(
        phone: params[:phone], country: params[:country], code: params[:code],
        password: params[:password], full_name: params[:fullName], email: params[:email]
      )
      render_success(data, status: :created)
    end
  end
end
