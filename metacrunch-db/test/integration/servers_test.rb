# frozen_string_literal: true

require "test_helper"

class ServersTest < Minitest::Test

  def test_servers
    skip "set TEST_POSTGRES_URL, TEST_MYSQL_URL or TEST_MARIADB_URL to test against servers (see test/compose.yml)" \
      unless Integration.servers?

    pass
  end

end
