require "test_helper"

class ContactTest < ActiveSupport::TestCase
  test "normalizes email to lowercase and strips whitespace" do
    contact = Contact.new(email: " Someone@Example.com ")
    contact.validate
    assert_equal "someone@example.com", contact.email
  end

  test "requires a valid, unique email" do
    contact = Contact.new(email: "not-an-email")
    assert_not contact.valid?
    assert_includes contact.errors[:email], "is invalid"

    contact = Contact.new(email: contacts(:one).email)
    assert_not contact.valid?
    assert_includes contact.errors[:email], "has already been taken"
  end

  test "tag_list reads and writes the tags array" do
    contact = contacts(:one)
    assert_equal "vip, newsletter", contact.tag_list

    contact.tag_list = "a; b, a"
    assert_equal [ "a", "b" ], contact.tags
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
