class Setting < ApplicationRecord
  encrypts :keila_api_key

  validates :keila_url, format: { with: URI::DEFAULT_PARSER.make_regexp(%w[http https]), allow_blank: true }

  # This app only ever manages a single settings row.
  def self.instance
    first_or_create!
  end

  def configured_for_sync?
    keila_url.present? && keila_api_key.present?
  end
end
