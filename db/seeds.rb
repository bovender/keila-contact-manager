# This file should ensure the existence of records required to run the application in every environment (production,
# development, test). The code here should be idempotent so that it can be executed at any point in every environment.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).

# This is a single/small-team tool: create the initial user from environment
# variables so a fresh self-hosted install can log in right away. Safe to
# re-run; it only acts when no user exists yet.
if User.none?
  email = ENV.fetch("ADMIN_EMAIL", "admin@example.com")
  password = ENV.fetch("ADMIN_PASSWORD", nil)

  if password.blank?
    warn "Skipping admin user creation: set ADMIN_EMAIL and ADMIN_PASSWORD to create the first login."
  else
    User.create!(email_address: email, password: password)
    puts "Created initial user #{email}"
  end
end
