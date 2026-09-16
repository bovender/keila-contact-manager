module KeilaApi
  # Pulls contacts from Keila via its REST API and upserts them locally,
  # the live-sync equivalent of KeilaCsv::Importer. Matching priority is
  # the same: this app's own uuid (embedded in Data on a prior export),
  # then Keila's External_id, then email.
  #
  # Deliberately never touches Contact#tags: Keila's contact API has no
  # concept of tags at all, so a synced contact carries no tag
  # information one way or the other. Touching tags here would silently
  # wipe out whatever was set locally or via CSV import.
  class Importer
    PAGE_SIZE = 100

    def self.import(client: KeilaApi.client!)
      new(client).import
    end

    def initialize(client)
      @client = client
    end

    def import
      result = SyncResult.new
      page = 0

      loop do
        response = @client.list_contacts(page: page, page_size: PAGE_SIZE)
        contacts = response["data"] || []
        contacts.each { |attrs| import_contact(attrs, result) }

        page += 1
        break if page >= response.dig("meta", "page_count").to_i
      end

      result.custom_fields.each { |key| CustomFieldDefinition.register!(key) }
      result
    end

    private

    def import_contact(attrs, result)
      email = attrs["email"].to_s.strip
      if email.blank?
        result.errors << { line: attrs["id"], message: "missing email" }
        return
      end

      data = (attrs["data"] || {}).dup
      uid = data.delete(Contact::RESERVED_DATA_KEY)
      external_id = attrs["external_id"]

      contact = find_matching_contact(uid: uid, external_id: external_id, email: email)
      was_new_record = contact.new_record?

      contact.email = email.downcase
      contact.first_name = attrs["first_name"]
      contact.last_name = attrs["last_name"]
      contact.external_id = external_id
      contact.status = attrs["status"]
      contact.data = contact.data.merge(data)

      if contact.save
        result.custom_fields |= data.keys
        was_new_record ? result.created += 1 : result.updated += 1
      else
        result.errors << { line: attrs["id"], message: contact.errors.full_messages.to_sentence }
      end
    end

    def find_matching_contact(uid:, external_id:, email:)
      contact = Contact.find_by(uuid: uid) if uid.present?
      contact ||= Contact.find_by(external_id: external_id) if external_id.present?
      contact || Contact.find_or_initialize_by(email: email.downcase)
    end
  end
end
