require "bundler/setup"
require "metacrunch/marcxml"
require "benchmark"

result = Benchmark.measure do
  100000.times do
    xml = File.read(File.join(__dir__, "..", "spec", "assets", "aleph_mab_xml", "file1.xml"))
    Metacrunch::Marcxml::Document.from_marcxml(xml)
  end
end

puts result
