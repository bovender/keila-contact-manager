class User < ApplicationRecord
  has_secure_password
  has_many :sessions, dependent: :destroy
  belongs_to :current_keila_project, class_name: "KeilaProject", optional: true, inverse_of: :users_with_this_active

  normalizes :email_address, with: ->(e) { e.strip.downcase }
end
