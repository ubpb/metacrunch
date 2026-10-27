# frozen_string_literal: true

require "test_helper"

class ConnectionParamsTest < Minitest::Test

  def test_connection_params_declare_url_user_and_password
    definitions = declared(Metacrunch::Db::CONNECTION_PARAMS)

    assert_equal [:url, :user, :password], definitions.keys
    assert_equal [true, false, false], definitions.values.map(&:required)
    assert_equal [false, false, true], definitions.values.map(&:secret?)
  end

  def test_a_prefix_names_the_params_and_descriptions
    definitions = declared(Metacrunch::Db.connection_params("source"))

    assert_equal [:source_url, :source_user, :source_password], definitions.keys
    assert_predicate definitions[:source_password], :secret?
    assert(definitions.values.all? { it.desc.include?("source database") })
  end

  def test_a_bad_prefix_is_refused
    ["Source", "1x", "", "a-b", :source].each do |prefix|
      error = assert_raises(ArgumentError) { Metacrunch::Db.connection_params(prefix) }

      assert_equal "prefix must be a lowercase word such as source, got #{prefix.inspect}", error.message
    end
  end

  def test_from_params_reads_the_declared_params
    params = bound(Metacrunch::Db::CONNECTION_PARAMS, {url: "postgres://db/catalog", user: "etl", password: "pw"})
    connection = Metacrunch::Db::Connection.from_params(params)

    assert_equal "#<Metacrunch::Db::Connection url=postgres://db/catalog user=etl password=[FILTERED]>",
                 connection.inspect
  end

  def test_from_params_leaves_out_what_is_not_given
    params = bound(Metacrunch::Db::CONNECTION_PARAMS, {url: "postgres://etl:pw@db/catalog"})

    assert_equal "postgres://[FILTERED]@db/catalog", Metacrunch::Db::Connection.from_params(params).url
  end

  def test_from_params_with_a_prefix
    declarations = proc do
      instance_exec(&Metacrunch::Db.connection_params("source"))
      instance_exec(&Metacrunch::Db.connection_params("target"))
    end
    params = bound(declarations, {source_url: "postgres://a/x", target_url: "mysql2://b/y", target_user: "u",
                                  target_password: "pw"})

    assert_equal "postgres://a/x", Metacrunch::Db::Connection.from_params(params, prefix: "source").url
    assert_equal "#<Metacrunch::Db::Connection url=mysql2://b/y user=u password=[FILTERED]>",
                 Metacrunch::Db::Connection.from_params(params, prefix: "target").inspect
  end

  private

  def declared(declarations) = Metacrunch::Params.new.tap { it.instance_exec(&declarations) }.definitions

  def bound(declarations, values)
    Metacrunch::Params.new.tap { it.instance_exec(&declarations) }.bind_values(values)
  end

end
