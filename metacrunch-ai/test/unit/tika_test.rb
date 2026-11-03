# frozen_string_literal: true

require "test_helper"

# Answers shaped like those of Tika 3.3 to PUT /rmeta/html: an Array whose first entry is the container document.
class TikaTest < Minitest::Test

  Tika = Metacrunch::Ai::Tika

  ENCRYPTED = "org.apache.tika.exception.EncryptedDocumentException: Unable to process: document is encrypted\n\t" \
              "at org.apache.tika.parser.pdf.PDFParser.parse(PDFParser.java:180)"
  TRUNCATED = "java.io.IOException: Missing root object specification in trailer.\n\t" \
              "at org.apache.pdfbox.pdfparser.PDFParser.initialParse(PDFParser.java:112)"

  def setup
    @api = FakeApi.new
  end

  def teardown
    @tika&.close
    @api.stop
  end

  def test_puts_the_document_to_rmeta_html
    answer(pages("One."))
    tika(headers: {"X-Tika-PDFOcrStrategy" => "no_ocr"}).extract("%PDF\xFF".b, type: "application/pdf")
    request = put_request

    assert_equal ["PUT", "/rmeta/html", "%PDF\xFF".b], [request.verb, request.path, request.body.b]
    assert_equal ["application/pdf", "application/json", "true", "no_ocr"],
                 request.headers.values_at("content-type", "accept", "x-tika-skip-embedded", "x-tika-pdfocrstrategy")
  end

  def test_without_a_type_the_bytes_are_octets
    answer(pages("One."))
    tika.extract("x")

    assert_equal "application/octet-stream", put_request.headers["content-type"]
  end

  def test_pages_from_page_divs_with_title_and_lang
    answer(pages("Page one.", "Page two.").merge("dc:title" => "Loans", "dc:language" => "en"))

    assert_equal({text: ["Page one.", "Page two."], title: "Loans", lang: "en", mark: nil}, tika.extract("x"))
  end

  def test_blank_pages_keep_their_numbers
    answer(pages("Page one.", "", "Page three."))

    assert_equal ["Page one.", "", "Page three."], tika.extract("x")[:text]
  end

  def test_without_pages_one_text_with_headings
    answer(content("<h1>Loans</h1><h2>Renewals</h2><p>x</p>"))

    assert_equal "# Loans\n\n## Renewals\n\nx", tika.extract("x", type: "application/msword")[:text]
  end

  def test_metadata_values_may_be_arrays
    answer(content("<p>x</p>").merge("dc:title" => ["Loans", "Other"], "dc:language" => [" "]))

    assert_equal ["Loans", nil], tika.extract("x").values_at(:title, :lang)
  end

  def test_an_encrypted_document_is_invalid_input
    answer({"X-TIKA:encrypted" => "true", "X-TIKA:EXCEPTION:container_exception" => ENCRYPTED})
    error = assert_raises(Metacrunch::Ai::InvalidInput) { tika.extract("x") }

    assert_equal "document is encrypted", error.message
  end

  def test_a_parse_error_without_text_is_invalid_input
    answer({"X-TIKA:EXCEPTION:container_exception" => TRUNCATED, "X-TIKA:content" => "<html><body> </body></html>"})
    error = assert_raises(Metacrunch::Ai::InvalidInput) { tika.extract("x") }

    assert_equal "java.io.IOException: Missing root object specification in trailer.", error.message
  end

  def test_a_parse_error_with_text_passes_with_a_mark
    answer(pages("Page one.").merge("X-TIKA:EXCEPTION:container_exception" => TRUNCATED))

    assert_equal({text: ["Page one."], title: nil, lang: nil, mark: "Text partly extracted"}, tika.extract("x"))
  end

  def test_too_deeply_nested_xhtml_is_invalid_input
    answer(content("#{"<div>" * 500}x"))

    assert_raises(Metacrunch::Ai::InvalidInput) { tika.extract("x") }
  end

  def test_no_content_is_no_text
    answer({"Content-Type" => "image/png"})

    assert_equal "", tika.extract("x")[:text]
  end

  def test_server_errors_are_retried
    answer(pages("One."))
    @api.on("PUT", "/rmeta/html", times: 1) { [503, {}, {"Retry-After" => "0"}] }

    assert_equal ["One."], tika(retries: 1).extract("x")[:text]
    assert_equal(2, @api.requests.count { it.verb == "PUT" })
  end

  def test_422_is_invalid_input
    @api.on("PUT", "/rmeta/html") { [422, "Unprocessable"] }

    assert_raises(Metacrunch::Ai::InvalidInput) { tika.extract("x") }
  end

  def test_malformed_answers_are_api_errors
    [{}, [], ["x"]].each do |body|
      @api.on("PUT", "/rmeta/html", times: 1) { [200, body] }
      error = assert_raises(Metacrunch::Ai::ApiError, body.inspect) { tika.extract("x") }

      assert_equal "tika at #{@api.url("/rmeta/html")}: malformed answer, no document", error.message
    end
  end

  def test_open_probes_and_stops_on_a_wrong_url
    @api.on("GET", "/tika") { [200, "This is Tika Server (Apache Tika 3.3.1). Please PUT"] }
    log = StringIO.new
    @tika = Tika.new(url: @api.url)
    @tika.open(Metacrunch::OpenContext.new(params: nil, logger: Logger.new(log)))

    assert_equal ["GET", "/tika"], @api.requests.first.to_h.values_at(:verb, :path)
    assert_raises(Metacrunch::Ai::ApiError) { Tika.new(url: @api.url("/wrong")).open }
  end

  def test_types_and_defaults
    tika = Tika.new(url: "http://localhost:9998")

    assert_nil tika.types
    assert_equal "http://localhost:9998", tika.url
  end

  def test_inspect_hides_the_headers
    tika = Tika.new(url: "http://user:pw@localhost:9998", headers: {"Authorization" => "Basic s3"})

    assert_equal %(#<Metacrunch::Ai::Tika url="http://localhost:9998">), tika.inspect
  end

  def test_validates_options
    [{url: "ftp://x"}, {url: "http://x", headers: []}, {url: "http://x", timeout: 0},
     {url: "http://x", retries: -1}].each do |options|
      assert_raises(ArgumentError, options.inspect) { Tika.new(**options) }
    end
  end

  def test_tika_from_params
    params = Struct.new(:tika_url).new(@api.url)
    tika = Metacrunch::Ai.tika(params, timeout: 10)

    assert_equal [Tika, @api.url], [tika.class, tika.url]
  end

  def test_tika_needs_a_url
    error = assert_raises(ArgumentError) { Metacrunch::Ai.tika(Struct.new(:tika_url).new(nil)) }

    assert_equal "tika_url is required", error.message
    assert_raises(ArgumentError) { Metacrunch::Ai.tika(Object.new) }
  end

  def test_tika_params_declare_the_url
    definitions = Metacrunch::Params.new.tap { it.use(Metacrunch::Ai::TIKA_PARAMS) }.definitions

    assert_equal [:tika_url], definitions.keys
    assert_includes definitions[:tika_url].desc, "Apache Tika server URL"
  end

  private

  def tika(**)
    @api.on("GET", "/tika") { [200, "This is Tika Server"] }
    @tika = Tika.new(url: @api.url, **).tap(&:open)
  end

  def put_request = @api.requests.find { it.verb == "PUT" }

  def answer(meta)
    @api.on("PUT", "/rmeta/html") { [200, [meta]] }
  end

  def content(body) = {"Content-Type" => "application/pdf", "X-TIKA:content" => xhtml(body)}

  def pages(*texts) = content(texts.map { %(<div class="page"><p>#{it}</p></div>) }.join)

  def xhtml(body)
    head = %(<head><meta name="pdf:PDFVersion" content="1.7"/><title></title></head>)
    %(<html xmlns="http://www.w3.org/1999/xhtml">#{head}<body>#{body}</body></html>)
  end

end
