# A pair of contacts the user has looked at on the duplicates page and
# decided are different people, so DuplicateFinder stops suggesting it.
# The lower contact id always goes first, which makes the pair unique
# regardless of the order it's given in.
class DuplicateDismissal < ApplicationRecord
  belongs_to :contact
  belongs_to :other_contact, class_name: "Contact"

  validates :other_contact_id, uniqueness: { scope: :contact_id }
  validate :same_project

  def self.dismiss!(a, b)
    first, second = [ a, b ].sort_by(&:id)
    find_or_create_by!(contact: first, other_contact: second)
  end

  # Dismissed pairs among a project's contacts, as [lower id, higher id].
  def self.pairs_for(project)
    where(contact_id: project.contacts.select(:id)).pluck(:contact_id, :other_contact_id).to_set
  end

  private

  def same_project
    return if contact.nil? || other_contact.nil?

    errors.add(:other_contact, "belongs to a different project") if contact.keila_project_id != other_contact.keila_project_id
  end
end
