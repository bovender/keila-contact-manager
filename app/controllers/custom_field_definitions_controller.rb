class CustomFieldDefinitionsController < ApplicationController
  def index
    @custom_field_definitions = CustomFieldDefinition.all
  end

  def create
    @custom_field_definition = CustomFieldDefinition.new(custom_field_definition_params)

    if @custom_field_definition.save
      redirect_back fallback_location: custom_field_definitions_path, notice: "Custom field added."
    else
      redirect_back fallback_location: custom_field_definitions_path,
                     alert: @custom_field_definition.errors.full_messages.to_sentence
    end
  end

  def update
    @custom_field_definition = CustomFieldDefinition.find(params[:id])

    if @custom_field_definition.update(custom_field_definition_params)
      redirect_to custom_field_definitions_path, notice: "Custom field updated."
    else
      redirect_to custom_field_definitions_path, alert: @custom_field_definition.errors.full_messages.to_sentence
    end
  end

  def destroy
    @custom_field_definition = CustomFieldDefinition.find(params[:id])
    @custom_field_definition.destroy
    redirect_to custom_field_definitions_path, notice: "Custom field removed from the registry (existing contact data is kept)."
  end

  private

  def custom_field_definition_params
    params.require(:custom_field_definition).permit(:key, :label, :position)
  end
end
