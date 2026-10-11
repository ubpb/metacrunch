# frozen_string_literal: true

if ENV.key?("COVERAGE")
  require "simplecov"

  SimpleCov.start do
    # One run is one result: no merging with results of earlier runs (e.g.
    # of a single test file), which SimpleCov reports when they are stale.
    merging false
    enable_coverage :branch
    minimum_coverage line: 95, branch: 90
    skip "/test/"
  end
end

require "minitest/autorun"
require "stringio"
require "metacrunch"

Dir[File.join(__dir__, "support", "*.rb")].each { |file| require file }
