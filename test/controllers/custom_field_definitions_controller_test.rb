require "test_helper"

class CustomFieldDefinitionsControllerTest < ActionDispatch::IntegrationTest
  setup { sign_in_as(users(:one)) }

  test "index lists known custom fields" do
    get custom_field_definitions_path
    assert_response :success
    assert_match "Company", response.body
  end

  test "create registers a new custom field" do
    assert_difference "CustomFieldDefinition.count", 1 do
      post custom_field_definitions_path, params: { custom_field_definition: { key: "Newsletter_opt_in", label: "Newsletter opt-in" } }
    end
    assert_redirected_to custom_field_definitions_path
  end

  test "update renames a custom field's label" do
    definition = custom_field_definitions(:company)
    patch custom_field_definition_path(definition), params: { custom_field_definition: { label: "Employer" } }

    assert_redirected_to custom_field_definitions_path
    assert_equal "Employer", definition.reload.label
  end

  test "destroy removes the definition but keeps contact data" do
    definition = custom_field_definitions(:company)
    contact = contacts(:one)
    assert_equal "Acme", contact.custom_field("Company")

    assert_difference "CustomFieldDefinition.count", -1 do
      delete custom_field_definition_path(definition)
    end

    assert_equal "Acme", contact.reload.custom_field("Company")
  end

  test "destroy with purge_data also deletes the field's data from every contact" do
    definition = custom_field_definitions(:company)
    contact = contacts(:one)
    assert_equal "Acme", contact.custom_field("Company")

    assert_difference "CustomFieldDefinition.count", -1 do
      delete custom_field_definition_path(definition, purge_data: true)
    end

    assert_nil contact.reload.custom_field("Company")
  end
end
