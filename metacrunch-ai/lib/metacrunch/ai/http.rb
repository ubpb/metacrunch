# frozen_string_literal: true

module Metacrunch
  module Ai
    # JSON over HTTP for model APIs: one persistent connection per object,
    # so per process, and retries with a growing delay for answers and
    # errors that may pass. Refusals of the input raise InvalidInput, other
    # refusals ApiError, and what still fails after the retries Unavailable.
    class Http

      RETRYABLE = [429, 500, 502, 503, 504].freeze
      INVALID_INPUT = [400, 413, 422].freeze
      # Lost connections, garbled answers and TLS errors, which may pass;
      # those of a certificate do not, but cannot be told apart.
      NETWORK_ERRORS = [
        Net::OpenTimeout, Net::ReadTimeout, Net::WriteTimeout, Net::HTTPBadResponse, IOError, OpenSSL::SSL::SSLError,
        Errno::ECONNREFUSED, Errno::ECONNRESET, Errno::ECONNABORTED, Errno::EPIPE, Errno::ETIMEDOUT,
        Errno::EHOSTUNREACH, Errno::ENETUNREACH
      ].freeze
      MAX_DELAY = 60
      EXCERPT = 300

      JSON_HEADERS = {"Content-Type" => "application/json", "Accept" => "application/json"}.freeze

      # An answer of get_raw: the status, the headers (lower-case names, the
      # first value of each) and the body as bytes.
      Raw = Data.define(:status, :headers, :body)

      # url: the API base, to which each request appends its path; its query
      # is kept. headers: sent with every request, over the defaults of each
      # method. name: for messages and log lines.
      def initialize(url:, headers: {}, timeout: 60, retries: 5, name: "api")
        @uri = Http.uri(url)
        raise ArgumentError, "headers must be a Hash, got #{headers.inspect}" unless headers.is_a?(Hash)
        unless timeout.is_a?(Numeric) && timeout.positive?
          raise ArgumentError, "timeout must be a positive number of seconds, got #{timeout.inspect}"
        end
        unless retries.is_a?(Integer) && !retries.negative?
          raise ArgumentError, "retries must be an Integer of 0 or more, got #{retries.inspect}"
        end

        @headers = headers
        @timeout = timeout
        @retries = retries
        @name = name
      end

      def self.uri(url)
        uri = URI(url.to_s)
        return uri if uri.is_a?(URI::HTTP) && uri.host

        raise ArgumentError, "url must be an http or https URL, got #{url.inspect}"
      rescue URI::InvalidURIError
        raise ArgumentError, "url must be an http or https URL, got #{url.inspect}"
      end

      # logger: where retries are logged.
      def open(logger = nil)
        @logger = logger
        self
      end

      def close
        @connection.finish if @connection&.started?
        @connection = nil
      end

      # Without the headers, which may hold a key.
      def inspect = "#<#{self.class.name} #{@name} url=#{location("").inspect}>"

      # POSTs body as JSON to the base path plus path and returns the answer,
      # a Hash.
      def post_json(path, body)
        response = with_retries(path) { send_request(Net::HTTP::Post, path, JSON.generate(body), JSON_HEADERS) }
        parse(path, response, "a JSON object", Hash)
      end

      # GETs the base path plus path and returns the body as text, UTF-8.
      def get(path)
        response = with_retries(path) { send_request(Net::HTTP::Get, path, nil, {"Accept" => "*/*"}) }
        response.body.to_s.dup.force_encoding(Encoding::UTF_8).scrub
      end

      # PUTs bytes of content_type to the base path plus path and returns the
      # answer, parsed JSON: a Hash or an Array.
      def put(path, bytes, content_type:, headers: {})
        response = with_retries(path) do
          send_request(Net::HTTP::Put, path, bytes,
                       {"Accept" => "application/json"}, headers.merge("Content-Type" => content_type))
        end
        parse(path, response, "JSON", Hash, Array)
      end

      # GETs the base path plus path and returns the answer whatever its
      # status (redirects and refusals too), except what is retried (429,
      # 5xx, network errors). A body over max_size bytes raises InvalidInput.
      def get_raw(path, headers: {}, max_size: nil)
        response = with_retries(path, raw: true) do
          send_request(Net::HTTP::Get, path, nil, {"Accept" => "*/*"}, headers) { read_limited(path, it, max_size) }
        end
        Raw.new(status: response.code.to_i, headers: response.to_hash.transform_values(&:first), body: response.body)
      rescue InvalidInput
        close
        raise
      end

      private

      # Yields until an answer comes that is returned: 2xx, or with raw: every
      # status that is not retried; other refusals raise at once, what may
      # pass is retried.
      def with_retries(path, raw: false)
        retries = 0
        loop do
          response = yield
        rescue *NETWORK_ERRORS => e
          close
          retries = retry_later(path, retries, e.class.name, error: e)
        else
          status = response.code.to_i
          retryable = RETRYABLE.include?(status)
          return response if status.between?(200, 299) || (raw && !retryable)

          refuse(path, status, response) unless retryable
          retries = retry_later(path, retries, status, response)
        end
      end

      # The headers: those of the method, the object's, those of the call. A
      # block reads the body.
      def send_request(type, path, body, defaults, headers = {}, &)
        request = type.new(request_uri(path), defaults.merge(@headers, headers))
        request.body = body if body
        connection.request(request, &)
      end

      # Reads the body of response in chunks, as bytes, up to max_size.
      def read_limited(path, response, max_size)
        body = +"".b
        response.read_body do |chunk|
          body << chunk
          next unless max_size && body.bytesize > max_size

          raise InvalidInput.new("#{@name} at #{location(path)}: larger than #{max_size} bytes",
                                 status: response.code.to_i)
        end
        response.body = body
      end

      def connection
        @connection ||= Net::HTTP.new(@uri.host, @uri.port).tap do |http|
          http.use_ssl = @uri.scheme == "https"
          http.open_timeout = http.read_timeout = http.write_timeout = @timeout
          http.start
        end
      end

      def request_uri(path) = "#{@uri.path.chomp("/")}#{path}#{"?#{@uri.query}" if @uri.query}"

      # The URL of a request for messages, without user info.
      def location(path) = "#{@uri.scheme}://#{@uri.host}:#{@uri.port}#{request_uri(path)}"

      # The parsed answer if it is one of types; else ApiError, whose message
      # says what was expected.
      def parse(path, response, expected, *types)
        answer = JSON.parse(response.body.to_s)
        return answer if types.any? { answer.is_a?(it) }

        malformed(path, response, expected)
      rescue JSON::ParserError
        malformed(path, response, expected)
      end

      def malformed(path, response, expected)
        body = excerpt(response.body)
        raise ApiError.new("#{@name} at #{location(path)}: malformed answer, not #{expected}#{": #{body}" if body}",
                           status: response.code.to_i, body:)
      end

      def refuse(path, status, response)
        body = excerpt(response.body)
        message = "#{@name} at #{location(path)}: #{status}#{": #{body}" if body}"
        raise (INVALID_INPUT.include?(status) ? InvalidInput : ApiError).new(message, status:, body:)
      end

      # Waits before the next try and returns the number of retries so far,
      # or raises Unavailable when no retry is left, with the last answer or
      # the message of the last error, unless that only repeats its class.
      # what: the status or the error class.
      def retry_later(path, retries, what, response = nil, error: nil)
        if retries >= @retries
          body = response && excerpt(response.body)
          reason = body || (error.message unless error.nil? || error.message.start_with?(what))
          raise Unavailable.new("#{@name} at #{location(path)}: still #{what} after #{@retries} retries" \
                                "#{": #{reason}" if reason}", status: response&.code&.to_i, body:)
        end

        delay = retry_after(response) || ([2**retries, MAX_DELAY].min * (0.5 + (rand / 2)))
        @logger&.warn("#{@name}: #{what}, retry #{retries + 1}/#{@retries} in #{format("%.1f", delay)} s")
        sleep(delay)
        retries + 1
      end

      # Retry-After in seconds or as an HTTP date, at most MAX_DELAY; nil
      # without one or for one that cannot be read.
      def retry_after(response)
        value = response&.[]("retry-after")
        return nil if value.nil?

        seconds = Integer(value, 10, exception: false) || (Time.httpdate(value) - Time.now)
        seconds.clamp(0, MAX_DELAY).to_f
      rescue ArgumentError
        nil
      end

      def excerpt(body)
        return nil if body.nil? || body.empty?

        text = body.dup.force_encoding(Encoding::UTF_8).scrub
        text.length > EXCERPT ? "#{text[0, EXCERPT]}..." : text
      end

    end
  end
end
