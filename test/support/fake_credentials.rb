# frozen_string_literal: true

# Credentials with fixed values, answering like a Credentials::Store.
class FakeCredentials

  def initialize(data)
    @data = data
  end

  def lookup(path) = @data[path]

  def origin(path) = "credential #{path} in test"

  def missing(path) = "#{path} not in test"

end
