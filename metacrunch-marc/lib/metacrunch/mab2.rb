require "metacrunch"
require "ox"

begin
  require "pry"
rescue LoadError ; end

module Metacrunch
  module Mab2
  end
end

require "metacrunch/mab2/version"
require "metacrunch/mab2/document"
require "metacrunch/mab2/cli"
require_relative "./mab2/aleph_mab_xml_document_factory"
