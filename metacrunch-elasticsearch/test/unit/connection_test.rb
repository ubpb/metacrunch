# frozen_string_literal: true

require "test_helper"

class ConnectionTest < Minitest::Test

  Connection = Metacrunch::Elasticsearch::Connection
  Error = Metacrunch::Elasticsearch::Error
  Errors = Elastic::Transport::Transport::Errors
  URL = FakeElasticsearch::URL

  def test_connect_checks_the_server_with_plain_json_and_returns_a_client
    fake = FakeElasticsearch.new
    client = fake.connection.connect

    assert_kind_of ::Elasticsearch::Client, client
    assert_equal([["GET", "/", "application/json"]], fake.requests.map { [it.verb, it.path, it.headers["accept"]] })
  end

  def test_the_client_does_not_check_the_product_again
    fake = FakeElasticsearch.new.on("HEAD", "/books") { [404, nil] }

    assert_silent { refute fake.connection.connect.indices.exists(index: "books") }
  end

  def test_the_client_authenticates_with_an_api_key_or_user_and_password
    fake = FakeElasticsearch.new
    fake.connection(api_key: "aWQ6a2V5").connect
    fake.connection(user: "elastic", password: "secret").connect

    assert_equal(["ApiKey aWQ6a2V5", "Basic #{["elastic:secret"].pack("m0")}"],
                 fake.requests.map { it.headers["authorization"] })
  end

  def test_ca_file_timeout_and_retries_reach_the_client
    options = Connection.new(ca_file: Pathname("/etc/ca.crt"), request_timeout: 5, retries: 2).client.transport.options

    assert_equal ["/etc/ca.crt", 5], [options.dig(:transport_options, :ssl, :ca_file),
                                      options.dig(:transport_options, :request, :timeout)]
    assert_equal 2, options[:retry_on_failure]
  end

  def test_client_options_win_and_stay_unchanged
    headers = {"x-test" => "1"}
    fake = FakeElasticsearch.new
    fake.connection(transport_options: {headers:}, retry_on_status: [503]).connect

    assert_equal "1", fake.requests.first.headers["x-test"]
    assert_equal({"x-test" => "1"}, headers)
  end

  def test_transport_options_add_to_authentication_timeout_and_ca_file
    fake = FakeElasticsearch.new
    connection = fake.connection(user: "elastic", password: "secret", ca_file: "/etc/ca.crt", request_timeout: 30,
                                 transport_options: {request: {open_timeout: 5}, ssl: {verify: false}})
    options = connection.client.transport.options[:transport_options]
    connection.connect

    assert_equal "Basic #{["elastic:secret"].pack("m0")}", fake.requests.first.headers["authorization"]
    assert_equal [{ca_file: "/etc/ca.crt", verify: false}, {timeout: 30, open_timeout: 5}],
                 [options[:ssl], options[:request]]
  end

  def test_a_client_option_wins_over_the_value_of_the_connection
    options = Connection.new(retries: 2, retry_on_failure: 7).client.transport.options

    assert_equal 7, options[:retry_on_failure]
  end

  def test_refuses_a_server_of_an_older_major_than_the_client
    error = assert_raises(Error) { Connection.check_version("8.19.3", "9.5.0", URL) }

    assert_equal "the elasticsearch gem 9.5.0 cannot talk to Elasticsearch 8.19.3 at #{URL}; " \
                 "use gem 8.x until the server runs 9", error.message
  end

  def test_accepts_the_same_major_and_a_server_one_major_ahead
    [["8.19.3", "8.19.3"], ["9.5.0", "8.19.3"], ["9.5.0", "9.5.0"]].each do |server, client|
      assert_nil Connection.check_version(server, client, URL)
    end
  end

  def test_connect_refuses_servers_of_unsupported_versions
    error = assert_raises(Error) { FakeElasticsearch.new(version: "7.17.0").connection.connect }

    assert_equal "Elasticsearch 7.17.0 at #{URL} is not supported; metacrunch-elasticsearch needs 8 or 9", error.message
  end

  def test_connect_refuses_other_products
    error = assert_raises(Error) { FakeElasticsearch.new(product: nil).connection.connect }

    assert_equal "#{URL} is not Elasticsearch (OpenSearch is not supported)", error.message
  end

  def test_connect_explains_failed_authentication
    fake = FakeElasticsearch.new.on("GET", "/") { [401, {"error" => {"type" => "security_exception"}}] }
    error = assert_raises(Error) { fake.connection.connect }

    assert_equal "authentication failed at #{URL}; #{Connection::AUTH_HINT}", error.message
  end

  def test_connect_names_the_url_when_the_request_fails
    fake = FakeElasticsearch.new.on("GET", "/") { raise Faraday::ConnectionFailed, "Connection refused" }
    error = assert_raises(Error) { fake.connection(retries: 0).connect }

    assert_equal "request to #{URL} failed: Connection refused", error.message
  end

  def test_failed_connections_are_retried
    fake = FakeElasticsearch.new.on("GET", "/", times: 2) { raise Faraday::ConnectionFailed, "Connection refused" }
    fake.connection(retries: 2).connect

    assert_equal 3, fake.requests.size
  end

  def test_the_next_url_takes_over_when_a_host_is_down
    fake = FakeElasticsearch.new
    fake.on("GET", "/") do |request|
      raise Faraday::ConnectionFailed, "Connection refused" if request.host == "a.test"

      [200, {"version" => {"number" => ::Elasticsearch::VERSION}}]
    end
    Connection.new(url: "http://a.test:9200,http://b.test:9200", retries: 1, adapter: fake.adapter).connect

    assert_equal ["a.test", "b.test"], fake.requests.map(&:host)
  end

  def test_describes_server_errors_with_elasticsearch_s_reason
    connection = Connection.new(url: URL)
    missing = Errors::NotFound.new("[404] #{JSON.generate(error: {type: "index_not_found_exception",
                                                                  reason: "no such index [books]"})}")
    forbidden = Errors::Forbidden.new('[403] {"error":{"type":"security_exception","reason":"action denied"}}')

    assert_equal "404 index_not_found_exception: no such index [books]", connection.describe(missing)
    assert_equal "403 security_exception: action denied; #{Connection::AUTH_HINT}", connection.describe(forbidden)
  end

  def test_validates_its_options
    {
      {url: "ftp://es.test"} => 'url must be an http or https URL, got "ftp://es.test"',
      {url: "http://u:p@"} => 'url must be an http or https URL, got "http://[FILTERED]@"',
      {url: "http://elastic:pa/ss@es.test:9200"} => 'url must be an http or https URL, got "http://[FILTERED]@es.test:9200"',
      {url: "http://elastic:p@ss@es.test:9200"} => 'url must be an http or https URL, got "http://[FILTERED]@es.test:9200"',
      {url: 9200} => "url must be a String or an Array, got Integer",
      {url: [9200]} => 'url must be an http or https URL, got "9200"',
      {url: "http://es test:9200"} => 'url must be an http or https URL, got "http://es test:9200"',
      {url: ""} => "url must name at least one URL",
      {api_key: ""} => "api_key must be a non-empty String",
      {user: "elastic"} => "user and password go together",
      {api_key: "k", user: "u", password: "p"} => "use api_key or user and password, not both",
      {ca_file: 1} => "ca_file must be a path, got Integer",
      {request_timeout: 0} => "request_timeout must be a positive number of seconds, got 0",
      {retries: -1} => "retries must be an Integer of 0 or more, got -1"
    }.each do |options, message|
      assert_equal message, assert_raises(ArgumentError) { Connection.new(**options) }.message
    end
  end

  def test_user_info_in_the_url_is_basic_authentication_for_every_url
    connection = Connection.new(url: "https://elastic:secret@es.test:9200, https://es2.test:9200")

    assert_equal "https://es.test:9200", connection.url
    assert_equal "#<Metacrunch::Elasticsearch::Connection url=https://es.test:9200,https://es2.test:9200 " \
                 "user=elastic password=[FILTERED]>", connection.inspect
  end

  def test_user_info_goes_into_a_header_not_into_the_url
    fake = FakeElasticsearch.new
    Connection.new(url: "http://elastic:se%2Fcret@es.test:9200", adapter: fake.adapter).connect
    request = fake.requests.first
    basic = "Basic #{["elastic:se/cret"].pack("m0")}"

    assert_equal [basic, "es.test"], [request.headers["authorization"], request.host]
  end

  def test_user_info_must_be_given_once
    both = "give user and password in url or as options, not both"

    {
      {url: "http://a:1@es.test:9200,http://b:2@es2.test:9200"} => "the URLs name different users",
      {url: "http://a:1@es.test:9200", user: "b", password: "2"} => both,
      {url: "http://a:1@es.test:9200", api_key: "k3y"} => "use api_key or user and password, not both"
    }.each do |options, message|
      assert_equal message, assert_raises(ArgumentError) { Connection.new(**options) }.message
    end
  end

  def test_inspect_shows_the_user_but_not_the_password
    assert_equal "#<Metacrunch::Elasticsearch::Connection url=#{URL} user=elastic password=[FILTERED]>",
                 Connection.new(url: URL, user: "elastic", password: "secret").to_s
  end

  def test_without_url_the_client_s_default_is_named
    with_env("ELASTICSEARCH_URL" => nil) { assert_equal "http://localhost:9200", Connection.new.url }
    with_env("ELASTICSEARCH_URL" => "http://a.test:9200,http://b.test:9200") do
      assert_equal "http://a.test:9200", Connection.new.url
    end
  end

  def test_connection_params_bind_from_the_environment_and_build_a_connection
    schema = Metacrunch::Params.new
    schema.instance_exec(&Metacrunch::Elasticsearch::CONNECTION_PARAMS)
    params = schema.bind_values({}, env: {"ELASTICSEARCH_URL" => URL, "ELASTICSEARCH_API_KEY" => "k3y"})

    assert_equal "#<Metacrunch::Elasticsearch::Connection url=#{URL} api_key=[FILTERED]>",
                 Connection.from_params(params).inspect
  end

  def test_from_params_takes_the_connection_params_a_recipe_declares
    params = Data.define(:url, :index).new(url: URL, index: "books")

    assert_equal URL, Connection.from_params(params).url
  end

  private

  def with_env(values)
    saved = values.keys.to_h { [it, ENV.fetch(it, nil)] }
    values.each { |key, value| ENV[key] = value }
    yield
  ensure
    saved.each { |key, value| ENV[key] = value }
  end

end
