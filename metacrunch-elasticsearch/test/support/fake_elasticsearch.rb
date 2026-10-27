# frozen_string_literal: true

# An Elasticsearch for unit tests, below the real client: its Faraday adapter
# (the client option adapter:) answers from routes instead of the network, so
# client, transport and Faraday run as they do against a server. A request
# without a route fails the test.
class FakeElasticsearch

  # A request as the server sees it. body: the String sent, or nil; headers
  # with lowercase names.
  Request = Data.define(:verb, :host, :path, :params, :body, :headers) do
    def json = JSON.parse(body)

    # The lines of a bulk body.
    def ndjson = body.lines.map { JSON.parse(it) }
  end

  URL = "http://es.test:9200"

  attr_reader :requests

  # version: the version GET / reports; product: the x-elastic-product
  # header of every answer (nil for none, as OpenSearch).
  def initialize(version: "#{Elasticsearch::VERSION[/\A\d+/]}.1.0", product: "Elasticsearch")
    @routes = []
    @requests = []
    @product = product
    on("GET", "/") { [200, {"version" => {"number" => version}}] }
  end

  # Answers requests with method and a path equal to path (a String) or
  # matching it (a Regexp) with the block's [status, body, headers]; a Hash
  # or Array body is sent as JSON. The block gets the Request. The newest
  # route wins; with times: it answers that many requests only.
  def on(method, path, times: nil, &answer)
    @routes.unshift({method:, path:, times:, answer:})
    self
  end

  # The requests other than the server check (GET /).
  def calls = @requests.reject { it.verb == "GET" && it.path == "/" }

  def connection(**)
    Metacrunch::Elasticsearch::Connection.new(url: URL, adapter:, **)
  end

  # A Faraday adapter class that asks this fake.
  def adapter
    fake = self
    Class.new(Faraday::Adapter) do
      define_method(:call) do |env|
        body = env.body
        super(env)
        status, answer, headers = fake.answer(env, body)
        save_response(env, status, answer, headers)
        @app.call(env)
      end
    end
  end

  def answer(env, body)
    path = env.url.path.gsub(/%\h\h/) { it[1..].hex.chr }
    request = Request.new(verb: env.method.to_s.upcase, host: env.url.host, path:,
                          params: URI.decode_www_form(env.url.query.to_s).to_h, body:,
                          headers: env.request_headers.to_h.transform_keys(&:downcase))
    @requests << request
    route = @routes.find { matches?(it, request) }
    raise "no route for #{request.verb} #{request.path}" unless route

    route[:times] -= 1 if route[:times]
    status, answer, headers = route[:answer].call(request)
    headers = {"x-elastic-product" => @product, "content-type" => "application/json"}.compact.merge(headers || {})
    [status, answer.is_a?(Hash) || answer.is_a?(Array) ? JSON.generate(answer) : answer.to_s, headers]
  end

  private

  def matches?(route, request)
    return false if route[:times]&.zero?
    return false unless route[:method] == request.verb

    route[:path].is_a?(Regexp) ? route[:path].match?(request.path) : route[:path] == request.path
  end

end
