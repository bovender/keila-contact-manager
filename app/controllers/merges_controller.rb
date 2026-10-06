# Merging two contacts of the active project into one: `new` previews the
# result for the chosen leading contact, `create` carries it out (see
# ContactMerge). Both take `contact_ids` (the two contacts) and
# `leading_id` (defaulting to the first of them).
class MergesController < ApplicationController
  before_action :require_current_project
  before_action :set_merge

  def new
  end

  def create
    @merge.apply!
    redirect_to after_merge_path, notice: "Merged #{@merge.other.email} into #{@merge.leading.email}." +
      (current_project.synced? ? " The next sync deletes #{@merge.other.email} in Keila too." : "")
  rescue ActiveRecord::RecordInvalid => e
    redirect_to new_merge_path(contact_ids: [ @merge.leading.id, @merge.other.id ], return_to: params[:return_to]),
      alert: "Could not merge: #{e.record.errors.full_messages.to_sentence}"
  end

  private

  def set_merge
    ids = Array(params[:contact_ids]).compact_blank.uniq
    if ids.size != 2
      redirect_to contacts_path, alert: "Pick exactly two contacts to merge."
      return
    end

    contacts = current_project.contacts.find(ids)
    leading = contacts.find { |c| c.id.to_s == params[:leading_id].to_s } || contacts.find { |c| c.id.to_s == ids.first.to_s }
    @merge = ContactMerge.new(leading, (contacts - [ leading ]).first)
    @return_to = params[:return_to] if params[:return_to] == "duplicates"
  end

  def after_merge_path
    @return_to ? duplicates_path : contact_path(@merge.leading)
  end
end
