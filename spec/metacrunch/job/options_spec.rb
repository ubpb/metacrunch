describe Metacrunch::Job::Dsl::Options do
  describe "#new" do

    context "when given an unknown options" do
      it "shows error and exit" do
        expect {
          expect { described_class.new(["--foo"]) do ; end }.to raise_error(SystemExit)
        }.to output(/Error/).to_stdout
      end
    end

    context "when a required option is missing" do
      it "shows error and exit" do
        expect {
          expect {
            described_class.new([]) do
              add(:foo, "-f", "--foo STRING", "Foo option", String, required: true)
            end
          }.to raise_error(SystemExit)
        }.to output(/Error/).to_stdout
      end
    end

    context "when a default option value is missing" do
      it "option has default value" do
        options = described_class.new([]) do
          add(:foo, "-f", "--foo STRING", "Foo option", String, default: "foo")
        end

        expect(options.options[:foo]).to eq("foo")
      end
    end

    context "when a default option value is given" do
      it "option has given value" do
        options = described_class.new(["-f", "bar"]) do
          add(:foo, "-f", "--foo STRING", "Foo option", String, default: "foo")
        end

        expect(options.options[:foo]).to eq("bar")
      end
    end

    context "when non-option arguments are required but none was given" do
      it "shows error and exit" do
        expect {
          expect {
            described_class.new([], require_args: true) do ; end
          }.to raise_error(SystemExit)
        }.to output(/Error/).to_stdout
      end
    end

  end
end
