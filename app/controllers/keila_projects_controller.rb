class KeilaProjectsController < ApplicationController
  before_action :set_keila_project, only: %i[edit update destroy activate test_connection]

  def index
    @keila_projects = KeilaProject.order(:name)
  end

  def new
    @keila_project = KeilaProject.new
  end

  def create
    @keila_project = KeilaProject.new(keila_project_params)

    if @keila_project.save
      Current.user.update!(current_keila_project: @keila_project) if current_project.nil?
      redirect_to keila_projects_path, notice: "Project created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @keila_project.update(keila_project_params)
      redirect_to keila_projects_path, notice: "Project updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    if @keila_project.destroy
      redirect_to keila_projects_path, notice: "Project deleted."
    else
      redirect_to keila_projects_path, alert: @keila_project.errors.full_messages.to_sentence
    end
  end

  def activate
    Current.user.update!(current_keila_project: @keila_project)
    redirect_to contacts_path, notice: "Switched to #{@keila_project.name}."
  end

  def test_connection
    unless @keila_project.configured_for_sync?
      redirect_to keila_projects_path, alert: "Add a Keila instance URL and API key for this project first."
      return
    end

    KeilaApi::Client.new(base_url: @keila_project.keila_url, api_key: @keila_project.keila_api_key)
      .list_contacts(page: 0, page_size: 1)
    redirect_to keila_projects_path, notice: "Connected to Keila successfully."
  rescue KeilaApi::Error => e
    redirect_to keila_projects_path, alert: "Could not connect to Keila: #{e.message}"
  end

  private

  def set_keila_project
    @keila_project = KeilaProject.find(params[:id])
  end

  def keila_project_params
    permitted = params.require(:keila_project).permit(:name, :keila_url, :keila_api_key)
    permitted.delete(:keila_api_key) if permitted[:keila_api_key].blank?
    permitted
  end
end
