# frozen_string_literal: true

# A filter job for pipes: it declares neither source nor sink, so it reads
# JSON Lines from stdin and writes JSON Lines to stdout. It collapses
# whitespace in string values and drops empty fields. The id extractor makes
# logs and rejects name records by their id.
#
#   bundle exec metacrunch run examples/normalize.rb < examples/data/publications.jsonl | head -n 3
#   bundle exec metacrunch run examples/hello.rb | bundle exec metacrunch run examples/normalize.rb
Metacrunch.job do
  source id: ->(record) { record["id"] }

  map do |record|
    record.filter_map do |key, value|
      value = value.gsub(/[[:space:]]+/, " ").strip if value.is_a?(String)
      [key, value] unless value.nil? || value == ""
    end.to_h
  end
end
