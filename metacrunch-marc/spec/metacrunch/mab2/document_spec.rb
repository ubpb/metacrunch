describe Metacrunch::Mab2::Document do

  # -----------------------------------------------------------------------
  # Parsing
  # -----------------------------------------------------------------------

  describe ".from_mab_xml" do
    let(:xml) { default_test_xml }
    let(:document) { Metacrunch::Mab2::Document.from_mab_xml(xml) }

    subject { document }

    it "should return a Mab2::Document" do
      expect(subject).to be_instance_of(Metacrunch::Mab2::Document)
    end
  end

  # -----------------------------------------------------------------------
  # Controlfields
  # -----------------------------------------------------------------------

  describe "#controlfield" do
    let(:document) { default_test_document }

    context "given nil tag" do
      subject { document.controlfield(nil) }

      it { is_expected.to be_nil }
    end

    context "given non-existing tag" do
      subject { document.controlfield("666") }

      it { is_expected.to be_nil }
    end

    context "given existing tag" do
      subject { document.controlfield("050") }

      it { is_expected.not_to be_nil }
      it { is_expected.to be_instance_of(Metacrunch::Mab2::Document::Controlfield) }
      it "should contain the correct values" do
        expect(subject.values).to eq(["a", nil, "a", nil])
      end
    end
  end

  describe "#add_controlfield" do
    let(:document) { empty_document }

    it "should add control field" do
      document.add_controlfield(create_controlfield("001", "a|a|"))
      expect(document.controlfield("001").values).to eq(["a", nil, "a", nil])
    end
  end

  # -----------------------------------------------------------------------
  # Datafields
  # -----------------------------------------------------------------------

  describe "#datafields" do
    let(:document) { default_test_document }

    context "given tag=nil" do
      subject { document.datafields(nil) }

      it "returns a DatafieldSet" do
        expect(subject).to be_instance_of(Metacrunch::Mab2::Document::DatafieldSet)
      end

      it "DatafieldSet contains all datafields" do
        expect(subject.count).to eq(document.instance_variable_get("@datafields_map").values.flatten(1).count)
      end
    end

    context "given non existing tag" do
      subject { document.datafields("_not_existing_tag_") }

      it "returns a DatafieldSet" do
        expect(subject).to be_instance_of(Metacrunch::Mab2::Document::DatafieldSet)
      end

      it "DatafieldSet is empty" do
        expect(subject.empty?).to be(true)
      end
    end

    context "given tag=100" do
      subject { document.datafields("100") }

      it "returns only datafields with tag=100" do
        expect(subject.all?{|f| f.tag=="100"}).to be(true)
      end
    end

    context "given tag=100 and tag=331" do
      subject { document.datafields(["100", "331"]) }

      it "returns only datafields with tag=100 or tag=331" do
        expect(subject.all?{|f| f.tag=="100" || f.tag=="331"}).to be(true)
      end
    end

    context "given tag=100 and ind1=-" do
      subject { document.datafields("100", ind1: "-") }

      it "returns only datafields with tag=100 and ind1=-" do
        expect(subject.all?{|f| f.tag=="100" || f.ind1=="-"}).to be(true)
      end
    end

    context "given tag=100 and ind2=2" do
      subject { document.datafields("100", ind2: "2") }

      it "returns only datafields with tag=100 and ind2=2" do
        expect(subject.all?{|f| f.tag=="100" || f.ind2=="2"}).to be(true)
      end
    end

    context "given tag=100 and ind1=a and ind2=2" do
      subject { document.datafields("100", ind2: "2") }

      it "returns only datafields with tag=100 and ind1=a and ind2=2" do
        expect(subject.all?{|f| f.tag=="100" || f.ind1=="a" || f.ind2=="2"}).to be(true)
      end
    end

    context "given tag=100 and ind1=:blank" do
      subject { document.datafields("100", ind1: :blank) }

      it "returns only datafields with tag=100 and ind1=' ' or ind1=-" do
        expect(subject.all?{|f| f.tag=="100" || f.ind1==" " || f.ind1=="-"}).to be(true)
      end
    end

    context "given tag=100 and ind1=[:blank, 'a']" do
      subject { document.datafields("100", ind1: [:blank, "a"]) }

      it "returns only datafield with tag=100 and ind1=(:blank || 'a')" do
        expect(subject.all?{|f| f.tag=="100" || f.ind1==" " || f.ind1=="-" || f.ind1=="a"}).to be(true)
      end
    end
  end

  describe "#add_datafield" do
    let(:document) { empty_document }

    it "should add data field" do
      expect(document.datafields("123").count).to eq(0)
      document.add_datafield(create_datafield("123", ind1: "a", ind2: nil))
      expect(document.datafields("123").count).to eq(1)
    end
  end

end
