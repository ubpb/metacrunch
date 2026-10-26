# frozen_string_literal: true

require "metacrunch/marc"

# Reads MARC records (MARCXML, ISO 2709 or MARC-in-JSON, told by the content
# of each file) and writes one JSON object per record (id, title, authors,
# subjects, links) to stdout as JSON Lines.
#
#   bundle exec metacrunch run examples/marc2jsonl.rb examples/data/catalog.mrc
Metacrunch.job do
  params do
    args :files, min: 1
  end

  source Metacrunch::Marc::Reader.new(params.files), id: ->(record) { record["001"]&.value }

  map do |record|
    {
      "id" => record["001"]&.value,
      "title" => record.field("245")&.join("a", "b", separator: " : "),
      "authors" => record.values(["100", "700"], "a"),
      "subjects" => record.values("650", "a"),
      "links" => record.values("856", "u", ind1: "4", ind2: "0")
    }
  end
end
