require_relative "../reader"

# This fetcher does not do anything besides returning the filename withouzt the
# file:// protocol prefix. It only exists to keep the implementation consistent.
class Metacrunch::File::Reader::FileSystemFetcher
  include Enumerable

  RECOGNIZED_PROTOCOL_REGEX = /\Afile:\/\//

  def self.accepts?(url)
    !!url[RECOGNIZED_PROTOCOL_REGEX]
  end

  def initialize(url, options = {})
    @url = url
  end

  def each
    yield @url.sub(RECOGNIZED_PROTOCOL_REGEX, "")
  end
end
