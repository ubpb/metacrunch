require "pry" if !ENV["CI"]

require "simplecov"
SimpleCov.start

require "metacrunch"
require "metacrunch/test_utils"

RSpec.configure do |config|
end
