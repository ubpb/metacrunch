describe Metacrunch::Mab2::AlephMabXmlDocumentFactory do

  context "with default test xml file" do
    let(:factory) { Metacrunch::Mab2::AlephMabXmlDocumentFactory.new(default_test_xml) }

    describe ".to_document" do
      subject { factory.to_document }

      it "should return a Mab2::Document" do
        expect(subject).to be_instance_of(Metacrunch::Mab2::Document)
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

private

  def default_test_xml
    File.read(File.join(RSpec.root, "assets", "aleph_mab_xml", "file1.xml"))
  end

end
