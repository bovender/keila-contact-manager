require "test_helper"

class SettingsControllerTest < ActionDispatch::IntegrationTest
  setup { sign_in_as(users(:one)) }

  test "edit shows the settings form" do
    get edit_settings_path
    assert_response :success
  end

  test "update saves the Keila URL and API key" do
    patch settings_path, params: { setting: { keila_url: "https://keila.example.com", keila_api_key: "secret" } }

    assert_redirected_to edit_settings_path
    assert Setting.instance.configured_for_sync?
  end

  test "update without a new api key keeps the existing one" do
    Setting.instance.update!(keila_url: "https://keila.example.com", keila_api_key: "secret")

    patch settings_path, params: { setting: { keila_url: "https://keila2.example.com", keila_api_key: "" } }

    assert_equal "secret", Setting.instance.keila_api_key
    assert_equal "https://keila2.example.com", Setting.instance.keila_url
  end
end
