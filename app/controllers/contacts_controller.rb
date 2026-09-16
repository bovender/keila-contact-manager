class ContactsController < ApplicationController
  PER_PAGE = 50

  before_action :require_current_project
  before_action :set_contact, only: %i[show edit update destroy]
  before_action :set_all_tags, only: %i[index new create edit update]

  def index
    @q = params[:q]
    @tag = params[:tag]
    @keila_configured = current_project.configured_for_sync?

    scope = current_project.contacts.search(@q).tagged_with(@tag).order(:email)
    @page = [ params[:page].to_i, 1 ].max
    @total_count = scope.count
    @contacts = scope.offset((@page - 1) * PER_PAGE).limit(PER_PAGE)
    @total_pages = (@total_count / PER_PAGE.to_f).ceil
  end

  def show
    @custom_field_definitions = CustomFieldDefinition.all
  end

  def new
    @contact = current_project.contacts.new
    @custom_field_definitions = CustomFieldDefinition.all
  end

  def create
    @contact = current_project.contacts.new
    assign_contact_attributes

    if @contact.save
      redirect_to contacts_path, notice: "Contact created."
    else
      @custom_field_definitions = CustomFieldDefinition.all
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    @custom_field_definitions = CustomFieldDefinition.all
  end

  def update
    assign_contact_attributes

    if @contact.save
      redirect_to contacts_path, notice: "Contact updated."
    else
      @custom_field_definitions = CustomFieldDefinition.all
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @contact.destroy
    redirect_to contacts_path, notice: "Contact deleted."
  end

  def import
  end

  def do_import
    file = params[:file]
    if file.blank?
      redirect_to import_contacts_path, alert: "Please choose a CSV file."
      return
    end

    result = KeilaCsv::Importer.import(file.path, project: current_project)
    notice = "Imported #{result.success_count} contact(s)."
    notice += " #{result.error_count} row(s) had errors: #{result.errors.first(5).map { |e| "line #{e[:line]}: #{e[:message]}" }.join('; ')}" if result.error_count.positive?
    redirect_to contacts_path, notice: notice
  rescue CSV::MalformedCSVError => e
    redirect_to import_contacts_path, alert: "Import failed: #{e.message}"
  end

  def export
    send_data KeilaCsv::Exporter.export(project: current_project), filename: "contacts-#{Date.current.iso8601}.csv", type: "text/csv"
  end

  # Confirmation screens: syncing the wrong Keila instance (a typo'd URL,
  # an API key for a different project than you meant) would otherwise
  # silently merge or push into a project you never intended to touch.
  # Showing both sides' contact counts up front gives you a chance to
  # notice before anything happens.
  def sync_from_keila
    @keila_count = KeilaApi.client!(current_project).contacts_count
    @local_count = current_project.contacts.count
  rescue KeilaApi::Error => e
    redirect_to contacts_path, alert: "Could not reach Keila: #{e.message}"
  end

  def do_sync_from_keila
    result = KeilaApi::Importer.import(project: current_project)
    redirect_to contacts_path, notice: sync_summary("Pulled", result)
  rescue KeilaApi::Error => e
    redirect_to contacts_path, alert: "Sync from Keila failed: #{e.message}"
  end

  def push_to_keila
    @keila_count = KeilaApi.client!(current_project).contacts_count
    @local_count = current_project.contacts.count
  rescue KeilaApi::Error => e
    redirect_to contacts_path, alert: "Could not reach Keila: #{e.message}"
  end

  def do_push_to_keila
    result = KeilaApi::Exporter.export(project: current_project)
    redirect_to contacts_path, notice: sync_summary("Pushed", result)
  rescue KeilaApi::Error => e
    redirect_to contacts_path, alert: "Push to Keila failed: #{e.message}"
  end

  def bulk_update
    tag = params[:tag].to_s.strip
    if tag.blank?
      redirect_to contacts_path(q: params[:q], tag: params[:current_tag]), alert: "Enter a tag name to add or remove it."
      return
    end

    contacts = target_contacts
    count = contacts.count
    if count.zero?
      redirect_to contacts_path(q: params[:q], tag: params[:current_tag]), alert: "Select at least one contact first."
      return
    end

    case params[:operation]
    when "tag"
      contacts.find_each { |c| c.update!(tags: (c.tags + [ tag ]).uniq) }
    when "untag"
      contacts.find_each { |c| c.update!(tags: c.tags - [ tag ]) }
    end

    redirect_to contacts_path(q: params[:q], tag: params[:current_tag]), notice: "Updated #{count} contact(s)."
  end

  def bulk_destroy
    count = target_contacts.destroy_all.size
    redirect_to contacts_path(q: params[:q], tag: params[:current_tag]), notice: "Deleted #{count} contact(s)."
  end

  private

  def require_current_project
    return if current_project

    redirect_to keila_projects_path, alert: "Create or switch to a project first."
  end

  # All of the current project's contacts matching the index filter (when
  # the "select all N matching this filter" banner was used) or just the
  # checked ones.
  def target_contacts
    if ActiveModel::Type::Boolean.new.cast(params[:select_all_matching])
      current_project.contacts.search(params[:q]).tagged_with(params[:current_tag])
    else
      current_project.contacts.where(id: params[:contact_ids])
    end
  end

  def set_contact
    @contact = current_project.contacts.find(params[:id])
  end

  def set_all_tags
    @all_tags = current_project.contacts.pluck(:data).flat_map { |data| data[Contact::TAGS_DATA_KEY] || [] }.uniq.sort
  end

  def sync_summary(verb, result)
    summary = "#{verb} #{result.success_count} contact(s) (#{result.created} new, #{result.updated} updated)."
    if result.error_count.positive?
      summary += " #{result.error_count} failed: #{result.errors.first(5).map { |e| e[:message] }.join('; ')}"
    end
    summary
  end

  def contact_params
    params.require(:contact).permit(
      :email, :first_name, :last_name, :external_id, :status, :tag_list,
      custom_fields: {}
    )
  end

  def assign_contact_attributes
    attrs = contact_params
    custom_fields = attrs.delete(:custom_fields) || {}
    @contact.assign_attributes(attrs)
    custom_fields.each { |key, value| @contact.set_custom_field(key, value) }
  end
end
