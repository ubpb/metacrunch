# frozen_string_literal: true

require "test_helper"

class HtmlTest < Minitest::Test

  Html = Metacrunch::Ai::Html

  PAGE = <<~HTML
    <!doctype html>
    <html lang="en"><head><title>  Loans
     | Library </title></head>
    <body>
      <header>Library</header><nav>Menu</nav>
      <main><h1>Loans</h1><nav>In this page</nav><p>Four weeks.</p><script>track()</script></main>
      <footer>Imprint</footer>
    </body></html>
  HTML

  def test_takes_main_without_its_navigation
    assert_equal({text: "# Loans\n\nFour weeks.", title: "Loans | Library", lang: "en"}, Html.new.extract(PAGE))
  end

  def test_falls_back_to_role_main
    html = %(<body><nav>Menu</nav><div role="main"><p>Content</p></div></body>)

    assert_equal "Content", text(html)
  end

  def test_falls_back_to_a_single_article
    assert_equal "Content", text("<body><p>Teaser</p><article><p>Content</p></article></body>")
  end

  def test_falls_back_to_body_without_header_footer_and_aside
    html = "<body><header>Logo</header><article>One</article><article>Two</article><aside>Ads</aside>" \
           "<footer>Imprint</footer></body>"

    assert_equal "One\n\nTwo", text(html)
  end

  def test_content_selector_takes_all_matches_once
    html = %(<body><div class="a"><p>First</p><div class="b"><p>Inner</p></div></div><p>Out</p>) +
           %(<div class="b"><p>Second</p></div></body>)

    assert_equal "First\n\nInner\n\nSecond", text(html, content: ".a, .b")
  end

  def test_a_content_selector_that_matches_nothing_falls_back
    assert_equal "# Loans\n\nFour weeks.", text(PAGE, content: "#missing")
  end

  def test_remove_selector
    html = %(<main><p class="cookie-banner">Cookies?</p><p>Content</p><ol class="breadcrumb"><li>Home</li></ol></main>)

    assert_equal "Content", text(html, remove: ".cookie-banner, .breadcrumb")
  end

  def test_hidden_elements_are_removed
    html = %(<main><p hidden>Secret</p><p aria-hidden="true">Icon</p><form><input></form><p>Shown</p></main>)

    assert_equal "Shown", text(html)
  end

  def test_title_from_h1_without_title
    assert_equal "Opening hours", Html.new.extract("<body><h1> Opening\n hours</h1><p>x</p></body>")[:title]
  end

  def test_no_break_spaces_in_the_title
    assert_equal "Loans | Library", Html.new.extract("<title>Loans&nbsp;|&nbsp;Library&nbsp;</title>")[:title]
  end

  def test_no_title_and_no_lang
    result = Html.new.extract("<p>x</p>")

    assert_equal [nil, nil], result.values_at(:title, :lang)
  end

  def test_charset_from_meta_for_bytes
    assert_equal "Öffnungszeiten", text("<meta charset=iso-8859-1><p>\xD6ffnungszeiten</p>".b)
  end

  def test_a_utf8_bom
    assert_equal "Öffnungszeiten", text("\xEF\xBB\xBF<p>\xC3\x96ffnungszeiten</p>".b)
  end

  def test_a_string_keeps_its_encoding
    assert_equal "Öffnungszeiten", text("<p>Öffnungszeiten</p>".encode(Encoding::ISO_8859_1))
  end

  def test_a_lying_charset_gives_valid_utf8
    result = text("<meta charset=utf-8><p>\xD6ffnungszeiten</p>".b)

    assert_predicate result, :valid_encoding?
    assert_equal "�ffnungszeiten", result
  end

  def test_an_empty_body
    assert_equal "", text("<html><body></body></html>")
    assert_equal "", text("")
  end

  def test_types
    assert_equal ["text/html", "application/xhtml+xml"], Html.new.types
  end

  def test_validates_options
    [{content: 1}, {content: "p["}, {remove: "!!"}, {remove: []}].each do |options|
      assert_raises(ArgumentError, options.inspect) { Html.new(**options) }
    end
  end

  private

  def text(html, **) = Html.new(**).extract(html, type: "text/html")[:text]

end
