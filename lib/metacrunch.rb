require "rubygems"
require "bundler/setup"

require "active_support"
require "active_support/core_ext"
require "commander"
require "sequel"

begin
  Bundler.require
rescue Bundler::GemfileNotFound ; end

begin
  require "pry"
rescue LoadError ; end

module Metacrunch
  require_relative "metacrunch/version"
  require_relative "metacrunch/cli"
  require_relative "metacrunch/job"
  require_relative "metacrunch/fs"
  require_relative "metacrunch/db"
end
