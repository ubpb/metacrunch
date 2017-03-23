describe Metacrunch::Marcxml do

  # -----------------------------------------------------------------------
  # Parsing
  # -----------------------------------------------------------------------

  describe ".parse, ()" do
    let(:xml) { default_test_xml }

    it "should return a Marcxml::Document" do
      document = Metacrunch::Marcxml.parse(xml)
      expect(document).to be_instance_of(Metacrunch::Marcxml::Document)

      document = Metacrunch::Marcxml(xml)
      expect(document).to be_instance_of(Metacrunch::Marcxml::Document)
    end
  end

end
