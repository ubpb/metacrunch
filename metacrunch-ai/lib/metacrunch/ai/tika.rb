# frozen_string_literal: true

module Metacrunch
  module Ai
    # An extractor for PDF, office and other documents through an Apache
    # Tika server (PUT /rmeta/html): the text as Markdown, a PDF's as an
    # Array of pages, with title and language when the document names them.
    # Embedded documents (attachments) are skipped.
    #
    # Tika answers 200 also for documents it cannot parse and puts the
    # exception into the metadata: without text the record fails with
    # InvalidInput ("document is encrypted" for an encrypted one), with text
    # it passes with the mark "Text partly extracted".
    class Tika

      PARTLY = "Text partly extracted"
      HEADERS = {"X-Tika-Skip-Embedded" => "true"}.freeze

      attr_reader :url

      # headers: further headers, e.g. X-Tika-PDFOcrStrategy for OCR with a
      # -full image. timeout: large PDFs take long; retries: a document that
      # timed out mostly times out again.
      def initialize(url:, headers: {}, timeout: 300, retries: 2)
        raise ArgumentError, "headers must be a Hash, got #{headers.inspect}" unless headers.is_a?(Hash)

        @url = url
        @http = Http.new(url:, headers: HEADERS.merge(headers), timeout:, retries:, name: "tika")
      end

      def types = nil

      # Asks the server for its greeting, so a wrong URL stops the job before
      # records are read. context: an OpenContext, for its logger.
      def open(context = nil)
        @http.open(context&.logger)
        @http.get("/tika")
        self
      end

      def close = @http.close

      def extract(content, type: nil)
        answer = @http.put("/rmeta/html", content.to_s.b, content_type: type || "application/octet-stream")
        document = answer.first if answer.is_a?(Array)
        raise ApiError, "tika at #{location}: malformed answer, no document" unless document.is_a?(Hash)

        text = text(document["X-TIKA:content"].to_s)
        {text:, title: value(document, "dc:title"), lang: value(document, "dc:language"), mark: mark(document, text)}
      end

      # Without the headers and user info, which may hold credentials.
      def inspect = "#<#{self.class.name} url=#{base.inspect}>"

      private

      def base
        uri = Http.uri(@url)
        "#{uri.scheme}://#{uri.host}:#{uri.port}#{uri.path.chomp("/")}"
      end

      def location = "#{base}/rmeta/html"

      def text(xhtml)
        return "" if xhtml.strip.empty?

        document = Nokogiri::HTML5(xhtml)
        pages = document.css("div.page")
        pages.empty? ? Markdown.convert(document.at_css("body") || document) : pages.map { Markdown.convert(it) }
      end

      # nil, or the mark for text Tika got despite an exception; raises
      # InvalidInput for an exception without text.
      def mark(document, text)
        exception = Array(document["X-TIKA:EXCEPTION:container_exception"]).first
        return nil if exception.nil?
        return PARTLY unless Array(text).all? { it.strip.empty? }

        encrypted = Array(document["X-TIKA:encrypted"]).first.to_s == "true"
        raise InvalidInput, encrypted ? "document is encrypted" : exception.lines.first.strip
      end

      def value(document, key)
        text = Array(document[key]).first.to_s.strip
        text unless text.empty?
      end

    end
  end
end
