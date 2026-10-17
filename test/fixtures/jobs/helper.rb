# frozen_string_literal: true

# A job with a transform of its own, as an object in the same file; the file
# still runs by path without -j.
trim = Metacrunch.transform { map(&:strip) }

Metacrunch.job do
  use trim
end
