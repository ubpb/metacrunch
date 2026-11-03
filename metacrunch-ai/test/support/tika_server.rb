# frozen_string_literal: true

# For the tests that need an Apache Tika server: they run against the server at TIKA_URL (see test/compose.yml) and
# skip without it.
module TikaServer

  HINT = "needs an Apache Tika server: set TIKA_URL (see test/compose.yml)"

  def setup
    skip HINT unless ENV["TIKA_URL"]

    super
  end

  def tika_url = ENV.fetch("TIKA_URL")

end
