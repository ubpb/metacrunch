# frozen_string_literal: true

require "test_helper"
require "zlib"
require "metacrunch/testing"

class SitemapReaderTest < Minitest::Test

  Reader = Metacrunch::Ai::Sitemap::Reader
  NS = %(xmlns="http://www.sitemaps.org/schemas/sitemap/0.9")

  def setup
    @site = FakeApi.new
  end

  def teardown
    @site.stop
  end

  def test_reads_a_urlset
    serve("/sitemap.xml", urlset(["https://www.example.org/a", "2026-10-30"], ["https://www.example.org/b", nil]))

    a = "https://www.example.org/a"
    b = "https://www.example.org/b"

    assert_equal [{"id" => a, "url" => a, "lastmod" => "2026-10-30"}, {"id" => b, "url" => b}],
                 read(@site.url("/sitemap.xml"))
  end

  def test_without_namespace_with_comments_and_whitespace
    xml = <<~XML
      <urlset>
        <!-- pages -->
        <url>
          <loc>https://www.example.org/a</loc>
          <changefreq>weekly</changefreq>
        </url>
      </urlset>
    XML
    serve("/plain.xml", xml)

    assert_equal ["https://www.example.org/a"], urls(@site.url("/plain.xml"))
  end

  def test_reads_an_index_and_gzip
    serve("/index.xml", index("/pages.xml", "/docs.xml.gz"))
    serve("/pages.xml", urlset(["https://www.example.org/a", nil]))
    serve("/docs.xml.gz", Zlib.gzip(urlset(["https://www.example.org/rules.pdf", nil])), "application/octet-stream")

    assert_equal ["https://www.example.org/a", "https://www.example.org/rules.pdf"], urls(@site.url("/index.xml"))
  end

  def test_nested_index_limit
    serve("/1.xml", index("/2.xml"))
    serve("/2.xml", index("/3.xml"))
    serve("/3.xml", index("/4.xml"))
    serve("/4.xml", urlset(["https://www.example.org/deep", nil]))
    records = read(@site.url("/1.xml"))

    assert_equal [Metacrunch::InvalidRecord], records.map(&:class)
    assert_equal @site.url("/4.xml"), records.first.raw
  end

  def test_locs_are_trimmed_and_unescaped
    serve("/s.xml", "<urlset #{NS}><url><loc>\n  https://www.example.org/a?x=1&amp;y=2  \n</loc></url></urlset>")

    assert_equal ["https://www.example.org/a?x=1&y=2"], urls(@site.url("/s.xml"))
  end

  def test_matching_and_since
    serve("/s.xml", urlset(["https://www.example.org/handbook/new", "2026-10-15"],
                           ["https://www.example.org/handbook/old", "2026-09-30T23:00:00-02:00"],
                           ["https://www.example.org/handbook/zoned", "2026-09-30T23:30:00-01:00"],
                           ["https://www.example.org/handbook/undated", nil],
                           ["https://www.example.org/news/new", "2026-10-20"]))
    found = urls(@site.url("/s.xml"), matching: %r{/handbook/}, since: "2026-10-01")

    assert_equal ["https://www.example.org/handbook/new", "https://www.example.org/handbook/old",
                  "https://www.example.org/handbook/zoned", "https://www.example.org/handbook/undated"], found
    assert_equal ["https://www.example.org/handbook/new", "https://www.example.org/handbook/undated"],
                 urls(@site.url("/s.xml"), matching: %r{/handbook/}, since: Time.utc(2026, 10, 1, 2))
  end

  def test_since_takes_a_date
    serve("/s.xml",
          urlset(["https://www.example.org/new", "2026-10-15"], ["https://www.example.org/old", "2026-09-01"]))

    assert_equal ["https://www.example.org/new"], urls(@site.url("/s.xml"), since: Date.new(2026, 10, 1))
  end

  def test_duplicates_once
    serve("/s.xml", urlset(["https://www.example.org/a", nil], ["https://www.example.org/a", "2026-10-01"]))

    assert_equal ["https://www.example.org/a"], urls(@site.url("/s.xml"))
  end

  def test_local_files
    Dir.mktmpdir do |dir|
      File.binwrite(File.join(dir, "s.xml.gz"), Zlib.gzip(urlset(["https://www.example.org/a", nil])))

      assert_equal ["https://www.example.org/a"], urls(File.join(dir, "s.xml.gz"))
    end
  end

  def test_site_reads_sitemap_lines
    serve("/robots.txt", "Sitemap: #{@site.url("/a.xml")}\nSitemap: #{@site.url("/missing.xml")}\n", "text/plain")
    serve("/a.xml", urlset(["https://www.example.org/a", nil]))
    records = Reader.site(@site.url, delay: 0).each.to_a

    assert_equal [Hash, Metacrunch::InvalidRecord], records.map(&:class)
    assert_equal @site.url("/missing.xml"), records.last.raw
  end

  def test_site_falls_back_to_sitemap_xml
    serve("/sitemap.xml", urlset(["https://www.example.org/a", nil]))

    assert_equal(["https://www.example.org/a"], Reader.site(@site.url, delay: 0).each.map { it["url"] })
    serve("/robots.txt", "Sitemap: #{@site.url("/gone.xml")}\n", "text/plain")

    assert_equal(["https://www.example.org/a"],
                 Reader.site(@site.url, delay: 0).each.grep_v(Metacrunch::InvalidRecord).map { it["url"] })
  end

  def test_site_with_an_unreachable_robots_txt_tries_sitemap_xml
    @site.on("GET", "/robots.txt") { [503, ""] }
    serve("/sitemap.xml", urlset(["https://www.example.org/a", nil]))

    assert_equal(["https://www.example.org/a"], Reader.site(@site.url, delay: 0, retries: 0).each.map { it["url"] })
  end

  def test_raises_when_no_sitemap_can_be_read
    serve("/text.xml", "not xml at all", "text/plain")
    serve("/page.xml", "<html><body/></html>")
    targets = ["/none.xml", "/text.xml", "/page.xml"].map { @site.url(it) }
    error = assert_raises(Metacrunch::InputError) { read(targets) }

    targets.each { assert_includes error.message, it }

    assert_includes error.message, "no sitemap: <html>"
  end

  def test_failures_before_the_first_success_come_after_it
    serve("/a.xml", urlset(["https://www.example.org/a", nil]))
    records = read([@site.url("/none.xml"), @site.url("/a.xml")])

    assert_equal [Hash, Metacrunch::InvalidRecord], records.map(&:class)
  end

  def test_in_a_job_with_fetch
    serve("/s.xml", urlset([@site.url("/page"), nil]))
    serve("/page", "<p>Loans</p>", "text/html")
    reader = Reader.new(@site.url("/s.xml"), delay: 0)
    fetch = Metacrunch::Ai::Fetch.new(delay: 0)
    job = Metacrunch.job do
      source reader, id: ->(page) { page["id"] }
      map fetch
    end

    assert_equal(["<p>Loans</p>"], Metacrunch::Testing.run(job).records.map { it["content"] })
  end

  def test_validates_options
    [[[], {}], [42, {}], ["x", {matching: "/a/"}], ["x", {since: "soon"}], ["x", {since: 1}]].each do |targets, options|
      assert_raises(ArgumentError, [targets, options].inspect) { Reader.new(targets, **options) }
    end
  end

  private

  def serve(path, body, type = "application/xml") = @site.on("GET", path) { [200, body, {"Content-Type" => type}] }

  def read(targets, **) = Reader.new(targets, delay: 0, **).each.to_a

  def urls(targets, **) = read(targets, **).map { it["url"] }

  def urlset(*entries)
    urls = entries.map { |loc, lastmod| "<url><loc>#{loc}</loc>#{"<lastmod>#{lastmod}</lastmod>" if lastmod}</url>" }
    %(<?xml version="1.0" encoding="UTF-8"?>\n<urlset #{NS}>#{urls.join}</urlset>)
  end

  def index(*paths)
    sitemaps = paths.map { "<sitemap><loc>#{@site.url(it)}</loc></sitemap>" }
    %(<?xml version="1.0" encoding="UTF-8"?>\n<sitemapindex #{NS}>#{sitemaps.join}</sitemapindex>)
  end

end
