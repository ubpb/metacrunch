describe Metacrunch::Job::Dsl::Options::Dsl do

  describe "#add" do
    let(:dsl) { described_class.new }

    context "when default and required options are present" do
      it "raises an error" do
        expect {
          dsl.add("foo", nil, default: "bar", required: true)
          }.to raise_error(ArgumentError)
      end
    end
  end

end
