require "test_helper"

module KeilaApi
  class ClientTest < ActiveSupport::TestCase
    BASE = "https://keila.example.com/api/v1/contacts".freeze

    setup do
      @client = Client.new(base_url: "https://keila.example.com", api_key: "secret-key")
    end

    test "list_contacts sends bearer auth and pagination params" do
      stub_request(:get, BASE)
        .with(query: { "paginate[page]" => "1", "paginate[page_size]" => "50" },
              headers: { "Authorization" => "Bearer secret-key" })
        .to_return(status: 200, body: { data: [ { "email" => "a@example.com" } ], meta: { page_count: 2 } }.to_json)

      response = @client.list_contacts(page: 1, page_size: 50)

      assert_equal [ { "email" => "a@example.com" } ], response["data"]
      assert_equal 2, response["meta"]["page_count"]
    end

    test "all_contacts follows every page" do
      [ 0, 1 ].each do |page|
        stub_request(:get, BASE)
          .with(query: { "paginate[page]" => page.to_s, "paginate[page_size]" => Client::PAGE_SIZE.to_s })
          .to_return(status: 200, body: { data: [ { "id" => "nc_#{page}" } ], meta: { page_count: 2 } }.to_json)
      end

      assert_equal %w[nc_0 nc_1], @client.all_contacts.map { |c| c["id"] }
    end

    test "create_contact posts the contact under a data key and returns it" do
      stub_request(:post, BASE)
        .with(body: { data: { email: "a@example.com" } }.to_json, headers: { "Content-Type" => "application/json" })
        .to_return(status: 200, body: { data: { "id" => "nc_new" } }.to_json)

      assert_equal({ "id" => "nc_new" }, @client.create_contact(email: "a@example.com"))
    end

    test "update_contact patches the contact" do
      stub_request(:patch, "#{BASE}/nc_123")
        .with(body: { data: { "first_name" => "Ann" } }.to_json)
        .to_return(status: 200, body: { data: { "id" => "nc_123", "first_name" => "Ann" } }.to_json)

      assert_equal "Ann", @client.update_contact("nc_123", { "first_name" => "Ann" })["first_name"]
    end

    test "update_contact_data patches the /data endpoint, replace_contact_data posts to it" do
      stub_request(:patch, "#{BASE}/nc_123/data").with(body: { data: { "Company" => "Acme" } }.to_json)
        .to_return(status: 200, body: { data: {} }.to_json)
      stub_request(:post, "#{BASE}/nc_123/data").with(body: { data: { "City" => "Mainz" } }.to_json)
        .to_return(status: 200, body: { data: {} }.to_json)

      @client.update_contact_data("nc_123", { "Company" => "Acme" })
      @client.replace_contact_data("nc_123", { "City" => "Mainz" })

      assert_requested :patch, "#{BASE}/nc_123/data"
      assert_requested :post, "#{BASE}/nc_123/data"
    end

    test "delete_contact copes with Keila's empty 204 response" do
      stub_request(:delete, "#{BASE}/nc_123").to_return(status: 204, body: "")

      assert_equal({}, @client.delete_contact("nc_123"))
    end

    test "raises ResponseError with the status for error responses" do
      stub_request(:patch, "#{BASE}/nc_123").to_return(status: 500, body: "boom")

      error = assert_raises(ResponseError) { @client.update_contact("nc_123", {}) }
      assert_equal 500, error.status
    end

    test "raises ConnectionError when Keila can't be reached" do
      stub_request(:get, BASE).with(query: hash_including({})).to_raise(Errno::ECONNREFUSED)

      assert_raises(ConnectionError) { @client.list_contacts }
    end
  end
end
