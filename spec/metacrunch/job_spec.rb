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

  describe "#destination" do
    context "when no destination is defined" do
      let(:job) do
        Metacrunch::Job.define{}.run
      end

      it "returns an empty array" do
        expect(job.destination).to be_nil
      end
    end

    context "when destination is defined" do
      let(:job) do
        Metacrunch::Job.define do
          require "metacrunch/test_utils"
          destination Metacrunch::TestUtils::DummyDestination.new
        end.run
      end

      it "returns the destination" do
        expect(job.destination).not_to be_nil
      end
    end
  end

  describe "#destination=" do
    let!(:job) { Metacrunch::Job.new }

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
    context "when no pre process is defined" do
      let(:job) do
        Metacrunch::Job.define{}.run
      end

      it "returns nil" do
        expect(job.pre_process).to be_nil
      end
    end

    context "when pre process is defined" do
      let(:job) do
        Metacrunch::Job.define do
          pre_process ->() {}
        end.run
      end

      it "returns the pre process instance" do
        expect(job.pre_process).not_to be_nil
      end
    end
  end

  describe "#pre_process=" do
    let!(:job) { Metacrunch::Job.new }

    context "when called with a callable" do
      it "adds the callable as a pre_process" do
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
    context "when no post process is defined" do
      let(:job) do
        Metacrunch::Job.define{}.run
      end

      it "returns an empty array" do
        expect(job.post_process).to be_nil
      end
    end

    context "when post process is defined" do
      let(:job) do
        Metacrunch::Job.define do
          post_process ->() {}
        end.run
      end

      it "returns the post process instance" do
        expect(job.post_process).not_to be_nil
      end
    end
  end

  describe "#post_process=" do
    let!(:job) { Metacrunch::Job.new }

    context "when called with a callable" do
      it "adds the callable as a post_process" do
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

    context "when called with an object that doesn't respond to #call" do
      it "raises an error" do
        expect{
          job.add_transformation(Metacrunch::TestUtils::DummyNonCallable.new)
        }.to raise_error(ArgumentError)
      end
    end

    context "when called with a callable and a buffer size > 0" do
      it "adds the buffer and the callable as a transformation" do
        job.add_transformation(-> {}, buffer: 1000)
        expect(job.transformations.count).to eq(2)
        expect(job.transformations[0]).to be_a(Metacrunch::Job::Buffer)
        expect(job.transformations[1]).to be_a(Proc)
      end
    end

    context "when called with a callable and a buffer size <= 0" do
      it "raises an argument error" do
        expect { job.add_transformation(-> {}, buffer: 0) }.to raise_error(ArgumentError)
        expect { job.add_transformation(-> {}, buffer: -2) }.to raise_error(ArgumentError)
      end
    end

    context "when called with a callable and a buffer function" do
      it "adds the buffer and the callable as a transformation" do
        job.add_transformation(-> {}, buffer: -> {})
        expect(job.transformations.count).to eq(2)
        expect(job.transformations[0]).to be_a(Metacrunch::Job::Buffer)
        expect(job.transformations[1]).to be_a(Proc)
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

      it "runs pre process" do
        expect(job.dsl.instance_variable_get("@pre_process_called")).to be(true)
      end

      it "runs post process" do
        expect(job.dsl.instance_variable_get("@post_process_called")).to be(true)
      end

      it "runs transformations" do
        expect(job.dsl.instance_variable_get("@transformation_called")).to be(true)
      end

      it "writes to a destination" do
        expect(job.destination.instance_variable_get("@write_called")).to be(true)
      end

      it "closes a destination" do
        expect(job.destination.instance_variable_get("@close_called")).to be(true)
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

      it "runs pre process" do
        expect(job.dsl.instance_variable_get("@pre_process_called")).to be(true)
      end

      it "runs post process" do
        expect(job.dsl.instance_variable_get("@post_process_called")).to be(true)
      end

      it "does not run transformations" do
        expect(job.dsl.instance_variable_get("@transformation_called")).to be_nil
      end

      it "does not write to a destination" do
        expect(job.destination.instance_variable_get("@write_called")).to be_nil
      end

      it "does not close a destination" do
        expect(job.destination.instance_variable_get("@close_called")).to be_nil
      end
    end
  end

end
