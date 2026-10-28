# frozen_string_literal: true

module Metacrunch
  module Redis
    # Errors of Connection#connect and of records a writer cannot write; the
    # readers raise Metacrunch::InputError, the writers
    # Metacrunch::OutputError. redis-client's error is the cause.
    class Error < Metacrunch::Error; end
  end
end
