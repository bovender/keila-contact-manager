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
