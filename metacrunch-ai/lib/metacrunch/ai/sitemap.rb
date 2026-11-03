# frozen_string_literal: true

module Metacrunch
  module Ai
    module Sitemap
      # Source: one record per page of sitemaps (sitemaps.org), {"id" => url,
      # "url" => url, "lastmod" => lastmod} (lastmod only when given). Reads
      # URLs (through the polite web client, without checking robots.txt:
      # sitemaps are published for crawlers) and local files; sitemap indexes
      # (up to 3 levels), gzip by its magic bytes, with or without namespace.
      # A URL listed twice is yielded once.
      #
      # A sitemap that cannot be read is yielded as InvalidRecord, so the
      # job's failure policy decides; when not one top-level sitemap can be
      # read, the source raises InputError.
      class Reader

        DEPTH = 3
        GZIP = "\x1F\x8B".b
        DATE = /\A\d{4}-\d\d-\d\d\z/

        # A sitemap that is none.
        class NotSitemap < Error; end

        Site = Data.define(:url)
        Run = Struct.new(:seen, :read, :waiting, :failures)
        FAILURES = [Error, Nokogiri::XML::SyntaxError, Zlib::Error, SystemCallError].freeze
        private_constant :Site, :Run, :FAILURES

        # Sitemaps of a website: those its robots.txt names in Sitemap lines,
        # else /sitemap.xml, which is also tried when all named ones fail.
        def self.site(url, **) = new(Site.new(Web.normalize(url)), **)

        # targets: URLs or local paths, one or an Array. matching: a Regexp
        # the URL must match. since: a time (ISO 8601 String, Date, Time);
        # pages with an earlier lastmod are skipped, pages without one kept.
        # Other options go to the web client (user_agent, delay, max_size,
        # redirects, timeout, retries).
        def initialize(targets, matching: nil, since: nil, **)
          @targets = targets.is_a?(Array) ? targets : [targets]
          valid = !@targets.empty? && @targets.all? { it.is_a?(String) || it.is_a?(Pathname) || it.is_a?(Site) }
          raise ArgumentError, "targets must be URLs or paths, got #{targets.inspect}" unless valid
          raise ArgumentError, "matching must be a Regexp, got #{matching.inspect}" unless
            matching.nil? || matching.is_a?(Regexp)

          @matching = matching
          @since = since.nil? ? nil : time(since)
          raise ArgumentError, "since must be a time, got #{since.inspect}" if since && @since.nil?

          @web = Web.new(**, robots: false)
        end

        def open(context) = @web.open(context.logger)

        def close = @web.close

        # Without a block an Enumerator. A top-level sitemap that fails before
        # the first one is read comes as InvalidRecord after it.
        def each(&)
          return enum_for(:each) unless block_given?

          run = Run.new(Set.new, false, [], [])
          @targets.each do |target|
            next attempt(target, run, &) unless target.is_a?(Site)

            named = site_maps(target.url)
            fallback = "#{Web.origin(target.url)}/sitemap.xml"
            read = named.map { attempt(it, run, &) }.any?
            attempt(fallback, run, &) unless read || named.any? { same?(it, fallback) }
          end
          raise InputError, "no sitemap could be read: #{run.failures.join(", ")}" unless run.read
        end

        private

        # Reads a top-level sitemap; true when it could be read.
        def attempt(target, run, &)
          read(target, 1, run.seen, &)
          run.read = true
          run.waiting.each(&)
          run.waiting.clear
          true
        rescue *FAILURES => e
          run.failures << "#{target} (#{e.message})"
          invalid = InvalidRecord.new(raw: target.to_s, error: e)
          run.read ? yield(invalid) : run.waiting << invalid
          false
        end

        def site_maps(url)
          @web.robots(origin(url)).sitemaps
        rescue Unavailable
          []
        end

        def same?(url, normalized)
          Web.normalize(url) == normalized
        rescue Error
          false
        end

        def origin(url)
          uri = URI(url)
          "#{uri.scheme}://#{uri.host}:#{uri.port}"
        end

        def read(location, depth, seen, &)
          children = []
          parse(load(location)) do |kind, entry|
            next children << entry["loc"] if kind == :sitemap

            page(entry, seen, &)
          end
          children.each do |child|
            raise NotSitemap, "#{child}: sitemap index deeper than #{DEPTH} levels" if depth >= DEPTH

            read(locate(child, location), depth + 1, seen, &)
          rescue *FAILURES => e
            yield InvalidRecord.new(raw: child, error: e)
          end
        end

        # A sitemap an index names: for a remote index a URL relative to it
        # (never a local file: NotHttp for other schemes), for a local index a
        # URL or a path relative to its directory.
        def locate(child, parent)
          return Web.resolve(parent, child) if remote?(parent)
          return child if remote?(child)

          File.expand_path(child, File.dirname(parent.to_s))
        end

        def page(entry, seen)
          url = entry["loc"]
          return if url.nil? || url.empty? || seen.include?(url)
          return if @matching && !@matching.match?(url)
          return if @since && (modified = time(entry["lastmod"])) && modified < @since

          seen << url
          yield({"id" => url, "url" => url, "lastmod" => entry["lastmod"]}.compact)
        end

        def load(location)
          body = remote?(location) ? fetch(location) : File.binread(location.to_s)
          body.start_with?(GZIP) ? Zlib.gunzip(body) : body
        end

        def remote?(location) = location.is_a?(String) && location.match?(%r{\Ahttps?://}i)

        def fetch(url)
          page = @web.get(url)
          raise ApiError.new("#{url}: #{page.status}", status: page.status) unless page.status.between?(200, 299)

          page.body
        end

        # Yields [:url or :sitemap, {"loc", "lastmod"}] per entry.
        def parse(xml)
          kind = nil
          entry = nil
          field = nil
          Nokogiri::XML::Reader(xml).each do |node|
            case node.node_type
            when Nokogiri::XML::Reader::TYPE_ELEMENT
              kind ||= root(node.local_name)
              name = node.local_name
              entry = {} if ["url", "sitemap"].include?(name)
              field = name if entry && ["loc", "lastmod"].include?(name) && !node.empty_element?
            when Nokogiri::XML::Reader::TYPE_TEXT, Nokogiri::XML::Reader::TYPE_CDATA
              entry[field] = "#{entry[field]}#{node.value}" if field
            when Nokogiri::XML::Reader::TYPE_END_ELEMENT
              if field == node.local_name
                entry[field] = entry[field].to_s.strip
                field = nil
              elsif entry && ["url", "sitemap"].include?(node.local_name)
                yield kind, entry
                entry = nil
              end
            end
          end
        end

        def root(name)
          return :url if name == "urlset"
          return :sitemap if name == "sitemapindex"

          raise NotSitemap, "no sitemap: <#{name}>"
        end

        # A Time for an ISO 8601 date or time (a date is its start in UTC),
        # a Date or a Time; nil for what it cannot read.
        def time(value)
          case value
          when Time then value.utc
          when Date then Time.utc(value.year, value.month, value.day)
          when DATE then Time.utc(*value.split("-").map { Integer(it, 10) })
          when String then Time.iso8601(value).utc
          end
        rescue ArgumentError
          nil
        end

      end
    end
  end
end
