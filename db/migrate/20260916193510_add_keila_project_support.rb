class AddKeilaProjectSupport < ActiveRecord::Migration[8.1]
  def up
    add_reference :contacts, :keila_project, foreign_key: true
    add_reference :users, :current_keila_project, foreign_key: { to_table: :keila_projects }

    # Every contact needs a project (see Contact#keila_project), so
    # existing installs need a default one to land in. Carry over the old
    # singleton Settings row (Keila URL/API key), if there was one, so
    # upgrading doesn't lose a working sync configuration.
    setting = defined?(Setting) ? Setting.first : nil
    default_project = KeilaProject.create!(
      name: "My Contacts",
      keila_url: setting&.keila_url,
      keila_api_key: setting&.keila_api_key
    )

    Contact.update_all(keila_project_id: default_project.id)
    User.update_all(current_keila_project_id: default_project.id)

    change_column_null :contacts, :keila_project_id, false

    remove_index :contacts, :email
    add_index :contacts, [ :email, :keila_project_id ], unique: true

    drop_table :settings, if_exists: true
  end

  def down
    create_table :settings do |t|
      t.string :keila_url
      t.string :keila_api_key
      t.timestamps
    end

    # Only meaningful if rolled back before app/models/setting.rb (and its
    # `encrypts`) is also removed; otherwise this just recreates an empty
    # table, which is the best a downgrade across this refactor can do.
    project = KeilaProject.first
    if project && defined?(Setting)
      Setting.reset_column_information
      Setting.create!(keila_url: project.keila_url, keila_api_key: project.keila_api_key)
    end

    remove_index :contacts, [ :email, :keila_project_id ]
    add_index :contacts, :email, unique: true

    remove_reference :users, :current_keila_project
    remove_reference :contacts, :keila_project
  end
end
