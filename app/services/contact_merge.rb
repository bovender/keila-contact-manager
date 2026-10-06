# Merges two contacts that turned out to be the same subscriber into the
# one the user picked as leading. The leading contact keeps its email and
# every value it has; the other contact only fills in what the leading
# one leaves blank, plus its tags. One exception: an "unsubscribed" status
# on either contact is kept, so a merge never signs anyone up again.
#
# The other contact is then deleted like any other (Contact#destroy), so
# if it had been synced, the next sync deletes it in Keila too, and pushes
# the leading contact's new values.
class ContactMerge
  # `source` is where the merged value comes from: :leading, :other, or
  # :both (tags combined from the two).
  Row = Struct.new(:label, :leading, :other, :result, :source)

  attr_reader :leading, :other

  def initialize(leading, other)
    raise ArgumentError, "can't merge a contact with itself" if leading == other
    raise ArgumentError, "contacts belong to different projects" if leading.keila_project_id != other.keila_project_id

    @leading = leading
    @other = other
  end

  def rows
    @rows ||= [
      Row.new("Email", leading.email, other.email, leading.email, :leading),
      filled_in("First name", :first_name),
      filled_in("Last name", :last_name),
      filled_in("External ID", :external_id),
      status_row,
      tags_row,
      *data_keys.map { |key| filled_in(labels.fetch(key, key), key, data: true) }
    ]
  end

  def apply!
    Contact.transaction do
      other.destroy!
      leading.first_name = result_of(:first_name)
      leading.last_name = result_of(:last_name)
      leading.external_id = result_of(:external_id)
      leading.status = status_row.result
      leading.data = merged_data
      leading.save!
    end
  end

  private

  def filled_in(label, key, data: false)
    mine = data ? leading.custom_field(key) : leading[key]
    theirs = data ? other.custom_field(key) : other[key]
    if mine.blank? && theirs.present?
      Row.new(label, mine, theirs, theirs, :other)
    else
      Row.new(label, mine, theirs, mine, :leading)
    end
  end

  def status_row
    @status_row ||=
      if other.status == "unsubscribed" && leading.status != "unsubscribed"
        Row.new("Status", leading.status, other.status, "unsubscribed", :other)
      else
        filled_in("Status", :status)
      end
  end

  def tags_row
    tags = (leading.tags + other.tags).uniq
    Row.new("Tags", leading.tags, other.tags, tags, tags == leading.tags ? :leading : :both)
  end

  def result_of(attribute)
    leading[attribute].presence || other[attribute]
  end

  def merged_data
    data = leading.data.dup
    data_keys.each { |key| data[key] = other.custom_field(key) if data[key].blank? && other.custom_field(key).present? }
    tags = tags_row.result
    tags.empty? ? data.except(Contact::TAGS_DATA_KEY) : data.merge(Contact::TAGS_DATA_KEY => tags)
  end

  def data_keys
    (leading.data.keys | other.data.keys) - [ Contact::RESERVED_DATA_KEY, Contact::TAGS_DATA_KEY ]
  end

  def labels
    @labels ||= leading.keila_project.custom_field_definitions.to_h { |cfd| [ cfd.key, cfd.label ] }
  end
end
