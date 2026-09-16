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

  # No Keila URL/API key configured (see Setting).
  class NotConfiguredError < Error; end

  def self.client!
    setting = Setting.instance
    unless setting.configured_for_sync?
      raise NotConfiguredError, "Add a Keila instance URL and API key in Settings first."
    end

    Client.new(base_url: setting.keila_url, api_key: setting.keila_api_key)
  end
end
