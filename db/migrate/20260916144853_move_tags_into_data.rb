class MoveTagsIntoData < ActiveRecord::Migration[8.1]
  def up
    Contact.reset_column_information
    Contact.find_each do |contact|
      # contact[:tags]/contact[:data], not contact.tags/contact.data: reads
      # the raw column via the attribute set, immune to Contact#tags being
      # redefined later to read from `data` instead of this soon-to-be-
      # removed column.
      raw_tags = contact[:tags]
      next if raw_tags.blank?

      contact.update_column(:data, contact[:data].merge("Tags" => raw_tags))
    end
    remove_column :contacts, :tags
  end

  def down
    add_column :contacts, :tags, :json, null: false, default: []
    Contact.reset_column_information
    Contact.find_each do |contact|
      data = contact[:data].dup
      tags = data.delete("Tags") || []
      contact.update_columns(tags: tags, data: data)
    end
  end
end
