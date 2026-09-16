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

  test "test_connection reports success when Keila responds" do
    Setting.instance.update!(keila_url: "https://keila.example.com", keila_api_key: "secret")
    stub_request(:get, "https://keila.example.com/api/v1/contacts")
      .with(query: { "paginate[page]" => "0", "paginate[page_size]" => "1" })
      .to_return(status: 200, body: { data: [], meta: {} }.to_json)

    post test_connection_settings_path

    assert_redirected_to edit_settings_path
    assert_equal "Connected to Keila successfully.", flash[:notice]
  end

  test "test_connection reports failure when Keila is unreachable" do
    Setting.instance.update!(keila_url: "https://keila.example.com", keila_api_key: "secret")
    stub_request(:get, "https://keila.example.com/api/v1/contacts")
      .with(query: { "paginate[page]" => "0", "paginate[page_size]" => "1" })
      .to_return(status: 401, body: { error: "unauthorized" }.to_json)

    post test_connection_settings_path

    assert_redirected_to edit_settings_path
    assert_match(/Could not connect to Keila/, flash[:alert])
  end

  test "test_connection without settings configured reports the missing configuration" do
    post test_connection_settings_path

    assert_redirected_to edit_settings_path
    assert_match(/Add a Keila instance URL and API key/, flash[:alert])
  end
end
