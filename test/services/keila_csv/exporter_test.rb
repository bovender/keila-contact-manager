require "test_helper"

module KeilaCsv
  class ExporterTest < ActiveSupport::TestCase
    test "exports contacts in Keila's canonical CSV format" do
      csv = Exporter.export(Contact.where(id: contacts(:one).id))
      rows = CSV.parse(csv, headers: true)

      assert_equal KeilaCsv::CANONICAL_FIELDS, rows.headers
      row = rows.first
      assert_equal "alice@example.com", row["Email"]
      assert_equal "vip;newsletter", row["Tags"]
      data = JSON.parse(row["Data"])
      assert_equal "Acme", data["Company"]
      assert_equal contacts(:one).uuid, data[Contact::RESERVED_DATA_KEY]
    end

    test "round-trips through the importer" do
      original = contacts(:one)
      csv = Exporter.export(Contact.where(id: original.id))

      original.destroy!

      require "tempfile"
      file = Tempfile.new([ "export", ".csv" ])
      file.write(csv)
      file.close
      result = Importer.import(file.path)

      assert_equal 1, result.created
      reimported = Contact.find_by!(email: original.email)
      assert_equal original.tags, reimported.tags
      assert_equal original.data, reimported.data
    ensure
      file&.unlink
    end
  end
end
