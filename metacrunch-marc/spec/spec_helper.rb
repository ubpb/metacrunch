require "pry" if !ENV["CI"]

require "simplecov"
SimpleCov.start do
  add_filter %r{^/spec/}
end

require "metacrunch/marcxml"

RSpec.configure do |config|
end

# Helper to provide RSpec.root
module ::RSpec
  module_function
  def root
    @spec_root ||= Pathname.new(__dir__)
  end
end

def empty_record
  Metacrunch::Marcxml::Record.new
end

def default_test_record
  record = Metacrunch::Marcxml::Record.new
  record.set_leader(create_leader("123456"))

  record.add_controlfield(create_controlfield("LDR", "01234"))
  record.add_controlfield(create_controlfield("050", "a|a|"))
  record.add_controlfield(create_controlfield("052", ["a", nil, "b"]))

  datafield = create_datafield("001", ind1: "-", ind2: "1")
  datafield.add_subfield(create_subfield("a", "HT12345"))
  record.add_datafield(datafield)

  datafield = create_datafield("100", ind1: "-", ind2: "1")
  datafield.add_subfield(create_subfield("p", "Doe, John"))
  datafield.add_subfield(create_subfield("9", "123456789"))
  record.add_datafield(datafield)

  datafield = create_datafield("100", ind1: "a", ind2: "2")
  datafield.add_subfield(create_subfield("p", "Sprotte, René"))
  datafield.add_subfield(create_subfield("9", "123456789"))
  record.add_datafield(datafield)

  datafield = create_datafield("100", ind1: " ", ind2: "1")
  datafield.add_subfield(create_subfield("p", "Sievers, Michael"))
  datafield.add_subfield(create_subfield("9", "123456789"))
  datafield.add_subfield(create_subfield("x", "123456789"))
  record.add_datafield(datafield)

  datafield = create_datafield("331", ind1: "-", ind2: "1")
  datafield.add_subfield(create_subfield("a", "<<The>> art of MAB processing"))
  record.add_datafield(datafield)

  record
end

def create_leader(value)
  Metacrunch::Marcxml::Record::Leader.new(value)
end

def create_controlfield(tag, values)
  Metacrunch::Marcxml::Record::Controlfield.new(tag, values)
end

def create_datafield(tag, ind1:nil, ind2:nil)
  Metacrunch::Marcxml::Record::Datafield.new(tag, ind1: ind1, ind2: ind2)
end

def create_subfield(code, value)
  Metacrunch::Marcxml::Record::Subfield.new(code, value)
end
