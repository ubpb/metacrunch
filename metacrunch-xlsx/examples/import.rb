# frozen_string_literal: true

require "metacrunch/xlsx"

# Reads the books of an Excel file and writes them as JSON Lines: the sheet
# "Bestand", whose German column names become keys. Numbers stay numbers,
# the "00123" numbers stay text, and an empty cell is nil.
#
#   bundle exec metacrunch run examples/import.rb examples/data/books.xlsx
#
# examples/data/books.xlsx is what examples/report.rb writes.
Metacrunch.job do
  params do
    args :files, min: 1
  end

  source Metacrunch::Xlsx::Reader.new(params.files, sheet: "Bestand")

  map do |book|
    {"id" => book["Nr."], "title" => book["Titel"], "year" => book["Jahr"], "copies" => book["Exemplare"]}
  end
end
