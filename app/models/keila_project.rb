# One project in the Keila instance this app is bound to (KEILA_URL).
# Keila scopes every API key to a single project and has no API for
# listing projects, so a project here is identified by that key alone; its
# name is just a local label.
class KeilaProject < ApplicationRecord
  encrypts :keila_api_key

  # Removing a project here only forgets the local copy -- nothing is
  # deleted in Keila, so contacts are removed without leaving tombstones
  # (see Contact#record_deletion) that a later sync would act on.
  has_many :contacts, dependent: :delete_all
  has_many :contact_deletions, dependent: :delete_all
  has_many :custom_field_definitions, dependent: :delete_all
  has_many :users_with_this_active, class_name: "User", foreign_key: :current_keila_project_id, dependent: :nullify, inverse_of: :current_keila_project

  validates :name, presence: true, uniqueness: true
  validates :keila_api_key, presence: true

  after_create { custom_field_definitions.ensure_tags_definition! }

  def self.keila_url
    Rails.configuration.x.keila_url
  end

  def configured_for_sync?
    self.class.keila_url.present? && keila_api_key.present?
  end

  def synced?
    last_synced_at.present?
  end
end
