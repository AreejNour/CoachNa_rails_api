Rails.application.routes.draw do
  get "/health", to: "health#show"

  scope path: "coach", module: "coach_app" do
    get "auth/countries", to: "countries#index"
    post "auth/signup/request-otp", to: "signups#request_otp"
    post "auth/signup/check-otp", to: "signups#check_otp"
    post "auth/signup/verify", to: "signups#verify"
    post "auth/login", to: "sessions#login"
    post "auth/refresh", to: "sessions#refresh"
    post "auth/logout", to: "sessions#logout"
    get "me", to: "me#show"
    patch "profile", to: "profiles#update"
    get "profile/status", to: "review#status"
    post "profile/submit", to: "review#submit"
    post "profile/documents", to: "documents#create"
    delete "profile/documents/:id", to: "documents#destroy"
    get "profile/documents/:id/file", to: "documents#file"
    get "packages", to: "packages#index"
    post "packages", to: "packages#create"
    patch "packages/:id", to: "packages#update"
    delete "packages/:id", to: "packages#destroy"
    get "questionnaire", to: "questionnaire#index"
    post "questionnaire/questions", to: "questionnaire#create"
    patch "questionnaire/questions/:id", to: "questionnaire#update"
    delete "questionnaire/questions/:id", to: "questionnaire#destroy"
  end

  # Last, so every unknown path gets a 404 in the API's envelope.
  match "/", to: "application#route_not_found", via: :all
  match "*path", to: "application#route_not_found", via: :all, format: false
end
