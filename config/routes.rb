Rails.application.routes.draw do
  resources :chats do
    resources :messages, only: [ :create ]
  end
  resources :models, only: [ :index, :show ] do
    collection do
      post :refresh
    end
  end
  resource :session
  resources :passwords, param: :token

  resources :meetings, only: %i[index show new create destroy] do
    resources :chats, controller: "meeting_chats", only: %i[index create show] do
      resources :messages, controller: "meeting_messages", only: [ :create ]
    end
  end

  get "up" => "rails/health#show", as: :rails_health_check

  root "meetings#index"
end
