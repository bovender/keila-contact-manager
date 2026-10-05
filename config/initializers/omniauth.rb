# Optional single sign-on via OpenID Connect (e.g. Keycloak), switched on
# by setting OIDC_ISSUER. While it's on, it's the only way to sign in:
# password login and password reset are turned off.
#
#   OIDC_ISSUER          e.g. https://sso.example.com/realms/example
#   OIDC_CLIENT_ID       the confidential client registered for this app
#   OIDC_CLIENT_SECRET
#   APP_URL              this app's public URL; the client's redirect URI
#                        is APP_URL/auth/oidc/callback
#   OIDC_PROVIDER_NAME   label on the sign-in button (optional)
#   OIDC_REQUIRED_GROUP  only let in users whose `groups` claim has this
#                        group (optional; the identity provider may gate
#                        access itself)
if ENV["OIDC_ISSUER"].present?
  Rails.application.config.x.oidc = {
    issuer: ENV["OIDC_ISSUER"],
    client_id: ENV.fetch("OIDC_CLIENT_ID"),
    client_secret: ENV.fetch("OIDC_CLIENT_SECRET"),
    redirect_uri: "#{ENV.fetch('APP_URL').chomp('/')}/auth/oidc/callback",
    provider_name: ENV["OIDC_PROVIDER_NAME"].presence || "single sign-on",
    required_group: ENV["OIDC_REQUIRED_GROUP"].presence
  }
end

# Tests switch SSO on and off per test (see `with_oidc`) with OmniAuth's
# test mode, so the middleware is always there for them.
if (settings = Rails.application.config.x.oidc || (Rails.env.test? && { issuer: "https://sso.example.com", client_id: "kcm", client_secret: "secret", redirect_uri: "http://www.example.com/auth/oidc/callback" }))
  Rails.application.config.middleware.use OmniAuth::Builder do
    provider :openid_connect,
             name: :oidc,
             issuer: settings[:issuer],
             discovery: true,
             scope: %i[openid email profile],
             response_type: :code,
             pkce: true,
             client_options: {
               identifier: settings[:client_id],
               secret: settings[:client_secret],
               redirect_uri: settings[:redirect_uri]
             }
  end

  OmniAuth.config.logger = Rails.logger
end
