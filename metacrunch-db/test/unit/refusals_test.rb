# frozen_string_literal: true

require "test_helper"

class RefusalsTest < Minitest::Test

  include Databases

  # The parts of the drivers' exceptions that tell what went wrong.
  PgResult = Data.define(:sqlstate) do
    def error_field(field) = (sqlstate if field == Metacrunch::Db::Refusals::PG_DIAG_SQLSTATE)
  end
  PgError = Data.define(:result)
  Mysql2Error = Data.define(:error_number)
  TrilogyError = Data.define(:error_code)
  SqliteError = Data.define(:code)

  def test_constraint_violations_are_refusals
    classes = [Sequel::UniqueConstraintViolation, Sequel::NotNullConstraintViolation,
               Sequel::ForeignKeyConstraintViolation, Sequel::CheckConstraintViolation]

    assert_equal(classes, classes.select { refused?(error(nil, it)) })
  end

  def test_postgres_data_exceptions_and_integrity_violations_are_refusals
    states = ["22001", "22P02", "22007", "23505"]

    assert_equal(states, states.select { refused?(error(PgError.new(PgResult.new(it)))) })
  end

  def test_other_postgres_errors_stop_the_run
    causes = ["42501", "25006", "53100", "42P01", nil].map { PgError.new(PgResult.new(it)) } << PgError.new(nil)

    assert_empty(causes.select { refused?(error(it)) })
  end

  def test_mysql_errors_of_values_and_constraints_are_refusals
    numbers = [1048, 1062, 1264, 1292, 1364, 1366, 1406, 1451, 1452, 3140, 3819, 4025]

    assert_equal(numbers, numbers.select { refused?(error(Mysql2Error.new(it))) })
    assert_equal(numbers, numbers.select { refused?(error(TrilogyError.new(it))) })
  end

  def test_other_mysql_errors_stop_the_run
    numbers = [1142, 1146, 1290, 1114, 1153]

    assert_empty(numbers.select { refused?(error(Mysql2Error.new(it))) || refused?(error(TrilogyError.new(it))) })
  end

  # Primary codes 18 (TOOBIG), 19 (CONSTRAINT, with its extended codes) and 20 (MISMATCH).
  def test_sqlite_errors_of_values_and_constraints_are_refusals
    codes = [18, 19, 20, 19 | (8 << 8)]

    assert_equal(codes, codes.select { refused?(error(SqliteError.new(it))) })
  end

  def test_other_sqlite_errors_stop_the_run
    assert_empty([5, 8, 13, nil].select { refused?(error(SqliteError.new(it))) })
  end

  def test_fatal_errors_stop_the_run
    classes = [Sequel::DatabaseConnectionError, Sequel::DatabaseDisconnectError, Sequel::SerializationFailure,
               Sequel::DatabaseLockTimeout]

    assert_empty(classes.select { refused?(error(nil, it)) })
  end

  def test_unknown_causes_and_other_errors_stop_the_run
    assert_empty([error(Object.new), error(nil), Sequel::Error.new("x")].select { refused?(it) })
  end

  def test_real_sqlite_errors
    database = create_books(sqlite, [{isbn: "1", title: "A"}])
    errors = [capture { database[:books].insert(isbn: "1", title: "B") },
              capture { database[:books].insert(isbn: "2", title: nil) },
              capture { database[:nope].insert(isbn: "2") }]

    assert_equal([true, true, false], errors.map { refused?(it) })
  end

  private

  def refused?(error) = Metacrunch::Db::Refusals.record?(error)

  def error(cause, error_class = Sequel::DatabaseError) = error_class.new("x").tap { it.wrapped_exception = cause }

  def capture
    yield
    nil
  rescue Sequel::Error => e
    e
  end

end
