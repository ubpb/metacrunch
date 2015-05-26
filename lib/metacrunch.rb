require "active_support"
require "active_support/core_ext"
require "active_support/builder"
require "parallel"
require "rubygems"
require "rubygems/package"
require "thor"
require "ox"

begin
  require "pry"
rescue LoadError ; end

module Metacrunch
  require_relative "./metacrunch/version"
  require_relative "./metacrunch/cli"
  require_relative "./metacrunch/command"
  require_relative "./metacrunch/file_reader"
  require_relative "./metacrunch/file_reader_entry"
  require_relative "./metacrunch/file_writer"
  require_relative "./metacrunch/tar_writer"
  require_relative "./metacrunch/snr"
  require_relative "./metacrunch/transformer"
  require_relative "./metacrunch/parallel"

  def self.load_plugins
    Gem.find_latest_files("metacrunch_plugin.rb").each do |path|
      load(path)
    end
  end

end
