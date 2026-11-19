# frozen_string_literal: true

Rails.application.routes.draw do
  get '/access', to: 'distribution/network_access#index', as: :distribution_network_access
  patch '/access', to: 'distribution/network_access#update'
  get '/catalog', to: 'distribution/catalog#index'
  get '/public/icons/:id', to: 'distribution/catalog#icon', as: :distribution_public_icon
  root to: 'distribution/workspace#landing'
  get '/udid', to: 'distribution/udids#index', as: :distribution_udid
  get '/udid/qrcode', to: 'distribution/udids#qrcode', as: :distribution_udid_qrcode
  get '/udid/profile', to: 'distribution/udids#profile', as: :distribution_udid_profile
  post '/udid/receive/:token', to: 'distribution/udids#receive', as: :distribution_udid_receive
  get '/udid/result/:token', to: 'distribution/udids#result', as: :distribution_udid_result
  get '/dashboard', to: 'dashboards#index', as: :legacy_dashboard
  post '/developers/preview', to: 'distribution/developers#preview', as: :distribution_developer_preview
  post '/developers/bundle', to: 'distribution/developers#bundle', as: :distribution_developer_bundle
  get '/developers/skill.zip', to: 'distribution/developers#skill', as: :distribution_developer_skill
  get '/notifications', to: 'distribution/notifications#index', as: :distribution_notifications
  patch '/notifications', to: 'distribution/notifications#update'
  post '/notifications/test', to: 'distribution/notifications#test', as: :distribution_test_notification
  get '/developers', to: 'distribution/developers#index', as: :distribution_developer
  get '/workspace', to: 'distribution/workspace#index', as: :distribution_workspace
  get '/workspace/apps/:id/packages/:platform/:bundle_id', to: 'distribution/apps#package', as: :distribution_manage_package, constraints: {bundle_id: /[^\/]+/}, format: false
  get '/workspace/apps/:id', to: 'distribution/apps#show', as: :distribution_manage_app
  patch '/workspace/apps/:id', to: 'distribution/apps#update'
  delete '/workspace/apps/:id', to: 'distribution/apps#destroy'
  delete '/workspace/apps/:id/packages/:platform/:bundle_id', to: 'distribution/apps#destroy_package', constraints: {bundle_id: /[^\/]+/}, format: false
  get '/upload', to: 'distribution/uploads#new', as: :distribution_new_upload
  post '/workspace/inspect', to: 'distribution/uploads#inspect_package', as: :distribution_inspect
  post '/workspace/duplicate', to: 'distribution/uploads#check_duplicate', as: :distribution_duplicate
  post '/workspace/uploads', to: 'distribution/uploads#create', as: :distribution_upload
  patch '/workspace/versions/:id', to: 'distribution/versions#update', as: :distribution_version
  delete '/workspace/versions/:id', to: 'distribution/versions#destroy'
  post '/workspace/versions/:id/share', to: 'distribution/versions#share', as: :distribution_version_share
  post '/workspace/environments/:id/share', to: 'distribution/versions#environment_share', as: :distribution_environment_share
  get '/workspace/operations', to: 'distribution/operations#index', as: :distribution_operations
  get '/a/:id/qrcode', to: 'distribution/app_downloads#qrcode', as: :distribution_app_qrcode
  get '/a/:id/packages/:platform/:bundle_id(/:package_environment)/qrcode', to: 'distribution/app_downloads#package_qrcode', as: :distribution_package_qrcode, constraints: {bundle_id: /[^\/]+/, package_environment: /testing|production/}, format: false
  get '/a/:id/packages/:platform/:bundle_id(/:package_environment)', to: 'distribution/app_downloads#package', as: :distribution_package, constraints: {bundle_id: /[^\/]+/, package_environment: /testing|production/}, format: false
  get '/a/:id', to: 'distribution/app_downloads#show', as: :distribution_app
  get '/d/:id/qrcode', to: 'distribution/public#qrcode', as: :distribution_environment_qrcode
  get '/d/:id', to: 'distribution/public#environment', as: :distribution_environment

  #############################################
  # User
  #############################################
  devise_for :users, controllers: {
    sessions: 'users/sessions',
    registrations: 'users/registrations',
    confirmations: 'users/confirmations',
    omniauth_callbacks: 'users/omniauth_callbacks',
  }, skip: :unlocks

  #############################################
  # App
  #############################################
  resources :apps do
    member do
      get :new_owner
      put :update_owner
    end

    collection do
      resources :archives, only: %i[index update destroy], path: 'archived', module: :apps, as: 'archived_apps'
    end

    resources :collaborators, except: %i[index show]

    resources :schemes, except: %i[show] do
      resources :channels, except: %i[index show]
    end

    resources :debug_files, only: [] do
      collection do
        get ':device', action: :device, as: :device
      end
    end
  end

  resources :channels, only: %i[index show] do
    member do
      delete :destroy_releases
    end

    resources :web_hooks, only: %i[new create destroy] do
      member do
        get :enable
        get :disable
        get 'test/:event', to: 'web_hooks#test', as: :test
      end
    end

    resources :releases, path_names: { new: 'upload' } do
      scope module: :releases do
        get :install, to: 'install#show'
      end

      scope module: :releases do
        get :qrcode, to: 'qrcode#show'
      end

      member do
        post :auth
      end
    end

    scope module: :channels do
      resources :versions, only: %i[index show destroy], constraints: { id: /(.+)+/ }
      resources :branches, only: %i[index destroy], constraints: { id: /(.+)+/ }
      resources :release_types, only: %i[index destroy], constraints: { id: /(.+)+/ }
    end
  end

  #############################################
  # Debug File
  #############################################
  resources :debug_files do
    member do
      post :reprocess
    end
  end

  #############################################
  # Teardown
  #############################################
  resources :teardowns, except: %i[edit update], path_names: { new: 'upload' }

  #############################################
  # Download
  #############################################
  namespace :download do
    resources :releases, only: :show do
      member do
        get ':filename', action: :download, filename: /.+/, as: 'filename'
      end
    end

    resources :debug_files, only: :show do
      member do
        get ':filename', action: :download, filename: /.+/, as: 'filename'
      end
    end
  end

  #############################################
  # UDID (iOS/iPadOS/arm chip macOS)
  #############################################
  resources :udid, as: :udid, param: :udid, only: %i[ index show edit update ] do
    collection do
      get :qrcode
      get :install
      post :retrieve, action: :create
    end

    member do
      post :register
    end
  end

  #############################################
  # Admin
  #############################################
  authenticate :user, ->(user) { user.admin? } do
    namespace :admin do
      root to: 'settings#index'

      resources :settings
      resources :users, except: :show do
        member do
          put :lock
          put :resend_confirmation
          delete :unlock
        end
      end
      resources :web_hooks, except: %i[ show new create ]
      resources :apple_teams, only: %i[ edit update ]
      resources :background_jobs, only: :index
      resources :system_info, only: :index
      resources :database_analytics, only: :index
      resources :apple_keys, except: %i[ edit update ] do
        member do
          put :sync_devices
          get :private_key
        end
      end

      resources :logs, only: %i[ index ] do
        collection do
          get :retrive
        end
      end

      resources :backups do
        collection do
          get :parse_schedule
        end

        member do
          post :enable
          post :disable
          post :perform
          delete :job, action: :cancel_job
          get :archive, action: :download_archive
          delete :archive, action: :destroy_archive
        end
      end

      resources :services, only: [] do
        collection do
          # appdock service
          post :restart
          get :status
          # smtp
          post :smtp_verify
        end
      end

      mount GoodJob::Engine, at: 'jobs', as: :jobs
      mount PgHero::Engine, at: 'pghero', as: :pghero
    end
  end

  #############################################
  # Misc
  #############################################
  resources :modals, only: :show, param: :type, constraints: { type: /[a-z0-9\-_]+/ }

  #############################################
  # API v1
  #############################################
  health_check_routes

  namespace :api do
    resources :users, except: %i[new edit] do
      collection do
        get :me
        get :search
      end

      member do
        post :lock
        delete :unlock
      end
    end

    resources :apps, except: %i[new edit] do
      collection do
        post :upload, to: 'apps/upload#create'

        get :latest, to: 'apps/latest#show'
        get :version_exist, to: 'apps/version_exist#show'
        get :versions, to: 'apps/versions#index'
        get 'versions/(:release_version)', to: 'apps/versions#show'
      end

      resources :schemes, except: %i[new edit], shallow: true do
        resources :channels, except: %i[new edit]
      end

      resources :collaborators, param: :user_id, except: %i[index new edit]
    end
    resources :releases, only: %i[update destroy]

    resources :debug_files, except: %i[new edit create] do
      collection do
        post :upload, action: :create
        get :download, to: 'debug_files/download#show'

        get 'exists/version', to: 'debug_files/exists#version'
        get 'exists/binary', to: 'debug_files/exists#binary'
        get 'exists/uuid', to: 'debug_files/exists#uuid'
      end
    end

    resources :devices, only: %i[update]
    resources :version, only: :index

    if Setting.show_footer_openapi_endpoints
      mount Rswag::Api::Engine => '/swagger', as: :openapi
      mount Rswag::Ui::Engine => '/swagger', as: :openapi_ui
    end

    match '*unmatched_route', via: :all, to: 'base#raise_not_found', format: :json
  end

  #############################################
  # API v2
  #############################################
  post '/graphql', to: 'graphql#execute'

  #############################################
  # Development Only
  #############################################
  if Rails.env.development?
    mount LetterOpenerWeb::Engine, at: '/tools/inbox'
    mount GraphiQL::Rails::Engine, at: "/tools/graphiql", graphql_path: "/graphql"
  end

  ############################################
  # URL Friendly
  ############################################
  product_alias = ->(request) { App.active.exists?(distribution_slug: request.path_parameters[:product_slug]) }
  get '/:product_slug/:platform/:package_code(/:package_environment)/qrcode', to: 'distribution/app_downloads#package_alias_qrcode',
      as: :distribution_package_alias_qrcode, constraints: {platform: /[a-z0-9]+/, package_code: /p[0-9]+/, package_environment: /testing|production/}, format: false
  get '/:product_slug/:platform/:package_code(/:package_environment)', to: 'distribution/app_downloads#package_alias',
      as: :distribution_package_alias, constraints: {platform: /[a-z0-9]+/, package_code: /p[0-9]+/, package_environment: /testing|production/}, format: false
  get '/:product_slug/qrcode', to: 'distribution/app_downloads#product_alias_qrcode',
      as: :distribution_product_alias_qrcode, constraints: product_alias, format: false
  get '/:product_slug', to: 'distribution/app_downloads#product_alias',
      as: :distribution_product_alias, constraints: product_alias, format: false
  scope path: ':channel', format: false, as: :friendly_channel do
    get '/overview', to: 'channels#show'
    get '', to: 'releases#index', as: 'releases'
    get 'versions', to: 'channels/versions#index', as: 'versions'
    get 'versions/:name', to: 'channels/versions#show', name: /(.+)+/, as: 'version'
    delete 'versions/:name', to: 'channels/versions#destroy', name: /(.+)+/
    get 'release_types/:name', to: 'channels/release_types#index', name: /(.+)+/, as: 'release_types'
    delete 'release_types/:name', to: 'channels/release_types#destroy', name: /(.+)+/
    get 'branches/:name', to: 'channels/branches#index', name: /(.+)+/, as: 'branches'
    delete 'branches/:name', to: 'channels/branches#destroy', name: /(.+)+/
    get ':id', to: 'releases#show', as: 'release'
    # get ':id/download', to: 'download/releases#show', as: 'channel_release_download'
  end

  match '/', via: %i[post put patch delete], to: 'application#raise_not_found', format: false
  match '*unmatched_route', via: :all, to: 'application#raise_not_found', format: false
end
