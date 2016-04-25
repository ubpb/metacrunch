require "rubygems"
require "active_support"
require "active_support/core_ext"
require "htmlentities"
require "nokogiri"
require "ox" unless RUBY_PLATFORM == "java"

module Metacrunch
  module Mab2
    require_relative "./mab2/builder"
    require_relative "./mab2/cli"
    require_relative "./mab2/document"
    require_relative "./mab2/version"
  end
end
