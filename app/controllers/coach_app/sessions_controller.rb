module CoachApp
  class SessionsController < ApplicationController
    def login
      e164 = Input.phone(params[:phone], params[:country])
      password = Input.text(params[:password])
      coach = Coach.find_by(phone: e164)
      unless coach && Password.verify(password, coach.password_hash)
        raise ApiError.new(401, "invalid credentials")
      end

      render_success({
        coach: CoachJson.call(coach),
        accessToken: AccessToken.sign(coach.id),
        refreshToken: RefreshTokens.issue(coach.id)
      })
    end

    def refresh
      presented = Input.text(params[:refreshToken])
      # One transaction, so a failure while issuing the new token doesn't burn the old one.
      tokens = CoachRefreshToken.transaction do
        coach_id = RefreshTokens.rotate(presented) || raise(ApiError.new(401, "invalid refresh token"))
        { accessToken: AccessToken.sign(coach_id), refreshToken: RefreshTokens.issue(coach_id) }
      end
      render_success(tokens)
    end

    def logout
      RefreshTokens.revoke(Input.text(params[:refreshToken]))
      render_success({})
    end
  end
end
