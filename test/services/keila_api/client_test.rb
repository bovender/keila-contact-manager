require "test_helper"

module KeilaApi
  class ClientTest < ActiveSupport::TestCase
    setup do
      @client = Client.new(base_url: "https://keila.example.com", api_key: "secret-key")
    end

    test "list_contacts sends bearer auth and pagination params" do
      stub_request(:get, "https://keila.example.com/api/v1/contacts")
        .with(query: { "paginate[page]" => "1", "paginate[page_size]" => "50" },
              headers: { "Authorization" => "Bearer secret-key" })
        .to_return(status: 200, body: { data: [ { "email" => "a@example.com" } ], meta: { page_count: 2 } }.to_json)

      response = @client.list_contacts(page: 1, page_size: 50)

      assert_equal [ { "email" => "a@example.com" } ], response["data"]
      assert_equal 2, response["meta"]["page_count"]
    end

    test "find_contact returns the contact by Keila id" do
      stub_request(:get, "https://keila.example.com/api/v1/contacts/nc_123")
        .to_return(status: 200, body: { data: { "id" => "nc_123", "email" => "a@example.com" } }.to_json)

      response = @client.find_contact("nc_123")

      assert_equal({ "id" => "nc_123", "email" => "a@example.com" }, response["data"])
    end

    test "find_contact passes id_type for email/external_id lookups" do
      stub_request(:get, "https://keila.example.com/api/v1/contacts/a@example.com")
        .with(query: { "id_type" => "email" })
        .to_return(status: 200, body: { data: { "email" => "a@example.com" } }.to_json)

      @client.find_contact("a@example.com", id_type: "email")

      assert_requested :get, "https://keila.example.com/api/v1/contacts/a@example.com?id_type=email"
    end

    test "find_contact returns nil on 404 instead of raising" do
      stub_request(:get, "https://keila.example.com/api/v1/contacts/missing@example.com")
        .to_return(status: 404, body: { error: "not found" }.to_json)

      assert_nil @client.find_contact("missing@example.com")
    end

    test "create_contact posts the contact under a data key" do
      stub_request(:post, "https://keila.example.com/api/v1/contacts")
        .with(
          body: { data: { email: "a@example.com" } }.to_json,
          headers: { "Content-Type" => "application/json" }
        )
        .to_return(status: 200, body: { data: { "id" => "nc_new" } }.to_json)

      response = @client.create_contact(email: "a@example.com")

      assert_equal "nc_new", response["data"]["id"]
    end

    test "update_contact_data patches the /data endpoint" do
      stub_request(:patch, "https://keila.example.com/api/v1/contacts/nc_123/data")
        .with(body: { data: { "Company" => "Acme" } }.to_json)
        .to_return(status: 200, body: { data: {} }.to_json)

      @client.update_contact_data("nc_123", { "Company" => "Acme" })

      assert_requested :patch, "https://keila.example.com/api/v1/contacts/nc_123/data"
    end

    test "raises ResponseError with the status for other error responses" do
      stub_request(:get, "https://keila.example.com/api/v1/contacts/nc_123")
        .to_return(status: 500, body: "boom")

      error = assert_raises(ResponseError) { @client.find_contact("nc_123") }
      assert_equal 500, error.status
    end
  end
end
