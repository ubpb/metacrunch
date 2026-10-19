# frozen_string_literal: true

require "test_helper"
require "json"
require "open3"

class ExeTransformsTest < Minitest::Test

  include CredentialsHelper

  ROOT = File.expand_path("../..", __dir__)
  # Settings of the developer's shell that would change a run.
  CLEAN_ENV = {"METACRUNCH_ENV" => nil, "METACRUNCH_CREDENTIALS" => nil, "METACRUNCH_MASTER_KEY" => nil}.freeze

  FILES = {
    "Metacrunchfile" => "Metacrunch.load_files \"jobs/*.rb\", \"transforms/*.rb\"\n",
    "transforms/checks.rb" => <<~RUBY,
      Metacrunch.transform "checks" do
        reject("No code") { it["code"].nil? }
        map { it.merge("n" => 100 / it.fetch("n")) }
      end
    RUBY
    # A before hook builds the lookup table in the main process; the
    # workers inherit it.
    "transforms/labels.rb" => <<~RUBY,
      Metacrunch.transform "labels" do
        labels = nil
        before { labels = {"a" => "Alpha", "b" => "Beta"} }
        map { it.merge("label" => labels.fetch(it["code"])) }
      end
    RUBY
    "jobs/enrich.rb" => <<~RUBY
      Metacrunch.job "enrich" do
        use "checks"
        use "labels"
        on_failure :skip
      end
    RUBY
  }.freeze

  # One record rejected (no code), one failed (division by zero).
  INPUT = <<~JSONL
    {"code":"a","n":1}
    {"code":"b","n":2}
    {"n":3}
    {"code":"a","n":0}
    {"code":"b","n":4}
  JSONL

  def test_a_job_with_transforms_gives_the_same_results_with_workers
    in_project do |root|
      inline = enrich(root)
      forked = enrich(root, "-w", "2")

      assert_equal inline, forked
      assert_equal [3, ["Alpha", "Beta", "Beta"]], [inline[:status], inline[:records].map { it["label"] }]
      assert_equal ["checks/reject#1", "checks/map#2", "labels/map#1"], inline[:stats]["steps"].keys
    end
  end

  def test_a_transform_runs_alone_through_stdin
    in_project do |root|
      stdout, stderr, status = metacrunch("labels", stdin_data: "{\"code\":\"b\"}\n", chdir: root)

      assert_equal [0, "{\"code\":\"b\",\"label\":\"Beta\"}\n"], [status.exitstatus, stdout], stderr
    end
  end

  private

  # Runs enrich with options and returns what two runs can be compared by:
  # the exit status, the records, the rejects and failures files and the
  # stats without times.
  def enrich(root, *options)
    files = ["rejects", "errors", "stats"].to_h { [it, File.join(root, "#{it}#{options.join}.json")] }
    stdout, stderr, status = metacrunch("run", *options, "--rejects", files["rejects"], "--failures", files["errors"],
                                        "--stats", files["stats"], "enrich", stdin_data: INPUT, chdir: root)
    raise "enrich failed (#{status.exitstatus}): #{stderr}" unless status.exitstatus == 3

    {status: status.exitstatus, records: stdout.lines.map { JSON.parse(it) },
     rejects: File.read(files["rejects"]), failures: File.read(files["errors"]),
     stats: JSON.parse(File.read(files["stats"]))["stats"].except("duration", "rate")}
  end

  # Yields the root of a temporary project with FILES.
  def in_project
    in_tmpdir do |root|
      FILES.each { |path, code| write_file(root, path, "# frozen_string_literal: true\n\n#{code}") }
      yield root
    end
  end

  # HOME points into the project, so ~/.metacrunch is never read.
  def metacrunch(*args, stdin_data:, chdir:)
    command = [RbConfig.ruby, "-I", File.join(ROOT, "lib"), File.join(ROOT, "exe", "metacrunch"), *args]
    Open3.capture3(CLEAN_ENV.merge("HOME" => chdir), *command, stdin_data:, chdir:)
  end

end
