# frozen_string_literal: true

# Writes the documents of an index as JSON Lines to stdout: all, or those a query string matches:
#
#   bundle exec metacrunch run --params examples/params.yml examples/export.rb --index books --query "lang:en"
require "metacrunch/elasticsearch"

Metacrunch.job do
  params do
    instance_exec(&Metacrunch::Elasticsearch::CONNECTION_PARAMS)
    param :index, String, required: true, desc: "index, alias or pattern to read"
    param :query, String, desc: "query string in Lucene syntax, e.g. lang:en"
  end

  query = params.query && {query_string: {query: params.query}}
  source Metacrunch::Elasticsearch::Reader.new(Metacrunch::Elasticsearch::Connection.from_params(params),
                                               index: params.index, query:)
end
