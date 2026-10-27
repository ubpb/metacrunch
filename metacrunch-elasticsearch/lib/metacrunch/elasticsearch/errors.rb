# frozen_string_literal: true

module Metacrunch
  module Elasticsearch

    # Errors of Indices, Search, the commands and the checks of Connection;
    # the reader raises Metacrunch::InputError, the writer
    # Metacrunch::OutputError. The client's error is the cause.
    class Error < Metacrunch::Error; end

    # A bulk item that Elasticsearch refused for good (e.g. 400 for a value the
    # mapping does not take, 409 for create on an existing id). The writer
    # reports it in Metacrunch::SinkFailures.
    class BulkItemError < Error

      attr_reader :status, :type, :reason, :action, :id

      def initialize(status:, type:, reason:, action:, id:)
        @status = status
        @type = type
        @reason = reason
        @action = action
        @id = id
        super("#{status} #{type}: #{reason} (#{[action, id].compact.join(" ")})")
      end

    end

    class << self

      # The HTTP status of an error the client raised, or nil (no response,
      # e.g. a refused connection).
      def status(error)
        error.message[/\A\[(\d{3})\]/, 1]&.to_i if error.is_a?(Elastic::Transport::Transport::ServerError)
      end

      # Status, type and reason of a server error as Elasticsearch gives them,
      # e.g. "404 index_not_found_exception: no such index [books]"; the
      # start of the body for answers that are not Elasticsearch's JSON.
      def reason(error)
        status = status(error)
        body = error.message.sub(/\A\[\d{3}\] ?/, "")
        cause = begin
          JSON.parse(body)["error"]
        rescue JSON::ParserError
          nil
        end
        return "#{status} #{cause["type"]}: #{cause["reason"]}" if cause.is_a?(Hash)

        text = cause.is_a?(String) ? cause : body[0, 200].strip
        text.empty? ? status.to_s : "#{status} #{text}"
      end

    end

  end
end
