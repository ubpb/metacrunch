describe Metacrunch::Marcxml::Record::Controlfield do

  let(:field) { Metacrunch::Marcxml::Record::Controlfield.new("001", "123456") }

  describe "#initialize" do
    it "creates a new control field" do
      expect(field).to be_instance_of(Metacrunch::Marcxml::Record::Controlfield)
    end
  end

  describe "#tag" do
    it "returns the tag of the control field" do
      expect(field.tag).to eq("001")
    end
  end

  describe "#value" do
    it "returns the value of the control field" do
      expect(field.value).to eq("123456")
    end
  end

  describe "#to_h" do
    it "returns the value of the control field as hash" do
      expect(field.to_h).to eq({"001" => "123456"})
    end
  end

end
