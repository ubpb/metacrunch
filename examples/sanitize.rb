# frozen_string_literal: true

require_relative "lib/issue_report"

# Sanitizes exported publication records: cleans every string field,
# marks what it changed, rejects records without a title and fails on a year
# that is not a number. Records go to --output as JSON Lines, every mark to
# --issues as a TSV report. On large exports the steps are expensive enough
# for workers (-w) to pay off; the results are the same with and without.
#
#   mkdir -p tmp
#   bundle exec metacrunch run -w 4 -i examples/data/publications.jsonl \
#     --rejects tmp/rejects.jsonl --errors tmp/errors.jsonl --stats tmp/stats.json \
#     examples/sanitize.rb --output tmp/publications.jsonl --issues tmp/issues.tsv
#
# examples/data/publications.jsonl gives 187 records, 8 rejects (no title) and 5
# errors (year "n.d."); the exit status is 3, "finished, but records failed".
Metacrunch.job "sanitize" do
  params do
    param :output, String, default: "-", desc: "JSON Lines file for the records (- for stdout)"
    param :issues, String, required: true, desc: "TSV file for the issue report"
  end

  source id: ->(record) { record["id"] }

  # Control characters other than tab and line breaks.
  control = /[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]/

  clean = lambda do |text, field, ctx|
    normalized = text.unicode_normalize(:nfkc)
    ctx.mark("Control character", value: field) if normalized.match?(control)
    visible = normalized.gsub(control, " ")
    collapsed = visible.gsub(/[[:space:]]+/, " ").strip
    ctx.mark("Whitespace", value: field) if collapsed != visible
    collapsed
  end

  map(name: "clean") do |record, ctx|
    record.to_h do |field, value|
      case value
      when String then [field, clean.call(value, field, ctx)]
      when Array then [field, value.map { it.is_a?(String) ? clean.call(it, field, ctx) : it }]
      else [field, value]
      end
    end
  end
  reject("No title") { it["title"].to_s.empty? }
  map(name: "year") { it.merge("year" => Integer(it["year"], 10)) }

  sink Examples::IssueReport.new(params.issues, Metacrunch::JsonLines::Writer.new(params.output)), batch: 100
  on_error :skip
end
