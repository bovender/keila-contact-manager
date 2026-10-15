require "test_helper"

class ContactTest < ActiveSupport::TestCase
  test "normalizes email to lowercase and strips whitespace" do
    contact = Contact.new(email: " Someone@Example.com ", keila_project: keila_projects(:alpha))
    contact.validate
    assert_equal "someone@example.com", contact.email
  end

  test "requires a valid email, unique within its project" do
    contact = Contact.new(email: "not-an-email", keila_project: keila_projects(:alpha))
    assert_not contact.valid?
    assert_includes contact.errors[:email], "is invalid"

    contact = Contact.new(email: contacts(:one).email, keila_project: keila_projects(:alpha))
    assert_not contact.valid?
    assert_includes contact.errors[:email], "has already been taken"
  end

  test "the same email is allowed in a different project" do
    contact = Contact.new(email: contacts(:one).email, keila_project: keila_projects(:beta))
    assert contact.valid?
  end

  test "requires a project" do
    contact = Contact.new(email: "new@example.com")
    assert_not contact.valid?
    assert_includes contact.errors[:keila_project], "must exist"
  end

  test "assigns a permanent uuid on creation and never changes it" do
    contact = Contact.create!(email: "new@example.com", keila_project: keila_projects(:alpha))
    uuid = contact.uuid
    assert_match(/\A[0-9a-f-]{36}\z/, uuid)

    contact.update!(first_name: "New")
    assert_equal uuid, contact.reload.uuid
  end

  test "set_custom_field refuses to overwrite the reserved uid key" do
    contact = contacts(:one)
    contact.set_custom_field(Contact::RESERVED_DATA_KEY, "hijacked")
    assert_nil contact.data[Contact::RESERVED_DATA_KEY]
  end

  test "requires a unique uuid" do
    contact = Contact.new(email: "dup@example.com", uuid: contacts(:one).uuid, keila_project: keila_projects(:alpha))
    assert_not contact.valid?
    assert_includes contact.errors[:uuid], "has already been taken"
  end

  test "tag_list reads and writes the tags array" do
    contact = contacts(:one)
    assert_equal "vip, newsletter", contact.tag_list

    contact.tag_list = "a; b, a"
    assert_equal [ "a", "b" ], contact.tags
  end

  test "tags are stored inside data, not a dedicated column" do
    contact = contacts(:one)
    assert_equal [ "vip", "newsletter" ], contact.data["Tags"]
  end

  test "tag_list= also accepts an array, as arrives from CSV/API imports" do
    contact = contacts(:two)
    contact.tag_list = [ "a", " b ", "a", "" ]
    assert_equal [ "a", "b" ], contact.tags
  end

  test "tags= clears the Tags data key entirely when set to an empty list" do
    contact = contacts(:one)
    contact.tags = []
    assert_nil contact.data["Tags"]
    assert_equal [], contact.tags
  end

  test "set_custom_field refuses to overwrite tags" do
    contact = contacts(:two)
    contact.set_custom_field(Contact::TAGS_DATA_KEY, "hijacked")
    assert_equal [ "newsletter" ], contact.tags
  end

  test "custom_field reads and set_custom_field writes into data, dropping blanks" do
    contact = contacts(:two)
    assert_nil contact.custom_field("Company")

    contact.set_custom_field("Company", "Acme")
    assert_equal "Acme", contact.custom_field("Company")

    contact.set_custom_field("Company", "")
    assert_nil contact.custom_field("Company")
  end

  test "search scope matches email, name, and external id" do
    assert_includes Contact.search("alice"), contacts(:one)
    assert_includes Contact.search("Anderson"), contacts(:one)
    assert_includes Contact.search("ext-1"), contacts(:one)
    assert_not_includes Contact.search("alice"), contacts(:two)
    assert_equal Contact.count, Contact.search("").count
  end

  test "tagged_with scope filters by tag membership" do
    assert_includes Contact.tagged_with("vip"), contacts(:one)
    assert_not_includes Contact.tagged_with("vip"), contacts(:two)
    assert_equal Contact.count, Contact.tagged_with(nil).count
  end

  test "with_custom_field scope filters on the JSON data column" do
    assert_includes Contact.with_custom_field("Company", "Acme"), contacts(:one)
    assert_not_includes Contact.with_custom_field("Company", "Acme"), contacts(:two)
  end

  test "having_custom_field scope matches contacts where the key is present regardless of value" do
    assert_includes Contact.having_custom_field("Company"), contacts(:one)
    assert_not_includes Contact.having_custom_field("Company"), contacts(:two)
    assert_equal Contact.none.to_a, Contact.having_custom_field(nil).to_a
  end

  test "status is normalized and limited to what Keila accepts" do
    contact = contacts(:one)
    contact.status = " Unsubscribed "
    assert contact.valid?
    assert_equal "unsubscribed", contact.status

    contact.status = "subscribed"
    assert_not contact.valid?

    contact.status = ""
    assert contact.valid?
    assert_nil contact.status
  end

  test "destroying a contact that was synced leaves a tombstone with its last synced state" do
    contact = contacts(:one)
    contact.update!(keila_id: "nc_1", sync_snapshot: contact.sync_state)

    assert_difference "ContactDeletion.count", 1 do
      contact.destroy
    end
    deletion = keila_projects(:alpha).contact_deletions.find_by!(keila_id: "nc_1")
    assert_equal "alice@example.com", deletion.email
    assert_equal "Acme", deletion.snapshot["data"]["Company"]
  end

  test "destroying a contact that was never synced leaves no tombstone" do
    assert_no_difference "ContactDeletion.count" do
      contacts(:one).destroy
    end
  end

  test "sync_state leaves out the reserved uid key" do
    contact = contacts(:one)
    contact.data = contact.data.merge(Contact::RESERVED_DATA_KEY => contact.uuid)

    assert_equal({ "Company" => "Acme", "Tags" => [ "vip", "newsletter" ] }, contact.sync_state["data"])
    assert_equal "alice@example.com", contact.sync_state["email"]
  end

  test "changing the status records when" do
    contact = contacts(:one)

    travel_to Time.zone.local(2026, 9, 1, 12) do
      contact.update!(status: "unsubscribed")
    end
    assert_equal Time.zone.local(2026, 9, 1, 12), contact.status_changed_at

    contact.update!(first_name: "Alicia")
    assert_equal Time.zone.local(2026, 9, 1, 12), contact.reload.status_changed_at
  end

  test "due_for_deletion finds contacts inactive for the retention period or longer" do
    old = contacts(:one)
    recent = contacts(:two)
    old.update!(status: "unsubscribed", status_changed_at: (Contact::INACTIVE_RETENTION + 1.day).ago)
    recent.update!(status: "unsubscribed")
    bounced = keila_projects(:alpha).contacts.create!(email: "dave@example.com", status: "unreachable", status_changed_at: 1.year.ago)
    keila_projects(:alpha).contacts.create!(email: "carol@example.com", status: "active", status_changed_at: 1.year.ago)

    assert_equal [ old, bounced ].sort_by(&:id), keila_projects(:alpha).contacts.due_for_deletion.order(:id).to_a
    assert old.due_for_deletion?
    assert bounced.due_for_deletion?
    assert_not recent.due_for_deletion?
  end
end
