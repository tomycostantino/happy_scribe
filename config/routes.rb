Rails.application.routes.draw do
  resource :session
  resources :passwords, param: :token

  resources :meetings, only: %i[index show new create destroy]

  get "up" => "rails/health#show", as: :rails_health_check

  root "meetings#index"
end
