class DuplicatesController < ApplicationController
  before_action :require_current_project

  def index
    @pairs = DuplicateFinder.for_project(current_project)
  end

  # "Not duplicates": stop suggesting this pair.
  def dismiss
    ids = Array(params[:contact_ids]).compact_blank.uniq
    if ids.size != 2
      redirect_to duplicates_path, alert: "Pick exactly two contacts."
      return
    end

    contacts = current_project.contacts.find(ids)
    DuplicateDismissal.dismiss!(*contacts)
    redirect_to duplicates_path, notice: "#{contacts.map(&:email).to_sentence} won't be suggested as duplicates again."
  end
end
