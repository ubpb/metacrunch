# frozen_string_literal: true

module Metacrunch
  module Ai
    # A polite client for documents on other people's servers: a user agent,
    # a minimum delay between two requests to one host (or the host's
    # Crawl-delay), robots.txt for every URL and every redirect, redirects up
    # to a limit, a size limit, and the retries of Http. One per Fetch or
    # Sitemap::Reader, so per process. Internal.
    class Web

      USER_AGENT = "metacrunch/#{VERSION} (+https://github.com/ubpb/metacrunch)".freeze
      AGENT = "metacrunch"
      REDIRECTS = [301, 302, 303, 307, 308].freeze
      # robots.txt is read up to this size; a larger one counts as missing.
      ROBOTS_SIZE = 500 * 1024
      # Bytes a path or query may not hold as they are (RFC 3986; brackets
      # only belong to IPv6 hosts): percent-encoded.
      UNSAFE = %r{[^A-Za-z0-9\-._~:/?@!$&'()*+,;=%]}n
      DEFAULT_PORTS = {"http" => 80, "https" => 443}.freeze

      # A URL that is not http or https.
      class NotHttp < Error; end
      # A host name with other than ASCII characters (IDN), not supported.
      class Idn < Error; end
      # A URL that robots.txt disallows.
      class Disallowed < Error; end

      # An answer: the status, the final URL, the headers (lower-case names)
      # and the body as bytes.
      Page = Data.define(:status, :url, :headers, :body)

      # The URL as a browser sends it: without fragment, the host in lower
      # case, without the scheme's default port, path and query
      # percent-encoded (UTF-8; bytes that are no UTF-8 as they are) where
      # needed. Raises NotHttp or Idn.
      def self.normalize(url)
        text = bytes(url.to_s).strip.sub(/#.*\z/m, "")
        match = %r{\A(https?)://([^/?#]+)(.*)\z}im.match(text)
        raise NotHttp, "not an http(s) URL: #{url.inspect}" unless match

        scheme, authority, rest = match.captures
        raise Idn, "host name not supported: #{authority.dup.force_encoding(Encoding::UTF_8).scrub}" unless
          authority.ascii_only?

        scheme = scheme.downcase
        rest = "/#{rest}" unless rest.start_with?("/")
        normalized = "#{scheme}://#{authority(scheme, authority)}#{encode(rest)}".force_encoding(Encoding::UTF_8)
        URI(normalized)
        normalized
      rescue URI::InvalidURIError
        raise NotHttp, "not an http(s) URL: #{url.inspect}"
      end

      # scheme://host[:port] of url, normalized, without a default port.
      def self.origin(url)
        uri = URI(normalize(url))
        "#{uri.scheme}://#{uri.host}#{":#{uri.port}" unless uri.port == uri.default_port}"
      end

      # The user info as written, the host in lower case, the port unless it
      # is the scheme's default.
      def self.authority(scheme, text)
        userinfo, at, hostport = text.rpartition("@")
        host, port = /\A(\[[^\]]*\]|[^:]*)(?::(\d*))?\z/.match(hostport)&.captures || [hostport, nil]
        port = nil if port.to_s.empty? || port.to_i == DEFAULT_PORTS[scheme]
        "#{userinfo}#{at}#{host.downcase}#{":#{port}" if port}"
      end

      # text as UTF-8 bytes in a binary String; another encoding is converted,
      # bytes that are no UTF-8 stay as they are.
      def self.bytes(text)
        unless [Encoding::UTF_8, Encoding::BINARY, Encoding::US_ASCII].include?(text.encoding)
          text = text.encode(Encoding::UTF_8)
        end
        text.b
      rescue EncodingError
        text.b
      end
      private_class_method :authority, :bytes

      # The URL a Location header names, relative to base, normalized.
      def self.resolve(base, location)
        location = location.strip.sub(/#.*\z/m, "")
        return normalize(location) if location.match?(%r{\Ahttps?://}i)
        return normalize("#{URI(base).scheme}:#{location}") if location.start_with?("//")

        normalize(URI.join(base, encode(location)).to_s)
      end

      def self.encode(text)
        bytes(text).gsub(/%(?![0-9A-Fa-f]{2})/n, "%25").gsub(UNSAFE) { format("%%%02X", it.ord) }
      end
      private_class_method :encode

      # delay: seconds between two requests to one host, raised by a
      # Crawl-delay in robots.txt up to max_delay; robots: false checks no
      # robots.txt; max_size: bytes; redirects: how many to follow. clock
      # (monotonic seconds) and sleeper are for tests.
      def initialize(user_agent: USER_AGENT, delay: 1, max_delay: 60, robots: true, max_size: 50 * 1024 * 1024,
                     redirects: 5, timeout: 30, retries: 2, clock: nil, sleeper: nil)
        validate(user_agent:, delay:, max_delay:, robots:, max_size:, redirects:, timeout:, retries:)
        @user_agent = user_agent
        @delay = delay
        @max_delay = max_delay
        @robots_on = robots
        @max_size = max_size
        @redirects = redirects
        @timeout = timeout
        @retries = retries
        @clock = clock || -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) }
        @sleeper = sleeper || ->(seconds) { sleep(seconds) }
        @clients = {}
        @robots = {}
        @last = {}
      end

      # logger: where retries are logged.
      def open(logger = nil)
        @logger = logger
        self
      end

      def close = @clients.each_value(&:close)

      # GETs url, following redirects, and returns a Page whatever its status
      # (except what Http retries and then raises as Unavailable). Raises
      # Disallowed, NotHttp, Idn, ApiError for too many redirects and
      # InvalidInput for a body over max_size.
      def get(url, max_size: @max_size)
        first = url = Web.normalize(url)
        (@redirects + 1).times do
          answer = request(URI(url), max_size)
          location = answer.headers["location"]
          return Page.new(status: answer.status, url:, headers: answer.headers, body: answer.body) unless
            REDIRECTS.include?(answer.status) && location

          url = Web.resolve(url, location)
        end
        raise ApiError, "#{first}: more than #{@redirects} redirects"
      end

      # The robots.txt of origin ("https://host:port"): cached when read (2xx)
      # or missing (4xx); raises Unavailable when unreachable, uncached.
      def robots(origin)
        @robots[origin] ||= read_robots(origin).tap { cut_delay(origin, it) }
      end

      private

      def request(uri, max_size)
        if @robots_on && !robots(origin(uri)).allowed?(uri.request_uri)
          raise Disallowed, "#{uri} is disallowed by robots.txt"
        end

        raw(uri, uri.request_uri, max_size)
      end

      def raw(uri, path, max_size)
        wait(uri.host)
        client(uri).get_raw(path, max_size:)
      ensure
        @last[uri.host] = @clock.call
      end

      # robots.txt, following up to 5 redirects; too many, a 4xx, a file too
      # large or a redirect to no http(s) URL count as no robots.txt.
      def read_robots(origin)
        site = uri = URI("#{origin}/robots.txt")
        6.times do
          answer = raw(uri, uri.request_uri, ROBOTS_SIZE)
          location = answer.headers["location"]
          next uri = URI(Web.resolve(uri.to_s, location)) if REDIRECTS.include?(answer.status) && location
          return Robots.parse(answer.body.dup.force_encoding(Encoding::UTF_8).scrub, agent: AGENT) if
            answer.status.between?(200, 299)
          return Robots::ALLOW if answer.status.between?(300, 499)

          unreachable(site, answer.status.to_s)
        end
        Robots::ALLOW
      rescue InvalidInput, NotHttp, Idn
        Robots::ALLOW
      rescue Unavailable => e
        unreachable(site, e.message, e.status)
      end

      def unreachable(uri, reason, status = nil)
        raise Unavailable.new("robots.txt of #{uri.host}:#{uri.port} unreachable: #{reason}", status:)
      end

      def wait(host)
        last = @last[host]
        return unless last

        remaining = last + delay(host) - @clock.call
        @sleeper.call(remaining) if remaining.positive?
      end

      def delay(host)
        crawl = @robots.find { |origin, _| URI(origin).host == host }&.last&.crawl_delay
        [@delay, (crawl || 0).clamp(..@max_delay)].max
      end

      def cut_delay(origin, robots)
        return unless robots.crawl_delay && robots.crawl_delay > @max_delay

        uri = URI(origin)
        @logger&.warn("robots.txt of #{uri.host}:#{uri.port} asks for a Crawl-delay of #{robots.crawl_delay} s; " \
                      "max_delay cuts it to #{@max_delay} s")
      end

      def client(uri)
        @clients[origin(uri)] ||= Http.new(url: origin(uri), headers: {"User-Agent" => @user_agent},
                                           timeout: @timeout, retries: @retries, name: uri.host).open(@logger)
      end

      def origin(uri) = "#{uri.scheme}://#{uri.host}:#{uri.port}"

      def validate(user_agent:, delay:, max_delay:, robots:, max_size:, redirects:, timeout:, retries:)
        raise ArgumentError, "user_agent must be a non-empty String, got #{user_agent.inspect}" unless
          Ai.text?(user_agent)
        raise ArgumentError, "delay must be seconds, 0 or more, got #{delay.inspect}" unless
          delay.is_a?(Numeric) && !delay.negative?
        raise ArgumentError, "max_delay must be seconds, 0 or more, got #{max_delay.inspect}" unless
          max_delay.is_a?(Numeric) && !max_delay.negative?
        raise ArgumentError, "robots must be true or false, got #{robots.inspect}" unless [true, false].include?(robots)
        raise ArgumentError, "redirects must be an Integer of 0 or more, got #{redirects.inspect}" unless
          redirects.is_a?(Integer) && !redirects.negative?
        raise ArgumentError, "timeout must be positive seconds, got #{timeout.inspect}" unless
          timeout.is_a?(Numeric) && timeout.positive?
        raise ArgumentError, "retries must be an Integer of 0 or more, got #{retries.inspect}" unless
          retries.is_a?(Integer) && !retries.negative?

        Ai.positive!(max_size, "max_size")
      end

    end
  end
end
