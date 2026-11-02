# frozen_string_literal: true

module Metacrunch
  module Ai

    class Error < Metacrunch::Error; end

    # A service refused a request or gave a useless answer. status: the
    # HTTP status, or nil (no answer); body: an excerpt of the answer, or
    # nil.
    class ApiError < Error

      attr_reader :status, :body

      def initialize(message, status: nil, body: nil)
        super(message)
        @status = status
        @body = body
      end

    end

    # The service refused the input (HTTP 400, 413, 422): one of the texts
    # may be at fault, not the service.
    class InvalidInput < ApiError; end

    # The service did not answer usefully after the retries (429, 5xx,
    # timeouts, lost connections).
    class Unavailable < ApiError; end

  end
end
