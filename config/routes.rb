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
    put "me/email", to: "me#update_email"
    post "devices", to: "devices#create"
    delete "devices/:token", to: "devices#destroy", constraints: { token: /[^\/]+/ }
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
    post "questionnaire/questions/bulk", to: "questionnaire#bulk"
    post "questionnaire/import", to: "questionnaire_imports#create"
    patch "questionnaire/questions/:id", to: "questionnaire#update"
    delete "questionnaire/questions/:id", to: "questionnaire#destroy"
    get "clients", to: "clients#index"
    post "clients/mark-seen", to: "clients#mark_seen"
    get "clients/:id", to: "clients#show"
    get "portion-sizes", to: "portion_sizes#show"
    put "portion-sizes", to: "portion_sizes#update"
    get "foods", to: "foods#index"
    post "foods", to: "foods#create"
    patch "foods/:id", to: "foods#update"
    delete "foods/:id", to: "foods#destroy"
    get "subscriptions/:subscription_id/plan", to: "plans#show"
    put "subscriptions/:subscription_id/plan/draft", to: "plans#save_draft"
    post "subscriptions/:subscription_id/plan/publish", to: "plans#publish"
    post "subscriptions/:subscription_id/plan/import", to: "plan_imports#create"
    get "reviews", to: "reviews#index"
    get "reviews/photos/:id", to: "reviews#photo"
    get "earnings", to: "earnings#show"
    get "conversations", to: "conversations#index"
    get "conversations/:id/messages", to: "conversations#messages"
    post "conversations/:id/messages", to: "conversations#send_message"
    post "conversations/:id/photo", to: "conversations#send_photo"
    get "clients/:id/answers/:question_id/photo", to: "clients#answer_photo"
    get "conversations/:id/messages/:message_id/photo", to: "conversations#photo"
    post "conversations/:id/read", to: "conversations#read"
    get "notifications/unread-count", to: "notifications#unread_count"
  end

  # Admin panel (server-rendered, session-authed): module `admin`, path `/admin`.
  scope path: "admin", module: "admin", as: "admin" do
    get "login", to: "sessions#new", as: :login
    post "login", to: "sessions#create"
    delete "logout", to: "sessions#destroy", as: :logout
    get "", to: "coaches#index", as: :root
    get "coaches/:id", to: "coaches#show", as: :coach
    get "coaches/:id/documents/:document_id", to: "coaches#document", as: :coach_document
    post "coaches/:id/approve", to: "coaches#approve", as: :approve_coach
    post "coaches/:id/request-changes", to: "coaches#request_changes", as: :request_changes_coach
    post "coaches/:id/reject", to: "coaches#reject", as: :reject_coach
    post "coaches/:id/suspend", to: "coaches#suspend", as: :suspend_coach
    post "coaches/:id/reactivate", to: "coaches#reactivate", as: :reactivate_coach
    post "coaches/:id/deactivate", to: "coaches#deactivate", as: :deactivate_coach
    get "reviews", to: "reviews#index", as: :reviews
    get "reviews/:id", to: "reviews#show", as: :review
    get "reviews/:id/photos/:photo_id", to: "reviews#photo", as: :review_photo
    post "reviews/:id/approve", to: "reviews#approve", as: :approve_review
    post "reviews/:id/reject", to: "reviews#reject", as: :reject_review
  end

  # Last, so every unknown path gets a 404 in the API's envelope.
  match "/", to: "application#route_not_found", via: :all
  match "*path", to: "application#route_not_found", via: :all, format: false
end
