module KeilaApi
  # Pushes local contacts to Keila via its REST API, the live-sync
  # equivalent of KeilaCsv::Exporter. Keila's contact API has no concept
  # of tags, so tags are never sent -- only email, name, external ID,
  # status and custom data.
  #
  # Since Keila's own contact ID isn't something this app tracks, each
  # push looks the contact up by email first: found means update, not
  # found means create (embedding this app's uuid in Data so a later
  # pull can match it back to the same local record even if the email
  # changes in Keila afterwards).
  class Exporter
    def self.export(contacts = Contact.order(:email), client: KeilaApi.client!)
      new(client).export(contacts)
    end

    def initialize(client)
      @client = client
    end

    def export(contacts)
      result = SyncResult.new
      contacts.find_each { |contact| push_contact(contact, result) }
      result
    end

    private

    def push_contact(contact, result)
      # Keila's API rejects explicit null for these fields (400 "null_value")
      # rather than treating it as "leave unset" -- omit anything blank
      # instead of sending it as nil.
      attrs = {
        email: contact.email,
        first_name: contact.first_name,
        last_name: contact.last_name,
        external_id: contact.external_id,
        status: contact.status
      }.compact
      attrs[:data] = contact.data.merge(Contact::RESERVED_DATA_KEY => contact.uuid)

      existing = @client.find_contact(contact.email, id_type: "email")

      if existing
        @client.update_contact(existing["data"]["id"], attrs)
        result.updated += 1
      else
        @client.create_contact(attrs)
        result.created += 1
      end
    rescue KeilaApi::ResponseError => e
      result.errors << { line: contact.email, message: e.message }
    end
  end
end
