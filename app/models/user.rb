class User < ApplicationRecord
  has_secure_password
  has_many :sessions, dependent: :destroy
  belongs_to :current_keila_project, class_name: "KeilaProject", optional: true, inverse_of: :users_with_this_active

  normalizes :email_address, with: ->(e) { e.strip.downcase }

  # The user signing in via single sign-on, created on first sign-in. Who
  # may sign in at all is up to the identity provider (and
  # OIDC_REQUIRED_GROUP). A user who existed before SSO was switched on is
  # matched by email once and by the provider's subject id from then on.
  def self.from_oidc(auth)
    email = auth.info.email.to_s
    user = find_by(oidc_subject: auth.uid) || find_by(email_address: email.strip.downcase) ||
           new(email_address: email, password: SecureRandom.base58(32))
    user.update!(oidc_subject: auth.uid, email_address: email)
    user
  end
end
