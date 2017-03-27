describe Metacrunch::Marcxml::Document::SubfieldSet do

  let(:document) { default_test_document }
  let(:datafield) { document.datafields.first }
  let(:subfields) { datafield.subfields.to_a }
  let(:set) { Metacrunch::Marcxml::Document::SubfieldSet.new(subfields) }
  let(:empty_set) { Metacrunch::Marcxml::Document::SubfieldSet.new(nil) }

  it "includes Enumerable module" do
    expect(set).to be_kind_of(Enumerable)
  end

  describe "#initialize" do
    it "creates a new sub field set" do
      expect(set).to be_instance_of(Metacrunch::Marcxml::Document::SubfieldSet)
      expect(empty_set).to be_instance_of(Metacrunch::Marcxml::Document::SubfieldSet)
    end
  end

  describe "#each" do
    it "returns an enumerator for the sub fields" do
      expect(set.each).to be_instance_of(Enumerator)
    end
  end

  describe "#to_a" do
    it "returns the sub fields as array" do
      expect(set.to_a).to be_instance_of(Array)
    end
  end

  describe "#empty?" do
    context "given no sub fields" do
      it "returns true" do
        expect(empty_set.empty?).to be(true)
      end
    end

    context "given sub fields" do
      it "returns false" do
        expect(set.empty?).to be(false)
      end
    end
  end

  describe "#present?" do
    context "given no sub fields" do
      it "returns false" do
        expect(empty_set.present?).to be(false)
      end
    end

    context "given sub fields" do
      it "returns true" do
        expect(set.present?).to be(true)
      end
    end
  end

  describe "#values" do
    let(:set) do
      Metacrunch::Marcxml::Document::SubfieldSet.new([
        create_subfield("1", ""),
        create_subfield("2", " "),
        create_subfield("3", nil),
        create_subfield("4", "Foo"),
        create_subfield("5", "Bar")
      ])
    end

    it "returns the value of each sub field as an array" do
      expect(set.values).to be_instance_of(Array)
      expect(set.values).not_to be_empty
      expect(set.values).to eq(["", " ", nil, "Foo", "Bar"])
    end
  end

  describe "#present_values" do
    let(:set) do
      Metacrunch::Marcxml::Document::SubfieldSet.new([
        create_subfield("1", ""),
        create_subfield("2", " "),
        create_subfield("3", nil),
        create_subfield("4", "Foo"),
        create_subfield("5", "Bar")
      ])
    end

    it "returns only the non nil and non empty value of each sub field as an array" do
      expect(set.present_values).to be_instance_of(Array)
      expect(set.present_values).not_to be_empty
      expect(set.present_values).to eq(["Foo", "Bar"])
    end
  end

  describe "#first_value" do
    let(:set) do
      Metacrunch::Marcxml::Document::SubfieldSet.new([
        create_subfield("1", ""),
        create_subfield("2", " "),
        create_subfield("3", nil),
        create_subfield("4", "Foo"),
        create_subfield("5", "Bar")
      ])
    end

    it "returns the first non empty value" do
      expect(set.first_value).to eq("Foo")
    end
  end

end
