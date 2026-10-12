# frozen_string_literal: true

# Paths and contents of test/fixtures.
module Fixtures

  DIR = File.expand_path("../fixtures", __dir__)

  def fixture_path(name) = File.join(DIR, name)

  def fixture(name) = File.read(fixture_path(name), encoding: "UTF-8")

end
