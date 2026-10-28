# frozen_string_literal: true

Metacrunch.job "books:export", desc: "Write the cached books as JSON Lines to stdout" do
  params do
    use Metacrunch::Redis::CONNECTION_PARAMS
    param :prefix, String, default: "book:", desc: "the start of the keys"
  end

  redis = Metacrunch::Redis::Connection.from_params(params)
  # Records are {"key" => "book:978...", "value" => the book}.
  source Metacrunch::Redis::KeyReader.new(redis, match: "#{params.prefix}*")
  map { it["value"] }
end
