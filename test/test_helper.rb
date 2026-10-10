# frozen_string_literal: true

if ENV.key?("COVERAGE")
  require "simplecov"

  SimpleCov.start do
    enable_coverage :branch
    minimum_coverage line: 95, branch: 90
    add_filter "/test/"
  end
end

require "minitest/autorun"
require "stringio"
require "metacrunch"

Dir[File.join(__dir__, "support", "*.rb")].each { |file| require file }
