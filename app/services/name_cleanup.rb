# One-off repair for a project's contact names. Older imports left names
# in custom fields (CSV headers like "first name" that the importer didn't
# recognize as First_name back then) and "NA" in place of missing names
# (R's way of writing them). Per contact and name field:
#
# - "NA" counts as no name, built-in or custom, and is cleared;
# - a custom name fills an empty built-in one;
# - a custom name that disagrees with the built-in one is a conflict: that
#   field is left alone, for a person to decide;
# - otherwise the custom name values are removed.
#
# Custom fields that no contact has data for any more are removed from the
# registry, too. Nothing changes unless `apply` is true; without it, the
# result says what would change.
class NameCleanup
  NAME_FIELDS = %w[first_name last_name].freeze
  MISSING = "NA".freeze

  Conflict = Data.define(:contact, :field, :built_in, :custom)

  Result = Struct.new(:custom_keys, :filled, :cleared, :conflicts, :removed_keys, :contacts_changed)

  def self.run(project, apply: false)
    new(project).run(apply:)
  end

  def initialize(project)
    @project = project
  end

  def run(apply:)
    keys = custom_name_keys
    result = Result.new(keys, Hash.new(0), Hash.new(0), [], [], 0)

    ActiveRecord::Base.transaction do
      @project.contacts.find_each do |contact|
        NAME_FIELDS.each { |field| clean(contact, field, keys[field], result) }
        next unless contact.changed?

        result.contacts_changed += 1
        contact.save! if apply
      end

      # A conflict leaves its contact's custom name data in place.
      conflicted = result.conflicts.map(&:field)
      result.removed_keys = keys.except(*conflicted).values.flatten
      @project.custom_field_definitions.where(key: result.removed_keys).destroy_all if apply
    end

    result
  end

  private

  # The project's Data keys that are really one of the name fields.
  def custom_name_keys
    data_keys = @project.contacts.pluck(:data).flat_map(&:keys).uniq
    NAME_FIELDS.index_with { |field| data_keys.select { |key| KeilaCsv.standard_field(key) == field } }
  end

  # Cleans one name field of the contact, in memory.
  def clean(contact, field, keys, result)
    built_in = name(contact[field])
    custom = keys.index_with { |key| name(contact.data[key]) }.compact
    if custom.values.uniq.size > 1 || (built_in && custom.any? && custom.values.first != built_in)
      result.conflicts << Conflict.new(contact:, field:, built_in:, custom:)
      return
    end

    result.cleared[field] += 1 if contact[field].to_s.strip == MISSING
    result.filled[field] += 1 if built_in.nil? && custom.any?
    cleaned = built_in || custom.values.first
    contact[field] = cleaned unless cleaned.to_s == contact[field].to_s
    contact.data = contact.data.except(*keys)
  end

  def name(value)
    value = value.to_s.strip
    value unless value.empty? || value == MISSING
  end
end
