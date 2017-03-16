describe Metacrunch::Marcxml::Document::Controlfield do

  describe "#initialize" do
    it "creates a new control field" do
      field = Metacrunch::Marcxml::Document::Controlfield.new("008", "061215s2007    gw ||||| |||| 00||||ger  ")
      expect(field).to be_instance_of(Metacrunch::Marcxml::Document::Controlfield)
    end
  end

  describe "#tag" do
    it "returns the tag of the control field" do
      field = Metacrunch::Marcxml::Document::Controlfield.new("008", "061215s2007    gw ||||| |||| 00||||ger  ")
      expect(field.tag).to eq("008")
    end
  end

  describe "#value" do
    it "returns the value of the control field" do
      field = Metacrunch::Marcxml::Document::Controlfield.new("008", "061215s2007    gw ||||| |||| 00||||ger  ")
      expect(field.value).to eq("061215s2007    gw ||||| |||| 00||||ger  ")
    end
  end

end
