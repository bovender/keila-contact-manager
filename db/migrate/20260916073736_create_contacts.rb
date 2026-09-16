class CreateContacts < ActiveRecord::Migration[8.1]
  def change
    create_table :contacts do |t|
      t.string :email, null: false
      t.string :first_name
      t.string :last_name
      t.string :external_id
      t.string :status
      t.json :tags, null: false, default: []
      t.json :data, null: false, default: {}

      t.timestamps
    end
    add_index :contacts, :email, unique: true
    add_index :contacts, :external_id
  end
end
