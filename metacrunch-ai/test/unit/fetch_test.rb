# frozen_string_literal: true

require "test_helper"
require "digest"
require "metacrunch/testing"

class FetchTest < Minitest::Test

  Fetch = Metacrunch::Ai::Fetch

  def setup
    @site = FakeApi.new
  end

  def teardown
    @site.stop
  end

  def test_adds_the_fields_of_a_file_record
    headers = {"Content-Type" => "text/html; charset=utf-8", "Last-Modified" => "Wed, 21 Oct 2026 07:28:00 GMT",
               "ETag" => '"v1"'}
    @site.on("GET", "/loans") { [200, "<p>Loans</p>", headers] }
    record = fetched({"id" => 7, "url" => @site.url("/loans")})

    assert_equal [7, @site.url("/loans"), "<p>Loans</p>", "text/html", 12, Digest::SHA256.hexdigest("<p>Loans</p>")],
                 record.values_at("id", "url", "content", "type", "size", "sha256")
    assert_equal ["2026-10-21T07:28:00Z", '"v1"', @site.url("/loans")], record.values_at("modified", "etag", "location")
    assert_match(/\A\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ\z/, record["fetched"])
  end

  def test_location_after_redirects_and_url_kept
    @site.on("GET", "/old") { [301, "", {"Location" => "/new"}] }
    @site.on("GET", "/new") { [200, "x", {"Content-Type" => "text/plain"}] }
    record = fetched({"url" => @site.url("/old")})

    assert_equal [@site.url("/old"), @site.url("/new")], record.values_at("url", "location")
  end

  def test_charset_sets_the_encoding
    @site.on("GET", "/latin") { [200, "\xD6ffnungszeiten".b, {"Content-Type" => "text/html; charset=ISO-8859-1"}] }
    @site.on("GET", "/odd") { [200, "x", {"Content-Type" => "text/plain; charset=nonsense"}] }
    @site.on("GET", "/pdf") { [200, "%PDF".b, {"Content-Type" => "application/pdf; charset=utf-8"}] }
    @site.on("GET", "/l1") { [200, "Caf\xE9".b, {"Content-Type" => "text/html; charset=Latin1"}] }
    @site.on("GET", "/utf8") { [200, "Café", {"Content-Type" => "text/plain; charset=utf8"}] }
    contents = ["/latin", "/odd", "/pdf", "/l1", "/utf8"].map { fetched({"url" => @site.url(it)})["content"] }

    assert_equal [Encoding::ISO_8859_1, Encoding::BINARY, Encoding::BINARY, Encoding::ISO_8859_1, Encoding::UTF_8],
                 contents.map(&:encoding)
    assert_equal(["Café", "Café"], contents.last(2).map { it.encode(Encoding::UTF_8) })
    Fetch::CHARSETS.each_value { assert_kind_of Encoding, Encoding.find(it) }
  end

  def test_no_content_type_is_octet_stream_and_missing_headers_are_left_out
    @site.on("GET", "/blob") { [200, "x", {"Content-Type" => "", "Last-Modified" => "yesterday"}] }
    record = fetched({"url" => @site.url("/blob")})

    assert_equal ["application/octet-stream", false, false], [record["type"], record.key?("etag"),
                                                              record.key?("modified")]
  end

  def test_marks
    @site.on("GET", "/robots.txt") { [200, "User-agent: *\nDisallow: /private/\n"] }
    [[404, "/missing"], [410, "/gone"], [403, "/secret"], [400, "/bad"]].each do |status, path|
      @site.on("GET", path) { [status, ""] }
    end
    @site.on("GET", "/away") { [301, "", {"Location" => "ftp://www.example.org/a"}] }
    urls = [nil, "  ", "mailto:desk@example.org", "https://bücher.example/a", "/private/x", "/missing", "/gone",
            "/secret", "/bad", "/away"].map { it&.start_with?("/") ? @site.url(it) : it }
    result = run_fetch([{}] + urls.map { {"url" => it} })

    assert_equal({"No URL to fetch" => 3, "Not an http(s) URL" => 1, "Host name not supported" => 1,
                  "Disallowed by robots.txt" => 1, "Not found (404)" => 1, "Not found (410)" => 1,
                  "Refused (403)" => 1, "Refused (400)" => 1, "Redirected to no http(s) URL" => 1},
                 result.stats.marked)
    assert_equal(11, result.records.count { !it.key?("content") })
  end

  def test_failures
    @site.on("GET", "/busy") { [503, ""] }
    @site.on("GET", "/loop") { [302, "", {"Location" => "/loop"}] }
    @site.on("GET", "/big") { [200, "x" * 20] }
    @site.on("GET", "/odd") { [501, ""] }
    result = run_fetch(["/busy", "/loop", "/big", "/odd"].map { {"url" => @site.url(it)} }, max_size: 10, retries: 0)

    assert_equal([Metacrunch::Ai::Unavailable, Metacrunch::Ai::ApiError, Metacrunch::Ai::InvalidInput,
                  Metacrunch::Ai::ApiError], result.failures.map { it.last.error.class })
  end

  def test_another_field
    @site.on("GET", "/a") { [200, "x"] }

    assert_equal "x", fetched({"link" => @site.url("/a")}, from: "link")["content"]
  end

  def test_needs_hash_records
    error = run_fetch(["https://www.example.org/"]).failures.first.last.error

    assert_equal [Metacrunch::ContractError, "Fetch needs Hash records, got String"], [error.class, error.message]
  end

  def test_validates_options
    [{from: ""}, {from: :url}, {delay: -1}, {user_agent: ""}, {max_size: 0}, {robots: "yes"}].each do |options|
      assert_raises(ArgumentError, options.inspect) { Fetch.new(**options) }
    end
  end

  def test_with_extract_in_a_job
    @site.on("GET", "/hours") { [200, "<main><h1>Opening hours</h1></main>", {"Content-Type" => "text/html"}] }
    fetch = Fetch.new(delay: 0)
    extract = Metacrunch::Ai::Extract.new(Metacrunch::Ai::Html.new)
    job = Metacrunch.job do
      map fetch
      map extract
    end
    records = Metacrunch::Testing.run(job, source: [{"url" => @site.url("/hours")}]).records

    assert_equal([["# Opening hours", "Opening hours"]], records.map { it.values_at("text", "title") })
  end

  private

  def run_fetch(records, **)
    fetch = Fetch.new(delay: 0, **)
    job = Metacrunch.job do
      map fetch
      on_failure :skip
    end
    Metacrunch::Testing.run(job, source: records)
  end

  def fetched(record, **)
    result = run_fetch([record], **)
    raise result.failures.first.last.error if result.failures.any?

    result.records.first
  end

end
