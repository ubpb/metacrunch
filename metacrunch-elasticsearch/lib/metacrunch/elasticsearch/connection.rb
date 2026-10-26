# frozen_string_literal: true

module Metacrunch
  module Elasticsearch

    # The connection params for jobs and commands:
    # params { instance_exec(&Metacrunch::Elasticsearch::CONNECTION_PARAMS) }
    # and Connection.from_params(params).
    CONNECTION_PARAMS = proc do
      param :url, String, env: "ELASTICSEARCH_URL", desc: "Elasticsearch URL, several comma-separated"
      param :api_key, String, env: "ELASTICSEARCH_API_KEY", credential: "elasticsearch.api_key",
                              desc: "API key (Base64, as Elasticsearch issues it)"
      param :user, String, env: "ELASTICSEARCH_USER", desc: "user for basic authentication"
      param :password, String, env: "ELASTICSEARCH_PASSWORD", credential: "elasticsearch.password",
                               desc: "password for basic authentication"
      param :ca_file, String, env: "ELASTICSEARCH_CA_FILE", desc: "CA certificate for TLS"
    end

    # Where and how to reach Elasticsearch. A value: building one does no
    # I/O. Every component builds its own client from it, so a reader and a
    # writer of one job (two threads with -w) share none.
    class Connection

      # The Elasticsearch majors this gem works with.
      SUPPORTED = (8..9)
      # Headers of the server check: plain JSON, so that it works whatever
      # compatibility the client asks for (client 9 sends compatible-with=9,
      # which Elasticsearch 8 refuses).
      PLAIN_JSON = {"accept" => "application/json", "content-type" => "application/json"}.freeze
      AUTH_HINT = "check api_key, or user and password " \
                  "(ELASTICSEARCH_API_KEY, ELASTICSEARCH_USER, ELASTICSEARCH_PASSWORD)"
      # The params that from_params reads, as CONNECTION_PARAMS declares them.
      PARAMS = [:url, :api_key, :user, :password, :ca_file].freeze
      DEFAULT_URL = "http://localhost:9200"

      attr_reader :request_timeout, :retries

      # A connection from the bound params of a job or command: the ones of
      # PARAMS it declares.
      def self.from_params(params)
        new(**PARAMS.select { params.respond_to?(it) }.to_h { [it, params.public_send(it)] })
      end

      # A URL for messages: user info (user:password@) as [FILTERED], up to the
      # last @, since a password may hold an unencoded / or @.
      def self.filter(url) = url.to_s.sub(%r{//.*@}, "//[FILTERED]@")

      # Raises Error unless a client of version client can talk to a server
      # of version server.
      def self.check_version(server, client, url)
        server_major = server[/\A\d+/].to_i
        client_major = client[/\A\d+/].to_i
        unless SUPPORTED.cover?(server_major)
          raise Error, "Elasticsearch #{server} at #{url} is not supported; metacrunch-elasticsearch needs 8 or 9"
        end
        return if server_major >= client_major

        raise Error, "the elasticsearch gem #{client} cannot talk to Elasticsearch #{server} at #{url}; " \
                     "use gem #{server_major}.x until the server runs #{client_major}"
      end

      # url: a String (several URLs comma-separated), an Array, or nil for
      # the client's default (ELASTICSEARCH_URL, else http://localhost:9200).
      # client_options go to ::Elasticsearch::Client.new and win over the
      # other options.
      def initialize(url: nil, api_key: nil, user: nil, password: nil, ca_file: nil, request_timeout: 60, retries: 3,
                     **client_options)
        @urls = parse_urls(url)
        @api_key = optional_string(api_key, :api_key)
        @user = optional_string(user, :user)
        @password = optional_string(password, :password)
        @ca_file = ca_file.nil? ? nil : path(ca_file)
        @request_timeout = timeout(request_timeout)
        @retries = count(retries)
        @client_options = client_options
        check_credentials
      end

      # The first URL for messages, user info filtered.
      def url
        Connection.filter((@urls || ENV.fetch("ELASTICSEARCH_URL", DEFAULT_URL).split(",")).first.strip)
      end

      # A new client. It sends no request yet.
      def client = ::Elasticsearch::Client.new(**client_arguments)

      # A new client after one request that checks the server: Elasticsearch,
      # in a version this client works with. Raises Error otherwise.
      #
      # The check goes to the client's transport: the client's own product
      # check (on its first request) prints a warning to stderr whenever that
      # request fails, e.g. with 401 or for a missing index. This check does
      # what the client's does and marks the client as checked.
      def connect
        client.tap do |client|
          response = client.transport.perform_request("GET", "/", {}, nil, PLAIN_JSON)
          raise ::Elasticsearch::UnsupportedProductError unless response.headers["x-elastic-product"] == "Elasticsearch"

          Connection.check_version(response.body.dig("version", "number").to_s, ::Elasticsearch::VERSION, url)
          client.instance_variable_set(:@verified, true)
        end
      rescue ::Elasticsearch::UnsupportedProductError, Elastic::Transport::Transport::Error => e
        raise Error, describe(e)
      end

      # What went wrong in a request, for messages: Elasticsearch's status,
      # type and reason, or why the request failed. Never shows secrets.
      def describe(error)
        case error
        when ::Elasticsearch::UnsupportedProductError then "#{url} is not Elasticsearch (OpenSearch is not supported)"
        when Elastic::Transport::Transport::ServerError then server_error(error)
        else "request to #{url} failed: #{error.message}"
        end
      end

      def inspect
        parts = ["url=#{(@urls || [url]).map { Connection.filter(it) }.join(",")}"]
        parts << "api_key=[FILTERED]" if @api_key
        parts << "user=#{@user} password=[FILTERED]" if @user
        "#<#{self.class.name} #{parts.join(" ")}>"
      end

      alias to_s inspect

      private

      # Basic authentication goes in a header of its own: as user and password
      # the client would put it into the URL, which Faraday warns about. The
      # timeout goes into transport_options too: the client's request_timeout
      # would replace the request options given there. client_options are
      # merged in deeply, so transport_options of their own keep these.
      def client_arguments
        arguments = {retry_on_failure: @retries.zero? ? false : @retries}
        arguments[:hosts] = @urls if @urls
        arguments[:api_key] = @api_key if @api_key
        transport = {request: {timeout: @request_timeout}}
        transport[:headers] = {"authorization" => "Basic #{["#{@user}:#{@password}"].pack("m0")}"} if @user
        transport[:ssl] = {ca_file: @ca_file} if @ca_file
        arguments[:transport_options] = transport
        merge(arguments, copy(@client_options))
      end

      # Hashes merged key by key; the values of theirs win.
      def merge(ours, theirs)
        ours.merge(theirs) { |_key, mine, other| mine.is_a?(Hash) && other.is_a?(Hash) ? merge(mine, other) : other }
      end

      # The client changes the Hashes it gets (headers, user and password).
      def copy(value)
        case value
        when Hash then value.transform_values { copy(it) }
        when Array then value.map { copy(it) }
        else value
        end
      end

      def server_error(error)
        case Elasticsearch.status(error)
        when 401 then "authentication failed at #{url}; #{AUTH_HINT}"
        when 403 then "#{Elasticsearch.reason(error)}; #{AUTH_HINT}"
        else Elasticsearch.reason(error)
        end
      end

      def parse_urls(value)
        return nil if value.nil?

        list = value.is_a?(String) ? value.split(",") : value
        raise ArgumentError, "url must be a String or an Array, got #{value.class}" unless list.is_a?(Array)

        list.map { http_url(it) }.tap do |urls|
          raise ArgumentError, "url must name at least one URL" if urls.empty?
        end
      end

      def http_url(value)
        url = value.is_a?(String) ? value.strip : value
        uri = url.is_a?(String) ? URI.parse(url) : nil
        return url if uri.is_a?(URI::HTTP) && uri.host && !uri.host.empty?

        raise ArgumentError, "url must be an http or https URL, got #{Connection.filter(value).inspect}"
      rescue URI::InvalidURIError
        raise ArgumentError, "url must be an http or https URL, got #{Connection.filter(value).inspect}"
      end

      def optional_string(value, name)
        return value if value.nil? || (value.is_a?(String) && !value.empty?)

        raise ArgumentError, "#{name} must be a non-empty String"
      end

      def path(value)
        return value.to_s if value.is_a?(String) || value.is_a?(Pathname)

        raise ArgumentError, "ca_file must be a path, got #{value.class}"
      end

      def timeout(value)
        return value if value.is_a?(Numeric) && value.positive?

        raise ArgumentError, "request_timeout must be a positive number of seconds, got #{value.inspect}"
      end

      def count(value)
        return value if value.is_a?(Integer) && !value.negative?

        raise ArgumentError, "retries must be an Integer of 0 or more, got #{value.inspect}"
      end

      def check_credentials
        raise ArgumentError, "user and password go together" if @user.nil? != @password.nil?
        raise ArgumentError, "use api_key or user and password, not both" if @api_key && @user
      end

    end

  end
end
