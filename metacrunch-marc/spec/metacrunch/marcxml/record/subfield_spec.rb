describe Metacrunch::Marcxml::Record::Subfield do

  let(:field) { field = Metacrunch::Marcxml::Record::Subfield.new("a", "Lorem Ipsum") }

  describe "#initialize" do
    it "creates a new sub field" do
      expect(field).to be_instance_of(Metacrunch::Marcxml::Record::Subfield)
      expect(field.code).to eq("a")
      expect(field.value).to eq("Lorem Ipsum")
    end
  end

  describe "#to_h" do
    it "returns the value of the sub field as hash" do
      expect(field.to_h).to eq({"a" => "Lorem Ipsum"})
    end
  end

end
