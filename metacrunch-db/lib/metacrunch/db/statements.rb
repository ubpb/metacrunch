# frozen_string_literal: true

module Metacrunch
  module Db
    # How the writer turns the rows of a batch into SQL: runs of consecutive
    # rows with the same action and columns, pieces of at most max_bytes,
    # and one statement per piece (one per row for updates).
    module Statements

      # A row of the batch: position is its index in the batch.
      Item = Data.define(:position, :action, :row)
      Run = Data.define(:action, :items)

      # What a value counts toward max_bytes, beside a String's bytes.
      QUOTES = 3
      OTHER = 24

      module_function

      # Consecutive items with the same action and the same columns, so the
      # order of the batch holds.
      def runs(items)
        items.chunk_while { |a, b| a.action == b.action && a.row.keys.sort == b.row.keys.sort }
             .map { Run.new(action: it.first.action, items: it) }
      end

      def size(row) = row.sum { |_, value| value.is_a?(String) ? value.bytesize + QUOTES : OTHER }

      # Items in pieces whose rows add up to at most max_bytes; an item
      # larger than that goes alone.
      def pieces(items, max_bytes)
        bytes = 0
        items.each_with_object([]) do |item, pieces|
          item_bytes = size(item.row)
          if pieces.empty? || bytes + item_bytes > max_bytes
            pieces << []
            bytes = 0
          end
          pieces.last << item
          bytes += item_bytes
        end
      end

      # The last item of each key, in their order. PostgreSQL refuses a key
      # twice in one upsert; applied in order, the last one wins anyway.
      def dedupe(items, key) = items.reverse.uniq { it.row.values_at(*key) }.reverse

      # Runs the SQL of items of one action and returns the items an update
      # found no row for ([] for the other actions).
      def execute(dataset, action, items, key)
        case action
        when :update then return items.reject { updated?(dataset, it.row, key) }
        when :delete then delete(dataset, items, key)
        else
          columns = items.first.row.keys
          target = action == :upsert ? upsert_dataset(dataset, columns, key) : dataset
          target.import(columns, items.map { it.row.values_at(*columns) })
        end
        []
      end

      # The dataset that upserts by key, setting the other columns: ON
      # CONFLICT on PostgreSQL and SQLite, ON DUPLICATE KEY UPDATE on MySQL
      # and MariaDB; nil for other databases.
      def upsert_dataset(dataset, columns, key)
        other = columns - key
        if dataset.respond_to?(:insert_conflict)
          return dataset.insert_conflict(target: key) if other.empty?

          dataset.insert_conflict(target: key, update: other.to_h { [it, Sequel[:excluded][it]] })
        elsif dataset.respond_to?(:on_duplicate_key_update)
          dataset.on_duplicate_key_update(*(other.empty? ? key : other))
        end
      end

      def delete(dataset, items, key)
        values = items.map { it.row.values_at(*key) }
        condition = key.size == 1 ? {key.first => values.map(&:first)} : {key => values}
        dataset.where(condition).delete
      end

      # Whether a row matched. Without other columns the key columns are set
      # to themselves, which counts the rows.
      def updated?(dataset, row, key)
        condition = row.slice(*key)
        other = row.except(*key)
        dataset.where(condition).update(other.empty? ? condition : other).positive?
      end

    end
  end
end
