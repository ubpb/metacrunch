require "metacrunch/mab2"

RSpec.configure do |config|
end

# Helper to provide RSpec.root
module ::RSpec
  module_function
  def root
    @spec_root ||= Pathname.new(__dir__)
  end
end
