# frozen_string_literal: true

require "test_helper"
require "time"

class HttpTest < Minitest::Test

  def setup
    @api = FakeApi.new
    @log = StringIO.new
  end

  def teardown
    @http&.close
    @api.stop
  end

  def test_posts_json_and_returns_the_parsed_answer
    @api.on("POST", "/v1/things") { [200, {"echo" => it.json}] }

    answer = http(headers: {"X-Extra" => "yes"}).post_json("/things", {"a" => [1, "ü"]})
    request = @api.requests.first

    assert_equal({"echo" => {"a" => [1, "ü"]}}, answer)
    assert_equal ["application/json", "yes"], request.headers.values_at("content-type", "x-extra")
  end

  def test_gets_the_body_as_text
    @api.on("GET", "/v1/hello") { [200, "Hello, world"] }

    assert_equal "Hello, world", http.get("/hello")
  end

  def test_puts_bytes_with_their_type_and_headers
    @api.on("PUT", "/v1/files") { [200, [{"size" => it.body.bytesize}]] }
    answer = http.put("/files", "\xFF\x00pdf".b, content_type: "application/pdf", headers: {"X-Extra" => "yes"})
    request = @api.requests.first

    assert_equal [{"size" => 5}], answer
    assert_equal ["application/pdf", "yes", "\xFF\x00pdf".b],
                 [*request.headers.values_at("content-type", "x-extra"), request.body.b]
  end

  def test_get_and_put_retry_like_post
    @api.on("GET", "/v1/hello") { [200, "hi"] }
    @api.on("GET", "/v1/hello", times: 1) { [503, {}] }
    @api.on("PUT", "/v1/files") { [200, {}] }
    @api.on("PUT", "/v1/files", times: 1) { [503, {}] }
    delays = no_sleep(http)

    assert_equal ["hi", {}], [@http.get("/hello"), @http.put("/files", "x", content_type: "text/plain")]
    assert_equal [1.0, 1.0], delays
    assert_includes @log.string, "things: 503, retry 1/5 in 1.0 s"
  end

  def test_put_keeps_the_query
    @api.on("PUT", "/v1/files?version=2") { [200, {}] }

    assert_empty http(url: @api.url("/v1?version=2")).put("/files", "x", content_type: "text/plain")
  end

  def test_put_refuses_malformed_json
    @api.on("PUT", "/v1/files") { [200, "<html>"] }

    assert_raises(Metacrunch::Ai::ApiError) { http.put("/files", "x", content_type: "text/plain") }
  end

  def test_get_refusals_raise_api_error
    @api.on("GET", "/v1/hello") { [404, "no"] }
    error = assert_raises(Metacrunch::Ai::ApiError) { http.get("/hello") }

    assert_equal "things at #{@api.url("/v1/hello")}: 404: no", error.message
  end

  def test_get_gives_valid_utf8
    @api.on("GET", "/v1/hello") { [200, "caf\xC3\xA9 \xFF".b] }

    assert_equal "café �", http.get("/hello")
  end

  def test_get_raw_passes_statuses_through
    @api.on("GET", "/v1/gone") { [404, "no", {"X-Reason" => "moved"}] }
    @api.on("GET", "/v1/away") { [301, "", {"Location" => "/v1/here"}] }
    raw = http.get_raw("/gone")
    away = http.get_raw("/away")

    assert_equal [404, "no", "moved"], [raw.status, raw.body, raw.headers["x-reason"]]
    assert_equal [301, "/v1/here"], [away.status, away.headers["location"]]
  end

  def test_get_raw_stops_reading_at_max_size
    @api.on("GET", "/v1/big") { [200, "x" * 11] }
    @api.on("GET", "/v1/fits") { [200, "x" * 10] }
    client = http
    fits = client.get_raw("/fits", max_size: 10)
    error = assert_raises(Metacrunch::Ai::InvalidInput) { client.get_raw("/big", max_size: 10) }
    after = client.get_raw("/fits", max_size: 10)

    assert_equal [10, 200, 10], [fits.body.bytesize, error.status, after.body.bytesize]
    assert_match(/larger than 10 bytes/, error.message)
  end

  def test_get_raw_retries_like_get
    @api.on("GET", "/v1/page") { [200, "ok"] }
    @api.on("GET", "/v1/page", times: 1) { [503, ""] }
    delays = no_sleep(http)
    raw = @http.get_raw("/page")

    assert_equal [200, "ok", [1.0]], [raw.status, raw.body, delays]
  end

  def test_get_raw_sends_headers_and_gives_bytes
    @api.on("GET", "/v1/file") { [200, "%PDF\xFF".b, {"Content-Type" => "application/pdf"}] }
    raw = http.get_raw("/file", headers: {"X-Extra" => "yes"})

    assert_equal ["%PDF\xFF".b, Encoding::BINARY, "application/pdf"],
                 [raw.body, raw.body.encoding, raw.headers["content-type"]]
    assert_equal "yes", @api.requests.first.headers["x-extra"]
  end

  def test_keeps_the_query_of_the_url
    @api.on("POST", "/v1/things?version=2") { [200, {}] }

    assert_empty http(url: @api.url("/v1?version=2")).post_json("/things", {})
  end

  def test_keeps_the_connection_between_requests
    @api.on("POST", "/v1/things") { [200, {}] }
    client = http
    3.times { client.post_json("/things", {}) }

    assert_equal 1, @api.accepts
  end

  def test_reconnects_when_the_server_closed_the_connection
    api = FakeApi.new(close_after_each: true)
    api.on("POST", "/v1/things") { [200, {"ok" => true}] }
    @http = Metacrunch::Ai::Http.new(url: api.url("/v1")).open(Logger.new(@log))

    assert_equal [{"ok" => true}] * 3, Array.new(3) { @http.post_json("/things", {}) }
    assert_equal 3, api.accepts
    assert_empty @log.string
  ensure
    api.stop
  end

  def test_retries_retryable_statuses_with_backoff
    @api.on("POST", "/v1/things") { [200, {"ok" => true}] }
    @api.on("POST", "/v1/things", times: 2) { [503, {"error" => "busy"}] }
    delays = no_sleep(http)

    assert_equal({"ok" => true}, @http.post_json("/things", {}))
    assert_equal [1.0, 2.0], delays
    assert_includes @log.string, "things: 503, retry 1/5 in 1.0 s"
  end

  def test_backoff_has_jitter_and_stops_growing_at_a_minute
    @api.on("POST", "/v1/things") { [500, {}] }
    delays = no_sleep(http(retries: 8), rand: 0.0)
    assert_raises(Metacrunch::Ai::Unavailable) { @http.post_json("/things", {}) }

    assert_equal [0.5, 1.0, 2.0, 4.0, 8.0, 16.0, 30.0, 30.0], delays
  end

  def test_honours_retry_after_seconds_and_dates_up_to_a_minute
    date = (Time.now + 10).httpdate
    @api.on("POST", "/v1/things") { [200, {}] }
    @api.on("POST", "/v1/things", times: 1) { [429, {}, {"Retry-After" => "600"}] }
    @api.on("POST", "/v1/things", times: 1) { [429, {}, {"Retry-After" => date}] }
    @api.on("POST", "/v1/things", times: 1) { [429, {}, {"Retry-After" => "3"}] }
    delays = no_sleep(http)
    @http.post_json("/things", {})

    assert_in_delta 3.0, delays[0]
    assert_in_delta 10.0, delays[1], 1.5
    assert_in_delta 60.0, delays[2]
  end

  def test_an_unreadable_retry_after_gives_the_backoff
    @api.on("POST", "/v1/things") { [200, {}] }
    @api.on("POST", "/v1/things", times: 1) { [429, {}, {"Retry-After" => "soon"}] }
    delays = no_sleep(http)
    @http.post_json("/things", {})

    assert_equal [1.0], delays
  end

  def test_raises_unavailable_after_the_retries
    @api.on("POST", "/v1/things") { [503, "overloaded"] }
    no_sleep(http(retries: 2))
    error = assert_raises(Metacrunch::Ai::Unavailable) { @http.post_json("/things", {}) }

    assert_equal "things at #{@api.url("/v1/things")}: still 503 after 2 retries: overloaded", error.message
    assert_equal [503, "overloaded", 3], [error.status, error.body, @api.requests.size]
  end

  def test_retries_timeouts
    @api.on("POST", "/v1/things") do
      sleep(0.5)
      [200, {}]
    end
    no_sleep(http(timeout: 0.1, retries: 1))
    error = assert_raises(Metacrunch::Ai::Unavailable) { @http.post_json("/things", {}) }

    assert_equal "things at #{@api.url("/v1/things")}: still Net::ReadTimeout after 1 retries", error.message
    assert_nil error.status
  end

  def test_retries_a_refused_connection
    url = @api.url("/v1")
    @api.stop
    no_sleep(http(url:, retries: 1))
    error = assert_raises(Metacrunch::Ai::Unavailable) { @http.post_json("/things", {}) }

    assert_match(/still Errno::ECONNREFUSED after 1 retries: Failed to open TCP connection to 127\.0\.0\.1/,
                 error.message)
    @api = FakeApi.new
  end

  def test_connects_to_an_ipv6_address
    no_sleep(http(url: "http://[::1]:1/v1", retries: 0))
    error = assert_raises(Metacrunch::Ai::Unavailable) { @http.get("/things") }

    assert_match(/still Errno::ECONNREFUSED/, error.message)
  end

  def test_retries_errors_of_the_network
    @api.on("POST", "/v1/things") { [200, {"ok" => true}] }
    errors = [Errno::ETIMEDOUT, Errno::EHOSTUNREACH, Errno::ENETUNREACH, Errno::ECONNABORTED, IOError,
              OpenSSL::SSL::SSLError, Socket::ResolutionError]
    failing = errors.dup
    client = http(retries: errors.size)
    delays = no_sleep(client)
    client.define_singleton_method(:send_request) { |*args| failing.empty? ? super(*args) : raise(failing.shift) }

    assert_equal({"ok" => true}, client.post_json("/things", {}))
    assert_equal errors.size, delays.size
    assert_includes @log.string, "things: Errno::EHOSTUNREACH, retry 2/#{errors.size}"
  end

  def test_retries_a_garbled_answer
    @api.on("POST", "/v1/things") { [200, {"ok" => true}] }
    @api.on("POST", "/v1/things", times: 1) { ["xyz", ""] }
    no_sleep(http)

    assert_equal({"ok" => true}, @http.post_json("/things", {}))
    assert_includes @log.string, "things: Net::HTTPBadResponse, retry 1/5"
  end

  def test_names_the_last_error_after_the_retries
    server = TCPServer.new("127.0.0.1", 0)
    thread = Thread.new { loop { not_tls(server.accept) } }
    no_sleep(http(url: "https://127.0.0.1:#{server.addr[1]}/v1", retries: 1))
    error = assert_raises(Metacrunch::Ai::Unavailable) { @http.post_json("/things", {}) }

    assert_match(/: still OpenSSL::SSL::SSLError after 1 retries: SSL_connect returned/, error.message)
    assert_nil error.body
  ensure
    thread&.kill&.join
    server&.close
  end

  def test_invalid_input_statuses
    [400, 413, 422].each do |status|
      @api.on("POST", "/v1/things", times: 1) { [status, {"error" => "too long"}] }
      error = assert_raises(Metacrunch::Ai::InvalidInput) { http.post_json("/things", {}) }

      assert_equal [status, %({"error":"too long"})], [error.status, error.body]
    end
    assert_equal 3, @api.requests.size
  end

  def test_other_statuses_raise_api_error_without_retry
    @api.on("POST", "/v1/things") { [401, {"error" => "no key"}] }
    error = assert_raises(Metacrunch::Ai::ApiError) { http.post_json("/things", {}) }

    assert_equal [Metacrunch::Ai::ApiError, "things at #{@api.url("/v1/things")}: 401: {\"error\":\"no key\"}"],
                 [error.class, error.message]
    assert_equal 1, @api.requests.size
  end

  def test_a_refusal_without_a_body
    @api.on("POST", "/v1/things") { [404, ""] }
    error = assert_raises(Metacrunch::Ai::ApiError) { http.post_json("/things", {}) }

    assert_equal ["things at #{@api.url("/v1/things")}: 404", nil], [error.message, error.body]
  end

  def test_retries_without_a_logger
    @api.on("POST", "/v1/things") { [200, {"ok" => true}] }
    @api.on("POST", "/v1/things", times: 1) { [502, "", {"Retry-After" => "0"}] }
    @http = Metacrunch::Ai::Http.new(url: @api.url("/v1"))

    assert_equal({"ok" => true}, @http.post_json("/things", {}))
  end

  def test_malformed_json_is_an_api_error
    @api.on("POST", "/v1/things") { [200, "<html>"] }
    error = assert_raises(Metacrunch::Ai::ApiError) { http.post_json("/things", {}) }

    assert_equal "things at #{@api.url("/v1/things")}: malformed answer, not a JSON object: <html>", error.message
  end

  def test_an_answer_without_a_body_is_an_api_error
    [204, 200].each do |status|
      @api.on("POST", "/v1/things", times: 1) { [status, ""] }
      error = assert_raises(Metacrunch::Ai::ApiError, status.to_s) { http.post_json("/things", {}) }

      assert_equal ["things at #{@api.url("/v1/things")}: malformed answer, not a JSON object", status, nil],
                   [error.message, error.status, error.body]
    end
  end

  def test_an_answer_that_is_not_an_object_is_an_api_error
    @api.on("POST", "/v1/things") { [200, [1, 2]] }

    assert_raises(Metacrunch::Ai::ApiError) { http.post_json("/things", {}) }
  end

  def test_body_excerpt_is_cut_at_300_characters
    @api.on("POST", "/v1/things") { [404, "x" * 400] }
    error = assert_raises(Metacrunch::Ai::ApiError) { http.post_json("/things", {}) }

    assert_equal "#{"x" * 300}...", error.body
  end

  def test_validates_options
    [{url: "ftp://host"}, {url: "not a url"}, {headers: []}, {timeout: 0}, {retries: -1}].each do |options|
      assert_raises(ArgumentError, options.inspect) { Metacrunch::Ai::Http.new(url: @api.url, **options) }
    end
  end

  def test_inspect_hides_the_headers
    http = Metacrunch::Ai::Http.new(url: "https://user:pw@api.example.org/v1", name: "embeddings",
                                    headers: {"Authorization" => "Bearer s3"})

    assert_equal %(#<Metacrunch::Ai::Http embeddings url="https://api.example.org:443/v1">), http.inspect
  end

  def test_close_without_a_connection_and_twice
    http = Metacrunch::Ai::Http.new(url: @api.url)
    http.close
    http.close
  end

  private

  def http(url: @api.url("/v1"), **)
    @http&.close
    @http = Metacrunch::Ai::Http.new(url:, name: "things", **).open(Logger.new(@log))
  end

  # Reads the client's TLS hello and answers in plain text, as a server
  # without TLS would.
  def not_tls(client)
    client.readpartial(16_384)
    client.write("HTTP/1.1 400 Bad Request\r\n\r\n")
  ensure
    client.close
  end

  def no_sleep(http, rand: 1.0)
    [].tap do |delays|
      http.define_singleton_method(:sleep) { |seconds| delays << seconds.round(1) }
      http.define_singleton_method(:rand) { rand }
    end
  end

end
