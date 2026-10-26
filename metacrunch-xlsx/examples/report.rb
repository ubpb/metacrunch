# frozen_string_literal: true

require "metacrunch/xlsx"

# Writes a report of books as an Excel file: German column names and a wide
# title column. The header row is bold, frozen and filtered; numbers of
# copies are numbers, the "00123" numbers stay text.
#
#   bundle exec metacrunch run examples/report.rb --target tmp/report.xlsx examples/data/books.jsonl
#
# The parameter is not called output: metacrunch's own -o/--output, given
# before the job file, would replace the Excel sink with JSON Lines.
Metacrunch.job do
  params do
    param :target, String, default: "report.xlsx", desc: "Excel file for the report"
    args :files, min: 1
  end

  source Metacrunch::JsonLines::Reader.new(params.files)

  map { it.merge("available" => it["copies"].to_i.positive?) }

  sink Metacrunch::Xlsx::Writer.new(
    params.target,
    columns: {"Nr." => "id", "Titel" => "title", "Jahr" => "year", "Exemplare" => "copies", "Verfügbar" => "available"},
    sheet: "Bestand",
    widths: {"Titel" => 60}
  )
end
