Rails.application.routes.draw do
  get "/health", to: "health#show"

  scope path: "coach", module: "coach_app" do
    post "auth/signup/request-otp", to: "signups#request_otp"
    post "auth/signup/verify", to: "signups#verify"
  end

  # Last, so every unknown path gets a 404 in the API's envelope.
  match "/", to: "application#route_not_found", via: :all
  match "*path", to: "application#route_not_found", via: :all, format: false
end
