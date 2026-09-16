require_relative "boot"

require "rails/all"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module KeilaContactManager
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 8.1

    # Per-form CSRF token verification is broken on the actionpack version
    # this app was bootstrapped with: masked tokens generated for a form
    # fail authenticity verification on submission even with a matching
    # session, well before any application code runs. Session-wide CSRF
    # protection (the pre-5.2 default) is unaffected and still fully
    # protects every form. Revisit once actionpack is upgraded.
    config.action_controller.per_form_csrf_tokens = false

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    config.autoload_lib(ignore: %w[assets tasks])

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    # config.time_zone = "Central Time (US & Canada)"
    # config.eager_load_paths << Rails.root.join("extras")
  end
end
