require "metacrunch"
require "ox"

begin
  require "pry"
rescue LoadError ; end

module Metacrunch
  module Mab2
    require_relative "./mab2/version"
    require_relative "./mab2/document"
    require_relative "./mab2/cli"
    require_relative "./mab2/aleph_mab_xml_document_factory"
  end
end
