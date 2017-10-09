describe Metacrunch::Job::Buffer do

  context "when a job with 95 data objects is run with a buffer size of 10" do
    let!(:job) do
      Metacrunch::Job.define do
        source 1..95
        transformation ->(bulk) {
          @no_of_run = (@no_of_run || 0) + 1
          (@bulks || @bulks = []) << bulk
        }, buffer: 10
      end.run
    end

    it "runs the transformation 10 times" do
      expect(job.dsl.instance_variable_get("@no_of_run")).to eq(10)
    end

    it "the first bulk contains the numbers 1..10" do
      expect(job.dsl.instance_variable_get("@bulks").first).to eq((1..10).to_a)
    end

    it "the last bulk contains the numbers 91..95" do
      expect(job.dsl.instance_variable_get("@bulks").last).to eq((91..95).to_a)
    end
  end

  context "when a job with 95 data objects is run with a buffer Proc that returns 'true' every 10 calls" do
    let!(:job) do
      Metacrunch::Job.define do
        source 1..95
        transformation ->(bulk) {
          @no_of_run = (@no_of_run || 0) + 1
          (@bulks || @bulks = []) << bulk
        }, buffer: -> {
          @buffer_calls = (@buffer_calls || 0) + 1

          if @buffer_calls == 10
            @buffer_calls = 0
            true
          end
        }
      end.run
    end

    it "runs the transformation 10 times" do
      expect(job.dsl.instance_variable_get("@no_of_run")).to eq(10)
    end

    it "the first bulk contains the numbers 1..10" do
      expect(job.dsl.instance_variable_get("@bulks").first).to eq((1..10).to_a)
    end

    it "the last bulk contains the numbers 91..95" do
      expect(job.dsl.instance_variable_get("@bulks").last).to eq((91..95).to_a)
    end
  end

end
