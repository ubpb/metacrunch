# frozen_string_literal: true

# The source fails with an error whose cause has an empty message.
Metacrunch.job do
  source(
    Enumerator.new do
      raise IOError, ""
    rescue IOError
      raise ArgumentError, "source broke"
    end
  )
end
