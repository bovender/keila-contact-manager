module KeilaCsv
  # Keila's built-in contact fields, in their canonical capitalisation for
  # export, and a lookup from the downcased header back to that
  # capitalisation for reading CSVs whose headers vary in case.
  CANONICAL_FIELDS = %w[Email First_name Last_name External_id Status Data].freeze
  DOWNCASED_FIELDS = CANONICAL_FIELDS.map(&:downcase).freeze
  CANONICAL_BY_DOWNCASED = DOWNCASED_FIELDS.zip(CANONICAL_FIELDS).to_h.freeze
end
