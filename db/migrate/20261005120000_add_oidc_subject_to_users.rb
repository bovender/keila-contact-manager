class AddOidcSubjectToUsers < ActiveRecord::Migration[8.1]
  def change
    # The identity provider's stable user id (`sub`), so a user signing in
    # via single sign-on stays the same user even if their email changes.
    add_column :users, :oidc_subject, :string
    add_index :users, :oidc_subject, unique: true
  end
end
