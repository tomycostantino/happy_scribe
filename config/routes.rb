Rails.application.routes.draw do
  resources :chats, only: %i[index new create show] do
    resources :messages, only: [ :create ]
  end
  resources :models, only: [ :index, :show ] do
    collection do
      post :refresh
    end
  end
  resource :session
  resources :passwords, param: :token

  resources :contacts

  namespace :happy_scribe do
    resources :imports, only: %i[index create]
  end

  resources :meetings, only: %i[index show new create destroy] do
    resources :follow_up_emails, only: %i[show]
    resources :participants, controller: "meeting_participants", only: %i[create update destroy]
    resources :chats, controller: "meeting_chats", only: %i[index create show] do
      resources :messages, controller: "meeting_messages", only: [ :create ]
    end
  end

  get "up" => "rails/health#show", as: :rails_health_check

  root "meetings#index"
end
