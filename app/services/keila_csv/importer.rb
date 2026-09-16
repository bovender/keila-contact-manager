require "csv"
require "json"

module KeilaCsv
  # Imports a Keila contact export (or a flat CSV with individual custom
  # field columns instead of a JSON "Data" column) into the local database,
  # scoped to a single KeilaProject -- imported/matched contacts always
  # belong to that project, so the same email in a different project's
  # data is never mistaken for the same contact.
  #
  # Contacts are matched, in order of preference, by this app's own
  # `Contact::RESERVED_DATA_KEY` embedded in the Data column (see
  # KeilaCsv::Exporter), by Keila's External_id, and finally by email. The
  # first two survive an email change made directly in Keila; matching by
  # email alone would instead create a duplicate contact. Custom field
  # values are merged into the existing data hash rather than replacing it
  # outright, so a re-import from Keila doesn't wipe out fields that only
  # exist locally. Any previously-unseen custom field is registered as a
  # CustomFieldDefinition so it immediately shows up in the contact form
  # and table.
  #
  # Tags (Contact::TAGS_DATA_KEY) get the same treatment as
  # Contact::RESERVED_DATA_KEY: pulled out of the Data blob (or a flat
  # "Tags" column) and assigned through Contact#tag_list=, which replaces
  # the tag list outright rather than merging it -- unlike other custom
  # fields, "whatever the source currently says" is the more useful
  # default for tags.
  #
  # Standard field headers (Email, First_name, ...) are matched
  # case-insensitively, but custom field headers keep their original casing
  # so they round-trip with Keila's own Data JSON keys unchanged.
  class Importer
    def self.import(io_or_path, project:)
      new(io_or_path, project).import
    end

    def initialize(io_or_path, project)
      @io_or_path = io_or_path
      @project = project
    end

    def import
      table = CSV.read(@io_or_path, headers: true, encoding: "bom|utf-8")
      raw_headers = table.headers.compact
      header_lookup = raw_headers.each_with_object({}) { |h, acc| acc[h.downcase] = h }
      custom_headers = raw_headers.reject { |h| KeilaCsv::DOWNCASED_FIELDS.include?(h.downcase) || h.downcase == "tags" }
      result = KeilaCsv::ImportResult.new

      table.each_with_index do |row, index|
        line_number = index + 2 # header line + 1-based rows

        email = value_for(row, header_lookup, "email").to_s.strip
        if email.blank?
          result.errors << { line: line_number, message: "missing email" }
          next
        end

        external_id = value_for(row, header_lookup, "external_id") if header_lookup.key?("external_id")
        new_data = extract_data(row, header_lookup, custom_headers, line_number, result)
        uid = new_data.delete(Contact::RESERVED_DATA_KEY)
        # A flat "Tags" column (case-insensitive, like the other standard
        # fields) takes priority over a "Tags" key inside a Data blob, but
        # either way it's popped out of new_data so it's never also merged
        # in as a stray ordinary custom field.
        data_tags = new_data.delete(Contact::TAGS_DATA_KEY)
        tags_value = header_lookup.key?("tags") ? value_for(row, header_lookup, "tags") : data_tags

        contact = find_matching_contact(uid: uid, external_id: external_id, email: email)
        was_new_record = contact.new_record?

        contact.email = email.downcase
        contact.first_name = value_for(row, header_lookup, "first_name") if header_lookup.key?("first_name")
        contact.last_name  = value_for(row, header_lookup, "last_name")  if header_lookup.key?("last_name")
        contact.external_id = external_id if header_lookup.key?("external_id")
        contact.status = value_for(row, header_lookup, "status") if header_lookup.key?("status")
        contact.tag_list = tags_value if tags_value
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

    def find_matching_contact(uid:, external_id:, email:)
      contact = @project.contacts.find_by(uuid: uid) if uid.present?
      contact ||= @project.contacts.find_by(external_id: external_id) if external_id.present?
      contact || @project.contacts.find_or_initialize_by(email: email.downcase)
    end

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
