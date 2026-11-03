# frozen_string_literal: true

require "test_helper"
require "metacrunch/testing"

# Fetch and Sitemap::Reader against nginx serving test/fixtures/web/site.
class WebServerTest < Minitest::Test

  include WebServer

  def test_site_reads_the_sitemaps
    urls = Metacrunch::Ai::Sitemap::Reader.site(web_url, delay: 0).each.map { it["url"] }

    assert_equal ["/handbook/loans.html", "/latin1/hours.html", "/private/notes.html", "/old-loans",
                  "/docs/rules.pdf", "/missing.html"].map { web_url(it) }, urls
  end

  def test_fetch_fields
    record = fetch(web_url("/handbook/loans.html"))

    assert_equal ["text/html", web_url("/handbook/loans.html")], record.values_at("type", "location")
    assert_match(/\A\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ\z/, record["modified"])
    assert_match(/\A"[0-9a-f-]+"\z/, record["etag"])
  end

  def test_a_charset_header_gives_the_encoding
    record = fetch(web_url("/latin1/hours.html"))
    text = Metacrunch::Ai::Html.new.extract(record["content"])[:text]

    assert_equal Encoding::ISO_8859_1, record["content"].encoding
    assert_includes text, "Café"
  end

  def test_robots_disallows_private
    assert_equal({"Disallowed by robots.txt" => 1}, run_fetch(web_url("/private/notes.html")).stats.marked)
  end

  def test_redirect_gives_location
    assert_equal web_url("/handbook/loans.html"), fetch(web_url("/old-loans"))["location"]
  end

  def test_a_missing_page_is_marked
    assert_equal({"Not found (404)" => 1}, run_fetch(web_url("/missing.html")).stats.marked)
  end

  private

  def run_fetch(url)
    fetch = Metacrunch::Ai::Fetch.new(delay: 0)
    job = Metacrunch.job { map fetch }
    Metacrunch::Testing.run(job, source: [{"url" => url}])
  end

  def fetch(url) = run_fetch(url).records.first

end
