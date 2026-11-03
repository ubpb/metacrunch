# frozen_string_literal: true

require "test_helper"

# robots.txt as RFC 9309 has it, for the user agent token metacrunch.
class RobotsTest < Minitest::Test

  Robots = Metacrunch::Ai::Robots

  OWN_AND_ALL = "User-agent: *\nDisallow: /\n\nUser-agent: metacrunch\nDisallow: /private/\n"
  LONGEST = "User-agent: *\nDisallow: /a\nAllow: /a/b\n"

  # [robots.txt, path, allowed?]
  CASES = [
    [OWN_AND_ALL, "/public/page", true],
    [OWN_AND_ALL, "/private/page", false],
    ["User-agent: MetaCrunch\nDisallow: /x\n", "/x", false],
    ["User-agent: metacrunch-bot\nDisallow: /x\n", "/x", true],
    ["User-agent: metacrunch/1.0\nDisallow: /x\n", "/x", false],
    ["User-agent: metacrunch\nDisallow: /a\n\nUser-agent: metacrunch\nDisallow: /b\n", "/b", false],
    ["User-agent: other\nUser-agent: metacrunch\nDisallow: /shared\n", "/shared/x", false],
    ["Disallow: /before\nUser-agent: *\nAllow: /\n", "/before", true],
    [LONGEST, "/a/b/c", true],
    [LONGEST, "/a/c", false],
    ["User-agent: *\nDisallow: /same\nAllow: /same\n", "/same", true],
    ["User-agent: *\nDisallow: /*.pdf$\n", "/docs/x.pdf", false],
    ["User-agent: *\nDisallow: /*.pdf$\n", "/docs/x.pdf?page=2", true],
    ["User-agent: *\nDisallow: /*?\n", "/search?q=x", false],
    ["User-agent: *\nDisallow: /*?\n", "/search", true],
    ["User-agent: *\nDisallow: /a$b\n", "/a$b", false],
    ["User-agent: *\nDisallow:\n", "/anything", true],
    ["User-agent: other\nDisallow: /\n", "/anything", true],
    ["User-agent: *\nDisallow: /\n", "/anything", false],
    ["User-agent: *\nDisallow: /\n", "/robots.txt", true],
    ["User-agent: *\nDisallow: /%c3%a4\n", "/%C3%A4/x", false],
    ["User-agent: *\nDisallow: /Bücher/\n", "/B%C3%BCcher/x", false],
    ["User-agent: *\nDisallow: /a b\n", "/a%20b", false],
    ["﻿User-agent: *\r\nDisallow: /x # comment\r\n# Disallow: /y\r\nnonsense\r\nFoo: bar\r\n", "/x", false],
    ["﻿User-agent: *\r\nDisallow: /x # comment\r\n# Disallow: /y\r\nnonsense\r\nFoo: bar\r\n", "/y", true],
    ["", "/anything", true]
  ].freeze

  def test_rules
    CASES.each do |text, path, expected|
      assert_equal expected, Robots.parse(text).allowed?(path), "#{path} in #{text.inspect}"
    end
  end

  def test_another_agent
    robots = Robots.parse("User-agent: other\nDisallow: /private/\n", agent: "Other")

    assert_equal([false, true], ["/private/x", "/public/x"].map { robots.allowed?(it) })
  end

  def test_crawl_delay_of_the_group
    delays = ["User-agent: *\nCrawl-delay: 2.5\n", "User-agent: *\nCrawl-delay: soon\n",
              "User-agent: other\nCrawl-delay: 9\n"].map { Robots.parse(it).crawl_delay }

    assert_equal [2.5, nil, nil], delays
  end

  def test_sitemaps_anywhere
    text = "Sitemap: https://www.example.org/a.xml\nUser-agent: *\nDisallow:\nsitemap:https://www.example.org/b.xml\n"

    assert_equal ["https://www.example.org/a.xml", "https://www.example.org/b.xml"], Robots.parse(text).sitemaps
  end

  def test_allow_all
    assert Robots::ALLOW.allowed?("/anything")
    assert_nil Robots::ALLOW.crawl_delay
    assert_empty Robots::ALLOW.sitemaps
  end

end
