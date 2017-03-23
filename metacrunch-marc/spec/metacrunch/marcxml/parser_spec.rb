describe Metacrunch::Marcxml::Parser do

  describe "#parse" do
    context "given a valid mab xml demo file" do
      let(:xml) { default_test_xml }
      let(:document) { Metacrunch::Marcxml.parse(xml) }

      subject { document }

      it "should return a Marcxml::Document" do
        expect(subject).to be_instance_of(Metacrunch::Marcxml::Document)
      end

      it "should find 2 data fields with tag 070" do
        expect(subject.datafields("070").count).to be(2)
      end

      it "should find 1 data field with tag 100" do
        expect(subject.datafields("100").first).not_to be_nil
      end

      it "sub field p of data field 100 is not nil" do
        expect(subject.datafields("100").first.subfields("p").first.value).not_to be_nil
      end

      it "decodes html entities" do
        expect(subject.datafields("331").subfields("a").values.first).to eq("<<Das>> Linux für Studenten")
      end
    end
  end

end
