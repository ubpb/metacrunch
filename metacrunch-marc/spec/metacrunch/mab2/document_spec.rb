describe Metacrunch::Mab2::Document do

  describe ".from_aleph_mab_xml" do
    let(:xml) { default_test_xml }
    let(:document) { Metacrunch::Mab2::Document.from_aleph_mab_xml(xml) }

    subject { document }

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

  describe "#add_controlfield" do
    let(:document) { empty_document }

    it "should add control fields" do
      document.add_controlfield(create_controlfield("001", "a|a|"))
      expect(document.controlfield("001").values).to eq(["a", nil, "a", nil])
    end
  end

  describe "#controlfield" do
    let(:document) { default_test_document }
    subject { document.controlfield("050") }

    it { is_expected.not_to be_nil }
    it { is_expected.to be_instance_of(Metacrunch::Mab2::Document::Controlfield) }
    it "should contain the correct values" do
      expect(subject.values).to eq(["a", nil, "a", nil])
    end
  end

  describe "#datafields" do
    let(:document) { default_test_document }

    context "given tag=100" do
      subject { document.datafields("100") }

      it "returns only datafields with tag=100" do
        expect(subject.count).to eq(3)
      end
    end

    context "given tag=100 and ind1=-" do
      subject { document.datafields("100", ind1: "-") }

      it "returns only datafields with tag=100 and ind1=-" do
        expect(subject.count).to eq(1)
      end
    end

    context "given tag=100 and ind2=2" do
      subject { document.datafields("100", ind2: "2") }

      it "returns only datafields with tag=100 and ind2=2" do
        expect(subject.count).to eq(1)
      end
    end

    context "given tag=100 and ind1=a and ind2=2" do
      subject { document.datafields("100", ind2: "2") }

      it "returns only datafields with tag=100 and ind1=a and ind2=2" do
        expect(subject.count).to eq(1)
      end
    end

    context "given tag=100 and ind1=:blank" do
      subject { document.datafields("100", ind1: :blank) }

      it "returns only datafields with tag=100 and ind1=' ' or ind1=-" do
        expect(subject.count).to eq(2)
      end
    end

    context "given tag=100 and ind1=[:blank, 'a']" do
      subject { document.datafields("100", ind1: [:blank, "a"]) }

      it "returns only datafield with tag=100 and ind1=(:blank || 'a')" do
        expect(subject.count).to eq(3)
      end
    end
  end

private

  def empty_document
    Metacrunch::Mab2::Document.new
  end

  def default_test_document
    document = Metacrunch::Mab2::Document.new
    document.add_controlfield(create_controlfield("LDR", "01234"))
    document.add_controlfield(create_controlfield("050", "a|a|"))
    document.add_controlfield(create_controlfield("052", ["a", nil, "b"]))

    datafield = create_datafield("100", ind1: "-", ind2: "1")
    datafield.add_subfield(create_subfield("p", "Doe, John"))
    datafield.add_subfield(create_subfield("9", "123456789"))
    document.add_datafield(datafield)

    datafield = create_datafield("100", ind1: "a", ind2: "2")
    datafield.add_subfield(create_subfield("p", "Sprotte, René"))
    datafield.add_subfield(create_subfield("9", "123456789"))
    document.add_datafield(datafield)

    datafield = create_datafield("100", ind1: " ", ind2: "1")
    datafield.add_subfield(create_subfield("p", "Sievers, Michael"))
    datafield.add_subfield(create_subfield("9", "123456789"))
    document.add_datafield(datafield)

    datafield = create_datafield("331", ind1: "-", ind2: "1")
    datafield.add_subfield(create_subfield("a", "<<The>> art of MAB processing"))
    document.add_datafield(datafield)

    document
  end

  def default_test_xml
    File.read(File.join(RSpec.root, "assets", "aleph_mab_xml", "file1.xml"))
  end

  def create_controlfield(tag, values)
    Metacrunch::Mab2::Document::Controlfield.new(tag, values)
  end

  def create_datafield(tag, ind1:nil, ind2:nil)
    Metacrunch::Mab2::Document::Datafield.new(tag, ind1: ind1, ind2: ind2)
  end

  def create_subfield(code, value)
    Metacrunch::Mab2::Document::Subfield.new(code, value)
  end

end
