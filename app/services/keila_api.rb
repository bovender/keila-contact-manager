module KeilaApi
  class Error < StandardError; end

  # Keila's API responded with an error status.
  class ResponseError < Error
    attr_reader :status

    def initialize(status, body)
      @status = status
      super("Keila API responded with #{status}: #{body}")
    end
  end

  # No Keila URL/API key configured for this project (see KeilaProject).
  class NotConfiguredError < Error; end

  def self.client!(project)
    unless project&.configured_for_sync?
      raise NotConfiguredError, "Add a Keila instance URL and API key for this project first."
    end

    Client.new(base_url: project.keila_url, api_key: project.keila_api_key)
  end
end
