class KeilaProject < ApplicationRecord
  encrypts :keila_api_key

  has_many :contacts, dependent: :restrict_with_error
  has_many :users_with_this_active, class_name: "User", foreign_key: :current_keila_project_id, dependent: :nullify, inverse_of: :current_keila_project

  validates :name, presence: true, uniqueness: true
  validates :keila_url, format: { with: URI::DEFAULT_PARSER.make_regexp(%w[http https]), allow_blank: true }

  def configured_for_sync?
    keila_url.present? && keila_api_key.present?
  end
end
