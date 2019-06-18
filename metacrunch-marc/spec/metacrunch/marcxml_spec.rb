describe Metacrunch::Marcxml do

  let(:xml) { <<-XML
    <datafield tag="001" ind1="-" ind2="-">
      <subfield code="a">some value</subfield>
    </datafield>
    XML
  }

  describe ".parse" do
    subject { Metacrunch::Marcxml.parse(xml) }
    it "should return a `Metacrunch::Marcxml::Document`" do
      expect(subject).to be_instance_of(Metacrunch::Marcxml::Document)
    end
  end

  describe ".()" do
    subject { Metacrunch::Marcxml(xml) }
    it "should return a `Metacrunch::Marcxml::Document`" do
      expect(subject).to be_instance_of(Metacrunch::Marcxml::Document)
    end
  end

end
