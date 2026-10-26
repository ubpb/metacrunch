# frozen_string_literal: true

require "metacrunch/marc"

# Cleans MARCXML records and writes them as MARCXML again: collapses runs of
# spaces in titles, drops links to cover images (856 with second indicator
# 2) and records the cleanup in field 883.
#
#   bundle exec metacrunch run examples/cleanup.rb --target tmp/clean.xml examples/data/catalog.xml
#
# The parameter is not called output: metacrunch's own -o/--output, given
# before the job file, would replace the MARCXML sink with JSON Lines.
Metacrunch.job do
  params do
    param :target, String, default: "-", desc: "MARCXML file for the cleaned records (- for stdout)"
    args :files, min: 1
  end

  source Metacrunch::Marc::Reader.new(params.files), id: ->(record) { record["001"]&.value }

  map(name: "titles") do |record|
    record.fields("245").each do |field|
      field.subfields.each { it.value = it.value.squeeze(" ").strip }
    end
    record
  end

  map(name: "covers") do |record|
    record.remove("856", ind2: "2")
    record
  end

  map(name: "provenance") do |record|
    record.add(Metacrunch::Marc::DataField.new("883", " ", " ", [["a", "metacrunch cleanup example"]]))
  end

  sink Metacrunch::Marc::Writer.new(params.target, format: :xml)
end
