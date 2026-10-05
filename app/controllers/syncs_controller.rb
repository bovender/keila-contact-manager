class SyncsController < ApplicationController
  # How long the contacts page banner may reuse Keila's contact list. Only
  # the banner does; the review screen and the sync itself always fetch
  # it fresh.
  STATUS_CACHE_TTL = 1.minute

  before_action :require_current_project

  # The "sync due?" banner on the contacts page, loaded lazily into a
  # Turbo Frame so the contacts table never waits for Keila.
  def status
    if current_project.configured_for_sync?
      remote = Rails.cache.fetch(status_cache_key, expires_in: STATUS_CACHE_TTL) do
        KeilaApi.client!(current_project).all_contacts
      end
      @plan = KeilaSync::Plan.build(current_project, remote_contacts: remote)
    end
    render layout: false
  rescue KeilaApi::Error => e
    @error = e.message
    render layout: false
  end

  def show
    @plan = KeilaSync::Plan.build(current_project)
  rescue KeilaApi::Error => e
    redirect_to contacts_path, alert: "Could not reach Keila: #{e.message}"
  end

  def create
    plan = KeilaSync::Plan.build(current_project)
    resolutions = params[:resolutions].respond_to?(:to_unsafe_h) ? params[:resolutions].to_unsafe_h : {}

    if params[:one_click].present? && !plan.one_click?
      redirect_to sync_path, alert: "Something changed in the meantime that needs a look before syncing."
      return
    end
    if plan.unresolved(resolutions).any?
      redirect_to sync_path, alert: "Please decide every conflict first. (Keila may also have changed in the meantime.)"
      return
    end

    result = KeilaSync::Executor.run(plan, resolutions: resolutions)
    Rails.cache.delete(status_cache_key)
    redirect_to contacts_path, **summary_flash(result)
  rescue KeilaApi::Error => e
    redirect_to contacts_path, alert: "Sync with Keila failed: #{e.message}"
  end

  private

  def status_cache_key
    [ "keila-remote-contacts", current_project.id ]
  end

  def summary_flash(result)
    parts = []
    parts << "#{result.pulled} updated from Keila" if result.pulled.positive?
    parts << "#{result.pushed} updated in Keila" if result.pushed.positive?
    parts << "#{result.deleted_here} deleted here" if result.deleted_here.positive?
    parts << "#{result.deleted_in_keila} deleted in Keila" if result.deleted_in_keila.positive?
    message = parts.any? ? "Synced with Keila: #{parts.to_sentence}." : "Synced with Keila, nothing to change."

    if result.errors.any?
      details = result.errors.first(5).map { |e| "#{e[:email]}: #{e[:message]}" }.join("; ")
      { alert: "#{message} #{result.errors.size} contact(s) failed: #{details}" }
    else
      { notice: message }
    end
  end
end
