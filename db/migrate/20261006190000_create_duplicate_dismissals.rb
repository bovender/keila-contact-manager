class CreateDuplicateDismissals < ActiveRecord::Migration[8.1]
  def change
    # Pairs of contacts the user has marked as "not duplicates", so the
    # duplicates page stops suggesting them. Stored with the lower contact
    # id first; deleting either contact removes the pair.
    create_table :duplicate_dismissals do |t|
      t.references :contact, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.references :other_contact, null: false, foreign_key: { to_table: :contacts, on_delete: :cascade }
      t.timestamps
    end
    add_index :duplicate_dismissals, %i[contact_id other_contact_id], unique: true
  end
end
