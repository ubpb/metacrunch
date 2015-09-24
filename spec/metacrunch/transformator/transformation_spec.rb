describe Metacrunch::Transformator::Transformation do
  class SomeStep < described_class::Step
    def call
      self.target = { muff: 1 }
    end
  end

  class SomeTransformation < described_class
    sequence [
      SomeStep
    ]
  end

  it "foo" do
    result = SomeTransformation.call({
      my: {
        awesome: {
          source: {
            title: "foo",
            description: "bar"
          }
        }
      }
    })

    result
  end
end
