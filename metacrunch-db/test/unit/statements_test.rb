# frozen_string_literal: true

require "test_helper"

class StatementsTest < Minitest::Test

  include Databases

  Statements = Metacrunch::Db::Statements

  # Without a key, the writer cannot tell which records must keep their order, so only neighbours share a statement.
  def test_runs_without_a_key_split_on_action_and_columns_and_keep_order
    items = [item(0, :insert, isbn: "1"), item(1, :insert, isbn: "2"), item(2, :insert, isbn: "3", title: "C"),
             item(3, :insert, title: "D", isbn: "4"), item(4, :insert, isbn: "5"), item(5, :delete, isbn: "1"),
             item(6, :insert, isbn: "6")]

    assert_equal [[:insert, [0, 1]], [:insert, [2, 3]], [:insert, [4]], [:delete, [5]], [:insert, [6]]],
                 positions(Statements.runs(items, nil))
  end

  # Records that leave out absent fields: with a key, those of the same columns share a statement.
  def test_runs_with_a_key_group_inserts_and_upserts_by_columns
    items = [item(0, :upsert, isbn: "1", title: "A"), item(1, :upsert, isbn: "2"),
             item(2, :upsert, isbn: "3", title: "C"), item(3, :upsert, isbn: "4"), item(4, :delete, isbn: "1"),
             item(5, :insert, isbn: "5", year: 1),
             item(6, :insert, isbn: "6"), item(7, :insert, isbn: "7", year: 2)]

    assert_equal [[:upsert, [0, 2]], [:upsert, [1, 3]], [:delete, [4]], [:insert, [5, 7]], [:insert, [6]]],
                 positions(Statements.runs(items, [:isbn]))
  end

  # A key again starts a new segment, so the records of one key stay in their order; the last one wins.
  def test_a_key_again_keeps_the_order_of_its_records
    items = [item(0, :upsert, isbn: "1"), item(1, :upsert, isbn: "1", title: "B"), item(2, :upsert, isbn: "2"),
             item(3, :upsert, isbn: "1")]

    assert_equal [[:upsert, [0]], [:upsert, [1]], [:upsert, [2]], [:upsert, [3]]],
                 positions(Statements.runs(items, [:isbn]))
  end

  # An insert may leave out its key, e.g. one the database generates.
  def test_inserts_without_a_key_value_never_repeat_it
    items = [item(0, :insert, title: "A"), item(1, :insert, title: "B"), item(2, :insert, title: "C", year: 1)]

    assert_equal [[:insert, [0, 1]], [:insert, [2]]], positions(Statements.runs(items, [:isbn]))
  end

  def test_size_counts_strings_by_bytes_and_other_values_flat
    assert_equal (3 + 3) + (2 + 3) + 24 + 24, Statements.size({a: "abc", b: "ä", c: 1, d: nil})
  end

  # Blobs go into SQL as hex, two characters per byte.
  def test_size_counts_a_blob_twice
    assert_equal (2 * 3) + 3, Statements.size({a: Sequel.blob("abc")})
  end

  def test_pieces_stay_under_max_bytes
    items = (0...6).map { item(it, :insert, title: "x" * 97) }
    pieces = Statements.pieces(items, 250)

    assert_equal([[0, 1], [2, 3], [4, 5]], pieces.map { it.map(&:position) })
  end

  def test_an_item_larger_than_max_bytes_goes_alone
    items = [item(0, :insert, title: "x"), item(1, :insert, title: "x" * 500), item(2, :insert, title: "y")]

    assert_equal([[0], [1], [2]], Statements.pieces(items, 100).map { it.map(&:position) })
  end

  def test_insert_is_one_multi_row_insert
    database = Sequel.mock(host: "postgres")
    Statements.execute(database[:books], :insert, [item(0, :insert, isbn: "1"), item(1, :insert, isbn: "2")], nil)

    assert_equal [%(INSERT INTO "books" ("isbn") VALUES ('1'), ('2'))], database.sqls.grep(/INSERT/)
  end

  def test_postgres_upsert_updates_the_other_columns
    assert_equal [%(INSERT INTO "books" ("isbn", "title") VALUES ('1', 'A') ON CONFLICT ("isbn") DO UPDATE SET ) +
                  %("title" = "excluded"."title")], upsert_sql("postgres", isbn: "1", title: "A")
  end

  def test_postgres_upsert_without_other_columns_does_nothing
    assert_equal [%(INSERT INTO "books" ("isbn") VALUES ('1') ON CONFLICT ("isbn") DO NOTHING)],
                 upsert_sql("postgres", isbn: "1")
  end

  def test_sqlite_upsert_uses_on_conflict
    assert_equal ["INSERT INTO `books` (`isbn`, `title`) VALUES ('1', 'A') ON CONFLICT (`isbn`) DO UPDATE SET " \
                  "`title` = `excluded`.`title`"], upsert_sql("sqlite", isbn: "1", title: "A")
  end

  def test_mysql_upsert_uses_on_duplicate_key_update
    assert_equal ["INSERT INTO `books` (`isbn`, `title`) VALUES ('1', 'A') ON DUPLICATE KEY UPDATE " \
                  "`title`=VALUES(`title`)"], upsert_sql("mysql", isbn: "1", title: "A")
  end

  def test_mysql_upsert_without_other_columns_sets_the_key
    assert_equal ["INSERT INTO `books` (`isbn`) VALUES ('1') ON DUPLICATE KEY UPDATE `isbn`=VALUES(`isbn`)"],
                 upsert_sql("mysql", isbn: "1")
  end

  def test_upsert_dataset_is_nil_without_upsert
    assert_nil Statements.upsert_dataset(Sequel.mock(host: "oracle")[:books], [:isbn], [:isbn])
  end

  def test_delete_uses_in
    database = Sequel.mock(host: "postgres")
    Statements.execute(database[:books], :delete, [item(0, :delete, isbn: "1"), item(1, :delete, isbn: "2")], [:isbn])

    assert_equal [%(DELETE FROM "books" WHERE ("isbn" IN ('1', '2')))], database.sqls
  end

  def test_delete_with_a_composite_key_uses_row_values
    database = Sequel.mock(host: "postgres")
    items = [item(0, :delete, isbn: "1", year: 1), item(1, :delete, isbn: "2", year: 2)]
    Statements.execute(database[:books], :delete, items, [:isbn, :year])

    assert_equal [%(DELETE FROM "books" WHERE (("isbn", "year") IN (('1', 1), ('2', 2))))], database.sqls
  end

  def test_update_sets_the_other_columns_per_row
    database = Sequel.mock(host: "postgres", numrows: 1)
    items = [item(0, :update, isbn: "1", title: "A"), item(1, :update, title: "B", isbn: "2")]

    assert_empty Statements.execute(database[:books], :update, items, [:isbn])
    assert_equal [%(UPDATE "books" SET "title" = 'A' WHERE ("isbn" = '1')),
                  %(UPDATE "books" SET "title" = 'B' WHERE ("isbn" = '2'))], database.sqls
  end

  def test_update_reports_items_without_a_row
    database = create_books(sqlite, [{isbn: "1", title: "A"}])
    items = [item(0, :update, isbn: "1", title: "B"), item(1, :update, isbn: "2", title: "C")]
    unmatched = Statements.execute(database[:books], :update, items, [:isbn])

    assert_equal [1], unmatched.map(&:position)
    assert_equal ["B"], database[:books].select_map(:title)
  end

  def test_update_without_other_columns_counts_existing_rows
    database = create_books(sqlite, [{isbn: "1", title: "A"}])
    items = [item(0, :update, isbn: "1"), item(1, :update, isbn: "2")]

    assert_equal [1], Statements.execute(database[:books], :update, items, [:isbn]).map(&:position)
  end

  private

  def item(position, action, **row) = Statements::Item.new(position:, action:, row:)

  def positions(runs) = runs.map { [it.action, it.items.map(&:position)] }

  def upsert_sql(host, **row)
    database = Sequel.mock(host:)
    Statements.execute(database[:books], :upsert, [item(0, :upsert, **row)], [:isbn])
    database.sqls.grep(/INSERT/)
  end

end
