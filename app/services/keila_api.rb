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

  # Keila couldn't be reached at all.
  class ConnectionError < Error; end

  # Keila's contact list had repeats or gaps (see Client#all_contacts), so
  # it can't be trusted to tell which contacts exist.
  class InconsistentListError < Error; end

  # No Keila instance URL (KEILA_URL) or no API key for this project.
  class NotConfiguredError < Error; end

  def self.client!(project)
    if KeilaProject.keila_url.blank?
      raise NotConfiguredError, "No Keila instance configured -- set the KEILA_URL environment variable."
    end
    unless project&.configured_for_sync?
      raise NotConfiguredError, "Add this project's Keila API key first."
    end

    Client.new(base_url: KeilaProject.keila_url, api_key: project.keila_api_key)
  end
end
