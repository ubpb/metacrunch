# frozen_string_literal: true

# Filter job: tags every record.
Metacrunch.job do
  map { it.merge("tagged" => true) }
end
