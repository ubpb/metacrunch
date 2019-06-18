describe Metacrunch::Marcxml::Parser do

  describe "#parse" do
    context "given a valid MarcXML string" do
      subject {
        described_class.new.parse <<-XML
          <datafield tag="001" ind1="-" ind2="-">
            <subfield code="a">&lt;&lt;Some&gt;&gt; HTML Entities: &eacute; &#123; &#x12a;</subfield>
          </datafield>
        XML
      }

      it "should return a Marcxml::Document" do
        expect(subject).to be_instance_of(Metacrunch::Marcxml::Document)
      end

      it "decodes html entities" do
        expect(subject.datafields("001").subfields("a").values.first).to eq("<<Some>> HTML Entities: é { Ī")
      end
    end
  end

end
