module KeilaApi
  # Pushes local contacts to Keila via its REST API, the live-sync
  # equivalent of KeilaCsv::Exporter. Keila's contact API has no concept
  # of tags, so tags are never sent -- only email, name, external ID,
  # status and custom data.
  #
  # Since Keila's own contact ID isn't something this app tracks, each
  # push looks the contact up by email (falling back to external_id) --
  # found means update, not found means create -- embedding this app's
  # uuid in Data so a later pull can match it back to the same local
  # record even if the email changes in Keila afterwards.
  #
  # Updates send the `data` merge through Keila's dedicated PATCH
  # .../data endpoint, never the general contact update endpoint: Keila's
  # own source (KeilaWeb.ApiContactController#update) casts `data`
  # straight through Ecto, which *replaces* the whole JSON object, not
  # merges it. Sending our local `data` there would silently delete any
  # field Keila has that this app doesn't know about -- e.g. one added
  # directly in Keila, by another integration, or by a contact filling
  # out a form.
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
      data = contact.data.merge(Contact::RESERVED_DATA_KEY => contact.uuid)

      existing = find_existing(contact)

      if existing
        id = existing["data"]["id"]
        @client.update_contact(id, attrs)
        @client.update_contact_data(id, data)
        result.updated += 1
      else
        @client.create_contact(attrs.merge(data: data))
        result.created += 1
      end
    rescue KeilaApi::ResponseError => e
      result.errors << { line: contact.email, message: e.message }
    end

    def find_existing(contact)
      @client.find_contact(contact.email, id_type: "email") ||
        (contact.external_id.present? && @client.find_contact(contact.external_id, id_type: "external_id"))
    end
  end
end
