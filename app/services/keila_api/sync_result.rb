module KeilaApi
  SyncResult = Struct.new(:created, :updated, :errors, :custom_fields) do
    def initialize(created: 0, updated: 0, errors: [], custom_fields: [])
      super
    end

    def success_count
      created + updated
    end

    def error_count
      errors.size
    end
  end
end
