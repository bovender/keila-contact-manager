require "test_helper"

module KeilaApi
  class ExporterTest < ActiveSupport::TestCase
    def client
      Client.new(base_url: "https://keila.example.com", api_key: "secret")
    end

    test "creates a new Keila contact, embedding this app's uuid, when none is found by email" do
      contact = contacts(:one)

      stub_request(:get, "https://keila.example.com/api/v1/contacts/#{contact.email}")
        .with(query: { "id_type" => "email" })
        .to_return(status: 404, body: { error: "not found" }.to_json)
      stub_request(:get, "https://keila.example.com/api/v1/contacts/#{contact.external_id}")
        .with(query: { "id_type" => "external_id" })
        .to_return(status: 404, body: { error: "not found" }.to_json)

      create_stub = stub_request(:post, "https://keila.example.com/api/v1/contacts")
        .with { |req| JSON.parse(req.body)["data"]["email"] == contact.email &&
                      JSON.parse(req.body)["data"]["data"][Contact::RESERVED_DATA_KEY] == contact.uuid }
        .to_return(status: 200, body: { data: { "id" => "nc_new" } }.to_json)

      result = Exporter.export(Contact.where(id: contact.id), client: client)

      assert_requested create_stub
      assert_equal 1, result.created
    end

    test "updates the existing Keila contact when one is found by email" do
      contact = contacts(:one)

      stub_request(:get, "https://keila.example.com/api/v1/contacts/#{contact.email}")
        .with(query: { "id_type" => "email" })
        .to_return(status: 200, body: { data: { "id" => "nc_existing", "email" => contact.email } }.to_json)

      update_stub = stub_request(:patch, "https://keila.example.com/api/v1/contacts/nc_existing")
        .to_return(status: 200, body: { data: {} }.to_json)
      data_stub = stub_request(:patch, "https://keila.example.com/api/v1/contacts/nc_existing/data")
        .to_return(status: 200, body: { data: {} }.to_json)

      result = Exporter.export(Contact.where(id: contact.id), client: client)

      assert_requested update_stub
      assert_requested data_stub
      assert_equal 1, result.updated
    end

    test "merges data through the dedicated endpoint instead of the general update, to avoid replacing it" do
      contact = contacts(:one)

      stub_request(:get, "https://keila.example.com/api/v1/contacts/#{contact.email}")
        .with(query: { "id_type" => "email" })
        .to_return(status: 200, body: { data: { "id" => "nc_existing", "email" => contact.email } }.to_json)

      update_stub = stub_request(:patch, "https://keila.example.com/api/v1/contacts/nc_existing")
        .with { |req| !JSON.parse(req.body)["data"].key?("data") }
        .to_return(status: 200, body: { data: {} }.to_json)
      data_stub = stub_request(:patch, "https://keila.example.com/api/v1/contacts/nc_existing/data")
        .with { |req| JSON.parse(req.body)["data"][Contact::RESERVED_DATA_KEY] == contact.uuid }
        .to_return(status: 200, body: { data: {} }.to_json)

      Exporter.export(Contact.where(id: contact.id), client: client)

      assert_requested update_stub
      assert_requested data_stub
    end

    test "pushes tags along as part of data, like any other custom field" do
      contact = contacts(:one)
      assert_equal [ "vip", "newsletter" ], contact.tags

      stub_request(:get, "https://keila.example.com/api/v1/contacts/#{contact.email}")
        .with(query: { "id_type" => "email" })
        .to_return(status: 404, body: { error: "not found" }.to_json)
      stub_request(:get, "https://keila.example.com/api/v1/contacts/#{contact.external_id}")
        .with(query: { "id_type" => "external_id" })
        .to_return(status: 404, body: { error: "not found" }.to_json)

      create_stub = stub_request(:post, "https://keila.example.com/api/v1/contacts")
        .with { |req| JSON.parse(req.body)["data"]["data"]["Tags"] == [ "vip", "newsletter" ] }
        .to_return(status: 200, body: { data: { "id" => "nc_new" } }.to_json)

      Exporter.export(Contact.where(id: contact.id), client: client)

      assert_requested create_stub
    end

    test "falls back to matching by external_id when no contact is found by email" do
      contact = contacts(:one)
      assert contact.external_id.present?

      stub_request(:get, "https://keila.example.com/api/v1/contacts/#{contact.email}")
        .with(query: { "id_type" => "email" })
        .to_return(status: 404, body: { error: "not found" }.to_json)
      stub_request(:get, "https://keila.example.com/api/v1/contacts/#{contact.external_id}")
        .with(query: { "id_type" => "external_id" })
        .to_return(status: 200, body: { data: { "id" => "nc_existing" } }.to_json)

      update_stub = stub_request(:patch, "https://keila.example.com/api/v1/contacts/nc_existing")
        .to_return(status: 200, body: { data: {} }.to_json)
      stub_request(:patch, "https://keila.example.com/api/v1/contacts/nc_existing/data")
        .to_return(status: 200, body: { data: {} }.to_json)

      result = Exporter.export(Contact.where(id: contact.id), client: client)

      assert_requested update_stub
      assert_equal 1, result.updated
    end

    test "omits blank fields instead of sending them as null" do
      contact = Contact.create!(email: "blank-fields@example.com")
      assert_nil contact.first_name
      assert_nil contact.status

      stub_request(:get, "https://keila.example.com/api/v1/contacts/#{contact.email}")
        .with(query: { "id_type" => "email" })
        .to_return(status: 404, body: { error: "not found" }.to_json)

      create_stub = stub_request(:post, "https://keila.example.com/api/v1/contacts")
        .with { |req|
          sent = JSON.parse(req.body)["data"]
          !sent.key?("first_name") && !sent.key?("last_name") &&
            !sent.key?("external_id") && !sent.key?("status")
        }
        .to_return(status: 200, body: { data: { "id" => "nc_new" } }.to_json)

      Exporter.export(Contact.where(id: contact.id), client: client)

      assert_requested create_stub
    end

    test "records an error and continues when Keila responds with a failure" do
      contact = contacts(:one)

      stub_request(:get, "https://keila.example.com/api/v1/contacts/#{contact.email}")
        .with(query: { "id_type" => "email" })
        .to_return(status: 500, body: "boom")

      result = Exporter.export(Contact.where(id: contact.id), client: client)

      assert_equal 1, result.error_count
      assert_equal 0, result.success_count
    end
  end
end
