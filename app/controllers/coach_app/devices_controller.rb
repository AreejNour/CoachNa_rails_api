module CoachApp
  class DevicesController < BaseController
    PLATFORMS = %w[ios android].freeze
    LANGUAGES = %w[ar en].freeze

    def create
      token = Input.trimmed(params[:token], max: 512)
      platform = params[:platform]
      language = params[:language]
      Input.invalid! unless PLATFORMS.include?(platform) && LANGUAGES.include?(language)

      DeviceToken.upsert(
        { owner_type: "coach", owner_id: current_coach.id, token: token, platform: platform, language: language,
          last_seen_at: Time.current },
        unique_by: :token
      )
      render_success({})
    end

    def destroy
      DeviceToken.where(token: params[:token], owner_type: "coach", owner_id: current_coach.id).delete_all
      render_success({})
    end
  end
end
