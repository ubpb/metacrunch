# frozen_string_literal: true

require "test_helper"

class ContextTest < Minitest::Test

  def test_reject_records_reason_value_and_step
    ctx = build_context
    ctx.step = "reject#2"
    ctx.reject!("Patent", value: "patent")

    assert_predicate ctx, :rejected?
    assert_equal Metacrunch::Rejection.new(reason: "Patent", value: "patent", step: "reject#2"), ctx.rejection
  end

  def test_mark_keeps_the_record_and_reports_the_reason
    reported = []
    ctx = build_context(on_mark: ->(reason) { reported << reason })
    ctx.step = "map#1"
    ctx.mark("No title")

    refute_predicate ctx, :rejected?
    assert_equal [Metacrunch::Mark.new(reason: "No title", value: nil, step: "map#1")], ctx.marks
    assert_equal ["No title"], reported
  end

  def test_copy_keeps_identity_but_not_marks_or_store
    parent = build_context
    parent.step = "flat_map#3"
    parent.mark("parent")
    parent.store[:cache] = 1
    child = parent.copy
    child.mark("child")
    child.store[:cache] = 2

    assert_equal ["rec1", 7, "flat_map#3"], [child.id, child.position, child.step]
    assert_equal [["parent"], 1], [parent.marks.map(&:reason), parent.store[:cache]]
    assert_equal ["parent", "child"], child.marks.map(&:reason)
  end

  def test_sealed_context_rejects_changes
    ctx = build_context.seal!

    assert_raises(Metacrunch::ContractError) { ctx.reject!("x") }
    assert_raises(Metacrunch::ContractError) { ctx.mark("x") }
  end

  def test_logger_prefixes_messages_with_id_or_position
    io = StringIO.new
    logger = Metacrunch.build_logger(io)
    build_context(id: "rec1", logger:).logger.warn("missing title")
    build_context(id: nil, logger:).logger.warn("no id")

    assert_match(/WARN  \[rec1\] missing title/, io.string)
    assert_match(/WARN  \[#7\] no id/, io.string)
  end

  def test_logger_supports_block_form_and_level_checks
    io = StringIO.new
    record_logger = build_context(logger: Metacrunch.build_logger(io)).logger
    record_logger.info { "lazy message" }
    record_logger.debug { raise "debug blocks must not run at level INFO" }

    assert_match(/INFO  \[rec1\] lazy message/, io.string)
    refute_predicate record_logger, :debug?
  end

  private

  def build_context(id: "rec1", logger: Logger.new(nil), on_mark: nil)
    Metacrunch::Context.new(id:, position: 7, logger:, on_mark:)
  end

end
