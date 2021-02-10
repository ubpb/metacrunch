describe Metacrunch::Marcxml::Record::Datafield do

  describe "#initialize" do
    it "creates a new data field" do
      field = Metacrunch::Marcxml::Record::Datafield.new("123", ind1: "1", ind2: nil)

      expect(field).to be_instance_of(Metacrunch::Marcxml::Record::Datafield)
      expect(field.tag).to eq("123")
      expect(field.ind1).to eq("1")
      expect(field.ind2).to be_nil
    end
  end

  describe "#subfields" do
    let(:record) { default_test_record }
    let(:datafield) { record.datafields("100").first }

    context "given code=nil" do
      subject { datafield.subfields(nil) }

      it "returns sub fields" do
        expect(subject).to be_instance_of(Array)
        expect(subject.first).to be_instance_of(Metacrunch::Marcxml::Record::Subfield)
      end

      it "SubfieldfieldSet contains all sub fields" do
        expect(subject.count).to eq(datafield.instance_variable_get("@subfields_map").values.flatten(1).count)
      end
    end

    context "given non existing code" do
      subject { datafield.subfields("_not_existing_code_") }

      it "returns empty array" do
        expect(subject).to be_instance_of(Array)
        expect(subject.empty?).to be(true)
      end
    end

    context "given code=p" do
      subject { datafield.subfields("p") }

      it "returns only sub fields with code=p" do
        expect(subject.all?{|f| f.code=="p"}).to be(true)
      end
    end

    context "given code=p and code=9" do
      subject { datafield.subfields(["p", "9"]) }

      it "returns only sub fields with code=p or code=9" do
        expect(subject.all?{|f| f.code=="p" || f.code=="9"}).to be(true)
      end
    end
  end

  describe "#add_subfield" do
    let(:record) { empty_record }
    let(:datafield) { record.add_datafield(create_datafield("123", ind1: "a", ind2: nil)) }

    it "should add sub field" do
      expect(datafield.subfields("a").count).to eq(0)
      datafield.add_subfield(create_subfield("a", "Lorem Ipsum"))
      expect(datafield.subfields("a").count).to eq(1)
    end
  end

end
