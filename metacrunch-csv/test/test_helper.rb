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

require "minitest/autorun"
require "logger"
require "stringio"
require "tmpdir"
require "fileutils"
require "zlib"
require "rubygems/package"
require "metacrunch/csv"

Dir[File.join(__dir__, "support", "*.rb")].each { |file| require file }
