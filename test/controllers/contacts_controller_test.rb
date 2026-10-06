require "test_helper"

class ContactsControllerTest < ActionDispatch::IntegrationTest
  setup { sign_in_as(users(:one)) }

  test "index requires authentication" do
    sign_out
    get contacts_path
    assert_redirected_to new_session_path
  end

  test "redirects to the projects page when no project is active" do
    users(:one).update!(current_keila_project: nil)

    get contacts_path

    assert_redirected_to keila_projects_path
    assert_equal "Create or switch to a project first.", flash[:alert]
  end

  test "index lists contacts and supports search" do
    get contacts_path, params: { q: "alice" }
    assert_response :success
    assert_match contacts(:one).email, response.body
    assert_no_match contacts(:two).email, response.body
  end

  test "index only shows contacts belonging to the active project" do
    other = Contact.create!(email: "other@example.com", keila_project: keila_projects(:beta))

    get contacts_path

    assert_response :success
    assert_match contacts(:one).email, response.body
    assert_no_match other.email, response.body
  end

  test "index remembers the page size it's asked for, within bounds" do
    project = users(:one).current_keila_project
    30.times { |i| Contact.create!(email: "many#{i}@example.com", keila_project: project) }

    get contacts_path, params: { per_page: 12 }
    assert_select "tbody tr", 12

    get contacts_path, params: { page: 2 }
    assert_select "tbody tr", 12

    get contacts_path, params: { per_page: 1 }
    assert_select "tbody tr", ContactsController::MIN_PER_PAGE
  end

  test "show 404s for a contact belonging to a different project" do
    other = Contact.create!(email: "other@example.com", keila_project: keila_projects(:beta))

    get contact_path(other)

    assert_response :not_found
  end

  test "show lists first and last name as fields of their own" do
    contact = contacts(:one)
    contact.update!(first_name: "Alicia", last_name: "Anders")

    get contact_path(contact)

    assert_select "dt", text: "First name"
    assert_select "dt", text: "Last name"
    assert_select "dt:contains('First name') + dd", text: "Alicia"
    assert_select "dt:contains('Last name') + dd", text: "Anders"
  end

  test "show displays the contact, including unregistered custom fields" do
    contact = contacts(:one)
    contact.set_custom_field("Orphaned_field", "leftover")
    contact.save!

    get contact_path(contact)

    assert_response :success
    assert_match contact.email, response.body
    assert_match "Acme", response.body
    assert_match "Orphaned_field", response.body
    assert_match "leftover", response.body
  end

  test "create adds a contact with custom fields, assigned to the active project" do
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
    assert_equal keila_projects(:alpha), contact.keila_project
  end

  test "create allows the same email already used in a different project" do
    Contact.create!(email: "shared@example.com", keila_project: keila_projects(:beta))

    assert_difference "Contact.count", 1 do
      post contacts_path, params: { contact: { email: "shared@example.com" } }
    end
    assert_redirected_to contacts_path
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

  test "do_import creates contacts from an uploaded CSV, assigned to the active project" do
    file = fixture_file_upload("contacts_import.csv", "text/csv")

    assert_difference "Contact.count", 1 do
      post import_contacts_path, params: { file: file }
    end

    assert_redirected_to contacts_path
    contact = Contact.find_by!(email: "imported@example.com")
    assert_equal keila_projects(:alpha), contact.keila_project
  end

  test "export returns a CSV of only the active project's contacts" do
    other = Contact.create!(email: "other@example.com", keila_project: keila_projects(:beta))

    get export_contacts_path

    assert_response :success
    assert_equal "text/csv", response.media_type
    assert_match contacts(:one).email, response.body
    assert_no_match other.email, response.body
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

  test "bulk_update with a blank tag is a no-op and says so" do
    original_tags = contacts(:one).tags

    post bulk_update_contacts_path, params: {
      contact_ids: [ contacts(:one).id ],
      operation: "tag",
      tag: "   "
    }

    assert_redirected_to contacts_path
    assert_equal "Enter a tag name to add or remove it.", flash[:alert]
    assert_equal original_tags, contacts(:one).reload.tags
  end

  test "bulk_update with no contacts selected is a no-op and says so" do
    post bulk_update_contacts_path, params: { operation: "tag", tag: "priority" }

    assert_redirected_to contacts_path
    assert_equal "Select at least one contact first.", flash[:alert]
    assert Contact.none? { |c| c.tags.include?("priority") }
  end

  test "bulk_destroy deletes selected contacts" do
    assert_difference "Contact.count", -2 do
      post bulk_destroy_contacts_path, params: { contact_ids: [ contacts(:one).id, contacts(:two).id ] }
    end
  end

  test "bulk actions never touch another project's contacts, even via select_all_matching" do
    other = Contact.create!(email: "other@example.com", keila_project: keila_projects(:beta), tag_list: "newsletter")

    post bulk_update_contacts_path, params: {
      select_all_matching: "1", current_tag: "newsletter", operation: "tag", tag: "priority"
    }

    assert_not_includes other.reload.tags, "priority"
  end

  test "bulk_update with select_all_matching tags every contact matching the filter, not just contact_ids" do
    post bulk_update_contacts_path, params: {
      select_all_matching: "1",
      current_tag: "newsletter",
      contact_ids: [ contacts(:one).id ],
      operation: "tag",
      tag: "priority"
    }

    assert_redirected_to contacts_path(tag: "newsletter")
    assert_includes contacts(:one).reload.tags, "priority"
    assert_includes contacts(:two).reload.tags, "priority"
  end

  test "bulk_destroy with select_all_matching deletes every contact matching the filter" do
    assert_difference "Contact.count", -2 do
      post bulk_destroy_contacts_path, params: { select_all_matching: "1", current_tag: "newsletter" }
    end
  end
end
