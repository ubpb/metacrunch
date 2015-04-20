describe Metacrunch::Mab2::Document::ControlField do

  describe ".initialize" do
    it "creates a new control field when using String values" do
      field = Metacrunch::Mab2::Document::ControlField.new("050", "a||b")
      expect(field.name).to eq("050")
      expect(field.values).to eq(["a", nil, nil, "b"])
    end

    it "creates a new control field when using Array values" do
      field = Metacrunch::Mab2::Document::ControlField.new("050", ["a", nil, nil, "b"])
      expect(field.name).to eq("050")
      expect(field.values).to eq(["a", nil, nil, "b"])
    end

    it "raises error if name is blank" do
      expect {
        Metacrunch::Mab2::Document::ControlField.new(nil, ["a", nil, nil, "b"])
      }.to raise_error(ArgumentError)

      expect {
        Metacrunch::Mab2::Document::ControlField.new("", ["a", nil, nil, "b"])
      }.to raise_error(ArgumentError)
    end
  end

  describe ".values=" do
    let(:field) { Metacrunch::Mab2::Document::ControlField.new("050", nil) }

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
end
