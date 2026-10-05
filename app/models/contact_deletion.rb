# Tombstone for a contact deleted here after it had been synced with
# Keila, so the next sync deletes it in Keila too instead of pulling it
# straight back. `snapshot` is the contact's last synced state: if Keila's
# copy no longer matches it, the contact was changed there in the
# meantime, and the deletion becomes a conflict to decide on.
class ContactDeletion < ApplicationRecord
  belongs_to :keila_project

  validates :keila_id, presence: true, uniqueness: { scope: :keila_project_id }
end
