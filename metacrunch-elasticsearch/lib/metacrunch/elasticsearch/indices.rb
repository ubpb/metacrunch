# frozen_string_literal: true

module Metacrunch
  module Elasticsearch
    # Index operations for full loads behind an alias: create an index named
    # after the alias and the time (create_for), load it, finish_load,
    # switch_alias, prune the old ones. The es: commands wrap these methods.
    # Every change is logged on info.
    class Indices

      # ALIAS-YYYYMMDD-HHMMSS, in UTC.
      STAMP = "%Y%m%d-%H%M%S"
      # Settings of a bulk load: no refresh, no replicas; finish_load puts
      # back the definition's values.
      BULK_LOAD = {"index.refresh_interval" => "-1", "index.number_of_replicas" => 0}.freeze
      # Static: Elasticsearch never changes it on an existing index.
      SHARDS = "index.number_of_shards"

      def initialize(connection, logger: nil)
        @connection = connection
        @logger = logger
        @client = nil
      end

      # Creates the index name with settings and mappings (Hashes or paths of
      # JSON files) and returns name. bulk_load: true sets BULK_LOAD over the
      # settings. Raises Error if the index exists.
      def create(name, settings: nil, mappings: nil, bulk_load: false)
        Names.check(name, "index")
        flat = Definition.flat_settings(Definition.load(settings, "settings"))
        flat.merge!(BULK_LOAD) if bulk_load
        mappings = Definition.load(mappings, "mappings")
        body = {}
        body["settings"] = flat unless flat.empty?
        body["mappings"] = mappings if mappings
        request { client.indices.create(index: name, body:) }
        logger.info("created #{name}")
        name
      end

      # Creates ALIAS-YYYYMMDD-HHMMSS (UTC) as create does and returns the name.
      def create_for(alias_name, **)
        create("#{Names.check(alias_name, "alias")}-#{Time.now.utc.strftime(STAMP)}", **)
      end

      # Puts back refresh interval and replicas after a bulk load, with the
      # values of settings (Elasticsearch's defaults where it has none), and
      # refreshes the index.
      def finish_load(name, settings: nil)
        Names.check(name, "index")
        flat = Definition.flat_settings(Definition.load(settings, "settings"))
        request { client.indices.put_settings(index: name, body: BULK_LOAD.keys.to_h { [it, flat[it]] }) }
        refresh(name)
        logger.info("finished loading #{name}")
      end

      # Points alias_name to index alone, in one atomic request; the first
      # time it adds the alias. Returns the indices it pointed to before.
      def switch_alias(alias_name, index)
        Names.check(alias_name, "alias")
        Names.check(index, "index")
        raise Error, "elasticsearch: #{index}: no such index" unless exists?(index)

        current = aliased(alias_name)
        return current if current == [index]
        if current.empty? && exists?(alias_name)
          raise Error, "elasticsearch: #{alias_name} is an index, not an alias; delete it before the alias can take " \
                       "its name"
        end

        actions = current.map { {remove: {index: it, alias: alias_name}} } << {add: {index:, alias: alias_name}}
        request { client.indices.update_aliases(body: {actions:}) }
        logger.info("#{alias_name}: #{current.empty? ? "(none)" : current.join(", ")} → #{index}")
        current
      end

      # Deletes the indices named ALIAS-YYYYMMDD-HHMMSS older than the one
      # the alias points to, but the keep newest of them. Newer ones without
      # the alias (a load that runs or failed) stay. Returns the names
      # deleted, or with dry_run: the names it would delete.
      def prune(alias_name, keep: 1, dry_run: false)
        Names.check(alias_name, "alias")
        unless keep.is_a?(Integer) && keep >= 0
          raise ArgumentError, "keep must be an Integer of 0 or more, got #{keep.inspect}"
        end

        stamped = /\A#{Regexp.escape(alias_name)}-\d{8}-\d{6}\z/
        active = aliased(alias_name)
        raise Error, "elasticsearch: no index behind #{alias_name}, so nothing is pruned" if active.empty?

        current = active.grep(stamped).min
        unless current
          logger.info("#{alias_name}: #{active.join(", ")} has no timestamp, so nothing is pruned")
          return []
        end

        older, newer = (names("#{alias_name}-*").grep(stamped) - active).sort.partition { it < current }
        newer.each { logger.info("#{it} is newer than #{current}, left alone") }
        older.first([older.size - keep, 0].max).each do |name|
          dry_run ? logger.info("would delete #{name}") : remove(name)
        end
      end

      # Puts settings (a Hash or the path of a JSON file); without
      # number_of_shards, which never changes. reopen: true closes the index
      # first and opens it again (for analysis settings).
      def update_settings(name, settings, reopen: false)
        Names.check(name, "index")
        flat = Definition.flat_settings(Definition.load(settings, "settings")).except(SHARDS)
        raise ArgumentError, "settings must name at least one setting to change" if flat.empty?
        return put_settings(name, flat) unless reopen

        request { client.indices.close(index: name) }
        begin
          put_settings(name, flat)
        ensure
          request { client.indices.open(index: name) }
        end
      end

      # Deletes the index name. Refuses an index that an alias points to,
      # unless force: true.
      def delete(name, force: false)
        Names.check(name, "index")
        raise Error, "elasticsearch: #{name} is an alias; delete the index behind it" unless aliased(name).empty?

        aliases = request { client.indices.get_alias(index: name).body.dig(name, "aliases").keys }
        unless aliases.empty? || force
          raise Error, "elasticsearch: #{aliases.join(", ")} #{aliases.one? ? "points" : "point"} to #{name}; " \
                       "switch #{aliases.one? ? "it" : "them"} first or use force"
        end

        remove(name)
      end

      def exists?(name) = request { client.indices.exists(index: name) }

      # The indices alias_name points to, sorted; [] for none.
      def aliased(alias_name)
        request { client.indices.get_alias(name: alias_name).body.keys.sort }
      rescue Error => e
        raise unless e.cause.is_a?(Elastic::Transport::Transport::Errors::NotFound)

        []
      end

      def refresh(name) = request { client.indices.refresh(index: name) }

      # Without the client, whose options hold the credentials.
      def inspect = "#<#{self.class.name} connection=#{@connection.inspect}>"

      # The open and closed indices that match pattern, sorted by name, as
      # {name:, aliases:, docs:, size: (bytes), health:, created: (Time)}.
      def list(pattern = "*")
        rows = request do
          client.cat.indices(index: pattern, format: "json", bytes: "b", expand_wildcards: "open,closed",
                             h: "index,health,docs.count,store.size,creation.date").body
        end
        aliases = request { client.cat.aliases(format: "json", h: "alias,index").body }.group_by { it["index"] }
        rows.map { row(it, aliases) }.sort_by { it[:name] }
      end

      # The rows of list as a table for the terminal.
      def self.table(rows)
        lines = [["index", "aliases", "docs", "size", "health", "created"]] + rows.map do |row|
          [row[:name], row[:aliases].join(","), row[:docs].to_s, size(row[:size]), row[:health].to_s,
           row[:created]&.strftime("%Y-%m-%d %H:%M").to_s]
        end
        widths = lines.transpose.map { |column| column.map(&:size).max }
        lines.map { |line| line.zip(widths).map { |text, width| text.ljust(width) }.join("  ").rstrip }.join("\n")
      end

      def self.size(bytes)
        return "" unless bytes

        unit, power = ["B", "KB", "MB", "GB", "TB"].each_with_index.find { |_, n| bytes < 1024**(n + 1) } || ["TB", 4]
        power.zero? ? "#{bytes} B" : format("%<value>.1f %<unit>s", value: bytes.fdiv(1024**power), unit:)
      end

      private

      def row(row, aliases)
        {name: row["index"], aliases: (aliases[row["index"]] || []).map { it["alias"] }.sort,
         docs: row["docs.count"]&.to_i, size: row["store.size"]&.to_i, health: row["health"],
         created: row["creation.date"] && Time.at(row["creation.date"].to_i / 1000).utc}
      end

      def put_settings(name, flat)
        request { client.indices.put_settings(index: name, body: flat) }
        logger.info("updated the settings of #{name}")
      rescue Error => e
        raise unless e.message.include?("non dynamic settings")

        raise Error, "#{e.message}; use reopen (--reopen) for settings that change only on a closed index"
      end

      def remove(name)
        request { client.indices.delete(index: name) }
        logger.info("deleted #{name}")
        name
      end

      # The names of the open and closed indices that match pattern.
      def names(pattern)
        rows = request do
          client.cat.indices(index: pattern, format: "json", h: "index", expand_wildcards: "open,closed").body
        end
        rows.map { it["index"] }
      end

      def request
        yield
      rescue Elastic::Transport::Transport::Error => e
        raise Error, "elasticsearch: #{@connection.describe(e)}"
      end

      def client
        @client ||= @connection.connect
      rescue Error => e
        raise Error, "elasticsearch: #{e.message}"
      end

      def logger = @logger || Metacrunch.logger

    end
  end
end
