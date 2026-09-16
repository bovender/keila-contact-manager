require "test_helper"
require "tempfile"

module KeilaCsv
  class ImporterTest < ActiveSupport::TestCase
    def import(csv_content)
      file = Tempfile.new([ "import", ".csv" ])
      file.write(csv_content)
      file.close
      Importer.import(file.path)
    ensure
      file&.unlink
    end

    test "creates new contacts and registers custom fields from the Data column" do
      result = import(<<~CSV)
        Email,First_name,Last_name,External_id,Status,Tags,Data
        carol@example.com,Carol,Clark,ext-3,active,vip;newsletter,"{""Company"":""Acme"",""Shoe_size"":""42""}"
      CSV

      assert_equal 1, result.created
      assert_equal 0, result.updated
      assert_empty result.errors

      contact = Contact.find_by!(email: "carol@example.com")
      assert_equal "Carol", contact.first_name
      assert_equal [ "vip", "newsletter" ], contact.tags
      assert_equal "Acme", contact.custom_field("Company")
      assert_equal "42", contact.custom_field("Shoe_size")
      assert CustomFieldDefinition.exists?(key: "Shoe_size")
    end

    test "upserts by email and merges new data into existing custom fields" do
      contact = contacts(:two)
      contact.set_custom_field("Existing_field", "kept")
      contact.save!

      result = import(<<~CSV)
        Email,Data
        #{contact.email},"{""Company"":""New Co""}"
      CSV

      assert_equal 0, result.created
      assert_equal 1, result.updated

      contact.reload
      assert_equal "New Co", contact.custom_field("Company")
      assert_equal "kept", contact.custom_field("Existing_field")
    end

    test "supports a flat CSV with individual custom-field columns instead of Data" do
      result = import(<<~CSV)
        Email,Company
        dora@example.com,Acme
      CSV

      contact = Contact.find_by!(email: "dora@example.com")
      assert_equal "Acme", contact.custom_field("Company")
      assert_equal [ "Company" ], result.custom_fields
    end

    test "re-matches an existing contact by its embedded uuid even if the email changed" do
      contact = contacts(:one)
      original_id = contact.id

      result = import(<<~CSV)
        Email,First_name,Data
        alice.new@example.com,Alice,"{""#{Contact::RESERVED_DATA_KEY}"":""#{contact.uuid}"",""Company"":""New Co""}"
      CSV

      assert_equal 0, result.created
      assert_equal 1, result.updated
      assert_equal 1, Contact.where(email: [ "alice@example.com", "alice.new@example.com" ]).count

      contact.reload
      assert_equal original_id, contact.id
      assert_equal "alice.new@example.com", contact.email
      assert_equal "New Co", contact.custom_field("Company")
    end

    test "never stores the reserved uid key as contact data or a custom field" do
      contact = contacts(:two)

      import(<<~CSV)
        Email,Data
        #{contact.email},"{""#{Contact::RESERVED_DATA_KEY}"":""some-other-uuid""}"
      CSV

      contact.reload
      assert_nil contact.data[Contact::RESERVED_DATA_KEY]
      assert_not CustomFieldDefinition.exists?(key: Contact::RESERVED_DATA_KEY)
    end

    test "falls back to matching by external_id when no uuid is embedded" do
      contact = contacts(:one)

      result = import(<<~CSV)
        Email,External_id
        alice.new@example.com,#{contact.external_id}
      CSV

      assert_equal 0, result.created
      assert_equal 1, result.updated
      assert_equal "alice.new@example.com", contact.reload.email
    end

    test "reads Tags from the Data JSON blob too, not just a flat column" do
      result = import(<<~CSV)
        Email,Data
        carol@example.com,"{""Tags"":[""vip"",""newsletter""],""Company"":""Acme""}"
      CSV

      contact = Contact.find_by!(email: "carol@example.com")
      assert_equal [ "vip", "newsletter" ], contact.tags
      assert_equal "Acme", contact.custom_field("Company")
      assert_not result.custom_fields.include?("Tags")
    end

    test "re-importing replaces the tag list outright rather than merging it" do
      contact = contacts(:one)
      assert_equal [ "vip", "newsletter" ], contact.tags

      import(<<~CSV)
        Email,Tags
        #{contact.email},just-this-one
      CSV

      assert_equal [ "just-this-one" ], contact.reload.tags
    end

    test "records an error for rows missing an email instead of raising" do
      result = import(<<~CSV)
        Email,First_name
        ,Nobody
      CSV

      assert_equal 0, result.success_count
      assert_equal 1, result.error_count
      assert_match(/missing email/, result.errors.first[:message])
    end
  end
end
