require "test_helper"

class SessionsControllerTest < ActionDispatch::IntegrationTest
  setup { @user = User.take }

  test "new" do
    get new_session_path
    assert_response :success
  end

  test "create with valid credentials" do
    post session_path, params: { email_address: @user.email_address, password: "password" }

    assert_redirected_to root_path
    assert cookies[:session_id]
  end

  test "create with invalid credentials" do
    post session_path, params: { email_address: @user.email_address, password: "wrong" }

    assert_redirected_to new_session_path
    assert_nil cookies[:session_id]
  end

  test "destroy" do
    sign_in_as(User.take)

    delete session_path

    assert_redirected_to new_session_path
    assert_empty cookies[:session_id]
  end
end

class SessionsControllerOidcTest < ActionDispatch::IntegrationTest
  def mock_oidc(email: "sso@example.com", uid: "sub-123", groups: [ "kcm" ])
    OmniAuth.config.mock_auth[:oidc] = OmniAuth::AuthHash.new(
      provider: "oidc", uid: uid,
      info: { email: email },
      credentials: { id_token: "id-token" },
      extra: { raw_info: { "groups" => groups } }
    )
  end

  def sign_in_via_sso
    post "/auth/oidc"
    follow_redirect! # OmniAuth test mode: straight to the callback
  end

  teardown { OmniAuth.config.mock_auth[:oidc] = nil }

  test "the sign-in page offers only single sign-on" do
    with_oidc do
      get new_session_path
      assert_match "Sign in with Example SSO", response.body
      assert_no_match "Enter your password", response.body
    end
  end

  test "password login and reset are refused" do
    with_oidc do
      post session_path, params: { email_address: users(:one).email_address, password: "password" }
      assert_redirected_to new_session_path
      assert_nil cookies[:session_id]

      get new_password_path
      assert_redirected_to new_session_path
    end
  end

  test "first sign-in creates the user, later ones find it by subject" do
    mock_oidc
    with_oidc do
      assert_difference "User.count", 1 do
        sign_in_via_sso
      end
      assert_redirected_to root_path
      assert cookies[:session_id].present?

      mock_oidc(email: "renamed@example.com")
      assert_no_difference "User.count" do
        sign_in_via_sso
      end
      assert_equal "renamed@example.com", User.find_by!(oidc_subject: "sub-123").email_address
    end
  end

  test "an existing user is matched by email on their first SSO sign-in" do
    mock_oidc(email: users(:one).email_address.upcase)
    with_oidc do
      assert_no_difference "User.count" do
        sign_in_via_sso
      end
      assert_equal "sub-123", users(:one).reload.oidc_subject
    end
  end

  test "OIDC_REQUIRED_GROUP keeps out users without that group" do
    mock_oidc(groups: [ "other" ])
    with_oidc(required_group: "kcm") do
      assert_no_difference "User.count" do
        sign_in_via_sso
      end
      assert_redirected_to new_session_path
      assert_match(/isn't allowed/, flash[:alert])
    end
  end

  test "the callback does nothing while SSO is off" do
    mock_oidc
    assert_no_difference "User.count" do
      sign_in_via_sso
    end
    assert_redirected_to new_session_path
  end

  test "signing out also ends the identity provider's session" do
    stub_request(:get, "https://sso.example.com/realms/test/.well-known/openid-configuration")
      .to_return(status: 200, headers: { "Content-Type" => "application/json" }, body: {
        issuer: "https://sso.example.com/realms/test",
        authorization_endpoint: "https://sso.example.com/realms/test/auth",
        token_endpoint: "https://sso.example.com/realms/test/token",
        jwks_uri: "https://sso.example.com/realms/test/certs",
        end_session_endpoint: "https://sso.example.com/realms/test/logout",
        response_types_supported: [ "code" ], subject_types_supported: [ "public" ],
        id_token_signing_alg_values_supported: [ "RS256" ]
      }.to_json)
    mock_oidc
    with_oidc do
      sign_in_via_sso
      delete session_path

      assert_response :see_other
      location = URI(response.location)
      assert_equal "sso.example.com", location.host
      assert_equal "/realms/test/logout", location.path
      query = Rack::Utils.parse_query(location.query)
      assert_equal "id-token", query["id_token_hint"]
      assert_equal "http://www.example.com/session/new", query["post_logout_redirect_uri"]
    end
  end

  test "oidc_failure explains what went wrong" do
    get "/auth/failure", params: { message: "invalid_credentials" }

    assert_redirected_to new_session_path
    assert_match(/Invalid credentials/, flash[:alert])
  end
end
