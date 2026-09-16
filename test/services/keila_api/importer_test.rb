require "test_helper"

module KeilaApi
  class ImporterTest < ActiveSupport::TestCase
    def import(client)
      Importer.import(client: client)
    end

    def stub_contacts_page(page:, contacts:, page_count: 1)
      stub_request(:get, "https://keila.example.com/api/v1/contacts")
        .with(query: { "paginate[page]" => page.to_s, "paginate[page_size]" => "100" })
        .to_return(status: 200, body: { data: contacts, meta: { page_count: page_count } }.to_json)
    end

    def client
      Client.new(base_url: "https://keila.example.com", api_key: "secret")
    end

    test "creates new contacts and registers custom fields, without touching tags" do
      contacts(:one).update!(tags: [ "vip" ])

      stub_contacts_page(page: 0, contacts: [
        { "id" => "nc_1", "email" => "carol@example.com", "first_name" => "Carol",
          "status" => "active", "data" => { "Company" => "Acme" } }
      ])

      result = import(client)

      assert_equal 1, result.created
      assert_empty result.errors
      contact = Contact.find_by!(email: "carol@example.com")
      assert_equal "Carol", contact.first_name
      assert_equal "Acme", contact.custom_field("Company")
      assert_equal [], contact.tags
      assert CustomFieldDefinition.exists?(key: "Company")
    end

    test "matches an existing contact by its embedded uuid even if the email changed" do
      contact = contacts(:one)
      original_id = contact.id
      contact.update!(tags: [ "vip" ])

      stub_contacts_page(page: 0, contacts: [
        { "id" => "nc_1", "email" => "alice.new@example.com", "first_name" => "Alice",
          "data" => { Contact::RESERVED_DATA_KEY => contact.uuid, "Company" => "New Co" } }
      ])

      result = import(client)

      assert_equal 0, result.created
      assert_equal 1, result.updated
      contact.reload
      assert_equal original_id, contact.id
      assert_equal "alice.new@example.com", contact.email
      assert_equal "New Co", contact.custom_field("Company")
      assert_equal [ "vip" ], contact.tags, "tags must be left untouched: Keila's API doesn't expose them"
    end

    test "falls back to matching by external_id when no uuid is embedded" do
      contact = contacts(:one)

      stub_contacts_page(page: 0, contacts: [
        { "id" => "nc_1", "email" => "alice.new@example.com", "external_id" => contact.external_id, "data" => {} }
      ])

      result = import(client)

      assert_equal 0, result.created
      assert_equal 1, result.updated
      assert_equal "alice.new@example.com", contact.reload.email
    end

    test "paginates through every page Keila reports" do
      stub_contacts_page(page: 0, contacts: [ { "id" => "nc_1", "email" => "a@example.com", "data" => {} } ], page_count: 2)
      stub_contacts_page(page: 1, contacts: [ { "id" => "nc_2", "email" => "b@example.com", "data" => {} } ], page_count: 2)

      result = import(client)

      assert_equal 2, result.created
      assert Contact.exists?(email: "a@example.com")
      assert Contact.exists?(email: "b@example.com")
    end

    test "records an error for contacts missing an email instead of raising" do
      stub_contacts_page(page: 0, contacts: [ { "id" => "nc_1", "email" => "", "data" => {} } ])

      result = import(client)

      assert_equal 0, result.success_count
      assert_equal 1, result.error_count
      assert_match(/missing email/, result.errors.first[:message])
    end

    test "raises NotConfiguredError when settings are incomplete" do
      assert_raises(NotConfiguredError) { Importer.import }
    end
  end
end
