require "metacrunch/mab2"
require "benchmark/ips"

Benchmark.ips do |x|
  x.config(time: 5, warmup: 2)

  @xml      = File.read(File.join(Pathname.new(__dir__), "..", "spec", "assets", "aleph_mab_xml", "file1.xml"))
  @document = Metacrunch::Mab2::Document.from_aleph_mab_xml(@xml)

  x.report("reference") do
    a = []

    datafields_struct = @document.send(:datafields_struct)
    datafields_set    = datafields_struct["PPE"]
    datafields        = datafields_set.to_a

    datafields.each do |datafield|
      subfields_struct = datafield.send(:subfields_struct)
      subfields_set    = subfields_struct["p"]
      subfields        = subfields_set.to_a

      subfields.each do |subfield|
        a << subfield.value
      end
    end
  end

  x.report("implementation") do
    @document.datafields("PPE").subfields("p").values
  end

  x.compare!
end

