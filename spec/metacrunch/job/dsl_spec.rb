describe Metacrunch::Job::Dsl do

  let!(:job) { Metacrunch::Job.new }
  subject { Metacrunch::Job::Dsl.new(job) }

  describe "#source" do
    context "when called with a valid source object (responds to #each)" do
      it "set the object as a source" do
        source = Metacrunch::TestUtils::DummySource.new
        job.source = source
        expect(job.source).to eq(source)
      end
    end

    context "when called with an invalid source object (doesn't responds to #each)" do
      it "raises an error" do
        expect{
          job.source = Metacrunch::TestUtils::InvalidDummySource.new
        }.to raise_error(ArgumentError)
      end
    end
  end

  describe "#destination" do
    context "when called with a valid destination object (responds to #write and #close)" do
      it "adds the object as a destination" do
        destination = Metacrunch::TestUtils::DummyDestination.new
        job.destination = destination
        expect(job.destination).to eq(destination)
      end
    end

    context "when called with an invalid destination object (doesn't responds to #write or #close)" do
      it "raises an error" do
        expect{
          job.destination = Metacrunch::TestUtils::InvalidDummyDestination.new
        }.to raise_error(ArgumentError)
      end
    end
  end

  describe "#pre_process" do
    context "when called with a callable" do
      it "sets the callable as a pre_process" do
        pre_process = Metacrunch::TestUtils::DummyCallable.new
        job.pre_process = pre_process
        expect(job.pre_process).to eq(pre_process)
      end
    end

    context "when called with an object that doesn't respond to #call" do
      it "raises an error" do
        expect{
          job.pre_process = Metacrunch::TestUtils::DummyNonCallable.new
        }.to raise_error(ArgumentError)
      end
    end
  end

  describe "#post_process" do
    context "when called with a callable" do
      it "sets the callable as a post_process" do
        post_process = Metacrunch::TestUtils::DummyCallable.new
        job.post_process = post_process
        expect(job.post_process).to eq(post_process)
      end
    end

    context "when called with an object that doesn't respond to #call" do
      it "raises an error" do
        expect{
          job.post_process = Metacrunch::TestUtils::DummyNonCallable.new
        }.to raise_error(ArgumentError)
      end
    end
  end

  describe "transformation" do
    context "when called with a callable" do
      it "adds the callable as a transformation" do
        job.add_transformation(Metacrunch::TestUtils::DummyCallable.new)
        expect(job.transformations.count).to eq(1)
      end
    end

    context "when called with an object that doesn't respond to #call" do
      it "raises an error" do
        expect{
          job.add_transformation(Metacrunch::TestUtils::DummyNonCallable.new)
        }.to raise_error(ArgumentError)
      end
    end
  end

  describe "options" do
    context "when called with a block" do
      it "registers the options" do
        subject.options do
          add :foo, "-f", "--foo VALUE", default: "foo"
        end

        expect(subject.options[:foo]).to eq("foo")
      end

      context "when args are present on the job object" do
        it "they override option values" do
          job.instance_variable_set("@args", ["-f", "bar"])
          subject.options do
            add :foo, "-f", "--foo VALUE", default: "foo"
          end

          expect(subject.options[:foo]).to eq("bar")
        end
      end
    end

    context "when called without a block" do
      before do
        subject.options do
          add :foo, default: "foo"
        end
      end

      it "returns defined options" do
        expect(subject.options.count).to be(1)
        expect(subject.options[:foo]).to eq("foo")
      end
    end
  end

end
