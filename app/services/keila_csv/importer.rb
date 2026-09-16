require "csv"
require "json"

module KeilaCsv
  # Imports a Keila contact export (or a flat CSV with individual custom
  # field columns instead of a JSON "Data" column) into the local database.
  #
  # Contacts are upserted by email. Custom field values are merged into the
  # existing data hash rather than replacing it outright, so a re-import
  # from Keila doesn't wipe out fields that only exist locally. Any
  # previously-unseen custom field is registered as a CustomFieldDefinition
  # so it immediately shows up in the contact form and table.
  #
  # Standard field headers (Email, First_name, ...) are matched
  # case-insensitively, but custom field headers keep their original casing
  # so they round-trip with Keila's own Data JSON keys unchanged.
  class Importer
    def self.import(io_or_path)
      new(io_or_path).import
    end

    def initialize(io_or_path)
      @io_or_path = io_or_path
    end

    def import
      table = CSV.read(@io_or_path, headers: true, encoding: "bom|utf-8")
      raw_headers = table.headers.compact
      header_lookup = raw_headers.each_with_object({}) { |h, acc| acc[h.downcase] = h }
      custom_headers = raw_headers.reject { |h| KeilaCsv::DOWNCASED_FIELDS.include?(h.downcase) }
      result = KeilaCsv::ImportResult.new

      table.each_with_index do |row, index|
        line_number = index + 2 # header line + 1-based rows

        email = value_for(row, header_lookup, "email").to_s.strip
        if email.blank?
          result.errors << { line: line_number, message: "missing email" }
          next
        end

        contact = Contact.find_or_initialize_by(email: email.downcase)
        was_new_record = contact.new_record?

        contact.first_name = value_for(row, header_lookup, "first_name") if header_lookup.key?("first_name")
        contact.last_name  = value_for(row, header_lookup, "last_name")  if header_lookup.key?("last_name")
        contact.external_id = value_for(row, header_lookup, "external_id") if header_lookup.key?("external_id")
        contact.status = value_for(row, header_lookup, "status") if header_lookup.key?("status")
        contact.tag_list = value_for(row, header_lookup, "tags") if header_lookup.key?("tags")

        new_data = extract_data(row, header_lookup, custom_headers, line_number, result)
        contact.data = contact.data.merge(new_data)

        if contact.save
          result.custom_fields |= new_data.keys
          if was_new_record
            result.created += 1
          else
            result.updated += 1
          end
        else
          result.errors << { line: line_number, message: contact.errors.full_messages.to_sentence }
        end
      end

      result.custom_fields.each { |key| CustomFieldDefinition.register!(key) }
      result
    end

    private

    def value_for(row, header_lookup, downcased_name)
      header = header_lookup[downcased_name]
      header && row[header]
    end

    def extract_data(row, header_lookup, custom_headers, line_number, result)
      data = {}

      data_header = header_lookup["data"]
      if data_header && row[data_header].present?
        begin
          parsed = JSON.parse(row[data_header])
          data.merge!(parsed) if parsed.is_a?(Hash)
        rescue JSON::ParserError => e
          result.errors << { line: line_number, message: "invalid Data JSON: #{e.message}" }
        end
      end

      custom_headers.each do |header|
        value = row[header]
        next if value.blank?

        data[header] = parse_flat_value(value)
      end

      data
    end

    def parse_flat_value(value)
      parsed = JSON.parse(value)
      parsed.is_a?(Hash) || parsed.is_a?(Array) ? parsed : value
    rescue JSON::ParserError
      value
    end
  end
end
