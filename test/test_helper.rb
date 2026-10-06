ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"
require_relative "test_helpers/session_test_helper"
require_relative "test_helpers/fake_keila"

require "webmock/minitest"
# allow_localhost covers Capybara/Selenium's own WebDriver traffic (system
# tests talk to a real remote browser over real HTTP); every other
# request -- notably to the Keila API -- must be stubbed explicitly.
WebMock.disable_net_connect!(allow_localhost: true)

OmniAuth.config.test_mode = true

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    OIDC_TEST_CONFIG = {
      issuer: "https://sso.example.com/realms/test", client_id: "kcm", client_secret: "secret",
      redirect_uri: "http://www.example.com/auth/oidc/callback", provider_name: "Example SSO", required_group: nil
    }.freeze

    def with_oidc(**overrides)
      original = Rails.configuration.x.oidc
      Rails.configuration.x.oidc = OIDC_TEST_CONFIG.merge(overrides)
      yield
    ensure
      Rails.configuration.x.oidc = original
    end

    def with_keila_url(url)
      original = Rails.configuration.x.keila_url
      Rails.configuration.x.keila_url = url
      yield
    ensure
      Rails.configuration.x.keila_url = original
    end

    def with_env(vars)
      originals = vars.keys.index_with { |key| ENV[key] }
      vars.each { |key, value| ENV[key] = value }
      yield
    ensure
      originals.each { |key, value| ENV[key] = value }
    end
  end
end
