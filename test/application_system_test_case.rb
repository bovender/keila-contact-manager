require "test_helper"

class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  # The app server Capybara starts runs on its own thread with its own
  # database connection, which can't see another connection's
  # not-yet-committed transaction -- so the fixture data this test thread
  # sets up would be invisible to it under the default transactional
  # fixtures. Fall back to fixtures being inserted (and cleaned up) for
  # real instead.
  self.use_transactional_tests = false

  # This sandbox (and CI) has no local Chrome/chromedriver, so system
  # tests always run against a real, separately-hosted Chrome via
  # Selenium's remote WebDriver protocol -- either the selenium/
  # standalone-chrome container CI spins up as a service, or one you run
  # yourself locally (see README's "Running system tests" section).
  driven_by :selenium, using: :chrome, screen_size: [ 1400, 1400 ],
            options: { browser: :remote, url: ENV.fetch("SELENIUM_REMOTE_URL", "http://localhost:4444/wd/hub") }

  # The remote Chrome runs in its own container and can't reach the Rails
  # test server via 127.0.0.1 -- that's itself, not this host. Fix the
  # Capybara server to a known port and address it as
  # host.docker.internal, which resolves back to the Docker host from
  # inside a container started with
  # --add-host=host.docker.internal:host-gateway (see
  # .github/workflows/ci.yml and the README).
  Capybara.server_host = "0.0.0.0"
  Capybara.server_port = ENV.fetch("CAPYBARA_SERVER_PORT", 45678).to_i
  Capybara.app_host = ENV.fetch("CAPYBARA_APP_HOST") { "http://host.docker.internal:#{Capybara.server_port}" }

  # Every Capybara/Selenium command round-trips over HTTP to the remote
  # browser container, adding latency a local headless browser wouldn't
  # have. Give assertions more room to retry before giving up.
  Capybara.default_max_wait_time = 5

  # A real Selenium-driven browser has its own cookie jar, so the
  # integration-test sign_in_as trick (which only fakes a cookie inside
  # the Ruby process) doesn't authenticate it -- log in through the
  # actual form instead.
  #
  # The form submits via Turbo (an async fetch, not a normal full-page
  # POST), so click_on returns as soon as the click fires, before the
  # response -- and the session cookie it sets -- actually lands. Asserting
  # on post-login page content makes Capybara retry/wait for that instead
  # of racing ahead while still logged out.
  def sign_in_via_ui(user, password: "password")
    visit new_session_path
    fill_in "Enter your email address", with: user.email_address
    fill_in "Enter your password", with: password
    click_on "Sign in"
    assert_selector "h1", text: "Contacts"
  end

  # Capybara's native click_on/find(...).click, against this remote Chrome,
  # intermittently fails to register at all -- no error, the click simply
  # doesn't seem to reach the browser's event loop in time, leaving the
  # page unchanged. Dispatching the click as plain in-browser JavaScript
  # instead (a single round trip, no separate WebDriver Actions-API
  # click) has been reliable in comparison. Prefer this over click_on for
  # any click whose effect you then assert on.
  def js_click(...)
    execute_script("arguments[0].click()", find(...))
  end
end
