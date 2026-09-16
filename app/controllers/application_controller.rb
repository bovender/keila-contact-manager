class ApplicationController < ActionController::Base
  include Authentication
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  helper_method :current_project

  private

  # The Keila project the signed-in user is currently working in. Every
  # contact belongs to exactly one project, so most of the app (contacts,
  # custom fields, sync) operates within whichever project this is.
  def current_project
    Current.user&.current_keila_project
  end
end
