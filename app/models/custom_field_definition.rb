class CustomFieldDefinition < ApplicationRecord
  validates :key, presence: true, uniqueness: true
  validates :label, presence: true

  before_validation :default_label_from_key, on: :create
  before_validation :assign_position, on: :create

  default_scope { order(:position) }

  # Finds or creates the definition for a custom data key encountered in
  # imported or manually entered contact data. Keeps the key's original
  # casing so it round-trips with Keila's Data JSON blob unchanged.
  def self.register!(key)
    key = key.to_s.strip
    return nil if key.blank?

    find_by(key: key) || create!(key: key)
  end

  private

  def default_label_from_key
    self.label = key.to_s.tr("_", " ").strip if label.blank?
  end

  def assign_position
    self.position = (CustomFieldDefinition.unscoped.maximum(:position) || -1) + 1
  end
end
