describe Metacrunch::Mab2::Document::Subfield do

  describe "#initialize" do
    it "creates a new sub field" do
      field = Metacrunch::Mab2::Document::Subfield.new("a", "Lorem Ipsum")

      expect(field).to be_instance_of(Metacrunch::Mab2::Document::Subfield)
      expect(field.code).to eq("a")
      expect(field.value).to eq("Lorem Ipsum")
    end
  end

end
