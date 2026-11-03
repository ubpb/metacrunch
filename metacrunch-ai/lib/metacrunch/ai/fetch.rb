# frozen_string_literal: true

module Metacrunch
  module Ai
    # A step that downloads the document whose URL a record holds, politely
    # (see Web), and adds the fields a FileList::Reader record has, so that
    # Extract follows: content, type, size, sha256, modified; and etag,
    # fetched and location (the URL after redirects). It follows no links.
    #
    # A record without a URL, with a URL that is no http(s) URL, redirects
    # to none or has an IDN host, one robots.txt disallows, and one the
    # server answers with 4xx passes without content and with a mark. 429, 5xx and network
    # errors after the retries, too many redirects and a body over max_size
    # fail the record.
    class Fetch

      NO_URL = "No URL to fetch"
      NOT_HTTP = "Not an http(s) URL"
      REDIRECTED = "Redirected to no http(s) URL"
      IDN = "Host name not supported"
      DISALLOWED = "Disallowed by robots.txt"
      TEXT = ["application/xhtml+xml", "application/xml", "application/json"].freeze
      OCTET_STREAM = "application/octet-stream"
      # Charset labels of the web (WHATWG Encoding Standard) that Ruby does
      # not know.
      CHARSETS = {
        "latin1" => "ISO-8859-1", "latin-1" => "ISO-8859-1", "l1" => "ISO-8859-1", "iso_8859-1" => "ISO-8859-1",
        "latin2" => "ISO-8859-2", "l2" => "ISO-8859-2", "latin9" => "ISO-8859-15", "l9" => "ISO-8859-15",
        "utf8" => "UTF-8", "unicode-1-1-utf-8" => "UTF-8", "x-cp1252" => "Windows-1252", "x-sjis" => "Shift_JIS",
        "ks_c_5601-1987" => "CP949"
      }.freeze

      # from: the field with the URL; the other options go to Web (user_agent,
      # delay, robots, max_size, redirects, timeout, retries).
      def initialize(from: "url", **)
        raise ArgumentError, "from must be a non-empty String, got #{from.inspect}" unless Ai.text?(from)

        @from = from
        @web = Web.new(**)
      end

      def open(context) = @web.open(context.logger)

      def close = @web.close

      def call(record, ctx)
        raise ContractError, "Fetch needs Hash records, got #{record.class}" unless record.is_a?(Hash)

        url = record[@from]
        return marked(record, ctx, NO_URL) if url.nil? || url.to_s.strip.empty?

        Web.normalize(url)
        download(record, ctx, url)
      rescue Web::NotHttp
        marked(record, ctx, NOT_HTTP)
      rescue Web::Idn
        marked(record, ctx, IDN)
      end

      private

      # The record's URL is an http(s) URL here, so NotHttp comes from a
      # redirect.
      def download(record, ctx, url)
        fetched = Time.now.utc.iso8601
        page = @web.get(url)
        return marked(record, ctx, refusal(page.status)) if page.status.between?(400, 499)
        raise ApiError.new("#{page.url}: #{page.status}", status: page.status) unless page.status.between?(200, 299)

        record.merge(fields(page, fetched))
      rescue Web::NotHttp
        marked(record, ctx, REDIRECTED)
      rescue Web::Disallowed
        marked(record, ctx, DISALLOWED)
      end

      def marked(record, ctx, reason)
        ctx.mark(reason)
        record
      end

      def refusal(status) = "#{[404, 410].include?(status) ? "Not found" : "Refused"} (#{status})"

      def fields(page, fetched)
        type, charset = media_type(page.headers["content-type"])
        {"content" => content(page.body, type, charset), "type" => type, "size" => page.body.bytesize,
         "sha256" => Digest::SHA256.hexdigest(page.body), "modified" => modified(page.headers["last-modified"]),
         "etag" => page.headers["etag"], "fetched" => fetched, "location" => page.url}.compact
      end

      # [type, charset] from a Content-Type header.
      def media_type(header)
        type, *parameters = header.to_s.split(";").map(&:strip)
        charset = parameters.filter_map { it[/\Acharset\s*=\s*"?([^";]+)"?\z/i, 1] }.first
        [type.to_s.empty? ? OCTET_STREAM : type.downcase, charset]
      end

      # Text in the encoding its charset names; anything else as bytes.
      def content(body, type, charset)
        return body unless charset && (type.start_with?("text/") || TEXT.include?(type))

        body.dup.force_encoding(Encoding.find(CHARSETS.fetch(charset.downcase, charset)))
      rescue ArgumentError
        body
      end

      def modified(header)
        Time.httpdate(header).utc.iso8601 if header
      rescue ArgumentError
        nil
      end

    end
  end
end
