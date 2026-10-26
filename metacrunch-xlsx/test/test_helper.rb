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
require "rexml/document"
require "zip"
require "metacrunch/xlsx"

# roo requires cgi, which warns on Ruby 4.0.
verbose = $VERBOSE
$VERBOSE = nil
require "roo"
$VERBOSE = verbose

Dir[File.join(__dir__, "support", "*.rb")].each { |file| require file }
