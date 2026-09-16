class CreateCustomFieldDefinitions < ActiveRecord::Migration[8.1]
  def change
    create_table :custom_field_definitions do |t|
      t.string :key, null: false
      t.string :label, null: false
      t.integer :position, null: false, default: 0

      t.timestamps
    end
    add_index :custom_field_definitions, :key, unique: true
  end
end
