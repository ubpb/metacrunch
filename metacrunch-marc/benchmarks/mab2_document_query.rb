require "metacrunch/mab2"
require "benchmark/ips"

Benchmark.ips do |x|
  x.config(time: 10, warmup: 2)

  @xml      = File.read(File.join(Pathname.new(__dir__), "..", "spec", "assets", "aleph_mab_xml", "file1.xml"))
  @document = Metacrunch::Mab2::Document.from_aleph_mab_xml(@xml)

  x.report("reference") do
    a = []

    data_fields_struct = @document.send(:data_fields_struct)
    data_fields_set = data_fields_struct["PPE"]
    data_fields = data_fields_set.to_a

    data_fields.each do |data_field|
      sub_fields_struct = data_field.send(:sub_fields_struct)
      sub_fields_set = sub_fields_struct["p"]
      sub_fields = sub_fields_set.to_a

      sub_fields.each do |sub_field|
        a << sub_field.value
      end
    end
  end

  x.report("implementation") do
    @document.values(data_field: "PPE", sub_field: "p")
  end

  x.compare!
end

