require "metacrunch/mab2"
require "benchmark/ips"

require "mabmapper"
require "mabmapper/aleph_mab_xml_engine"
class EmptyMabmapperEngine < Mabmapper::Engine
  document_class Mabmapper::MabXml::Document
end

Benchmark.ips do |x|
  x.config(time: 5, warmup: 2)

  @xml = File.read(File.join(Pathname.new(__dir__), "..", "spec", "assets", "aleph_mab_xml", "file1.xml"))

  x.report("mabmapper") do
    @document = EmptyMabmapperEngine.new.process("dummy.xml", @xml)
  end

  x.report("metacrunch") do
    @document = Metacrunch::Mab2::Document.from_aleph_mab_xml(@xml)
  end

  x.compare!
end
