# Two-way sync between one project's local contacts and its Keila
# project. KeilaSync::Plan works out what changed on which side since the
# last sync, KeilaSync::Executor carries it out.
#
# A contact's "state" is the hash Contact#sync_state returns: Keila's
# built-in fields plus `data` (without Contact::RESERVED_DATA_KEY). The
# state both sides agreed on at the last sync is kept per contact as
# `sync_snapshot`; comparing each side against it is what tells a change
# made here from one made in Keila. A field is identified either by its
# attribute name ("email") or as "data:<key>" for a custom field.
module KeilaSync
  DATA_PREFIX = "data:".freeze

  class UnresolvedConflictsError < StandardError; end

  def self.remote_state(remote)
    Contact::SYNCED_ATTRIBUTES.index_with { |attr| remote[attr] }
      .merge("data" => (remote["data"] || {}).except(Contact::RESERVED_DATA_KEY))
  end

  def self.fields_of(*states)
    data_keys = states.compact.flat_map { |state| (state["data"] || {}).keys }.uniq
    Contact::SYNCED_ATTRIBUTES + data_keys.map { |key| "#{DATA_PREFIX}#{key}" }
  end

  def self.value_at(state, field)
    return nil if state.nil?

    if field.start_with?(DATA_PREFIX)
      (state["data"] || {})[field.delete_prefix(DATA_PREFIX)]
    else
      state[field]
    end
  end

  # Blank and missing are the same thing; emails compare case-insensitively
  # and tags regardless of order.
  def self.normalize(field, value)
    value = value.strip if value.is_a?(String)
    return nil if value.nil? || value == "" || value == [] || value == {}
    return value.downcase if field == "email" && value.is_a?(String)
    return value.map(&:to_s).sort if field == "#{DATA_PREFIX}#{Contact::TAGS_DATA_KEY}" && value.is_a?(Array)

    value
  end

  def self.same_value?(field, a, b)
    normalize(field, a) == normalize(field, b)
  end

  def self.same_state?(a, b)
    return false if a.nil? || b.nil?

    fields_of(a, b).all? { |field| same_value?(field, value_at(a, field), value_at(b, field)) }
  end

  # Builds a state from `base`, with the given field values set (nil
  # removes a custom field).
  def self.with_values(base, values)
    state = base.deep_dup
    state["data"] = (state["data"] || {}).dup
    values.each do |field, value|
      if field.start_with?(DATA_PREFIX)
        key = field.delete_prefix(DATA_PREFIX)
        normalize(field, value).nil? ? state["data"].delete(key) : state["data"][key] = value
      else
        state[field] = value
      end
    end
    state
  end

  def self.field_label(field)
    field.start_with?(DATA_PREFIX) ? field.delete_prefix(DATA_PREFIX) : field.humanize
  end

  # Opaque, form-safe key for one conflict decision.
  def self.token(*parts)
    Base64.urlsafe_encode64(parts.join("|"), padding: false)
  end
end
