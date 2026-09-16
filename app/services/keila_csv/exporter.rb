require "csv"
require "json"

module KeilaCsv
  # Exports contacts back into Keila's native, importable CSV format:
  # standard fields in their canonical capitalisation, tags joined with
  # semicolons, and custom fields packed into a single "Data" JSON column.
  class Exporter
    def self.export(contacts = Contact.order(:email))
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
            Array(contact.tags).join(";"),
            contact.data.presence&.to_json
          ]
        end
      end
    end
  end
end
