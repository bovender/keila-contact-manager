class CustomFieldDefinition < ApplicationRecord
  validates :key, presence: true, uniqueness: true,
                   exclusion: { in: [ Contact::RESERVED_DATA_KEY ], message: "is reserved for internal use" }
  validates :label, presence: true

  before_validation :default_label_from_key, on: :create
  before_validation :assign_position, on: :create
  before_destroy :refuse_if_protected

  default_scope { order(:position) }

  # Finds or creates the definition for a custom data key encountered in
  # imported or manually entered contact data. Keeps the key's original
  # casing so it round-trips with Keila's Data JSON blob unchanged.
  def self.register!(key)
    key = key.to_s.strip
    return nil if key.blank? || key == Contact::RESERVED_DATA_KEY

    find_by(key: key) || create!(key: key)
  end

  # Tags gets its own dedicated UI (pills, filters, bulk tag/untag), so its
  # registry entry always exists and can't be removed -- called from
  # db/seeds.rb, which runs on every boot, so this is idempotent and also
  # covers upgrading an existing install.
  def self.ensure_tags_definition!
    definition = find_or_create_by!(key: Contact::TAGS_DATA_KEY) { |d| d.label = "Tags" }
    definition.update_column(:position, -1) unless definition.position == -1
    definition
  end

  def protected?
    key == Contact::TAGS_DATA_KEY
  end

  # Number of contacts whose data currently holds a value for this key.
  # Used to warn before permanently deleting the field's data.
  def contacts_count
    Contact.having_custom_field(key).count
  end

  private

  def refuse_if_protected
    return unless protected?

    errors.add(:base, "#{label} is a protected field and can't be removed")
    throw :abort
  end

  def default_label_from_key
    self.label = key.to_s.tr("_", " ").strip if label.blank?
  end

  def assign_position
    self.position = (CustomFieldDefinition.unscoped.maximum(:position) || -1) + 1
  end
end
