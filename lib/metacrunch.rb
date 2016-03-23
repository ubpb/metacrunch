require "active_support"
require "active_support/core_ext"
require "rubygems"
require "rubygems/package"
require "commander"

begin
  require "pry"
rescue LoadError ; end

module Metacrunch
  require_relative "./metacrunch/version"
  require_relative "./metacrunch/cli"

  def self.load_plugins
    Gem.find_latest_files("metacrunch_plugin.rb").each do |path|
      load(path)
    end
  end

end
