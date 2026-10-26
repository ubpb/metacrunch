# frozen_string_literal: true

require "metacrunch/csv"

# Writes CSV that Excel opens with a double click in a German or French
# locale: semicolons, Windows-1252, German column names.
#
#   bundle exec metacrunch run examples/books2excel.rb --target tmp/books.csv examples/data/books.csv
#
# The parameter is not called output: metacrunch's own -o/--output, given
# before the job file, would replace the CSV sink with JSON Lines.
Metacrunch.job do
  params do
    param :target, String, default: "-", desc: "CSV file for Excel (- for stdout)"
    args :files, min: 1
  end

  source Metacrunch::Csv::Reader.new(params.files)

  sink Metacrunch::Csv::Writer.new(params.target, columns: {"Nr." => "id", "Titel" => "title", "Jahr" => "year"},
                                                  col_sep: ";", encoding: "Windows-1252")
end
