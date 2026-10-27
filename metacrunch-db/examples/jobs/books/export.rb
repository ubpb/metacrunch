# frozen_string_literal: true

Metacrunch.job "books:export", desc: "Write the books as JSON Lines to stdout" do
  params do
    use Metacrunch::Db::CONNECTION_PARAMS
    param :since, Integer, default: 0, desc: "only books first published in or after this year"
  end

  db = Metacrunch::Db::Connection.from_params(params)
  source Metacrunch::Db::Reader.new(db, query: "SELECT * FROM books WHERE year >= :since ORDER BY isbn",
                                        values: {since: params.since}, count: true)
  # JSON has no dates and no decimals: Date and Time become ISO 8601, BigDecimal a decimal String.
  map do |book|
    book.transform_values do |value|
      case value
      when Date, Time then value.iso8601
      when BigDecimal then value.to_s("F")
      else value
      end
    end
  end
end
