require "bundler/setup"
require "metacrunch/mab2"
require "benchmark"

result = Benchmark.measure do
  100000.times do
    xml = File.read(File.join(__dir__, "..", "spec", "assets", "aleph_mab_xml", "file1.xml"))
    Metacrunch::Mab2::Document.from_mab_xml(xml)
  end
end

puts result
