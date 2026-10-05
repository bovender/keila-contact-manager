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

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    def with_keila_url(url)
      original = Rails.configuration.x.keila_url
      Rails.configuration.x.keila_url = url
      yield
    ensure
      Rails.configuration.x.keila_url = original
    end
  end
end
