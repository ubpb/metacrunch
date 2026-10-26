# frozen_string_literal: true

require "metacrunch/csv"

# Reads CSV files with a header row and writes one JSON object per row to
# stdout as JSON Lines. Values stay Strings ("0306406152" keeps its zero);
# only the year becomes a number.
#
#   bundle exec metacrunch run examples/csv2jsonl.rb examples/data/books.csv
Metacrunch.job do
  params do
    args :files, min: 1
  end

  source Metacrunch::Csv::Reader.new(params.files), id: ->(record) { record["id"] }

  map do |record|
    record.merge("year" => Integer(record["year"], exception: false))
  end
end
