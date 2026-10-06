require "application_system_test_case"

class SingleSignOnTest < ApplicationSystemTestCase
  setup do
    OmniAuth.config.mock_auth[:oidc] = OmniAuth::AuthHash.new(
      provider: "oidc", uid: "sub-123", info: { email: users(:one).email_address },
      credentials: { id_token: "id-token" }, extra: { raw_info: { "groups" => [ "kcm" ] } }
    )
  end

  teardown { OmniAuth.config.mock_auth[:oidc] = nil }

  test "the sign-in page goes straight on to the identity provider" do
    with_oidc do
      visit contacts_path
      assert_selector "h1", text: "Contacts"
    end
  end

  test "the sign-in page stays put when sign-in was refused" do
    with_oidc(required_group: "admins") do
      visit contacts_path
      assert_text "Your account isn't allowed to use this app."
      assert_button "Sign in with Example SSO"
    end
  end
end
