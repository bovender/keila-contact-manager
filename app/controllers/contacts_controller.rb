class ContactsController < ApplicationController
  PER_PAGE = 50

  before_action :set_contact, only: %i[show edit update destroy]
  before_action :set_all_tags, only: %i[index new create edit update]

  def index
    @q = params[:q]
    @tag = params[:tag]

    scope = Contact.search(@q).tagged_with(@tag).order(:email)
    @page = [ params[:page].to_i, 1 ].max
    @total_count = scope.count
    @contacts = scope.offset((@page - 1) * PER_PAGE).limit(PER_PAGE)
    @total_pages = (@total_count / PER_PAGE.to_f).ceil
  end

  def show
    @custom_field_definitions = CustomFieldDefinition.all
  end

  def new
    @contact = Contact.new
    @custom_field_definitions = CustomFieldDefinition.all
  end

  def create
    @contact = Contact.new
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

    result = KeilaCsv::Importer.import(file.path)
    notice = "Imported #{result.success_count} contact(s)."
    notice += " #{result.error_count} row(s) had errors: #{result.errors.first(5).map { |e| "line #{e[:line]}: #{e[:message]}" }.join('; ')}" if result.error_count.positive?
    redirect_to contacts_path, notice: notice
  rescue CSV::MalformedCSVError => e
    redirect_to import_contacts_path, alert: "Import failed: #{e.message}"
  end

  def export
    send_data KeilaCsv::Exporter.export, filename: "contacts-#{Date.current.iso8601}.csv", type: "text/csv"
  end

  def bulk_update
    contacts = target_contacts
    tag = params[:tag].to_s.strip
    count = contacts.count

    if tag.present?
      case params[:operation]
      when "tag"
        contacts.find_each { |c| c.update!(tags: (c.tags + [ tag ]).uniq) }
      when "untag"
        contacts.find_each { |c| c.update!(tags: c.tags - [ tag ]) }
      end
    end

    redirect_to contacts_path(q: params[:q], tag: params[:current_tag]), notice: "Updated #{count} contact(s)."
  end

  def bulk_destroy
    count = target_contacts.destroy_all.size
    redirect_to contacts_path(q: params[:q], tag: params[:current_tag]), notice: "Deleted #{count} contact(s)."
  end

  private

  # All contacts currently matching the index filter (when the "select all
  # N matching this filter" banner was used) or just the checked ones.
  def target_contacts
    if ActiveModel::Type::Boolean.new.cast(params[:select_all_matching])
      Contact.search(params[:q]).tagged_with(params[:current_tag])
    else
      Contact.where(id: params[:contact_ids])
    end
  end

  def set_contact
    @contact = Contact.find(params[:id])
  end

  def set_all_tags
    @all_tags = Contact.pluck(:tags).flatten.uniq.sort
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
