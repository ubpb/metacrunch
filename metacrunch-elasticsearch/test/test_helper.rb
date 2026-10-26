# frozen_string_literal: true

if ENV.key?("COVERAGE")
  require "simplecov"

  SimpleCov.start do
    # One run is one result: no merging with results of earlier runs.
    merging false
    enable_coverage :branch
    minimum_coverage line: 95, branch: 90
    skip "/test/"
    skip "/vendor/"
  end
end

# Warnings of the client gems that Ruby shows only with -w, as the tests run: the transport calls MultiJson, which
# multi_json 1.21 deprecates, and client 8.19 requires cgi, which Ruby 4.0 no longer ships. Every other warning
# passes.
module QuietClient

  CLIENT_WARNINGS = /MultiJson constant|\AMultiJSON\.\w+ is deprecated|install cgi gem/

  def warn(message, ...)
    super unless message.match?(CLIENT_WARNINGS)
  end

end
Warning.singleton_class.prepend(QuietClient)

require "minitest/autorun"
require "logger"
require "stringio"
require "tmpdir"
require "fileutils"
require "metacrunch/elasticsearch"

Dir[File.join(__dir__, "support", "*.rb")].each { |file| require file }
