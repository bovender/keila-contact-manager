# In-memory stand-in for KeilaApi::Client, behaving like the real Keila
# contacts API as far as sync relies on it (checked against a live
# instance): ids assigned on create, status defaulting to "active", emails
# kept as given, `null` rejected but "" clearing a field, PATCH .../data
# merging and POST .../data replacing.
class FakeKeila
  attr_reader :contacts, :calls

  def initialize
    @contacts = {}
    @calls = []
    @sequence = 0
  end

  # Adds a contact directly "in Keila" (as if made there) and returns its id.
  def add(attrs)
    id = "nc_#{@sequence += 1}"
    @contacts[id] = {
      "id" => id, "email" => nil, "first_name" => nil, "last_name" => nil,
      "external_id" => nil, "status" => "active", "data" => {}
    }.merge(attrs.deep_stringify_keys)
    id
  end

  def edit(id, attrs)
    @contacts.fetch(id).merge!(attrs.deep_stringify_keys)
  end

  def all_contacts
    @calls << [ :all_contacts ]
    @contacts.values.map(&:deep_dup)
  end

  def create_contact(attrs)
    attrs = attrs.deep_stringify_keys
    @calls << [ :create_contact, attrs ]
    if @contacts.values.any? { |c| c["email"] == attrs["email"] }
      raise KeilaApi::ResponseError.new(400, "email has already been taken")
    end

    @contacts.fetch(add(attrs.compact)).deep_dup
  end

  def update_contact(id, attrs)
    attrs = attrs.deep_stringify_keys
    @calls << [ :update_contact, id, attrs ]
    raise KeilaApi::ResponseError.new(400, "null_value") if attrs.values.any?(&:nil?)

    contact = fetch(id)
    attrs.each { |key, value| contact[key] = value.presence }
    contact.deep_dup
  end

  def update_contact_data(id, data)
    @calls << [ :update_contact_data, id, data ]
    contact = fetch(id)
    contact["data"] = (contact["data"] || {}).merge(data)
    contact.deep_dup
  end

  def replace_contact_data(id, data)
    @calls << [ :replace_contact_data, id, data ]
    contact = fetch(id)
    contact["data"] = data
    contact.deep_dup
  end

  def delete_contact(id)
    @calls << [ :delete_contact, id ]
    @contacts.delete(id)
    {}
  end

  def writes
    @calls.reject { |call| call.first == :all_contacts }
  end

  private

  def fetch(id)
    @contacts[id] or raise KeilaApi::ResponseError.new(404, "not found")
  end
end
