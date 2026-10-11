# frozen_string_literal: true

# Fails as soon as anything is opened, read or run.
class Unopenable

  def open(_context) = raise("must not be opened")

  def each = raise("must not be read")

end

Metacrunch.job do
  source Unopenable.new
  before { raise "hooks must not run" }
end
