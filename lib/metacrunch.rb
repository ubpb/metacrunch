require "active_support"
require "active_support/core_ext"
require "parallel"
require "rubygems"
require "rubygems/package"
require "thor"
require "thor/group"

begin
  require "pry"
rescue LoadError ; end

module Metacrunch

  def self.load_plugins
    Gem.find_latest_files("metacrunch_plugin.rb").each do |path|
      load(path)
    end
  end

end

require "metacrunch/version"
require "metacrunch/cli"
require "metacrunch/command"
require "metacrunch/utils"
