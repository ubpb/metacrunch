# frozen_string_literal: true

# The synthetic records of the benchmarks: about 3 KB as MARCXML, 1.2 KB as
# ISO 2709.
def record(number)
  fields = [Metacrunch::Marc::ControlField.new("001", "record-#{number}"),
            Metacrunch::Marc::ControlField.new("005", "20240101120000.0"),
            Metacrunch::Marc::ControlField.new("008", "240101s2024    gw            000 0 eng d")]
  12.times do |index|
    subfields = [["a", "Value #{index} of record #{number} with a few words"], ["b", "Second value"],
                 ["0", "(DE-000)#{number}-#{index}"]]
    fields << Metacrunch::Marc::DataField.new((100 + (index * 60)).to_s, "1", " ", subfields)
  end
  Metacrunch::Marc::Record.new(leader: "00000nam a2200000 c 4500", type: "Bibliographic", fields:)
end
