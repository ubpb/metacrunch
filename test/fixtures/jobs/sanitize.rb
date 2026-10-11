# frozen_string_literal: true

# Sanitizes titles: marks what it changes, rejects records
# without a title and fails on a broken year. Used to compare runs with and
# without workers.
Metacrunch.job do
  source id: ->(record) { record["id"] }
  map do |record, ctx|
    title = record["title"].to_s
    clean = title.unicode_normalize(:nfkc).gsub(/\s+/, " ").strip
    ctx.mark("Whitespace", value: title) if clean != title
    record.merge("title" => clean)
  end
  reject("No title") { it["title"].empty? }
  map { it.merge("year" => Integer(it["year"])) }
  on_error :skip
end
