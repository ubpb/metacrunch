require "active_support"
require "active_support/core_ext"
require "active_support/builder"
require "rubygems"
require "rubygems/package"
require "thor"
require "ox"

module Metacrunch
  require_relative "./metacrunch/version"

  def self.load_plugins
    Gem.find_latest_files("metacrunch_plugin.rb").each do |path|
      load(path)
    end
  end

end
