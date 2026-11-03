# frozen_string_literal: true

require "test_helper"

# The web client with two fake servers as two hosts (127.0.0.1 and localhost) and a clock that only sleeping moves.
class WebTest < Minitest::Test

  Web = Metacrunch::Ai::Web

  def setup
    @a = FakeApi.new
    @b = FakeApi.new
    @now = 0.0
    @slept = []
    [@a, @b].each { it.on("GET", %r{\A/\d\z}) { [200, "page"] } }
  end

  def teardown
    @web&.close
    @a.stop
    @b.stop
  end

  def test_gets_a_page
    @a.on("GET", "/page") { [200, "<p>x</p>", {"Content-Type" => "text/html", "ETag" => '"v1"'}] }
    page = client.get(@a.url("/page"))

    assert_equal [200, @a.url("/page"), "<p>x</p>", '"v1"'], [page.status, page.url, page.body, page.headers["etag"]]
    assert_equal Web::USER_AGENT, @a.requests.last.headers["user-agent"]
    assert_match(%r{\Ametacrunch/\S+ \(\+https://github.com/ubpb/metacrunch\)\z}, Web::USER_AGENT)
  end

  def test_waits_the_delay_per_host
    web = client(delay: 1, robots: false)
    [@a.url("/1"), other(@b.url("/1")), @a.url("/2")].each { web.get(it) }

    assert_equal([1.0], @slept.map { it.round(1) })
  end

  def test_robots_txt_is_read_once_and_counts_as_a_request
    @a.on("GET", "/robots.txt") { [200, "User-agent: *\nDisallow: /private/\n"] }
    web = client(delay: 1)
    web.get(@a.url("/1"))
    web.get(@a.url("/2"))

    assert_equal(["/robots.txt", "/1", "/2"], @a.requests.map(&:path))
    assert_equal([1.0, 1.0], @slept.map { it.round(1) })
  end

  def test_disallowed_urls_raise
    @a.on("GET", "/robots.txt") { [200, "User-agent: metacrunch\nDisallow: /private/\n"] }

    assert_raises(Web::Disallowed) { client.get(@a.url("/private/x")) }
    refute(@a.requests.any? { it.path == "/private/x" })
  end

  def test_a_missing_robots_txt_allows_all
    assert_equal 200, client.get(@a.url("/1")).status
  end

  def test_an_unreachable_robots_txt_fails_and_is_not_cached
    @a.on("GET", "/robots.txt", times: 1) { [503, ""] }
    web = client(retries: 0)
    error = assert_raises(Metacrunch::Ai::Unavailable) { web.get(@a.url("/1")) }

    assert_match(/\Arobots.txt of 127.0.0.1:\d+ unreachable/, error.message)
    assert_equal 200, web.get(@a.url("/1")).status
  end

  def test_robots_txt_follows_redirects
    @a.on("GET", "/robots.txt") { [301, "", {"Location" => "/robots-real.txt"}] }
    @a.on("GET", "/robots-real.txt") { [200, "User-agent: *\nDisallow: /x\n"] }

    assert_raises(Web::Disallowed) { client.get(@a.url("/x")) }
  end

  def test_odd_robots_txt_answers_allow_all
    answers = {"/robots.txt" => [302, "", {"Location" => "/robots.txt"}]}
    [answers, {"/robots.txt" => [200, "x" * ((500 * 1024) + 1)]},
     {"/robots.txt" => [301, "", {"Location" => "mailto:webmaster@example.org"}]}].each do |routes|
      api = FakeApi.new
      routes.each { |path, answer| api.on("GET", path) { answer } }
      api.on("GET", "/1") { [200, "page"] }

      assert_equal 200, client.get(api.url("/1")).status, routes.inspect
    ensure
      @web.close
      api.stop
    end
  end

  def test_a_robots_txt_with_another_server_error_is_unreachable
    @a.on("GET", "/robots.txt") { [501, ""] }

    assert_raises(Metacrunch::Ai::Unavailable) { client.get(@a.url("/1")) }
  end

  def test_crawl_delay_raises_the_wait
    @a.on("GET", "/robots.txt") { [200, "User-agent: *\nCrawl-delay: 3\n"] }
    web = client(delay: 1)
    web.get(@a.url("/1"))

    assert_equal([3.0], @slept.map { it.round(1) })
  end

  def test_follows_redirects
    @a.on("GET", "/old") { [301, "", {"Location" => "/1"}] }
    @a.on("GET", "/away") { [302, "", {"Location" => other(@b.url("/2"))}] }
    @a.on("GET", "/scheme") { [307, "", {"Location" => other(@b.url("/3")).sub("http:", "")}] }
    web = client
    urls = ["/old", "/away", "/scheme"].map { web.get(@a.url(it)).url }

    assert_equal [@a.url("/1"), other(@b.url("/2")), other(@b.url("/3"))], urls
  end

  def test_each_hop_is_checked
    @b.on("GET", "/robots.txt") { [200, "User-agent: *\nDisallow: /x\n"] }
    @a.on("GET", "/old") { [301, "", {"Location" => other(@b.url("/x"))}] }

    assert_raises(Web::Disallowed) { client.get(@a.url("/old")) }
  end

  def test_loops_end
    @a.on("GET", "/loop") { [302, "", {"Location" => "/loop"}] }
    error = assert_raises(Metacrunch::Ai::ApiError) { client(redirects: 5).get(@a.url("/loop")) }

    assert_match(/more than 5 redirects/, error.message)
    assert_equal(6, @a.requests.count { it.path == "/loop" })
  end

  def test_max_size
    @a.on("GET", "/big") { [200, "x" * 20] }

    assert_raises(Metacrunch::Ai::InvalidInput) { client(max_size: 10).get(@a.url("/big")) }
    assert_equal 20, @web.get(@a.url("/big"), max_size: 30).body.bytesize
  end

  def test_robots_off_reads_no_robots_txt
    client(robots: false).get(@a.url("/1"))

    assert_equal(["/1"], @a.requests.map(&:path))
  end

  def test_robots_of_an_origin
    @a.on("GET", "/robots.txt") { [200, "Sitemap: https://www.example.org/sitemap.xml\n"] }

    assert_equal ["https://www.example.org/sitemap.xml"], client.robots(@a.url).sitemaps
  end

  def test_normalizes_urls_like_browsers
    assert_equal "https://www.example.org/B%C3%BCcher%20neu.pdf?q=a%7Cb&p=100%25",
                 Web.normalize(" https://www.example.org/Bücher neu.pdf?q=a|b&p=100%#teil ")
    assert_equal(["http://www.example.org/", "https://www.example.org/?q=1", "https://www.example.org/a%20b"],
                 ["HTTP://www.example.org", "https://www.example.org?q=1",
                  "https://www.example.org/a%20b"].map { Web.normalize(it) })
  end

  def test_refuses_other_urls
    ["mailto:desk@example.org", "ftp://www.example.org/a", "www.example.org/a", "https://", nil,
     "https://exa mple.org/a"].each do |url|
      assert_raises(Web::NotHttp, url.inspect) { Web.normalize(url) }
    end
    assert_raises(Web::Idn) { Web.normalize("https://bücher.example/") }
  end

  def test_validates_options
    [{delay: -1}, {delay: "1"}, {redirects: -1}, {redirects: 1.5}, {max_size: 0}, {user_agent: ""}, {robots: nil},
     {timeout: 0}, {retries: -1}].each do |options|
      assert_raises(ArgumentError, options.inspect) { Web.new(**options) }
    end
  end

  private

  def client(**)
    sleeper = lambda do |seconds|
      @slept << seconds
      @now += seconds
    end
    @web = Web.new(delay: 0, clock: -> { @now }, sleeper:, **).open
  end

  # The same server under the name localhost: another host for the delay and robots.txt.
  def other(url) = url.sub("127.0.0.1", "localhost")

end
