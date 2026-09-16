class SettingsController < ApplicationController
  def edit
    @setting = Setting.instance
  end

  def update
    @setting = Setting.instance

    if @setting.update(setting_params)
      redirect_to edit_settings_path, notice: "Settings saved."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def test_connection
    KeilaApi.client!.list_contacts(page: 0, page_size: 1)
    redirect_to edit_settings_path, notice: "Connected to Keila successfully."
  rescue KeilaApi::Error => e
    redirect_to edit_settings_path, alert: "Could not connect to Keila: #{e.message}"
  end

  private

  def setting_params
    permitted = params.require(:setting).permit(:keila_url, :keila_api_key)
    permitted.delete(:keila_api_key) if permitted[:keila_api_key].blank?
    permitted
  end
end
