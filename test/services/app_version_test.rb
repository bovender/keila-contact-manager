require "test_helper"

class AppVersionTest < ActiveSupport::TestCase
  test "a deployed app reads its version from the environment" do
    sha = "0123456789abcdef0123456789abcdef01234567"
    with_env("KAMAL_VERSION" => sha, "GIT_COMMIT_TIMESTAMP" => "2026-10-06T09:15:00+02:00") do
      assert_equal sha, AppVersion.commit_sha
      assert_equal "0123456", AppVersion.short_sha
      assert_equal Time.utc(2026, 10, 6, 7, 15), AppVersion.commit_time
      assert_equal "https://github.com/bovender/keila-contact-manager/commit/#{sha}", AppVersion.commit_url
    end
  end

  test "an unparseable timestamp is left out" do
    with_env("GIT_COMMIT_TIMESTAMP" => "yesterday") do
      assert_nil AppVersion.commit_time
    end
  end
end
