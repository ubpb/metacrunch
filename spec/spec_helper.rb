require "pry" if !ENV["CI"]

require "simplecov"
SimpleCov.start do
  add_filter %r{^/spec/}
end

require "metacrunch"
require "metacrunch/test_utils"

RSpec.configure do |config|
end

# Helper to provide RSpec.root
module ::RSpec
  module_function
  def root
    @spec_root ||= Pathname.new(__dir__)
  end
end
