Rails.application.routes.draw do
  get "/health", to: "health#show"

  scope path: "coach", module: "coach_app" do
    post "auth/signup/request-otp", to: "signups#request_otp"
    post "auth/signup/verify", to: "signups#verify"
    post "auth/login", to: "sessions#login"
    post "auth/refresh", to: "sessions#refresh"
    post "auth/logout", to: "sessions#logout"
    get "me", to: "me#show"
  end

  # Last, so every unknown path gets a 404 in the API's envelope.
  match "/", to: "application#route_not_found", via: :all
  match "*path", to: "application#route_not_found", via: :all, format: false
end
