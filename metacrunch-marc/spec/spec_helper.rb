if ENV["CODECLIMATE_REPO_TOKEN"]
  require "codeclimate-test-reporter"
  CodeClimate::TestReporter.start
else
  require "simplecov"
  SimpleCov.start
end

require "metacrunch/marcxml"

begin
  require "pry"
rescue LoadError
end

RSpec.configure do |config|
  config.expect_with :rspec do |expectations|
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end

  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end
end

# Helper to provide RSpec.root
module ::RSpec
  module_function
  def root
    @spec_root ||= Pathname.new(__dir__)
  end
end

def asset_dir
  File.expand_path(File.join(File.dirname(__FILE__), "assets"))
end

def read_asset(path_to_file)
  File.read(File.expand_path(File.join(asset_dir, path_to_file)))
end

def empty_document
  Metacrunch::Marcxml::Document.new
end

def default_test_document
  document = Metacrunch::Marcxml::Document.new
  document.add_controlfield(create_controlfield("LDR", "01234"))
  document.add_controlfield(create_controlfield("050", "a|a|"))
  document.add_controlfield(create_controlfield("052", ["a", nil, "b"]))

  datafield = create_datafield("001", ind1: "-", ind2: "1")
  datafield.add_subfield(create_subfield("a", "HT12345"))
  document.add_datafield(datafield)

  datafield = create_datafield("100", ind1: "-", ind2: "1")
  datafield.add_subfield(create_subfield("p", "Doe, John"))
  datafield.add_subfield(create_subfield("9", "123456789"))
  document.add_datafield(datafield)

  datafield = create_datafield("100", ind1: "a", ind2: "2")
  datafield.add_subfield(create_subfield("p", "Sprotte, René"))
  datafield.add_subfield(create_subfield("9", "123456789"))
  document.add_datafield(datafield)

  datafield = create_datafield("100", ind1: " ", ind2: "1")
  datafield.add_subfield(create_subfield("p", "Sievers, Michael"))
  datafield.add_subfield(create_subfield("9", "123456789"))
  datafield.add_subfield(create_subfield("x", "123456789"))
  document.add_datafield(datafield)

  datafield = create_datafield("331", ind1: "-", ind2: "1")
  datafield.add_subfield(create_subfield("a", "<<The>> art of MAB processing"))
  document.add_datafield(datafield)

  document
end

def default_test_xml
  File.read(File.join(RSpec.root, "assets", "aleph_mab_xml", "file1.xml"))
end

def create_controlfield(tag, values)
  Metacrunch::Marcxml::Document::Controlfield.new(tag, values)
end

def create_datafield(tag, ind1:nil, ind2:nil)
  Metacrunch::Marcxml::Document::Datafield.new(tag, ind1: ind1, ind2: ind2)
end

def create_subfield(code, value)
  Metacrunch::Marcxml::Document::Subfield.new(code, value)
end
