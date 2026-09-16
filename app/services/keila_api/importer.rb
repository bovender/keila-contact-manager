module KeilaApi
  # Pulls contacts from Keila via its REST API and upserts them locally,
  # scoped to a single KeilaProject (a Keila API key is itself scoped to
  # one Keila project, and matching/creating contacts here is scoped the
  # same way so the same email in two different projects never collides).
  # This is the live-sync equivalent of KeilaCsv::Importer. Matching
  # priority is the same: this app's own uuid (embedded in Data on a
  # prior export), then Keila's External_id, then email.
  #
  # Keila's contact API has no concept of tags of its own, but if a
  # contact's Data happens to include a "Tags" key (Contact::TAGS_DATA_KEY
  # -- typically because this app pushed it there previously), it's
  # applied through Contact#tag_list=, which replaces the tag list
  # outright rather than merging it. A contact with no such key in Data
  # leaves local tags untouched.
  class Importer
    PAGE_SIZE = 100

    def self.import(project:, client: KeilaApi.client!(project))
      new(project, client).import
    end

    def initialize(project, client)
      @project = project
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
      tags_value = data.delete(Contact::TAGS_DATA_KEY)
      external_id = attrs["external_id"]

      contact = find_matching_contact(uid: uid, external_id: external_id, email: email)
      was_new_record = contact.new_record?

      contact.email = email.downcase
      contact.first_name = attrs["first_name"]
      contact.last_name = attrs["last_name"]
      contact.external_id = external_id
      contact.status = attrs["status"]
      contact.tag_list = tags_value if tags_value
      contact.data = contact.data.merge(data)

      if contact.save
        result.custom_fields |= data.keys
        was_new_record ? result.created += 1 : result.updated += 1
      else
        result.errors << { line: attrs["id"], message: contact.errors.full_messages.to_sentence }
      end
    end

    def find_matching_contact(uid:, external_id:, email:)
      contact = @project.contacts.find_by(uuid: uid) if uid.present?
      contact ||= @project.contacts.find_by(external_id: external_id) if external_id.present?
      contact || @project.contacts.find_or_initialize_by(email: email.downcase)
    end
  end
end
