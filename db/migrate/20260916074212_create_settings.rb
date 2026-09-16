class CreateSettings < ActiveRecord::Migration[8.1]
  def change
    create_table :settings do |t|
      t.string :keila_url
      t.string :keila_api_key

      t.timestamps
    end
  end
end
