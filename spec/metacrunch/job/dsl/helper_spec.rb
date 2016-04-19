describe Metacrunch::Job::Dsl::Helper do

  describe "#buffer" do
    subject { Metacrunch::Job::Dsl::Helper.new }

    it "buffers data up to buffer size" do
      expect(subject.buffer(:some_id, {foo: "foo"}, size: 3)).to be_nil
      expect(subject.buffer(:some_id, {foo: "foo"}, size: 3)).to be_nil
      expect(subject.buffer(:some_id, {foo: "foo"}, size: 3)).to eq([{foo: "foo"}, {foo: "foo"}, {foo: "foo"}])
      expect(subject.instance_variable_get("@buffers")[:some_id]).to eq([])
    end
  end

end
