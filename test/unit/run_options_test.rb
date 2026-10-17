# frozen_string_literal: true

require "test_helper"
require "tmpdir"

class RunOptionsTest < Minitest::Test

  include PipelineHelper

  RunOptions = Metacrunch::RunOptions

  # Stdin that claims to be a terminal.
  class TerminalInput < StringIO

    def tty? = true

  end

  def setup
    @dir = Dir.mktmpdir
  end

  def teardown
    FileUtils.remove_entry(@dir)
  end

  def test_without_options_the_pipeline_is_unchanged
    pipeline = build_pipeline do
      source [1]
      sink CollectingSink.new
    end

    assert_equal pipeline, apply(RunOptions.new, pipeline)
  end

  def test_a_job_without_source_and_sink_filters_stdin_to_stdout
    stdout = StringIO.new
    pipeline = apply(RunOptions.new, build_pipeline { map { it * 2 } }, stdin: StringIO.new("1\n2\n"), stdout:)
    Metacrunch::Engine.new(pipeline).run

    assert_equal "2\n4\n", stdout.string
  end

  def test_a_job_without_source_does_not_read_a_terminal
    error = assert_raises(Metacrunch::UsageError) do
      apply(RunOptions.new, build_pipeline { map { it } }, stdin: TerminalInput.new)
    end

    assert_equal "the job reads JSON Lines from stdin, which is a terminal; pipe them in (< FILE) or use -i PATH",
                 error.message
  end

  def test_input_and_output_replace_the_source_and_sink
    input = File.join(@dir, "in.jsonl")
    output = File.join(@dir, "out.jsonl")
    File.write(input, "1\n2\n")
    replaced = CollectingSink.new
    pipeline = build_pipeline do
      source [99]
      map { it + 1 }
      sink replaced
    end
    Metacrunch::Engine.new(apply(RunOptions.new(input:, output:), pipeline)).run

    assert_equal "2\n3\n", File.read(output)
    assert_empty replaced.events
  end

  def test_dash_means_the_cli_streams
    stdout = StringIO.new
    pipeline = build_pipeline do
      source [99]
      sink CollectingSink.new
    end
    applied = apply(RunOptions.new(input: "-", output: "-"), pipeline, stdin: StringIO.new("7\n"), stdout:)
    Metacrunch::Engine.new(applied).run

    assert_equal "7\n", stdout.string
  end

  def test_rejects_and_errors_may_share_a_file
    path = File.join(@dir, "bad.jsonl")
    pipeline = build_pipeline do
      source [1, 2, 3]
      reject("Two") { it == 2 }
      map { it == 3 ? raise("three") : it }
      sink CollectingSink.new
      on_error :skip
    end
    applied = apply(RunOptions.new(rejects: path, errors: File.join(@dir, ".", "bad.jsonl")), pipeline)
    Metacrunch::Engine.new(applied).run
    lines = File.readlines(path).map { JSON.parse(it) }

    assert_same applied.rejects.sink, applied.errors.sink
    assert_equal([["Two", nil], [nil, "RuntimeError"]],
                 lines.map { [it.dig("rejection", "reason"), it.dig("failure", "error")] })
  end

  def test_rejects_and_errors_may_share_stdout
    stdout = StringIO.new
    pipeline = build_pipeline do
      source [1, 2]
      reject("Two") { it == 2 }
      map { raise "broken" }
      sink CollectingSink.new
      on_error :skip
    end
    applied = apply(RunOptions.new(rejects: "-", errors: "-"), pipeline, stdout:)
    Metacrunch::Engine.new(applied).run

    assert_same applied.rejects.sink, applied.errors.sink
    assert_equal 2, stdout.string.lines.size
  end

  def test_shared_stdout_of_rejects_and_errors_still_conflicts_with_records
    pipeline = build_pipeline { source [1] }
    error = assert_raises(Metacrunch::UsageError) { apply(RunOptions.new(rejects: "-", errors: "-"), pipeline) }

    assert_equal "stdout is used by both the default output (the job has no sink) and --rejects/--errors",
                 error.message
  end

  def test_stdout_is_used_once
    pipeline = build_pipeline do
      source [1]
      sink CollectingSink.new
    end
    conflicts = [RunOptions.new(output: "-", rejects: "-"), RunOptions.new(errors: "-", stats: "-")]
    messages = conflicts.map { |options| assert_raises(Metacrunch::UsageError) { apply(options, pipeline) }.message }

    assert_equal ["stdout is used by both --output and --rejects", "stdout is used by both --errors and --stats"],
                 messages
  end

  def test_a_job_without_sink_keeps_stdout_for_its_records
    pipeline = build_pipeline { source [1] }
    error = assert_raises(Metacrunch::UsageError) { apply(RunOptions.new(rejects: "-"), pipeline) }

    assert_equal "stdout is used by both the default output (the job has no sink) and --rejects", error.message
  end

  def test_files_must_not_be_shared
    path = File.join(@dir, "x.jsonl")
    same = File.join(@dir, ".", "x.jsonl")
    pipeline = build_pipeline { source [1] }
    conflicts = [RunOptions.new(input: path, output: same), RunOptions.new(output: path, stats: same)]
    messages = conflicts.map { |options| assert_raises(Metacrunch::UsageError) { apply(options, pipeline) }.message }

    assert_equal ["--input and --output name the same file: #{same}",
                  "--output and --stats name the same file: #{same}"], messages
  end

  def test_links_to_the_same_file_are_recognized
    real = File.join(@dir, "real")
    FileUtils.mkdir_p(real)
    input = File.join(real, "in.jsonl")
    File.write(input, "1\n")
    File.symlink(real, File.join(@dir, "link"))
    File.link(input, File.join(@dir, "hard.jsonl"))
    pipeline = build_pipeline { source [1] }
    conflicts = [RunOptions.new(input:, output: File.join(@dir, "link", "in.jsonl")),
                 RunOptions.new(input:, output: File.join(@dir, "hard.jsonl")),
                 RunOptions.new(output: File.join(real, "new.jsonl"), stats: File.join(@dir, "link", "new.jsonl"))]
    messages = conflicts.map { |options| assert_raises(Metacrunch::UsageError) { apply(options, pipeline) }.message }

    assert_equal(3, messages.count { it.include?("name the same file") })
  end

  def test_limit_and_error_policy_override_the_job
    pipeline = build_pipeline do
      source [1]
      on_error :skip, max_errors: 5
    end
    aborting = apply(RunOptions.new(limit: 3, on_error: :abort), pipeline)
    skipping = apply(RunOptions.new(on_error: :skip), pipeline)
    stricter = apply(RunOptions.new(max_errors: 0), pipeline)

    assert_equal [3, :abort, nil], [aborting.limit, aborting.on_error, aborting.max_errors]
    assert_equal [:skip, 5], [skipping.on_error, skipping.max_errors]
    assert_equal 0, stricter.max_errors
  end

  def test_max_errors_needs_skip
    pipeline = build_pipeline { source [1] }
    error = assert_raises(Metacrunch::UsageError) { apply(RunOptions.new(max_errors: 3), pipeline) }

    assert_equal "--max-errors needs the error policy skip (add --on-error skip)", error.message
  end

  def test_apply_input_leaves_the_sinks_alone
    applied = RunOptions.new.apply_input(build_pipeline { map { it } }, stdin: StringIO.new("1\n"))

    assert_instance_of Metacrunch::JsonLines::Reader, applied.source
    assert_nil applied.sink
  end

  private

  def apply(options, pipeline, stdin: StringIO.new, stdout: StringIO.new)
    options.apply(pipeline, stdin:, stdout:)
  end

end
