# frozen_string_literal: true

module Metacrunch
  module Elasticsearch
    # The pieces of the writer's bulk requests: an item per record, requests
    # of at most a size, and what Elasticsearch answered for each item.
    module Bulk

      ACTIONS = [:index, :create, :update, :upsert, :delete].freeze
      NEEDS_ID = [:update, :upsert, :delete].freeze
      # Elasticsearch's limit for _id.
      MAX_ID_BYTES = 512

      # One action of a request. position: the index of its record in the
      # batch; lines: its NDJSON, the action line and (except for delete) the
      # document line.
      Item = Data.define(:position, :action, :id, :lines)

      module_function

      # The items for records, and {position => error} for the records that
      # cannot be sent: not a Hash, no id where the action needs one, an id
      # that is not a String or Integer, empty or too long, an action that is
      # not one of ACTIONS, or a value JSON cannot write (NaN, invalid UTF-8).
      # id and action are the writer's options: a key or callable, a Symbol
      # or callable.
      def items(records, index:, id:, action:)
        failed = {}
        items = records.each_with_index.filter_map do |record, position|
          item(record, position, index, id, action)
        rescue StandardError => e
          failed[position] = e
          nil
        end
        [items, failed]
      end

      # The items in requests of at most max_bytes; an item that is larger
      # alone.
      def requests(items, max_bytes)
        size = 0
        items.slice_before do |item|
          size += item.lines.bytesize
          (size > max_bytes).tap { size = item.lines.bytesize if it }
        end.to_a
      end

      def body(items) = items.map(&:lines).join

      # Each item with its result ({"status" => ..., "error" => {...}}), or
      # with nil when the response reports no errors.
      def results(items, response)
        return items.map { [it, nil] } unless response["errors"]

        items.zip(response["items"].map { it.values.first })
      end

      def ok?(item, result)
        return true if result.nil? || result["status"] < 300

        item.action == :delete && result["status"] == 404
      end

      # A status that may pass when the item is sent again: 429 (too many
      # requests) and 5xx.
      def transient?(result) = result["status"] == 429 || result["status"] >= 500

      def error(item, result)
        cause = result["error"].is_a?(Hash) ? result["error"] : {"type" => "error", "reason" => result["error"].to_s}
        BulkItemError.new(status: result["status"], type: cause["type"], reason: cause["reason"], action: item.action,
                          id: item.id)
      end

      def too_large(item)
        BulkItemError.new(status: 413, type: "request_entity_too_large", reason: "the document alone is too large",
                          action: item.action, id: item.id)
      end

      def item(record, position, index, id, action)
        raise Error, "the record is #{article(record.class)}, not a Hash" unless record.is_a?(Hash)

        name = action_of(record, action)
        key = id_of(record, id, name)
        Item.new(position:, action: name, id: key, lines: lines(name, index, key, record))
      end

      def action_of(record, action)
        name = action.respond_to?(:call) ? action.call(record) : action
        return name if ACTIONS.include?(name)

        raise Error, "the action must be one of #{ACTIONS.map(&:inspect).join(", ")}, got #{name.inspect}"
      end

      def id_of(record, id, action)
        value = id.respond_to?(:call) ? id.call(record) : id && record[id]
        if value.nil?
          raise Error, "#{action} needs an id, and the record has none" if NEEDS_ID.include?(action)

          return nil
        end
        unless value.is_a?(String) || value.is_a?(Integer)
          raise Error, "the id must be a String or an Integer, got #{value.class}"
        end

        text = value.to_s
        raise Error, "the id is empty" if text.empty?
        raise Error, "the id is longer than #{MAX_ID_BYTES} bytes" if text.bytesize > MAX_ID_BYTES

        text
      end

      def lines(action, index, id, record)
        target = {"_index" => index}
        target["_id"] = id if id
        header = JSON.generate({(action == :upsert ? :update : action) => target})
        case action
        when :delete then "#{header}\n"
        when :update then "#{header}\n#{JSON.generate({"doc" => record})}\n"
        when :upsert then "#{header}\n#{JSON.generate({"doc" => record, "doc_as_upsert" => true})}\n"
        else "#{header}\n#{JSON.generate(record)}\n"
        end
      end

      def article(klass) = "#{klass.name.match?(/\A[AEIOU]/) ? "an" : "a"} #{klass}"

    end
  end
end
