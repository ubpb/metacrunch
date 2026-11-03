# frozen_string_literal: true

require "test_helper"

class MarkdownTest < Minitest::Test

  def test_headings_and_paragraphs
    assert_equal "# A\n\nx\n\n### B", md("<h1>A</h1><p>x</p><h3>B</h3>")
  end

  def test_inline_elements_give_their_text
    assert_equal "Read the rules now", md(%(<p>Read <a href="/x">the <em>rules</em></a>  now</p>))
  end

  def test_line_breaks
    assert_equal "a\nb", md("<p>a<br>b</p>")
  end

  def test_nested_lists
    html = "<ul><li>a<ul><li>b</li></ul></li><li>c</li></ul><ol><li>x</li><li>y<ul><li>z</li></ul></li></ol>"

    assert_equal "- a\n  - b\n- c\n\n1. x\n2. y\n   - z", md(html)
  end

  def test_list_items_with_paragraphs
    assert_equal "- a\n  b", md("<ul><li><p>a</p><p>b</p></li></ul>")
  end

  def test_tables_with_a_header_row
    html = "<table><tr><th>Day</th><th>Hours</th></tr><tr><td>Mon</td><td>9–18 | late</td></tr></table>"

    assert_equal "| Day | Hours |\n| --- | --- |\n| Mon | 9–18 \\| late |", md(html)
  end

  def test_tables_without_th_take_the_first_row
    html = "<table><tr><td>Day</td><td>Hours</td></tr><tr><td>Mon</td><td>9</td></tr></table>"

    assert_equal "| Day | Hours |\n| --- | --- |\n| Mon | 9 |", md(html)
  end

  def test_colspan_keeps_the_columns
    html = %(<table><tr><td colspan="2">x</td></tr><tr><td>a</td><td>b</td></tr></table>)

    assert_equal "| x |  |\n| --- | --- |\n| a | b |", md(html)
  end

  def test_short_rows_are_padded
    assert_equal "| a | b |\n| --- | --- |\n| c |  |",
                 md("<table><tr><td>a</td><td>b</td></tr><tr><td>c</td></tr></table>")
  end

  def test_cells_on_one_line
    html = "<table><tr><th>A</th></tr><tr><td><p>a</p><p>b</p><table><tr><td>c</td></tr></table></td></tr></table>"

    assert_equal "| A |\n| --- |\n| a b c |", md(html)
  end

  def test_a_caption_comes_before_its_table
    html = "<table><caption>Opening <b>hours</b></caption><tr><th>Day</th></tr><tr><td>Mon</td></tr></table>"

    assert_equal "Opening hours\n\n| Day |\n| --- |\n| Mon |", md(html)
  end

  def test_an_empty_table
    assert_equal "a", md("<table></table><p>a</p>")
  end

  def test_code_blocks_keep_their_text
    assert_equal "```\na  b\n  c\n```", md("<pre><code>a  b\n  c</code></pre>")
  end

  def test_code_with_backticks_gets_a_longer_fence
    assert_equal "````\nx ``` y\n````", md("<pre>x ``` y</pre>")
  end

  def test_blockquotes
    assert_equal "> a\n>\n> b", md("<blockquote><p>a</p><p>b</p></blockquote>")
  end

  def test_definition_lists
    assert_equal "Loan\n\n4 weeks", md("<dl><dt>Loan</dt><dd>4 weeks</dd></dl>")
  end

  def test_an_image_alone_gives_its_alt_text
    html = %(<figure><img alt="Floor plan"><figcaption>Ground floor</figcaption></figure><p>x <img alt="icon"> y</p>)

    assert_equal "Floor plan\n\nGround floor\n\nx y", md(html)
  end

  def test_whitespace_and_empty_blocks
    assert_equal "a\n\nb\n\nc", md("<div><p> a </p>\n\n<div></div><p>b</p><hr><p>\n c\n</p></div>")
  end

  def test_text_beside_blocks
    assert_equal "Intro\n\nPara\n\ntail more", md("<div>Intro <p>Para</p> tail <span>more</span></div>")
  end

  def test_skips_scripts_styles_and_head
    document = Nokogiri::HTML5(<<~HTML)
      <html><head><title>T</title><meta name="x" content="y"><style>p {}</style></head>
      <body><script>x()</script><noscript>Enable it</noscript><template><p>t</p></template><p>a</p><!-- c --></body></html>
    HTML

    assert_equal "a", Metacrunch::Ai::Markdown.convert(document)
  end

  def test_an_empty_node
    assert_equal "", md("")
  end

  private

  def md(html) = Metacrunch::Ai::Markdown.convert(Nokogiri::HTML5(html).at("body"))

end
