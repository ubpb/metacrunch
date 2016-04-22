if ENV["CODECLIMATE_REPO_TOKEN"]
  require "codeclimate-test-reporter"
  CodeClimate::TestReporter.start
else
  require "simplecov"
  SimpleCov.start
end

require "metacrunch/mab2"

begin
  require "pry"
rescue LoadError
end

RSpec.configure do |config|
  config.expect_with :rspec do |expectations|
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end

  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end
end

# Helper to provide RSpec.root
module ::RSpec
  module_function
  def root
    @spec_root ||= Pathname.new(__dir__)
  end
end

def asset_dir
  File.expand_path(File.join(File.dirname(__FILE__), "assets"))
end

def read_asset(path_to_file)
  File.read(File.expand_path(File.join(asset_dir, path_to_file)))
end
