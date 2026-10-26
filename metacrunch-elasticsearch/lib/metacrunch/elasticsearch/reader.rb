# frozen_string_literal: true

module Metacrunch
  module Elasticsearch
    # A source: the documents of an index, alias or pattern, or those a query
    # matches, read page by page with a point in time and search_after.
    # Records are the documents (_source, Hashes with String keys), or with
    # hits: true the hits ("_index", "_id", "_source", ...).
    class Reader

      # Elasticsearch's time values, e.g. "30s", "5m".
      TIME_VALUE = /\A\d+(?:d|h|m|s|ms|micros|nanos)\z/
      # The fastest order when the order does not matter.
      SHARD_DOC = [{"_shard_doc" => "asc"}].freeze
      # Elasticsearch's limit of hits per search.
      MAX_SIZE = 10_000
      EXPIRED = "; the point in time expired between two pages: give the reader a longer keep_alive"

      # A hit as a record: without the internal "sort" and "_score".
      def self.hit(hit) = hit.except("sort", "_score")

      def initialize(connection, index:, query: nil, source: nil, sort: nil, size: 1000, keep_alive: "5m",
                     hits: false)
        @connection = connection
        @index = Names.targets(index).join(",")
        @query = hash_or_nil(query, :query)
        @source = source_filter(source, hits)
        @sort = sort.nil? ? SHARD_DOC : sort_order(sort)
        @size = page_size(size)
        @keep_alive = time_value(keep_alive)
        @hits = hits
        @client = nil
        @logger = nil
        @total = nil
        @read = 0
      end

      def open(context)
        @logger = context.logger
        @client = connect
      end

      # Yields each record; without a block an Enumerator. Every call reads
      # anew. Opens and closes a point in time.
      def each(&)
        return enum_for(:each) unless block_given?

        @client ||= connect
        read_pages(&)
      end

      # The share of the hits read so far, 0.0 to 1.0; nil before the first
      # page.
      def progress
        return nil unless @total
        return 1.0 if @total.zero?

        [@read.fdiv(@total), 1.0].min
      end

      private

      def read_pages
        @total = nil
        @read = 0
        pit = request { @client.open_point_in_time(index: @index, keep_alive: @keep_alive).body["id"] }
        after = nil
        loop do
          response = request { @client.search(body: search_body(pit, after)).body }
          pit = response["pit_id"] || pit
          hits = response.dig("hits", "hits")
          @total ||= response.dig("hits", "total", "value")
          hits.each do |hit|
            @read += 1
            yield(@hits ? Reader.hit(hit) : hit["_source"])
          end
          break if hits.size < @size

          after = hits.last["sort"]
        end
      ensure
        close_point_in_time(pit) if pit
      end

      # The first page counts the hits for progress.
      def search_body(pit, after)
        body = {size: @size, sort: @sort, pit: {id: pit, keep_alive: @keep_alive}, track_total_hits: after.nil?}
        body[:query] = @query if @query
        body[:_source] = @source unless @source.nil?
        body[:search_after] = after if after
        body
      end

      # A point in time expires on its own, so a failed close is no reason to
      # stop the job.
      def close_point_in_time(pit)
        @client.close_point_in_time(body: {id: pit})
      rescue Elastic::Transport::Transport::Error => e
        logger.warn("elasticsearch #{@index}: could not close the point in time: #{@connection.describe(e)}")
      end

      def connect
        @connection.connect
      rescue Error => e
        raise InputError, "elasticsearch #{@index}: #{e.message}"
      end

      # A point in time that expired between two pages: the steps or sinks
      # took longer than keep_alive for one page.
      def request
        yield
      rescue Elastic::Transport::Transport::Error => e
        hint = e.message.include?("search_context_missing_exception") ? EXPIRED : ""
        raise InputError, "elasticsearch #{@index}: #{@connection.describe(e)}#{hint}"
      end

      def logger = @logger || Metacrunch.logger

      def hash_or_nil(value, name)
        return value if value.nil? || value.is_a?(Hash)

        raise ArgumentError, "#{name} must be a Hash, got #{value.class}"
      end

      def source_filter(value, hits)
        raise ArgumentError, "source: false needs hits: true" if value == false && !hits
        return value if [nil, true, false].include?(value) || [String, Array, Hash].any? { value.is_a?(it) }

        raise ArgumentError, "source must be true, false, a field, an Array of fields or a Hash, got #{value.class}"
      end

      def sort_order(value)
        return value if [String, Array, Hash].any? { value.is_a?(it) }

        raise ArgumentError, "sort must be a field, an Array or a Hash, got #{value.class}"
      end

      def page_size(value)
        return value if value.is_a?(Integer) && value.between?(1, MAX_SIZE)

        raise ArgumentError, "size must be an Integer from 1 to #{MAX_SIZE}, got #{value.inspect}"
      end

      def time_value(value)
        return value if value.is_a?(String) && value.match?(TIME_VALUE)

        raise ArgumentError, "keep_alive must be an Elasticsearch time value such as \"5m\", got #{value.inspect}"
      end

    end
  end
end
