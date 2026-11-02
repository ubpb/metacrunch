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
      NETWORK_ERRORS = [
        Net::OpenTimeout, Net::ReadTimeout, Net::WriteTimeout, EOFError, Errno::ECONNRESET, Errno::ECONNREFUSED,
        Errno::EPIPE
      ].freeze
      MAX_DELAY = 60
      EXCERPT = 300

      # url: the API base, to which post_json appends its path; its query is
      # kept. name: for messages and log lines.
      def initialize(url:, headers: {}, timeout: 60, retries: 5, name: "api")
        @uri = Http.uri(url)
        raise ArgumentError, "headers must be a Hash, got #{headers.inspect}" unless headers.is_a?(Hash)
        unless timeout.is_a?(Numeric) && timeout.positive?
          raise ArgumentError, "timeout must be a positive number of seconds, got #{timeout.inspect}"
        end
        unless retries.is_a?(Integer) && !retries.negative?
          raise ArgumentError, "retries must be an Integer of 0 or more, got #{retries.inspect}"
        end

        @headers = {"Content-Type" => "application/json", "Accept" => "application/json"}.merge(headers)
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

      # POSTs body as JSON to the base path plus path and returns the answer,
      # a Hash.
      def post_json(path, body)
        json = JSON.generate(body)
        retries = 0
        loop do
          response = post(path, json)
        rescue *NETWORK_ERRORS => e
          close
          retries = retry_later(path, retries, e.class.name)
        else
          status = response.code.to_i
          return parse(path, response) if status.between?(200, 299)

          refuse(path, status, response) unless RETRYABLE.include?(status)
          retries = retry_later(path, retries, status, response)
        end
      end

      private

      def post(path, json)
        request = Net::HTTP::Post.new(request_uri(path), @headers)
        request.body = json
        connection.request(request)
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

      def parse(path, response)
        answer = JSON.parse(response.body)
        return answer if answer.is_a?(Hash)

        malformed(path, response)
      rescue JSON::ParserError
        malformed(path, response)
      end

      def malformed(path, response)
        raise ApiError.new("#{@name} at #{location(path)}: malformed answer, not a JSON object: " \
                           "#{excerpt(response.body)}", status: response.code.to_i, body: excerpt(response.body))
      end

      def refuse(path, status, response)
        body = excerpt(response.body)
        message = "#{@name} at #{location(path)}: #{status}#{": #{body}" if body}"
        raise (INVALID_INPUT.include?(status) ? InvalidInput : ApiError).new(message, status:, body:)
      end

      # Waits before the next try and returns the number of retries so far,
      # or raises Unavailable when no retry is left. what: the status or the
      # error class.
      def retry_later(path, retries, what, response = nil)
        if retries >= @retries
          body = response && excerpt(response.body)
          raise Unavailable.new("#{@name} at #{location(path)}: still #{what} after #{@retries} retries" \
                                "#{": #{body}" if body}", status: response&.code&.to_i, body:)
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
