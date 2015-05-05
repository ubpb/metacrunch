require "metacrunch/mab2"
require "benchmark/ips"

Benchmark.ips do |x|
  x.config(time: 5, warmup: 2)

  @xml = File.read(File.join(Pathname.new(__dir__), "..", "spec", "assets", "aleph_mab_xml", "file1.xml"))

  x.report("implementation") do
    @document = Metacrunch::Mab2::Document.from_aleph_mab_xml(@xml)
  end

  x.compare!
end
