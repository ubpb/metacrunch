require "pry" if !ENV["CI"]
require "simplecov"

require "metacrunch"
require "metacrunch/test_utils"

SimpleCov.start

RSpec.configure do |config|
end
