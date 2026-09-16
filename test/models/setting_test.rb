require "test_helper"

class SettingTest < ActiveSupport::TestCase
  test "instance memoizes a single settings row" do
    assert_difference "Setting.count", 1 do
      Setting.instance
    end
    assert_no_difference "Setting.count" do
      Setting.instance
    end
  end

  test "configured_for_sync? requires both a URL and an API key" do
    setting = Setting.new
    assert_not setting.configured_for_sync?

    setting.keila_url = "https://keila.example.com"
    assert_not setting.configured_for_sync?

    setting.keila_api_key = "secret"
    assert setting.configured_for_sync?
  end

  test "keila_api_key is stored encrypted" do
    setting = Setting.create!(keila_url: "https://keila.example.com", keila_api_key: "secret")
    raw = ActiveRecord::Base.connection.select_value(
      "SELECT keila_api_key FROM settings WHERE id = #{setting.id}"
    )
    assert_not_equal "secret", raw
    assert_equal "secret", setting.reload.keila_api_key
  end
end
