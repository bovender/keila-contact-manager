class UnsubscribedContactsController < ApplicationController
  before_action :require_current_project

  def index
    @contacts = current_project.contacts.unsubscribed.order(:status_changed_at, :email)
  end

  # Only contacts still unsubscribed, in case one signed up again after
  # the page was loaded (a sync can turn them active meanwhile).
  def purge
    contacts = current_project.contacts.unsubscribed.where(id: Array(params[:contact_ids]).compact_blank)
    if contacts.none?
      redirect_to unsubscribed_contacts_path, alert: "Select at least one contact first."
      return
    end

    count = contacts.destroy_all.size
    redirect_to unsubscribed_contacts_path, notice: "Deleted #{helpers.pluralize(count, 'unsubscribed contact')}. " \
                                                    "The next sync deletes them in Keila too."
  end
end
