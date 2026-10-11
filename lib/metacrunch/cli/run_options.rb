# frozen_string_literal: true

module Metacrunch
  class Cli
    # The options of `metacrunch run` that change the pipeline: source and
    # sinks replaced by JSON Lines, the filter default, the limit and the
    # error policy. Paths may be "-" for stdin or stdout.
    RunOptions = Data.define(:input, :output, :rejects, :errors, :stats, :limit, :on_error, :max_errors) do
      def initialize(input: nil, output: nil, rejects: nil, errors: nil, stats: nil, limit: nil, on_error: nil,
                     max_errors: nil)
        super
      end

      # Returns the pipeline with all options applied. Raises UsageError
      # for options that conflict.
      def apply(pipeline, stdin:, stdout:)
        check_stdout!(pipeline)
        check_files!
        apply_input(pipeline, stdin:).with(
          sink: sink(pipeline, stdout), **side_sinks(pipeline, stdout), limit: limit || pipeline.limit,
          **error_policy(pipeline)
        )
      end

      # Only the input: -i, or JSON Lines from stdin for a job without
      # source (the filter default).
      def apply_input(pipeline, stdin:)
        return pipeline.with(source: JsonLines::Reader.new(input == JsonLines::STDIO ? stdin : input)) if input
        return pipeline if pipeline.source
        if stdin.tty?
          raise UsageError, "job has no source and stdin is a terminal; pipe JSON Lines in or use -i PATH"
        end

        pipeline.with(source: JsonLines::Reader.new(stdin))
      end

      private

      def sink(pipeline, stdout)
        return SinkAdapter.new(JsonLines::Writer.new(target(output, stdout))) if output
        return pipeline.sink if pipeline.sink

        SinkAdapter.new(JsonLines::Writer.new(stdout))
      end

      # --rejects and --errors naming the same file share one writer.
      def side_sinks(pipeline, stdout)
        writers = {}
        writer = ->(path) { writers[key(path)] ||= JsonLines::ContextWriter.new(target(path, stdout)) }
        {
          rejects: rejects ? SinkAdapter.new(writer.call(rejects)) : pipeline.rejects,
          errors: errors ? SinkAdapter.new(writer.call(errors)) : pipeline.errors
        }
      end

      def target(path, stdout) = path == JsonLines::STDIO ? stdout : path

      def key(path) = path == JsonLines::STDIO ? path : File.expand_path(path)

      def error_policy(pipeline)
        policy = on_error || pipeline.on_error
        if max_errors && policy != :skip
          raise UsageError, "--max-errors needs the error policy skip (add --on-error skip)"
        end

        {on_error: policy, max_errors: policy == :skip ? max_errors || pipeline.max_errors : nil}
      end

      # Only one option may use stdout. A job without sink uses it for its
      # records unless -o is given.
      def check_stdout!(pipeline)
        options = {"--output" => output, "--rejects" => rejects, "--errors" => errors, "--stats" => stats}
        users = options.select { |_option, path| path == JsonLines::STDIO }.keys
        users.unshift("the default output (the job has no sink)") if output.nil? && pipeline.sink.nil?
        return if users.size < 2

        raise UsageError, "stdout is used by both #{users[0]} and #{users[1]}"
      end

      # A file must not be written twice, or read and written at once, except
      # by --rejects and --errors, which share a writer.
      def check_files!
        options = {"--input" => input, "--output" => output, "--rejects" => rejects, "--errors" => errors,
                   "--stats" => stats}
        files = options.reject { |_option, path| path.nil? || path == JsonLines::STDIO }
        files.to_a.combination(2).each do |(first, first_path), (second, second_path)|
          next if [first, second] == ["--rejects", "--errors"]
          next unless key(first_path) == key(second_path)

          raise UsageError, "#{first} and #{second} name the same file: #{second_path}"
        end
      end
    end
  end
end
