Rails.application.routes.draw do
  resource :session
  resources :passwords, param: :token

  resources :keila_projects do
    member do
      post :activate
      post :test_connection
    end
  end

  resources :custom_field_definitions, only: [ :index, :create, :update, :destroy ]

  resources :contacts do
    collection do
      get :import
      post :import, action: :do_import
      get :export
      post :bulk_update
      post :bulk_destroy
      get :sync_from_keila
      post :sync_from_keila, action: :do_sync_from_keila
      get :push_to_keila
      post :push_to_keila, action: :do_push_to_keila
    end
  end

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  root "contacts#index"
end
