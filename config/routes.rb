Rails.application.routes.draw do
  resources :chats do
    resources :messages, only: [:create]
  end
  resources :models, only: [:index, :show] do
    collection do
      post :refresh
    end
  end
  resource :session
  resources :passwords, param: :token

  resources :meetings, only: %i[index show new create destroy]

  get "up" => "rails/health#show", as: :rails_health_check

  root "meetings#index"
end
