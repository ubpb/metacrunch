# frozen_string_literal: true

require "test_helper"
require "metacrunch/testing"

class ExtractTest < Minitest::Test

  Extract = Metacrunch::Ai::Extract

  # An extractor with a fixed answer that notes its calls.
  class Fixed

    attr_reader :types, :calls

    def initialize(types, **result)
      @types = types
      @result = {text: "text", title: nil, lang: nil}.merge(result)
      @calls = []
    end

    def extract(content, type:)
      @calls << [content, type]
      raise @result[:error] if @result[:error]

      @result.except(:error)
    end

  end

  # One that notes open and close.
  class Openable < Fixed

    attr_reader :events

    def open(context) = (@events ||= []) << [:open, context]

    def close = (@events ||= []) << :close

  end

  def test_routes_by_type
    html = Fixed.new(["text/html"], text: "from html")
    any = Fixed.new(nil, text: "from any")
    records = run_extract(Extract.new(html, any), [doc("text/html; charset=utf-8"), doc("application/pdf")]).records

    assert_equal(["from html", "from any"], records.map { it["text"] })
    assert_equal [["<p>", "text/html"]], html.calls
    assert_equal [["<p>", "application/pdf"]], any.calls
  end

  def test_types_are_matched_without_case
    html = Fixed.new(["text/html"], text: "from html")

    assert_equal "from html", run_extract(Extract.new(html), [doc("Text/HTML")]).records.first["text"]
  end

  def test_a_record_without_type_goes_to_the_first_extractor
    first = Fixed.new(["text/html"], text: "first")
    records = run_extract(Extract.new(first, Fixed.new(nil)), [{"content" => "x"}]).records

    assert_equal(["first"], records.map { it["text"] })
    assert_equal [["x", nil]], first.calls
  end

  def test_no_extractor_for_the_type_fails_the_record
    result = run_extract(Extract.new(Fixed.new(["text/html"])), [doc("application/zip"), doc("text/html")])
    error = result.failures.first.last.error

    assert_equal [Metacrunch::Ai::Error, "no extractor for application/zip"], [error.class, error.message]
    assert_equal 1, result.records.size
  end

  def test_writes_text_title_and_lang_and_drops_the_content
    extract = Extract.new(Fixed.new(nil, text: "# Loans", title: "Loans", lang: "en"))
    record = run_extract(extract, [doc("text/html").merge("id" => 1)]).records.first

    assert_equal({"id" => 1, "type" => "text/html", "text" => "# Loans", "title" => "Loans", "lang" => "en"}, record)
  end

  def test_other_fields
    extract = Extract.new(Fixed.new(nil, text: "t", title: "T", lang: "de"), from: "body", type: "mime", into: "plain",
                                                                             title: "name", lang: "language")
    record = run_extract(extract, [{"body" => "x", "mime" => "text/html"}]).records.first

    assert_equal({"mime" => "text/html", "plain" => "t", "name" => "T", "language" => "de"}, record)
  end

  def test_title_and_lang_off
    extract = Extract.new(Fixed.new(nil, title: "Found", lang: "en"), title: nil, lang: nil)
    record = run_extract(extract, [doc("text/html").merge("title" => "Given")]).records.first

    assert_equal ["Given", nil], record.values_at("title", "lang")
  end

  def test_a_found_title_replaces_and_none_keeps
    found = run_extract(Extract.new(Fixed.new(nil, title: "Found")), [doc("x").merge("title" => "Given")])
    none = run_extract(Extract.new(Fixed.new(nil)), [doc("x").merge("title" => "Given")])

    assert_equal ["Found", "Given"], [found.records.first["title"], none.records.first["title"]]
  end

  def test_pages_stay_an_array
    record = run_extract(Extract.new(Fixed.new(nil, text: ["One.", "Two."])), [doc("application/pdf")]).records.first

    assert_equal ["One.", "Two."], record["text"]
  end

  def test_blank_text_is_marked
    result = run_extract(Extract.new(Fixed.new(nil, text: "")), [doc("x")])
    pages = run_extract(Extract.new(Fixed.new(nil, text: ["", " ", nil])), [doc("x")])

    assert_equal [{"No text extracted" => 1}] * 2, [result.stats.marked, pages.stats.marked]
    assert_equal 1, result.records.size
  end

  def test_a_mark_of_the_extractor_is_set
    result = run_extract(Extract.new(Fixed.new(nil, mark: "Text partly extracted")), [doc("x")])

    assert_equal({"Text partly extracted" => 1}, result.stats.marked)
  end

  def test_missing_content_is_marked_without_a_call
    extractor = Fixed.new(nil)
    result = run_extract(Extract.new(extractor), [{"type" => "text/html"}, {"content" => nil}])

    assert_equal(["", ""], result.records.map { it["text"] })
    assert_equal({"No text extracted" => 2}, result.stats.marked)
    assert_empty extractor.calls
  end

  def test_an_error_fails_only_its_record
    broken = Fixed.new(["application/pdf"], error: Metacrunch::Ai::InvalidInput.new("document is encrypted"))
    result = run_extract(Extract.new(broken, Fixed.new(nil)), [doc("application/pdf"), doc("text/html")])

    assert_equal(["document is encrypted"], result.failures.map { it.last.error.message })
    assert_equal 1, result.records.size
  end

  def test_an_extractor_without_text_fails_the_record
    error = run_extract(Extract.new(Fixed.new(nil, text: 42)), [doc("x")]).failures.first.last.error

    assert_equal [Metacrunch::Ai::Error, "ExtractTest::Fixed gave no text: 42"], [error.class, error.message]
  end

  def test_open_and_close_reach_the_extractors
    openable = Openable.new(nil)
    extract = Extract.new(Fixed.new(["text/html"]), openable)
    extract.open(:context)
    extract.close

    assert_equal [[:open, :context], :close], openable.events
  end

  def test_needs_hash_records
    error = run_extract(Extract.new(Fixed.new(nil)), ["<p>"]).failures.first.last.error

    assert_equal [Metacrunch::ContractError, "Extract needs Hash records, got String"], [error.class, error.message]
  end

  def test_validates_options
    fixed = Fixed.new(nil)
    cases = [[[], {}], [[Object.new], {}], [[fixed], {into: ""}], [[fixed], {from: :content}], [[fixed], {type: nil}],
             [[fixed], {title: ""}], [[fixed], {lang: 1}]]

    cases.each do |extractors, options|
      assert_raises(ArgumentError, options.inspect) { Extract.new(*extractors, **options) }
    end
  end

  def test_with_html_and_text_in_a_job
    extract = Extract.new(Metacrunch::Ai::Html.new, Metacrunch::Ai::Text.new)
    records = run_extract(extract, [{"type" => "text/html", "content" => "<main><h1>Loans</h1></main>"},
                                    {"type" => "text/markdown", "content" => "# Rules\r\n"}]).records

    assert_equal(["# Loans", "# Rules\n"], records.map { it["text"] })
    assert_equal "Loans", records.first["title"]
  end

  private

  def doc(type) = {"type" => type, "content" => "<p>"}

  def run_extract(extract, records)
    job = Metacrunch.job do
      map extract
      on_failure :skip
    end
    Metacrunch::Testing.run(job, source: records)
  end

end
