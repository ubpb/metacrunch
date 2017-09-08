describe Metacrunch::Job do

  describe ".define" do

    context "when called with a block" do
      let(:job) do
         Metacrunch::Job.define {}
      end

      it "creates a job" do
        expect(job).to be_a(Metacrunch::Job)
      end
    end

    context "when called with a valid script (a string containing valid ruby code)" do
      let(:job) do
        script = <<-EOT
          require "metacrunch/test_utils"
          source Metacrunch::TestUtils::DummySource.new
          destination Metacrunch::TestUtils::DummyDestination.new
          pre_process ->() { @pre_process_called = true }
          transformation ->(row) { @transformation_called = true }
          post_process ->() { @post_process_called = true }
        EOT

        Metacrunch::Job.define(script)
      end

      it "creates a job" do
        expect(job).to be_a(Metacrunch::Job)
      end
    end

    context "when called with an invalid script (a string containing invalid ruby code)" do
      let(:job) do
        script = <<-EOT
          This is not valid ruby code
        EOT

        Metacrunch::Job.define(script)
      end

      it "throws an exception" do
        expect{job}.to raise_error(SyntaxError)
      end
    end
  end

  describe "#source" do
    context "when no source is defined" do
      let(:job) do
        Metacrunch::Job.define{}.run
      end

      it "returns nil" do
        expect(job.source).to be_nil
      end
    end

    context "when source is defined" do
      let(:job) do
        Metacrunch::Job.define do
          require "metacrunch/test_utils"
          source Metacrunch::TestUtils::DummySource.new
        end.run
      end

      it "returns the source instances" do
        expect(job.source).not_to be_nil
      end
    end
  end

  describe "#source=" do
    let!(:job) { Metacrunch::Job.new }

    context "when called with a valid source object (responds to #each)" do
      it "adds the object as a source" do
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

  describe "#destinations" do
    context "when no destinations are defined" do
      let(:job) do
        Metacrunch::Job.define{}.run
      end

      it "returns an empty array" do
        expect(job.destinations).to eq([])
      end
    end

    context "when destinations are defined" do
      let(:job) do
        Metacrunch::Job.define do
          require "metacrunch/test_utils"
          destination Metacrunch::TestUtils::DummyDestination.new
          destination Metacrunch::TestUtils::DummyDestination.new
        end.run
      end

      it "returns the destination instances" do
        expect(job.destinations.count).to eq(2)
      end
    end
  end

  describe "#add_destination" do
    let!(:job) { Metacrunch::Job.new }

    context "when called with a valid destination object (responds to #write and #close)" do
      it "adds the object as a destination" do
        job.add_destination(Metacrunch::TestUtils::DummyDestination.new)
        expect(job.destinations.count).to eq(1)
      end
    end

    context "when called with an invalid destination object (doesn't responds to #write or #close)" do
      it "raises an error" do
        expect{
          job.add_destination(Metacrunch::TestUtils::InvalidDummyDestination.new)
        }.to raise_error(ArgumentError)
      end
    end
  end

  describe "#pre_processes" do
    context "when no pre processes are defined" do
      let(:job) do
        Metacrunch::Job.define{}.run
      end

      it "returns an empty array" do
        expect(job.pre_processes).to eq([])
      end
    end

    context "when pre processes are defined" do
      let(:job) do
        Metacrunch::Job.define do
          pre_process ->() {}
          pre_process ->() {}
        end.run
      end

      it "returns the pre process instances" do
        expect(job.pre_processes.count).to eq(2)
      end
    end
  end

  describe "#add_pre_process" do
    let!(:job) { Metacrunch::Job.new }

    context "when called with a callable" do
      it "adds the callable as a pre_process" do
        job.add_pre_process(Metacrunch::TestUtils::DummyCallable.new)
        expect(job.pre_processes.count).to eq(1)
      end
    end

    context "when called with a block" do
      it "adds the block as a pre_process" do
        job.add_pre_process do ; end
        expect(job.pre_processes.count).to eq(1)
      end
    end

    context "when called with an object that does't respond to #call" do
      it "raises an error" do
        expect{
          job.add_pre_process(Metacrunch::TestUtils::DummyNonCallable.new)
        }.to raise_error(ArgumentError)
      end
    end
  end

  describe "#post_processes" do
    context "when no post processes are defined" do
      let(:job) do
        Metacrunch::Job.define{}.run
      end

      it "returns an empty array" do
        expect(job.post_processes).to eq([])
      end
    end

    context "when post processes are defined" do
      let(:job) do
        Metacrunch::Job.define do
          post_process ->() {}
          post_process ->() {}
        end.run
      end

      it "returns the post process instances" do
        expect(job.post_processes.count).to eq(2)
      end
    end
  end

  describe "#add_post_process" do
    let!(:job) { Metacrunch::Job.new }

    context "when called with a callable" do
      it "adds the callable as a post_process" do
        job.add_post_process(Metacrunch::TestUtils::DummyCallable.new)
        expect(job.post_processes.count).to eq(1)
      end
    end

    context "when called with a block" do
      it "adds the block as a post_process" do
        job.add_post_process do ; end
        expect(job.post_processes.count).to eq(1)
      end
    end

    context "when called with an object that does't respond to #call" do
      it "raises an error" do
        expect{
          job.add_post_process(Metacrunch::TestUtils::DummyNonCallable.new)
        }.to raise_error(ArgumentError)
      end
    end
  end

  describe "#transformations" do
    context "when no transformations are defined" do
      let(:job) do
        Metacrunch::Job.define{}.run
      end

      it "returns an empty array" do
        expect(job.transformations).to eq([])
      end
    end

    context "when transformations are defined" do
      let(:job) do
        Metacrunch::Job.define do
          transformation ->() {}
          transformation ->() {}
        end.run
      end

      it "returns the transformation instances" do
        expect(job.transformations.count).to eq(2)
      end
    end
  end

  describe "#add_transformation" do
    let!(:job) { Metacrunch::Job.new }

    context "when called with a callable" do
      it "adds the callable as a transformation" do
        job.add_transformation(Metacrunch::TestUtils::DummyCallable.new)
        expect(job.transformations.count).to eq(1)
      end
    end

    context "when called with a block" do
      it "adds the block as a transformation" do
        job.add_transformation do ; end
        expect(job.transformations.count).to eq(1)
      end
    end

    context "when called with an object that does't respond to #call" do
      it "raises an error" do
        expect{
          job.add_transformation(Metacrunch::TestUtils::DummyNonCallable.new)
        }.to raise_error(ArgumentError)
      end
    end
  end

  describe "#run" do
    context "when source is defined" do
      let!(:job) do
        Metacrunch::Job.define do
          require "metacrunch/test_utils"
          source Metacrunch::TestUtils::DummySource.new
          destination Metacrunch::TestUtils::DummyDestination.new
          pre_process ->() { @pre_process_called = true }
          transformation ->(row) { @transformation_called = true }
          post_process ->() { @post_process_called = true }
        end.run
      end

      it "runs pre processes" do
        expect(job.builder.instance_variable_get("@pre_process_called")).to be(true)
      end

      it "runs post processes" do
        expect(job.builder.instance_variable_get("@post_process_called")).to be(true)
      end

      it "runs transformations" do
        expect(job.builder.instance_variable_get("@transformation_called")).to be(true)
      end

      it "writes to a destination" do
        expect(job.destinations.first.instance_variable_get("@write_called")).to be(true)
      end

      it "closes a destination" do
        expect(job.destinations.first.instance_variable_get("@close_called")).to be(true)
      end
    end

    context "when source is not defined" do
      let!(:job) do
        Metacrunch::Job.define do
          destination Metacrunch::TestUtils::DummyDestination.new
          pre_process ->() { @pre_process_called = true }
          transformation ->() { @transformation_called = true }
          post_process ->() { @post_process_called = true }
        end.run
      end

      it "runs pre processes" do
        expect(job.builder.instance_variable_get("@pre_process_called")).to be(true)
      end

      it "runs post processes" do
        expect(job.builder.instance_variable_get("@post_process_called")).to be(true)
      end

      it "does not run transformations" do
        expect(job.builder.instance_variable_get("@transformation_called")).to be_nil
      end

      it "does not run write to a destination" do
        expect(job.destinations.first.instance_variable_get("@write_called")).to be_nil
      end

      it "closes a destination" do
        expect(job.destinations.first.instance_variable_get("@close_called")).to be(true)
      end
    end
  end

end
