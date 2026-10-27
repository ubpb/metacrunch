# frozen_string_literal: true

module Metacrunch
  module Db
    # A sink: writes records into a table, one transaction per batch. The
    # action (insert, upsert, update, delete) is fixed or chosen per record.
    # Rows the database refuses (constraints, values a column does not take,
    # see Refusals) and records the writer cannot write are reported in
    # Metacrunch::SinkFailures, so the job's failure policy decides; other
    # errors stop the run with the batch rolled back. Use it with
    # batch: (sink Writer.new(...), batch: 1000).
    class Writer

      NO_UPSERT = "upsert needs PostgreSQL, SQLite, MySQL or MariaDB"
      # In SQLite's default journal mode a reading statement keeps others
      # from committing, such as the reader of a job that writes the file it
      # reads; WAL lets them write.
      LOCKED = "; another connection holds the file, such as a reader of the same file: set PRAGMA journal_mode=WAL " \
               "once"
      # A batch of at least SPARSE² records whose statements hold fewer than
      # SPARSE records on average gets the hint of hint_columns.
      SPARSE = 4

      # table: a name (Table). action: one of ACTIONS or a callable(record)
      # returning one. key: the column or columns (an Array) that identify a
      # row; required but for :insert. max_bytes: the upper limit of the
      # values of one statement.
      def initialize(connection, table:, action: :insert, key: nil, max_bytes: 1024 * 1024)
        @connection = connection
        @table = Table.new(table)
        @action = action_option(action)
        @key = key_option(key)
        check_key_needed
        @max_bytes = positive(max_bytes, :max_bytes)
        @database = nil
        @schema = nil
        @columns = nil
        @upsert_checked = false
        @columns_hinted = false
        @logger = nil
        @hinted = false
      end

      # Connects and checks the table: it exists, has the key columns, and
      # for upserts the key is unique and the database can upsert.
      def open(context)
        @logger = context.logger
        database
      end

      # One record per transaction: the engine calls write without batch:.
      def write(record)
        unless @hinted
          @hinted = true
          logger.info("db #{@table}: writing one record per transaction; use `sink ..., batch: 1000`")
        end
        write_batch([record])
      end

      def write_batch(records)
        database
        failed = {}
        items = items_of(records, failed)
        write_items(items, failed) unless items.empty?
        raise SinkFailures, failed unless failed.empty?
      end

      def close
        @database&.disconnect
        @database = nil
      end

      def inspect
        action = @action.respond_to?(:call) ? "(callable)" : @action
        key = @key ? " key=#{@key.join(",")}" : ""
        "#<#{self.class.name} table=#{@table} action=#{action}#{key} connection=#{@connection.inspect}>"
      end

      private

      def items_of(records, failed)
        records.each_with_index.filter_map do |record, position|
          action = action_for(record)
          row = Values.row(record, table: @table, columns: @columns, key: @key, action:)
          Statements::Item.new(position:, action:, row:)
        rescue Error => e
          failed[position] = e
          nil
        end
      end

      def write_items(items, failed)
        runs = Statements.runs(items, @key)
        hint_columns(items, runs)
        database.transaction { runs.each { write_run(it, failed) } }
      rescue Sequel::Error => e
        raise OutputError, "#{label}: #{e.message}#{LOCKED if locked?(e)}"
      end

      # sqlite3 is loaded only for SQLite.
      def locked?(error) = defined?(::SQLite3::BusyException) && error.wrapped_exception.is_a?(::SQLite3::BusyException)

      # Without a key, only neighbours with the same columns share a
      # statement (Statements.runs), which records that leave out absent
      # fields rarely are.
      def hint_columns(items, runs)
        return if @key || @columns_hinted || items.size < SPARSE * SPARSE || runs.size * SPARSE <= items.size

        @columns_hinted = true
        logger.info("db #{@table}: records with different columns share no statement; give the writer key: or every " \
                    "record the same columns")
      end

      # Updates are one statement per row, so a run of them is one piece. The
      # items of an upsert run have keys of their own (Statements.runs).
      def write_run(run, failed)
        dataset = database[@table.identifier]
        check_upsert(database) if run.action == :upsert
        pieces = run.action == :update ? [run.items] : Statements.pieces(run.items, @max_bytes)
        pieces.each { attempt(dataset, run.action, it, failed) }
      end

      # Runs items in a savepoint. When the database refuses a record, each
      # item runs in a savepoint of its own; the records it still refuses are
      # failures.
      def attempt(dataset, action, items, failed)
        unmatched(execute(dataset, action, items), failed)
      rescue Sequel::DatabaseError => e
        raise unless Refusals.record?(e)

        items.each do |item|
          unmatched(execute(dataset, action, [item]), failed)
        rescue Sequel::DatabaseError => refusal
          raise unless Refusals.record?(refusal)

          failed[item.position] = refusal
        end
      end

      def execute(dataset, action, items)
        database.transaction(savepoint: true) { Statements.execute(dataset, action, items, @key) }
      end

      def unmatched(items, failed)
        items.each do |item|
          where = @key.map { "#{it} = #{item.row[it].inspect}" }.join(", ")
          failed[item.position] = Error.new("no row with #{where} in #{@table}")
        end
      end

      def upsert?(database) = !Statements.upsert_dataset(database[@table.identifier], @key, @key).nil?

      # The database, connected and the table checked; a failed check
      # disconnects it again.
      def database
        @database ||= begin
          opened = connect
          check_table(opened)
          opened
        rescue OutputError
          opened&.disconnect
          raise
        end
      end

      def connect
        @connection.connect
      rescue Error => e
        raise OutputError, "#{label}: #{e.message}"
      end

      def check_table(database)
        raise OutputError, "#{label}: no such table" unless database.table_exists?(@table.identifier)

        @schema = database.supports_schema_parsing? ? database.schema(@table.identifier) : nil
        check_columns if @schema
        check_upsert(database) if @action == :upsert
      rescue Sequel::Error => e
        raise OutputError, "#{label}: #{e.message}"
      end

      def check_columns
        @columns = @schema.to_set(&:first)
        missing = @key.to_a.reject { @columns.include?(it) }
        raise OutputError, "#{label}: key #{missing.join(", ")} is no column of #{@table}" unless missing.empty?
      end

      # The database can upsert, by a unique key: checked when the writer
      # opens for action: :upsert, and at the first upsert of a callable
      # action. ON DUPLICATE KEY UPDATE would insert a second row for a key
      # that is not unique.
      def check_upsert(database)
        return if @upsert_checked
        raise OutputError, "#{label}: #{NO_UPSERT}; this is #{database.database_type}" unless upsert?(database)

        check_unique(database) if @schema
        @upsert_checked = true
      end

      # ON CONFLICT needs a unique index of exactly the key; ON DUPLICATE KEY
      # UPDATE would take any.
      def check_unique(database)
        key = @key.sort
        return if @schema.select { |_, info| info[:primary_key] }.map(&:first).sort == key
        return unless database.supports_index_parsing?
        return if database.indexes(@table.identifier).each_value.any? { it[:unique] && it[:columns].sort == key }

        raise OutputError, "#{label}: key #{@key.join(", ")} is neither the primary key nor a unique index of #{@table}"
      end

      def action_for(record)
        return @action unless @action.respond_to?(:call)

        action = @action.call(record)
        return action if ACTIONS.include?(action)

        raise Error, "action must be one of #{ACTIONS.map(&:inspect).join(", ")}, got #{action.inspect}"
      end

      def label = "db #{@table}"

      def logger = @logger || Metacrunch.logger

      def action_option(value)
        return value if ACTIONS.include?(value) || value.respond_to?(:call)

        raise ArgumentError, "action must be one of #{ACTIONS.map(&:inspect).join(", ")} or a callable, " \
                             "got #{value.inspect}"
      end

      def key_option(value)
        return nil if value.nil?

        columns = Array(value)
        if columns.empty? || !columns.all? { (it.is_a?(String) || it.is_a?(Symbol)) && !it.empty? }
          raise ArgumentError, "key must be a column or an Array of columns, got #{value.inspect}"
        end

        columns.map(&:to_sym)
      end

      def check_key_needed
        return if @key || @action == :insert
        raise ArgumentError, "a callable action needs key:" if @action.respond_to?(:call)

        raise ArgumentError, "action #{@action.inspect} needs key:"
      end

      def positive(value, name)
        return value if value.is_a?(Integer) && value.positive?

        raise ArgumentError, "#{name} must be a positive Integer, got #{value.inspect}"
      end

    end
  end
end
