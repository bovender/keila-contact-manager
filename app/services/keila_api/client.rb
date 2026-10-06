require "net/http"
require "json"
require "erb"

module KeilaApi
  # Thin wrapper around the subset of Keila's REST API
  # (https://keila.io, Bearer-token authenticated, scoped to a single
  # project by the API key itself) this app uses to sync contacts.
  #
  # Contacts are always addressed by Keila's own id here; KeilaSync keeps
  # track of it per contact.
  class Client
    # Keila sorts its contact list by insertion time alone (to the second,
    # without a tiebreaker), so the order of contacts inserted in the same
    # second -- e.g. by one CSV import -- can differ between two requests.
    # Fetched page by page, such contacts can then show up on two pages and
    # be missing from both, which a sync would take for contacts deleted in
    # Keila. So all_contacts asks for everything as a single page (Keila
    # doesn't limit the page size), and rejects a list with repeats.
    PAGE_SIZE = 10_000

    def initialize(base_url:, api_key:)
      @base_url = base_url.to_s.chomp("/")
      @api_key = api_key
    end

    # Returns { "data" => [...], "meta" => {"page" => _, "page_count" => _, "count" => _} }
    def list_contacts(page: 0, page_size: 100)
      get("/api/v1/contacts", "paginate[page]" => page, "paginate[page_size]" => page_size)
    end

    # Every contact in the project, as an array of contact hashes.
    def all_contacts
      response = list_contacts(page: 0, page_size: PAGE_SIZE)
      if response.dig("meta", "count").to_i > PAGE_SIZE
        # Room for contacts signing up in the meantime.
        response = list_contacts(page: 0, page_size: response.dig("meta", "count").to_i + 100)
      end

      contacts = response["data"] || []
      count = response.dig("meta", "count").to_i
      repeated = contacts.map { |contact| contact["id"] }.tally.count { |_, n| n > 1 }
      if repeated.positive? || contacts.size < count
        raise InconsistentListError, "Keila returned an inconsistent contact list (#{contacts.size} contacts, " \
                                     "#{repeated} of them more than once, #{count} expected). Please try again."
      end
      contacts
    end

    # The create/update calls return the contact as Keila stored it.
    def create_contact(attrs)
      post("/api/v1/contacts", data: attrs)["data"]
    end

    # Only the built-in fields: Keila *replaces* `data` wholesale when it's
    # sent here, so data changes go through the dedicated endpoints below.
    def update_contact(id, attrs)
      patch("/api/v1/contacts/#{ERB::Util.url_encode(id)}", data: attrs)["data"]
    end

    # Shallow-merges the given keys into the contact's existing data.
    def update_contact_data(id, data)
      patch("/api/v1/contacts/#{ERB::Util.url_encode(id)}/data", data: data)["data"]
    end

    # Replaces the contact's data outright -- the only way to remove a key.
    def replace_contact_data(id, data)
      post("/api/v1/contacts/#{ERB::Util.url_encode(id)}/data", data: data)["data"]
    end

    def delete_contact(id)
      request(Net::HTTP::Delete, "/api/v1/contacts/#{ERB::Util.url_encode(id)}")
    end

    private

    def get(path, query)
      request(Net::HTTP::Get, path, query: query)
    end

    def post(path, body)
      request(Net::HTTP::Post, path, body: body)
    end

    def patch(path, body)
      request(Net::HTTP::Patch, path, body: body)
    end

    def request(http_method_class, path, query: {}, body: nil)
      uri = URI("#{@base_url}#{path}")
      uri.query = URI.encode_www_form(query) if query.present?

      req = http_method_class.new(uri)
      req["Authorization"] = "Bearer #{@api_key}"
      req["Accept"] = "application/json"
      if body
        req["Content-Type"] = "application/json"
        req.body = body.to_json
      end

      response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https",
                                 open_timeout: 10, read_timeout: 60) { |http| http.request(req) }

      case response
      when Net::HTTPSuccess
        response.body.present? ? JSON.parse(response.body) : {}
      else
        raise ResponseError.new(response.code.to_i, response.body)
      end
    rescue SocketError, SystemCallError, Net::OpenTimeout, Net::ReadTimeout, OpenSSL::SSL::SSLError => e
      raise ConnectionError, "Could not reach Keila at #{@base_url}: #{e.message}"
    end
  end
end
