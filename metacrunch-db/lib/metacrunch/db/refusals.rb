# frozen_string_literal: true

module Metacrunch
  module Db
    # Which errors of a statement belong to its records: a constraint they
    # violate, or a value a column does not take. The writer retries the
    # records of such a statement alone and reports those the database still
    # refuses as failed records. Every other error (a lost connection, a
    # deadlock, no right to write, a read-only or full database) would refuse
    # every record and stops the run. Unknown adapters count only Sequel's
    # constraint violations.
    module Refusals

      # Errors that never belong to a record.
      FATAL = [Sequel::DatabaseConnectionError, Sequel::DatabaseDisconnectError, Sequel::SerializationFailure,
               Sequel::DatabaseLockTimeout].freeze
      # libpq's field code of the SQLSTATE ("C"), as PG::PG_DIAG_SQLSTATE.
      PG_DIAG_SQLSTATE = "C".ord
      # SQLSTATE classes of PostgreSQL: data exceptions (too long, invalid
      # input, out of range) and integrity constraint violations.
      PG_CLASSES = ["22", "23"].freeze
      # Error numbers of MySQL and MariaDB: a NULL, a duplicate, a value out
      # of range, truncated or incorrect, a missing default, a foreign key,
      # invalid JSON, a CHECK constraint (3819 MySQL, 4025 MariaDB).
      MYSQL_ERRORS = [1048, 1062, 1216, 1217, 1264, 1265, 1292, 1364, 1366, 1406, 1451, 1452, 1690, 3140, 3819,
                      4025].freeze
      # Primary result codes of SQLite: TOOBIG, CONSTRAINT, MISMATCH.
      SQLITE_CODES = [18, 19, 20].freeze

      module_function

      def record?(error)
        return false unless error.is_a?(Sequel::DatabaseError)
        return false if FATAL.any? { error.is_a?(it) }
        return true if error.is_a?(Sequel::ConstraintViolation)

        driver?(error.wrapped_exception)
      end

      # By the driver's exception: pg, mysql2, trilogy, sqlite3.
      def driver?(cause)
        if cause.respond_to?(:result)
          PG_CLASSES.include?(cause.result&.error_field(PG_DIAG_SQLSTATE).to_s[0, 2])
        elsif cause.respond_to?(:error_number)
          MYSQL_ERRORS.include?(cause.error_number)
        elsif cause.respond_to?(:error_code)
          MYSQL_ERRORS.include?(cause.error_code)
        elsif cause.respond_to?(:code)
          cause.code.is_a?(Integer) && SQLITE_CODES.include?(cause.code & 0xFF)
        else
          false
        end
      end

    end
  end
end
