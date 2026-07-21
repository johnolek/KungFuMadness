Rails.application.routes.draw do
  # Local email inbox (development only): browse sent mail (magic links) here.
  mount LetterOpenerWeb::Engine, at: "/letter_opener" if Rails.env.development?

  # Registration: email-first, with an optional passkey
  get "sign-up", to: "registrations#new", as: :signup
  post "sign-up", to: "registrations#create"
  post "sign-up/options", to: "registrations#options", as: :signup_options
  post "sign-up/passkey", to: "registrations#create_passkey", as: :signup_passkey

  # Passkey (WebAuthn) sign in
  get "sign-in", to: "sessions#new", as: :login
  post "sign-in/options", to: "sessions#options", as: :login_options
  post "sign-in", to: "sessions#create"
  delete "sign-out", to: "sessions#destroy", as: :logout

  # Passwordless email sign-in / verification (magic link with a prefetch guard)
  post "sign-in/email", to: "email_sign_ins#create", as: :email_sign_in_request
  get "sign-in/email/:token", to: "email_sign_ins#show", as: :email_sign_in
  post "sign-in/email/:token", to: "email_sign_ins#confirm", as: :email_sign_in_confirm

  namespace :settings do
    resources :credentials, only: %i[index create destroy] do
      post :options, on: :collection
    end
  end

  # Roster + public fighter profiles (scouting).
  resources :fighters, only: %i[index show]

  # Standings: all-time XP leaders + most active this week (humans and bots).
  get "leaderboard", to: "leaderboard#show", as: :leaderboard

  # Challenge lifecycle: new/create commit the challenger's moves; show is the
  # opponent's blind respond page; accept resolves, decline rejects.
  resources :challenges, only: %i[new create show] do
    member do
      post :accept
      post :decline
    end
  end

  # Public playback for resolved fights.
  resources :fights, only: %i[show]

  # Web Push opt-in: register/refresh (POST) or drop (DELETE) the browser's
  # subscription for the current user, keyed by endpoint in the JSON body.
  post "push_subscriptions", to: "push_subscriptions#create"
  delete "push_subscriptions", to: "push_subscriptions#destroy"

  # Push preferences: how many challenges must be pending before a push fires.
  patch "push_settings", to: "push_settings#update"

  # Game preferences (bot challenges, spoiler shield).
  patch "preferences", to: "preferences#update"

  # Own-profile customization: portrait upload + short bio.
  patch "profile", to: "profiles#update"

  # PWA: dynamic manifest + service worker (the SW must be same-origin at root
  # scope to control the whole app). Rendered from app/views/pwa/*. The pinned
  # formats keep template lookup working when browsers send Accept headers
  # Rails treats as browser-generated (Chrome's manifest fetch otherwise
  # negotiates to :html and 500s on the missing template).
  get "manifest", to: "rails/pwa#manifest", as: :pwa_manifest, defaults: { format: :json }
  get "service-worker", to: "rails/pwa#service_worker", as: :pwa_service_worker, defaults: { format: :js }

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  get "up" => "rails/health#show", as: :rails_health_check

  # Defines the root path route ("/")
  root "dojo#show"
end
