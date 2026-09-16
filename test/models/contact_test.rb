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
end
