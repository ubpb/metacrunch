# frozen_string_literal: true

require "test_helper"

# The writer as a user with some privileges on the table only (see test/support/integration.rb); SQLite has none.
module PrivilegeTests

  PASSWORD = "metacrunch"

  def setup
    super
    skip "SQLite has no users" if type == :sqlite
  end

  # A denied INSERT refuses every record: the run stops instead of failing each of them.
  def test_a_user_who_may_only_read_stops_the_run
    name = create_books
    error = assert_raises(Metacrunch::OutputError) do
      as_user("SELECT", name) { write([{"isbn" => "1", "title" => "A"}], table: name, connection: it) }
    end

    assert_match(/\Adb #{name}: .*(permission denied|command denied)/i, error.message)
  end

  private

  # Yields a connection as a new user with privileges on table; drops the user afterwards.
  def as_user(privileges, table)
    user = "#{@prefix}user"
    create_user(user, privileges, table)
    yield Metacrunch::Db::Connection.new(url: @url.sub(%r{//[^/@]*@}, "//"), user:, password: PASSWORD)
  ensure
    drop_user(user)
  end

  def create_user(user, privileges, table)
    if type == :postgres
      database.run("CREATE ROLE #{user} LOGIN PASSWORD '#{PASSWORD}'")
      database.run("GRANT #{privileges} ON #{table} TO #{user}")
    else
      database.run("CREATE USER '#{user}'@'%' IDENTIFIED BY '#{PASSWORD}'")
      database.run("GRANT #{privileges} ON #{schema}.#{table} TO '#{user}'@'%'")
    end
  end

  def drop_user(user)
    if type == :postgres
      database.run("DROP OWNED BY #{user}")
      database.run("DROP ROLE IF EXISTS #{user}")
    else
      database.run("DROP USER IF EXISTS '#{user}'@'%'")
    end
  end

end

Integration.define("Privileges", PrivilegeTests)
