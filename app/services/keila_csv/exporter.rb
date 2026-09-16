require "csv"
require "json"

module KeilaCsv
  # Exports contacts back into Keila's native, importable CSV format:
  # standard fields in their canonical capitalisation, and custom fields
  # (Tags included -- it's just a Data key, see Contact::TAGS_DATA_KEY)
  # packed into a single "Data" JSON column.
  #
  # Each contact's permanent internal uuid is smuggled into Data under
  # Contact::RESERVED_DATA_KEY so that re-importing a later Keila export of
  # the same contact re-matches it correctly even if the email changed in
  # the meantime (see KeilaCsv::Importer).
  class Exporter
    def self.export(project:, contacts: project.contacts.order(:email))
      new(contacts).export
    end

    def initialize(contacts)
      @contacts = contacts
    end

    def export
      CSV.generate(headers: true) do |csv|
        csv << KeilaCsv::CANONICAL_FIELDS

        @contacts.each do |contact|
          csv << [
            contact.email,
            contact.first_name,
            contact.last_name,
            contact.external_id,
            contact.status,
            contact.data.merge(Contact::RESERVED_DATA_KEY => contact.uuid).to_json
          ]
        end
      end
    end
  end
end
