describe Metacrunch::Mab2::Document::Controlfield do

  describe "#initialize" do
    it "creates a new control field when using String values" do
      field = Metacrunch::Mab2::Document::Controlfield.new("050", "a||b")

      expect(field).to be_instance_of(Metacrunch::Mab2::Document::Controlfield)
      expect(field.tag).to eq("050")
      expect(field.values).to eq(["a", nil, nil, "b"])
    end

    it "creates a new control field when using Array values" do
      field = Metacrunch::Mab2::Document::Controlfield.new("050", ["a", nil, nil, "b"])

      expect(field).to be_instance_of(Metacrunch::Mab2::Document::Controlfield)
      expect(field.tag).to eq("050")
      expect(field.values).to eq(["a", nil, nil, "b"])
    end
  end

  describe "#tag" do
    it "returns the tag of the control field" do
      field = Metacrunch::Mab2::Document::Controlfield.new("050", ["a", nil, nil, "b"])

      expect(field.tag).to eq("050")
    end
  end

  describe "#values=" do
    let(:field) { Metacrunch::Mab2::Document::Controlfield.new("050", nil) }

    it "sets field values using String" do
      field.values = "a||b"
      expect(field.values).to eq(["a", nil, nil, "b"])
    end

    it "sets field values using Array" do
      field.values = ["a", nil, nil, "b"]
      expect(field.values).to eq(["a", nil, nil, "b"])
    end

    it "fails on arrays that contain elements longer than one char" do
      expect{
        field.values = ["a", "bc"]
      }.to raise_error(ArgumentError)
    end

    it "converts array values into String" do
      field.values = [8, nil]
      expect(field.values).to eq(["8", nil])
    end

    it "converts empty string values for arrays into nil" do
      field.values = ["", nil]
      expect(field.values).to eq([nil, nil])
    end

    it "converts nil into empty array" do
      field.values = nil
      expect(field.values).to eq([])
    end
  end

  describe "#values" do
    it "returns the values of a control field" do
      field = Metacrunch::Mab2::Document::Controlfield.new("050", ["a", nil, nil, "b"])

      expect(field.values).to eq(["a", nil, nil, "b"])
    end
  end

  describe "#at" do
    it "returns the value a the given index position" do
      field = Metacrunch::Mab2::Document::Controlfield.new("050", ["a", nil, nil, "b"])

      expect(field.at(0)).to eq("a")
    end

    it "returns nil on non existing value index" do
      field = Metacrunch::Mab2::Document::Controlfield.new("050", ["a", nil, nil, "b"])

      expect(field.at(999)).to be_nil
    end
  end

end
