class BindProjectsToSingleKeilaInstance < ActiveRecord::Migration[8.1]
  # The app is now bound to exactly one Keila instance (KEILA_URL), and a
  # project here *is* a project in that instance -- identified by its API
  # key, since Keila scopes every API key to a single project. The
  # per-project URL goes away, custom fields become per project (each Keila
  # project has its own Data keys), and contacts gain what two-way sync
  # needs: Keila's own contact id, a snapshot of the state both sides
  # agreed on at the last sync, and tombstones for local deletions.
  def up
    remove_column :keila_projects, :keila_url, :string
    add_column :keila_projects, :last_synced_at, :datetime

    add_column :contacts, :keila_id, :string
    add_column :contacts, :sync_snapshot, :json
    add_index :contacts, [ :keila_project_id, :keila_id ], unique: true

    create_table :contact_deletions do |t|
      t.references :keila_project, null: false, foreign_key: true
      t.string :keila_id, null: false
      t.string :email
      t.json :snapshot
      t.timestamps
    end
    add_index :contact_deletions, [ :keila_project_id, :keila_id ], unique: true

    add_reference :custom_field_definitions, :keila_project, foreign_key: true
    remove_index :custom_field_definitions, :key
    # Every existing project gets its own copy of the old global registry.
    execute <<~SQL
      INSERT INTO custom_field_definitions (key, label, position, keila_project_id, created_at, updated_at)
      SELECT d.key, d.label, d.position, p.id, d.created_at, d.updated_at
      FROM custom_field_definitions d CROSS JOIN keila_projects p
      WHERE d.keila_project_id IS NULL
    SQL
    execute "DELETE FROM custom_field_definitions WHERE keila_project_id IS NULL"
    change_column_null :custom_field_definitions, :keila_project_id, false
    add_index :custom_field_definitions, [ :keila_project_id, :key ], unique: true
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
