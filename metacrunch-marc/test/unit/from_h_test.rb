# frozen_string_literal: true

require "test_helper"

class FromHTest < Minitest::Test

  Marc = Metacrunch::Marc
  Record = Metacrunch::Marc::Record
  ControlField = Metacrunch::Marc::ControlField
  DataField = Metacrunch::Marc::DataField

  # Shapes that from_h refuses, and its messages.
  REFUSED = [
    ["x", %(a record must be a Hash, got "x")],
    [{fields: []}, %(unknown key :fields; a record has "leader" and "fields")],
    [{"fields" => [], "x" => 1}, %(unknown key "x"; a record has "leader" and "fields")],
    [{}, %(a record needs "fields")],
    [{"fields" => {}}, "fields: must be an Array, got {}"],
    [{"leader" => 5, "fields" => []}, "leader: a value must be a String, got 5"],
    [{"fields" => [12]}, "fields[0]: a field must be an object with one key, its tag, got 12"],
    [{"fields" => [{"001" => "1", "002" => "2"}]},
     %(fields[0]: a field must be an object with one key, its tag, got {"001" => "1", "002" => "2"})],
    [{"fields" => [{"001": "1"}]}, %(fields[0]: a tag must be a String, got :"001")],
    [{"fields" => [{"001" => 1}]},
     "fields[0] (001): a field must be a String (a control field) or an object (a data field), got 1"],
    [{"fields" => [{"245" => {"x" => 1, "subfields" => []}}]},
     %(fields[0] (245): unknown key "x"; a data field has "ind1", "ind2" and "subfields")],
    [{"fields" => [{"245" => {"ind1" => "1"}}]}, %(fields[0] (245): a data field needs "subfields")],
    [{"fields" => [{"245" => {"subfields" => 3}}]}, "fields[0] (245) subfields: must be an Array, got 3"],
    [{"fields" => [{"245" => {"ind1" => 1, "subfields" => []}}]},
     "fields[0] (245) ind1: an indicator must be a String, got 1"],
    [{"fields" => [{"245" => {"subfields" => [{"a" => "x", "b" => "y"}]}}]},
     "fields[0] (245) subfields[0]: a subfield must be an object with one key, its code, " \
     "got {\"a\" => \"x\", \"b\" => \"y\"}"],
    [{"fields" => [{"245" => {"subfields" => [{a: "x"}]}}]},
     "fields[0] (245) subfields[0]: a code must be a String, got :a"],
    [{"fields" => [{"245" => {"subfields" => [{"a" => 12}]}}]},
     "fields[0] (245) subfields[0]: a value must be a String, got 12"],
    [{"fields" => [{"245" => {"subfields" => [{"a" => "x\u0001"}]}}]},
     %(fields[0] (245) subfields[0]: "\\u0001" cannot be represented in XML 1.0)],
    [{"fields" => [{"24\u0001" => "x"}]}, %(fields[0]: "\\u0001" cannot be represented in XML 1.0)]
  ].freeze

  def test_builds_what_to_h_returns
    record = Record.new(leader: "00000nam a2200000 c 4500",
                        fields: [ControlField.new("001", "1"), DataField.new("245", "1", "0", [["a", "T"]]),
                                 DataField.new("500", " ", " ")])

    assert_equal record, Record.from_h(record.to_h)
  end

  def test_the_leader_may_be_missing_or_null
    assert_nil Record.from_h({"fields" => [{"001" => "1"}]}).leader
    assert_nil Record.from_h({"leader" => nil, "fields" => []}).leader
  end

  def test_missing_and_null_indicators_are_blank
    record = Record.from_h({"fields" => [{"245" => {"subfields" => [{"a" => "x"}]}},
                                         {"246" => {"ind1" => nil, "ind2" => "1", "subfields" => []}}]})

    assert_equal [" ", " "], [record["245"].ind1, record["245"].ind2]
    assert_equal [" ", "1"], [record["246"].ind1, record["246"].ind2]
  end

  def test_normalize
    assert_equal "Müller", Record.from_h({"fields" => [{"001" => "Mu\u0308ller"}]}, normalize: :nfc)["001"].value
  end

  def test_takes_other_encodings
    assert_equal "Müller", Record.from_h({"fields" => [{"001" => "Müller".encode("ISO-8859-1")}]})["001"].value
  end

  def test_refuses_other_shapes_with_the_path
    REFUSED.each do |hash, message|
      error = assert_raises(Marc::ParseError, hash.inspect) { Record.from_h(hash) }

      assert_equal message, error.message
    end
  end

  def test_rejects_invalid_arguments
    assert_raises(ArgumentError) { Record.from_h({"fields" => []}, normalize: :nfd) }
  end

end
