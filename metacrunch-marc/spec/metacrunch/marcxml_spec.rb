describe Metacrunch::Marcxml do

  let(:xml) { <<-XML
    <record>
      <datafield tag="001" ind1="-" ind2="-">
        <subfield code="a">some value</subfield>
      </datafield>
    </record>
    XML
  }

  let(:collection_xml) { <<-XML
    <collection>
      <record>
        <datafield tag="001" ind1="-" ind2="-">
          <subfield code="a">some value</subfield>
        </datafield>
      </record>
      <record>
        <datafield tag="001" ind1="-" ind2="-">
          <subfield code="a">some other value</subfield>
        </datafield>
      </record>
    </collection>
    XML
  }

  context "collection_mode = false" do
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

    describe ".[]" do
      subject { Metacrunch::Marcxml[xml] }
      it "should return a `Metacrunch::Marcxml::Document`" do
        expect(subject).to be_instance_of(Metacrunch::Marcxml::Document)
      end
    end
  end

  context "collection_mode = true" do
    describe ".parse" do
      subject { Metacrunch::Marcxml.parse(collection_xml, collection_mode: true) }
      it "should return a `Metacrunch::Marcxml::Document`" do
        expect(subject).to be_instance_of(Array)
        expect(subject.first).to be_instance_of(Metacrunch::Marcxml::Document)
        expect(subject.count).to eq(2)
      end
    end

    describe ".()" do
      subject { Metacrunch::Marcxml(collection_xml, collection_mode: true) }
      it "should return a `Metacrunch::Marcxml::Document`" do
        expect(subject).to be_instance_of(Array)
        expect(subject.first).to be_instance_of(Metacrunch::Marcxml::Document)
        expect(subject.count).to eq(2)
      end
    end

    describe ".[]" do
      subject { Metacrunch::Marcxml[collection_xml] }
      it "should return a `Metacrunch::Marcxml::Document`" do
        expect(subject).to be_instance_of(Metacrunch::Marcxml::Document)
      end
    end
  end

end
