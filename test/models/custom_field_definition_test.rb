require "test_helper"

class CustomFieldDefinitionTest < ActiveSupport::TestCase
  test "register! finds an existing definition by key" do
    assert_no_difference "CustomFieldDefinition.count" do
      definition = CustomFieldDefinition.register!("Company")
      assert_equal custom_field_definitions(:company), definition
    end
  end

  test "register! creates a new definition with a humanized label and next position" do
    assert_difference "CustomFieldDefinition.count", 1 do
      definition = CustomFieldDefinition.register!("Favorite_color")
      assert_equal "Favorite_color", definition.key
      assert_equal "Favorite color", definition.label
      assert_equal custom_field_definitions(:birthday).position + 1, definition.position
    end
  end

  test "register! ignores blank keys" do
    assert_nil CustomFieldDefinition.register!("  ")
  end

  test "register! and validation both refuse the reserved uid key" do
    assert_nil CustomFieldDefinition.register!(Contact::RESERVED_DATA_KEY)

    definition = CustomFieldDefinition.new(key: Contact::RESERVED_DATA_KEY, label: "Nope")
    assert_not definition.valid?
    assert_includes definition.errors[:key], "is reserved for internal use"
  end

  test "orders by position by default" do
    assert_equal CustomFieldDefinition.order(:position).to_a, CustomFieldDefinition.all.to_a
  end

  test "contacts_count reports how many contacts hold a value for this key" do
    assert_equal 1, custom_field_definitions(:company).contacts_count
    assert_equal 0, custom_field_definitions(:birthday).contacts_count
  end
end
