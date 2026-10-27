# frozen_string_literal: true

module Metacrunch
  module Db
    # A source: the rows of a table, of a SQL query or of a Sequel dataset,
    # as Hashes with String keys and Sequel's values. One query per read,
    # streamed where the adapter can: a cursor on PostgreSQL, Dataset#stream
    # on mysql2; SQLite steps through the result itself. Other drivers
    # (trilogy, ...) may hold the whole result in memory.
    class Reader

      # Rows per fetch of a PostgreSQL cursor.
      FETCH_SIZE = 1000
      # PostgreSQL takes the idle limit in milliseconds as a 32-bit Integer.
      MAX_IDLE_TIMEOUT = 2_147_483
      PREVIEW = 60

      # table: a name (Table). query: SQL, or a callable that gets the
      # Sequel::Database and returns a Sequel::Dataset. values: the values of
      # the placeholders of a SQL query, a Hash (:name) or an Array (?).
      # count: count the rows first, for progress. idle_timeout: seconds the
      # database may wait for the job between two rows.
      def initialize(connection, table: nil, query: nil, values: nil, count: false, idle_timeout: 3600)
        raise ArgumentError, "give table: or query:" if table.nil? && query.nil?
        raise ArgumentError, "give table: or query:, not both" if table && query

        @connection = connection
        @table = table && Table.new(table)
        @query = query_option(query)
        @values = values_option(values)
        @count = boolean(count, :count)
        @idle_timeout = idle_timeout_option(idle_timeout)
        @database = nil
        @total = nil
        @read = 0
      end

      def open(_context)
        @database = connect
      end

      # Yields each record; without a block an Enumerator. Every call reads
      # anew.
      def each(&)
        return enum_for(:each) unless block_given?

        @database ||= connect
        read(&)
        self
      end

      # The share of the rows read so far, 0.0 to 1.0, with count: true; nil
      # before the count and without it.
      def progress
        return nil unless @total
        return 1.0 if @total.zero?

        [@read.fdiv(@total), 1.0].min
      end

      def close
        @database&.disconnect
        @database = nil
      end

      def inspect = "#<#{self.class.name} #{described} connection=#{@connection.inspect}>"

      private

      # The rows on one connection: the idle limit is a setting of the
      # session. A Sequel error that a later step or sink raises while it has
      # the record passes unchanged.
      def read
        @total = nil
        @read = 0
        yielding = false
        @database.synchronize do
          set_idle_timeout
          data = dataset
          @total = data.count if @count
          rows = stream(data)
          rows.each do |row|
            check_columns(rows) if @read.zero?
            @read += 1
            yielding = true
            yield row.transform_keys(&:to_s)
            yielding = false
          end
        end
      rescue Sequel::Error => e
        raise if yielding

        raise InputError, "#{label}: #{e.message}"
      end

      def dataset
        return @database[@table.identifier] if @table
        return fetch if @query.is_a?(String)

        @query.call(@database).tap do |result|
          unless result.is_a?(Sequel::Dataset)
            raise InputError, "#{label}: the query must return a Sequel::Dataset, got #{result.class}"
          end
        end
      end

      def fetch
        case @values
        when Hash then @database.fetch(@query, @values)
        when Array then @database.fetch(@query, *@values)
        else @database.fetch(@query)
        end
      end

      # As Sequel's paged_each does per adapter, but without its need for an
      # order: one query.
      def stream(data)
        return data.use_cursor(rows_per_fetch: FETCH_SIZE) if data.respond_to?(:use_cursor)
        return data.stream if data.respond_to?(:stream)

        data
      end

      # MySQL ends a streamed result the job does not take for
      # net_write_timeout (60 s by default); PostgreSQL may end the cursor's
      # transaction, idle while the job works, after
      # idle_in_transaction_session_timeout.
      def set_idle_timeout
        case @database.database_type
        when :mysql then @database.run("SET SESSION net_write_timeout = #{@idle_timeout}")
        when :postgres then @database.run("SET idle_in_transaction_session_timeout = #{@idle_timeout * 1000}")
        end
      end

      # Two columns of one name would give one key of the Hash.
      def check_columns(rows)
        twice = rows.columns.tally.find { |_, count| count > 1 }&.first
        return unless twice

        raise InputError, "#{label}: the result has the column #{twice} twice; name the columns apart (AS)"
      end

      def connect
        @connection.connect
      rescue Error => e
        raise InputError, "#{label}: #{e.message}"
      end

      def label = @table ? "db #{@table}" : "db query"

      def described
        return "table=#{@table}" if @table
        return "query=(callable)" unless @query.is_a?(String)

        sql = @query.squeeze(" ").strip
        "query=#{(sql.length > PREVIEW ? "#{sql[0, PREVIEW]}..." : sql).inspect}"
      end

      def query_option(value)
        return value if value.nil? || (value.is_a?(String) && !value.strip.empty?) || value.respond_to?(:call)

        raise ArgumentError, "query must be SQL (a String) or a callable that returns a Sequel::Dataset, " \
                             "got #{value.inspect}"
      end

      def values_option(value)
        return nil if value.nil?
        raise ArgumentError, "values: needs a SQL query" unless @query.is_a?(String)
        return value if value.is_a?(Hash) || value.is_a?(Array)

        raise ArgumentError, "values must be a Hash (for :name placeholders) or an Array (for ?), got #{value.inspect}"
      end

      def boolean(value, name)
        return value if [true, false].include?(value)

        raise ArgumentError, "#{name} must be true or false, got #{value.inspect}"
      end

      def idle_timeout_option(value)
        return value if value.is_a?(Integer) && value.between?(1, MAX_IDLE_TIMEOUT)

        raise ArgumentError, "idle_timeout must be an Integer of seconds from 1 to #{MAX_IDLE_TIMEOUT}, " \
                             "got #{value.inspect}"
      end

    end
  end
end
