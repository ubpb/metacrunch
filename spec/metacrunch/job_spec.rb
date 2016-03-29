describe Metacrunch::Job do

  it "works" do
    context = Metacrunch::Job.define do

      class MyDummySource
        def each
          (1..10).each do |number|
            yield({number: number})
          end
        end
      end

      class MyDummyDestination
        attr_reader :data

        def write(row)
          (@data ||= []) << row
        end

        def close
          # nope
        end
      end

      def some_method
        @some_method_called = true
      end

      source      MyDummySource.new
      destination MyDummyDestination.new

      pre_process do
        @pre_process_called = true
        some_method
      end

      # Delete all even numbers
      transformation do |row|
        row[:number].odd? ? row : nil
      end

      # Add 10 to each row
      transformation do |row|
        row[:number] = row[:number] + 10
        row
      end

      post_process do
        @post_process_called = true
      end

    end

    job = Metacrunch::Job.run(context, {foo: "bar"})

    expect(context.instance_variable_get("@pre_process_called")).to eq(true)
    expect(context.instance_variable_get("@post_process_called")).to eq(true)
    expect(context.instance_variable_get("@some_method_called")).to eq(true)

    expect(job.options).to eq({foo: "bar"})
    expect(job.sources.size).to eq(1)
    expect(job.destinations.size).to eq(1)
    expect(job.pre_processes.size).to eq(1)
    expect(job.post_processes.size).to eq(1)
    expect(job.transformations.size).to eq(2)
    expect(job.destinations.first.data).to eq([{:number=>11}, {:number=>13}, {:number=>15}, {:number=>17}, {:number=>19}])
  end

end
