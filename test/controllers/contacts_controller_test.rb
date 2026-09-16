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

  def stub_keila_count(count)
    stub_request(:get, "https://keila.example.com/api/v1/contacts")
      .with(query: { "paginate[page]" => "0", "paginate[page_size]" => "1" })
      .to_return(status: 200, body: { data: [], meta: { count: count } }.to_json)
  end

  test "sync_from_keila shows a confirmation with counts from both sides" do
    Setting.instance.update!(keila_url: "https://keila.example.com", keila_api_key: "secret")
    stub_keila_count(5)

    get sync_from_keila_contacts_path

    assert_response :success
    assert_match "5", response.body
    assert_match Contact.count.to_s, response.body
  end

  test "sync_from_keila without settings configured redirects with an alert" do
    get sync_from_keila_contacts_path

    assert_redirected_to contacts_path
    assert_match(/Could not reach Keila/, flash[:alert])
  end

  test "do_sync_from_keila pulls contacts and reports a summary" do
    Setting.instance.update!(keila_url: "https://keila.example.com", keila_api_key: "secret")
    stub_request(:get, "https://keila.example.com/api/v1/contacts")
      .with(query: { "paginate[page]" => "0", "paginate[page_size]" => "100" })
      .to_return(status: 200, body: {
        data: [ { "id" => "nc_1", "email" => "new@example.com", "data" => {} } ],
        meta: { page_count: 1 }
      }.to_json)

    post sync_from_keila_contacts_path

    assert_redirected_to contacts_path
    assert_match(/Pulled 1 contact/, flash[:notice])
    assert Contact.exists?(email: "new@example.com")
  end

  test "push_to_keila shows a confirmation with counts from both sides" do
    Setting.instance.update!(keila_url: "https://keila.example.com", keila_api_key: "secret")
    stub_keila_count(3)

    get push_to_keila_contacts_path

    assert_response :success
    assert_match "3", response.body
  end

  test "do_push_to_keila pushes local contacts, merging data via the dedicated endpoint" do
    Setting.instance.update!(keila_url: "https://keila.example.com", keila_api_key: "secret")
    Contact.delete_all
    contact = Contact.create!(email: "push@example.com")

    stub_request(:get, "https://keila.example.com/api/v1/contacts/#{contact.email}")
      .with(query: { "id_type" => "email" })
      .to_return(status: 404, body: { error: "not found" }.to_json)
    stub_request(:post, "https://keila.example.com/api/v1/contacts")
      .to_return(status: 200, body: { data: { "id" => "nc_new" } }.to_json)

    post push_to_keila_contacts_path

    assert_redirected_to contacts_path
    assert_match(/Pushed 1 contact/, flash[:notice])
  end
end
