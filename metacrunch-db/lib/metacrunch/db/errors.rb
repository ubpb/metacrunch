# frozen_string_literal: true

module Metacrunch
  module Db
    # Errors of Connection#connect and of records the writer cannot write;
    # the reader raises Metacrunch::InputError, the writer
    # Metacrunch::OutputError. Sequel's error is the cause.
    class Error < Metacrunch::Error; end
  end
end
