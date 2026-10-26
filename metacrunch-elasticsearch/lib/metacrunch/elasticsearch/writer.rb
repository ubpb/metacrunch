# frozen_string_literal: true

module Metacrunch
  module Elasticsearch
    # A sink: writes records with bulk requests, the action chosen per record.
    # Requests that Elasticsearch refuses for now (429, 502, 503, 504) and
    # items it refuses for now (429, 5xx) are sent again after a backoff;
    # records it refuses for good, and records that cannot be sent, are
    # reported in Metacrunch::SinkFailures, so the job's failure policy
    # decides. Use it with batch: (sink Writer.new(...), batch: 1000).
    class Writer

      # Request statuses that may pass when sent again.
      RETRY_STATUSES = [429, 502, 503, 504].freeze
      # Only what the writer reads of a bulk response.
      FILTER_PATH = "errors,items.*.status,items.*.error"
      MAX_DELAY = 60
      # Index blocks that refuse writes.
      WRITE_BLOCKS = ["write", "read_only", "read_only_allow_delete"].freeze

      # index: a name, or an alias with one index (or a write index). id: a
      # key or a callable(record) giving the _id; nil lets Elasticsearch
      # assign ids. action: one of Bulk::ACTIONS or a callable(record) giving
      # one. max_bytes: the upper limit of one request. retries: how often a
      # request or item is sent again.
      def initialize(connection, index:, id: nil, action: :index, max_bytes: 10 * 1024 * 1024, retries: 5)
        @connection = connection
        @index = Names.check(index, "index")
        @id = id_option(id)
        @action = action_option(action)
        @max_bytes = positive(max_bytes, :max_bytes)
        @retries = retries_option(retries)
        @client = nil
        @logger = nil
        @hinted = false
      end

      # Connects and checks that the index or alias exists: Elasticsearch
      # would create a missing one with dynamic mappings.
      def open(context)
        @logger = context.logger
        client
      end

      # One record per request: the engine calls write without batch:.
      def write(record)
        unless @hinted
          @hinted = true
          logger.info("elasticsearch #{@index}: writing one record per request; use `sink ..., batch: 1000`")
        end
        write_batch([record])
      end

      # Without the client, whose options hold the credentials.
      def inspect = "#<#{self.class.name} index=#{@index} connection=#{@connection.inspect}>"

      def write_batch(records)
        items, failed = Bulk.items(records, index: @index, id: @id, action: @action)
        Bulk.requests(items, @max_bytes).each { deliver(it, failed) }
        raise SinkFailures, failed unless failed.empty?
      end

      private

      # Sends items in one request, and again those Elasticsearch refuses for
      # now. Adds the items it refuses for good to failed.
      def deliver(items, failed)
        retries = 0
        until items.empty?
          status, results = post(items)
          return split(items, failed) if status == 413

          status, items = sort_out(results, failed) if results
          retries = retry_later(retries, status, items.size) unless items.empty?
        end
      end

      # Returns [status] for a request to send again or to split (413), else
      # [nil, results].
      def post(items)
        [nil, Bulk.results(items, client.bulk(body: Bulk.body(items), filter_path: FILTER_PATH).body)]
      rescue Elastic::Transport::Transport::Error => e
        status = Elasticsearch.status(e)
        return [status] if status == 413 || RETRY_STATUSES.include?(status)

        raise OutputError, "elasticsearch #{@index}: #{@connection.describe(e)}"
      end

      # The status and items to send again; the items refused for good go to
      # failed.
      def sort_out(results, failed)
        status = nil
        again = results.filter_map do |item, result|
          next if Bulk.ok?(item, result)

          if Bulk.transient?(result)
            status = result["status"]
            next item
          end
          failed[item.position] = Bulk.error(item, result)
          nil
        end
        [status, again]
      end

      # A request too large for Elasticsearch: halves are sent alone, and a
      # single document that is too large fails.
      def split(items, failed)
        return failed[items.first.position] = Bulk.too_large(items.first) if items.size == 1

        items.each_slice((items.size + 1) / 2) { deliver(it, failed) }
      end

      def retry_later(retries, status, count)
        if retries >= @retries
          raise OutputError, "elasticsearch #{@index}: #{count} #{count == 1 ? "record" : "records"} still refused " \
                             "with #{status} after #{@retries} retries"
        end

        delay = [2**retries, MAX_DELAY].min * (0.5 + (rand / 2))
        logger.warn("elasticsearch #{@index}: bulk #{status}, retry #{retries + 1}/#{@retries} " \
                    "in #{format("%.1f", delay)} s")
        sleep(delay)
        retries + 1
      end

      def client
        @client ||= begin
          client = @connection.connect
          exists = client.indices.exists(index: @index)
          raise OutputError, "elasticsearch #{@index}: no such index or alias" unless exists

          check_writable(client, write_target(client))
          client
        rescue Error => e
          raise OutputError, "elasticsearch #{@index}: #{e.message}"
        rescue Elastic::Transport::Transport::Error => e
          raise OutputError, "elasticsearch #{@index}: #{@connection.describe(e)}"
        end
      end

      # The index the records go to: the index, the one of an alias, or the
      # write index of an alias of several. Without a write index such an
      # alias takes no writes, and Elasticsearch would refuse every record.
      def write_target(client)
        indices = client.indices.get_alias(name: @index).body
        return indices.keys.first if indices.size == 1

        write = indices.find { |_, entry| entry.dig("aliases", @index, "is_write_index") }
        return write.first if write

        raise OutputError, "elasticsearch #{@index}: the alias points to #{indices.keys.sort.join(", ")} and to none " \
                           "of them as its write index"
      rescue Elastic::Transport::Transport::Errors::NotFound
        @index
      end

      # A closed index, or one with a block that refuses writes, would refuse
      # every record too.
      def check_writable(client, name)
        rows = client.cat.indices(index: name, h: "index,status", format: "json", expand_wildcards: "all").body
        raise OutputError, "elasticsearch #{@index}: #{name} is closed" if rows.any? { it["status"] == "close" }

        blocks = client.indices.get_settings(index: name, filter_path: "*.settings.index.blocks").body
        block = WRITE_BLOCKS.find { blocks.dig(name, "settings", "index", "blocks", it) == "true" }
        raise OutputError, "elasticsearch #{@index}: #{name} (index.blocks.#{block}) refuses writes" if block
      end

      def logger = @logger || Metacrunch.logger

      def id_option(value)
        return value if value.nil? || value.is_a?(String) || value.is_a?(Symbol) || value.respond_to?(:call)

        raise ArgumentError, "id must be a key or a callable, got #{value.inspect}"
      end

      def action_option(value)
        return value if Bulk::ACTIONS.include?(value) || value.respond_to?(:call)

        raise ArgumentError, "action must be one of #{Bulk::ACTIONS.map(&:inspect).join(", ")} or a callable, " \
                             "got #{value.inspect}"
      end

      def positive(value, name)
        return value if value.is_a?(Integer) && value.positive?

        raise ArgumentError, "#{name} must be a positive Integer, got #{value.inspect}"
      end

      def retries_option(value)
        return value if value.is_a?(Integer) && !value.negative?

        raise ArgumentError, "retries must be an Integer of 0 or more, got #{value.inspect}"
      end

    end
  end
end
