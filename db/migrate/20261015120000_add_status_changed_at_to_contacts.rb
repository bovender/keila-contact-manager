class AddStatusChangedAtToContacts < ActiveRecord::Migration[8.1]
  def change
    # When the contact got its current status, so contacts unsubscribed for
    # a while can be pointed out for deletion. Existing contacts get the
    # time of their last change, which is no earlier than their status's.
    add_column :contacts, :status_changed_at, :datetime

    up_only do
      execute "UPDATE contacts SET status_changed_at = updated_at WHERE status IS NOT NULL"
    end
  end
end
