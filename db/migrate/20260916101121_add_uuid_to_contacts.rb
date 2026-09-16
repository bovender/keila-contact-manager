class AddUuidToContacts < ActiveRecord::Migration[8.1]
  def up
    add_column :contacts, :uuid, :string
    Contact.reset_column_information
    Contact.find_each { |contact| contact.update_column(:uuid, SecureRandom.uuid) }
    change_column_null :contacts, :uuid, false
    add_index :contacts, :uuid, unique: true
  end

  def down
    remove_index :contacts, :uuid
    remove_column :contacts, :uuid
  end
end
