require "test_helper"

class ContactsControllerTest < ActionDispatch::IntegrationTest
  setup { sign_in_as(users(:one)) }

  test "index requires authentication" do
    sign_out
    get contacts_path
    assert_redirected_to new_session_path
  end

  test "index lists contacts and supports search" do
    get contacts_path, params: { q: "alice" }
    assert_response :success
    assert_match contacts(:one).email, response.body
    assert_no_match contacts(:two).email, response.body
  end

  test "create adds a contact with custom fields" do
    assert_difference "Contact.count", 1 do
      post contacts_path, params: {
        contact: {
          email: "new@example.com",
          first_name: "New",
          tag_list: "vip",
          custom_fields: { "Company" => "Acme" }
        }
      }
    end

    assert_redirected_to contacts_path
    contact = Contact.find_by!(email: "new@example.com")
    assert_equal [ "vip" ], contact.tags
    assert_equal "Acme", contact.custom_field("Company")
  end

  test "update rejects an invalid email" do
    contact = contacts(:one)
    patch contact_path(contact), params: { contact: { email: "not-an-email" } }

    assert_response :unprocessable_entity
    assert_equal "alice@example.com", contact.reload.email
  end

  test "destroy removes the contact" do
    assert_difference "Contact.count", -1 do
      delete contact_path(contacts(:one))
    end
    assert_redirected_to contacts_path
  end

  test "do_import creates contacts from an uploaded CSV" do
    file = fixture_file_upload("contacts_import.csv", "text/csv")

    assert_difference "Contact.count", 1 do
      post import_contacts_path, params: { file: file }
    end

    assert_redirected_to contacts_path
    assert Contact.exists?(email: "imported@example.com")
  end

  test "export returns a CSV of contacts" do
    get export_contacts_path
    assert_response :success
    assert_equal "text/csv", response.media_type
    assert_match contacts(:one).email, response.body
  end

  test "bulk_update tags selected contacts" do
    post bulk_update_contacts_path, params: {
      contact_ids: [ contacts(:one).id, contacts(:two).id ],
      operation: "tag",
      tag: "priority"
    }

    assert_redirected_to contacts_path
    assert_includes contacts(:one).reload.tags, "priority"
    assert_includes contacts(:two).reload.tags, "priority"
  end

  test "bulk_destroy deletes selected contacts" do
    assert_difference "Contact.count", -2 do
      post bulk_destroy_contacts_path, params: { contact_ids: [ contacts(:one).id, contacts(:two).id ] }
    end
  end
end
