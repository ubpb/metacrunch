describe Metacrunch::Mab2::Document::DatafieldSet do

  let(:document) { default_test_document }
  let(:datafields) { document.datafields.to_a }
  let(:set) { Metacrunch::Mab2::Document::DatafieldSet.new(datafields) }
  let(:empty_set) { Metacrunch::Mab2::Document::DatafieldSet.new(nil) }

  it "includes Enumerable module" do
    expect(set).to be_kind_of(Enumerable)
  end

  describe "#initialize" do
    it "creates a new data field set" do
      expect(set).to be_instance_of(Metacrunch::Mab2::Document::DatafieldSet)
      expect(empty_set).to be_instance_of(Metacrunch::Mab2::Document::DatafieldSet)
    end
  end

  describe "#each" do
    it "returns an enumerator for the data fields" do
      expect(set.each).to be_instance_of(Enumerator)
    end
  end

  describe "#to_a" do
    it "returns the data fields as array" do
      expect(set.to_a).to be_instance_of(Array)
    end
  end

  describe "#empty?" do
    context "given no data fields" do
      it "returns true" do
        expect(empty_set.empty?).to be(true)
      end
    end

    context "given data fields" do
      it "returns false" do
        expect(set.empty?).to be(false)
      end
    end
  end

  describe "#present?" do
    context "given no data fields" do
      it "returns false" do
        expect(empty_set.present?).to be(false)
      end
    end

    context "given data fields" do
      it "returns true" do
        expect(set.present?).to be(true)
      end
    end
  end

  describe "#subfields" do
    context "given code=nil" do
      subject { set.subfields(nil) }

      it "returns a SubfieldSet" do
        expect(subject).to be_instance_of(Metacrunch::Mab2::Document::SubfieldSet)
      end

      it "SubfieldSet contains all sub fields" do
        expect(subject.count).to eq(set.instance_variable_get("@datafields").map{|f| f.subfields.count}.sum)
      end
    end

    context "given non existing code" do
      subject { set.subfields("_not_existing_code_") }

      it "returns a SubfieldSet" do
        expect(subject).to be_instance_of(Metacrunch::Mab2::Document::SubfieldSet)
      end

      it "SubfieldSet is empty" do
        expect(subject.empty?).to be(true)
      end
    end

    context "given code=p" do
      subject { set.subfields("p") }

      it "returns only sub fields with code=p" do
        expect(subject.all?{|f| f.code=="p"}).to be(true)
      end
    end

    context "given code=p and code=9" do
      subject { set.subfields(["p", "9"]) }

      it "returns only sub fields with code=p or code=9" do
        expect(subject.all?{|f| f.code=="p" || f.code=="9"}).to be(true)
      end
    end
  end

end
