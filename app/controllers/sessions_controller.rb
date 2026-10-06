class SessionsController < ApplicationController
  allow_unauthenticated_access only: %i[ new create oidc_callback oidc_failure ]
  rate_limit to: 10, within: 3.minutes, only: :create, with: -> { redirect_to new_session_path, alert: "Try again later." }
  before_action :refuse_password_login, only: :create, if: :oidc_enabled?

  def new
  end

  def create
    if user = User.authenticate_by(params.permit(:email_address, :password))
      start_new_session_for user
      redirect_to after_authentication_url
    else
      redirect_to new_session_path, alert: "Try another email address or password."
    end
  end

  # OmniAuth has done the OpenID Connect exchange by the time this runs.
  def oidc_callback
    auth = request.env["omniauth.auth"]
    unless oidc_enabled? && auth && auth.info.email.present?
      redirect_to new_session_path, alert: "Single sign-on didn't provide an email address."
      return
    end
    if (group = oidc_config[:required_group]) && Array(auth.extra&.raw_info&.dig("groups")).exclude?(group)
      redirect_to new_session_path, alert: "Your account isn't allowed to use this app."
      return
    end

    start_new_session_for User.from_oidc(auth)
    session[:oidc_id_token] = auth.credentials&.id_token
    redirect_to after_authentication_url
  end

  def oidc_failure
    redirect_to new_session_path, alert: "Single sign-on failed: #{params[:message].to_s.humanize}."
  end

  def destroy
    id_token = session.delete(:oidc_id_token)
    terminate_session

    if oidc_enabled? && (logout_url = oidc_logout_url(id_token))
      redirect_to logout_url, allow_other_host: true, status: :see_other
    elsif oidc_enabled?
      # The notice also keeps the sign-in page from going straight back to
      # the identity provider, whose session is still active.
      redirect_to new_session_path, status: :see_other,
        notice: "Signed out here, but you're still signed in with #{oidc_config[:provider_name]}."
    else
      redirect_to new_session_path, status: :see_other
    end
  end

  private

  def refuse_password_login
    redirect_to new_session_path, alert: "Please sign in with #{oidc_config[:provider_name]}."
  end

  # Signing out here also ends the identity provider's session, so the
  # next sign-in actually asks for credentials again.
  def oidc_logout_url(id_token)
    endpoint = Rails.cache.fetch([ "oidc-end-session-endpoint", oidc_config[:issuer] ], expires_in: 1.day) do
      OpenIDConnect::Discovery::Provider::Config.discover!(oidc_config[:issuer]).end_session_endpoint
    end
    return if endpoint.blank?

    query = { client_id: oidc_config[:client_id], post_logout_redirect_uri: new_session_url, id_token_hint: id_token }.compact
    "#{endpoint}?#{query.to_query}"
  rescue OpenIDConnect::Discovery::DiscoveryFailed, SocketError, SystemCallError => e
    Rails.logger.warn("OIDC logout endpoint discovery failed: #{e.message}")
    nil
  end
end
