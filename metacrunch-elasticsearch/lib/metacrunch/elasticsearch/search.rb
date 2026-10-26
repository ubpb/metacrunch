# frozen_string_literal: true

module Metacrunch
  module Elasticsearch
    # Lookups for steps, e.g. the _id of a record whose id is uncertain:
    # search.ids({term: {isbn: record["isbn"]}}, size: 2). Each process (each
    # worker of -w) gets its own client on its first lookup.
    class Search

      def initialize(connection, index:)
        @connection = connection
        @index = Names.targets(index).join(",")
        @client = nil
        @pid = nil
      end

      # The _ids of the documents query matches, at most size.
      def ids(query, size: 10) = search(query, size, _source: false).map { it["_id"] }

      # The hits query matches, at most size, as the reader's hits: true.
      def hits(query, size: 10) = search(query, size).map { Reader.hit(it) }

      private

      def search(query, size, **body)
        raise ArgumentError, "query must be a Hash, got #{query.class}" unless query.is_a?(Hash)
        unless size.is_a?(Integer) && size.between?(1, Reader::MAX_SIZE)
          raise ArgumentError, "size must be an Integer from 1 to #{Reader::MAX_SIZE}, got #{size.inspect}"
        end

        response = client.search(index: @index, body: {query:, size:, **body}, allow_partial_search_results: false)
        response.body.dig("hits", "hits")
      rescue Elastic::Transport::Transport::Error => e
        raise Error, "elasticsearch #{@index}: #{@connection.describe(e)}"
      end

      def client
        @client = nil unless @pid == Process.pid
        @client ||= @connection.connect.tap { @pid = Process.pid }
      rescue Error => e
        raise Error, "elasticsearch #{@index}: #{e.message}"
      end

    end
  end
end
