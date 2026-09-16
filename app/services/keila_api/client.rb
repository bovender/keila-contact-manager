require "net/http"
require "json"
require "erb"

module KeilaApi
  # Thin wrapper around the subset of Keila's REST API
  # (https://keila.io, Bearer-token authenticated, scoped to a single
  # project by the API key itself) this app uses to sync contacts.
  #
  # Notably, Keila's contact API has no concept of Tags at all -- only
  # Email, First_name, Last_name, External_id, Status and Data are
  # readable/writable through it. Tags remain CSV-only.
  class Client
    def initialize(base_url:, api_key:)
      @base_url = base_url.to_s.chomp("/")
      @api_key = api_key
    end

    # Returns { "data" => [...], "meta" => {"page" => _, "page_count" => _, "count" => _} }
    def list_contacts(page: 0, page_size: 100)
      get("/api/v1/contacts", "paginate[page]" => page, "paginate[page_size]" => page_size)
    end

    # Total contact count for the project this API key is scoped to --
    # cheap enough to show a "you're about to sync N contacts" prompt
    # before actually pulling/pushing anything.
    def contacts_count
      list_contacts(page: 0, page_size: 1).dig("meta", "count")
    end

    # id_type: nil (Keila's own id), "email", or "external_id"
    def find_contact(id, id_type: nil)
      get("/api/v1/contacts/#{ERB::Util.url_encode(id)}", (id_type && { "id_type" => id_type }) || {})
    rescue ResponseError => e
      raise unless e.status == 404

      nil
    end

    def create_contact(attrs)
      post("/api/v1/contacts", data: attrs)
    end

    # Shallow-merges attrs (typically just the custom `data` hash) into
    # the existing contact instead of replacing it outright.
    def update_contact_data(id, data, id_type: nil)
      patch("/api/v1/contacts/#{ERB::Util.url_encode(id)}/data", (id_type && { "id_type" => id_type }) || {}, data: data)
    end

    def update_contact(id, attrs, id_type: nil)
      patch("/api/v1/contacts/#{ERB::Util.url_encode(id)}", (id_type && { "id_type" => id_type }) || {}, data: attrs)
    end

    private

    def get(path, query)
      request(Net::HTTP::Get, path, query: query)
    end

    def post(path, body)
      request(Net::HTTP::Post, path, body: body)
    end

    def patch(path, query, body)
      request(Net::HTTP::Patch, path, query: query, body: body)
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

      response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https") { |http| http.request(req) }

      case response
      when Net::HTTPSuccess
        JSON.parse(response.body || "{}")
      else
        raise ResponseError.new(response.code.to_i, response.body)
      end
    end
  end
end
