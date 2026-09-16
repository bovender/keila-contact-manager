class Contact < ApplicationRecord
  before_validation { self.email = email.to_s.strip.downcase }

  validates :email, presence: true,
                     uniqueness: { case_sensitive: false },
                     format: { with: URI::MailTo::EMAIL_REGEXP }

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

    where("EXISTS (SELECT 1 FROM json_each(contacts.tags) WHERE json_each.value = ?)", tag)
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

  def tag_list
    Array(tags).join(", ")
  end

  def tag_list=(value)
    self.tags = value.to_s.split(/[,;]/).map(&:strip).reject(&:blank?).uniq
  end

  def custom_field(key)
    data[key.to_s]
  end

  def set_custom_field(key, value)
    key = key.to_s
    new_data = data.dup
    if value.blank?
      new_data.delete(key)
    else
      new_data[key] = value
    end
    self.data = new_data
  end
end
