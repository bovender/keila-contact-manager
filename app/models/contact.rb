class Contact < ApplicationRecord
  # Reserved Data key this app uses to smuggle its own permanent identifier
  # (the `uuid` column below) through Keila's Data JSON blob. It round-trips
  # on export/re-import so contacts can be re-matched even if their email
  # changes, without depending on Keila's optional External_id. It's
  # stripped from `data` on import (see KeilaCsv::Importer) so it never
  # shows up as an editable custom field.
  RESERVED_DATA_KEY = "Kcm_uid"

  # Keila itself has no concept of tags at all -- not in its schema, its own
  # CSV export, or its API. Tags here are just a Data key like any other
  # custom field (so they show up in Data when exported/pushed), but with
  # a permanent, non-deletable CustomFieldDefinition and dedicated UI
  # (pills, filters, bulk tag/untag) since they're central to how contacts
  # get organized in this app.
  TAGS_DATA_KEY = "Tags"

  belongs_to :keila_project

  before_validation { self.email = email.to_s.strip.downcase }
  before_validation(on: :create) { self.uuid ||= SecureRandom.uuid }

  # Scoped to keila_project, not global: the same email can legitimately
  # be a different person in a different Keila project (Keila itself
  # scopes its own uniqueness the same way, on (email, project_id)).
  validates :email, presence: true,
                     uniqueness: { scope: :keila_project_id, case_sensitive: false },
                     format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :uuid, presence: true, uniqueness: true

  scope :search, ->(term) {
    return all if term.blank?

    pattern = "%#{sanitize_sql_like(term)}%"
    where(
      "email LIKE :p OR first_name LIKE :p OR last_name LIKE :p OR external_id LIKE :p",
      p: pattern
    )
  }

  scope :tagged_with, ->(tag) {
    return all if tag.blank?

    where("EXISTS (SELECT 1 FROM json_each(contacts.data, ?) WHERE json_each.value = ?)", json_path_for(TAGS_DATA_KEY), tag)
  }

  scope :with_custom_field, ->(key, value) {
    return all if key.blank?

    where("json_extract(contacts.data, ?) = ?", json_path_for(key), value.to_s)
  }

  # Contacts whose data hash has this key present at all, regardless of
  # value. Used to warn before permanently deleting a custom field's data.
  scope :having_custom_field, ->(key) {
    return none if key.blank?

    where("json_type(contacts.data, ?) IS NOT NULL", json_path_for(key))
  }

  def self.json_path_for(key)
    %($."#{key.to_s.gsub('"', '\\"')}")
  end

  def full_name
    [ first_name, last_name ].reject(&:blank?).join(" ")
  end

  def tags
    data[TAGS_DATA_KEY] || []
  end

  def tags=(value)
    list = normalize_tags(value.is_a?(Array) ? value : Array(value))
    new_data = data.dup
    if list.empty?
      new_data.delete(TAGS_DATA_KEY)
    else
      new_data[TAGS_DATA_KEY] = list
    end
    self.data = new_data
  end

  def tag_list
    tags.join(", ")
  end

  # Accepts either a delimited string (from the contact form) or an array
  # (from CSV/API imports, where a "Tags" value may already be a JSON array).
  def tag_list=(value)
    self.tags = value.is_a?(Array) ? value : value.to_s.split(/[,;]/)
  end

  def custom_field(key)
    data[key.to_s]
  end

  def set_custom_field(key, value)
    key = key.to_s
    return if key == RESERVED_DATA_KEY || key == TAGS_DATA_KEY

    new_data = data.dup
    if value.blank?
      new_data.delete(key)
    else
      new_data[key] = value
    end
    self.data = new_data
  end

  private

  def normalize_tags(list)
    list.map { |t| t.to_s.strip }.reject(&:blank?).uniq
  end
end
