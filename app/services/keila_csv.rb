module KeilaCsv
  # Keila's built-in contact fields, in their canonical capitalisation for
  # export, and a lookup from the downcased header back to that
  # capitalisation for reading CSVs whose headers vary in case.
  CANONICAL_FIELDS = %w[Email First_name Last_name External_id Status Data].freeze
  DOWNCASED_FIELDS = CANONICAL_FIELDS.map(&:downcase).freeze
  CANONICAL_BY_DOWNCASED = DOWNCASED_FIELDS.zip(CANONICAL_FIELDS).to_h.freeze

  # The standard fields an import recognizes, Tags included, by their name
  # without separators.
  STANDARD_FIELDS = (DOWNCASED_FIELDS + %w[tags]).index_by { |field| field.delete("_") }.freeze

  # The standard field a CSV header (or a Data key) stands for, ignoring
  # case, spaces, underscores and hyphens: "First name", "first-name" and
  # "FirstName" all mean "first_name", "E-mail" means "email". nil for
  # anything else.
  def self.standard_field(header)
    STANDARD_FIELDS[header.to_s.downcase.delete(" _-")]
  end
end
