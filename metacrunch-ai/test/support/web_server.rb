# frozen_string_literal: true

# For the tests that need a web server: they run against the nginx at WEB_URL (see test/compose.yml), which serves
# test/fixtures/web/site, and skip without it. The fixtures name the server as http://127.0.0.1:8089.
module WebServer

  HINT = "needs a web server: set WEB_URL (see test/compose.yml)"

  def setup
    skip HINT unless ENV["WEB_URL"]

    super
  end

  def web_url(path = "") = "#{ENV.fetch("WEB_URL").chomp("/")}#{path}"

end
