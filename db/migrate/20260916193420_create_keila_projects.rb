class CreateKeilaProjects < ActiveRecord::Migration[8.1]
  def change
    create_table :keila_projects do |t|
      t.string :name, null: false
      t.string :keila_url
      t.string :keila_api_key

      t.timestamps
    end
    add_index :keila_projects, :name, unique: true
  end
end
