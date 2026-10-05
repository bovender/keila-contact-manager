module SyncsHelper
  def sync_value(value)
    return tag.span("empty", class: "italic text-gray-400") if KeilaSync.normalize(nil, value).nil?

    value.is_a?(Array) ? value.join(", ") : value.to_s
  end

  def sync_field_label(field)
    KeilaSync.field_label(field)
  end

  # "First name: Ann → Anna; Tags: vip → vip, board"
  def sync_field_changes(item, fields)
    safe_join(fields.map { |field|
      f = item.fields[field]
      from, to = f[:action] == :pull ? [ f[:local], f[:remote] ] : [ f[:remote], f[:local] ]
      safe_join([ tag.span("#{sync_field_label(field)}:", class: "text-gray-500"), " ", sync_value(from), " → ", sync_value(to) ])
    }, tag.span("; ", class: "text-gray-400"))
  end

  def sync_item_description(item, fields)
    case item.kind
    when :create_local then "new in Keila, will be added here"
    when :create_remote then "new here, will be added to Keila"
    when :delete_local then tag.span("deleted in Keila, will be deleted here", class: "text-red-600")
    when :delete_remote then tag.span("deleted here, will be deleted in Keila", class: "text-red-600")
    else sync_field_changes(item, fields)
    end
  end
end
