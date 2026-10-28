# frozen_string_literal: true

require "test_helper"
require "json"
require "open3"

# Runs the example project as a user would, through metacrunch's executable with its params file, on keys of the
# test's own (--queue, --prefix) on the first server that is set.
class ExamplesTest < Minitest::Test

  EXAMPLES = File.expand_path("../../examples", __dir__)
  ISBNS = ["9780140449136", "9780141439518", "9780140449266", "9780199535569", "9780141439600"].freeze

  def setup
    @target = Integration.targets.first
    skip Integration::HINT unless @target

    @queue = "metacrunch-test:#{SecureRandom.hex(4)}:books"
    @prefix = "metacrunch-test:#{SecureRandom.hex(4)}:book:"
  end

  def teardown
    return unless @target

    Metacrunch::Redis::Connection.new(url: @target.url).connect do |redis|
      keys = []
      redis.scan("MATCH", "#{@prefix}*") { keys << it }
      redis.call("DEL", @queue, *keys)
    end
  end

  def test_enqueue_then_consume_writes_the_books_that_are_not_deleted
    run!("books:enqueue", "--queue", @queue)

    assert_equal "#{@queue}: 6 entries\n", run!("books:queue", "--queue", @queue)
    books = run!("books:consume", "--queue", @queue, "--wait", "0.5").lines.map { JSON.parse(it) }

    assert_equal(ISBNS, books.map { it["isbn"] })
    assert_equal "#{@queue}: 0 entries\n", run!("books:queue", "--queue", @queue)
  end

  def test_the_queue_command_empties_the_queue
    run!("books:enqueue", "--queue", @queue)

    assert_equal "#{@queue}: emptied\n", run!("books:queue", "--queue", @queue, "--clear")
    assert_equal "#{@queue}: 0 entries\n", run!("books:queue", "--queue", @queue)
  end

  def test_cache_then_export_gives_the_cached_books
    run!("books:cache", "--prefix", @prefix)
    books = run!("books:export", "--prefix", @prefix).lines.map { JSON.parse(it) }

    assert_equal ISBNS.sort, books.map { it["isbn"] }.sort
  end

  private

  def run!(*)
    stdout, stderr, status = Open3.capture3(RbConfig.ruby, Integration::BIN, "run", "--params", "params.yml", *,
                                            "--url", @target.url, chdir: EXAMPLES)

    assert_predicate status, :success?, stderr
    stdout
  end

end
