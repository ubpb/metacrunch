# frozen_string_literal: true

module Metacrunch
  # Pushes source records through the steps of a pipeline: builds the chain
  # of steps, creates the per-record contexts and applies the failure policy.
  # Records that leave the chain go to an outlet, which has three methods:
  # deliver(record, ctx), reject(record, ctx) and fail(record, ctx).
  # Executors run one Processor per process.
  class Processor

    # Returned by map/filter/reject evaluation when the record goes no further.
    DROPPED = Object.new.freeze

    # The records and contexts a batch step holds until it runs: when it
    # holds size of them, and on flush. run gets the pairs taken out.
    class Batch

      def initialize(size, run)
        @size = size
        @run = run
        @pairs = []
      end

      def add(record, ctx)
        @pairs << [record, ctx]
        flush if @pairs.size >= @size
      end

      def flush
        return if @pairs.empty?

        pairs = @pairs
        @pairs = []
        @run.call(pairs)
      end

    end

    # Wraps errors from later steps and sinks while a flat_map streams its
    # children, so they are not counted as failures of the flat_map step.
    # It inherits from Exception on purpose: the flat_map's Enumerable runs
    # user code around each yield, and a `rescue => e` there must not be
    # able to swallow these errors.
    class DownstreamFailure < Exception # rubocop:disable Lint/InheritException

      attr_reader :original

      def initialize(original)
        @original = original
        super(original.message)
      end

    end

    # stats: the StatsCollector to count in. observer: optional; receives
    # step_in(step, record, ctx) and step_out(step, outputs, ctx).
    def initialize(pipeline, stats:, outlet:, observer: nil)
      @pipeline = pipeline
      @stats = stats
      @outlet = outlet
      @observer = observer
      @on_mark = stats.method(:mark)
      @opened = []
      @batches = []
      @chain = build_chain
      @batches.reverse!
    end

    # Opens the step callables, each object once, in step order.
    def open
      context = OpenContext.new(params: @pipeline.params, logger: @pipeline.logger)
      Components.open(@pipeline.steps.map(&:callable).uniq(&:__id__), context, @opened)
    end

    # Closes the opened step callables in reverse order and returns the
    # first error (see Components.close). A second call closes nothing.
    def close
      opened = @opened
      @opened = []
      Components.close(opened, @pipeline.logger)
    end

    # Pushes one source record through the chain. position: its 1-based
    # number in the source.
    def call(record, position)
      @stats.count_read
      return fail_invalid(record, position) if record.is_a?(InvalidRecord)

      id = @pipeline.id_extractor&.call(record)
      @chain.call(record, Context.new(id:, position:, logger: @pipeline.logger, on_mark: @on_mark))
    end

    # Runs the batch steps on the records they hold, in step order: what a
    # step passes on may fill the buffer of a later one, which runs after it.
    def flush
      @batches.each(&:flush)
      nil
    end

    private

    # A record the source could not read fails as the pseudo-step "source".
    # The observer sees it like a step without output.
    def fail_invalid(invalid, position)
      ctx = Context.new(id: nil, position:, logger: @pipeline.logger, on_mark: @on_mark)
      ctx.step = SOURCE_STEP
      @observer&.step_in(SOURCE_STEP, invalid.raw, ctx)
      begin
        @stats.record_failed(invalid.error)
        handle_failure(SOURCE_STEP, invalid.raw, ctx, invalid.error)
      ensure
        @observer&.step_out(SOURCE_STEP, [], ctx)
      end
    end

    def build_chain
      @pipeline.steps.reverse.reduce(@outlet.method(:deliver)) { |downstream, step| link(step, downstream) }
    end

    # One link of the chain. Only the step itself is covered by the error
    # policy; errors raised further down (later steps, sinks) pass through.
    def link(step, downstream)
      counter = @stats.counter(step.name)
      return batch_link(step, counter, downstream) if step.batch

      step.kind == :flat_map ? flat_map_link(step, counter, downstream) : single_link(step, counter, downstream)
    end

    # map, filter and reject: at most one output, no intermediate Array.
    def single_link(step, counter, downstream)
      lambda do |record, ctx|
        ctx.step = step.name
        counter.input += 1
        @observer&.step_in(step.name, record, ctx)
        begin
          output = evaluate(step, record, ctx)
        rescue *Engine::RECOVERABLE => e
          next fail_observed(step, record, ctx, e)
        end
        @observer&.step_out(step.name, output.equal?(DROPPED) ? [] : [output], ctx)
        if ctx.rejected?
          reject_record(record, ctx)
        elsif output.equal?(DROPPED)
          counter.filtered += 1
        else
          counter.output += 1
          downstream.call(output, ctx)
        end
      end
    end

    # flat_map: streams each child downstream as the step's Enumerable
    # yields it. Children forwarded before an error in the step's own
    # iteration stay forwarded; a reject! during the iteration ends it.
    # The observer's step_out comes after the children went downstream.
    def flat_map_link(step, counter, downstream)
      lambda do |record, ctx|
        ctx.step = step.name
        counter.input += 1
        @observer&.step_in(step.name, record, ctx)
        stream_children(step, counter, downstream, record, ctx) { timed(step) { step.call(record, ctx) } }
      end
    end

    # Streams the children of the Enumerable the block returns (see
    # flat_map_link); flat_map batch steps hand in a record's result.
    def stream_children(step, counter, downstream, record, ctx)
      children = @observer ? [] : nil
      begin
        result = yield
        unless ctx.rejected?
          flat_map_contract!(step, result)
          result.each do |child|
            break if ctx.rejected?

            children&.push(child)
            counter.output += 1
            forward_child(downstream, child, ctx)
          end
        end
      rescue DownstreamFailure => e
        raise e.original, cause: e.original.cause
      rescue Context::Rejected
        return fail_record(step, record, ctx, foreign_rejection) unless ctx.rejected?
      rescue *Engine::RECOVERABLE => e
        return fail_record(step, record, ctx, e)
      ensure
        @observer&.step_out(step.name, children, ctx)
      end
      reject_record(record, ctx) if ctx.rejected?
    end

    # A step with batch: buffers records with their contexts (Batch) and
    # runs the batch function on them; with an observer one at a time.
    def batch_link(step, counter, downstream)
      batch = Batch.new(@observer ? 1 : step.batch, ->(pairs) { run_batch(step, counter, downstream, pairs) })
      @batches << batch
      batch.method(:add)
    end

    # Calls the batch function once for the pairs and applies each result
    # to its record, in order. If the call raises or breaks the contract,
    # every record of the batch fails with that error.
    def run_batch(step, counter, downstream, pairs)
      pairs.each do |record, ctx|
        ctx.step = step.name
        @observer&.step_in(step.name, record, ctx)
      end
      counter.input += pairs.size
      begin
        results = call_batch(step, pairs)
      rescue *Engine::RECOVERABLE => e
        return pairs.each { |record, ctx| fail_observed(step, record, ctx, e) }
      end
      pairs.each_with_index do |(record, ctx), index|
        apply_result(step, counter, downstream, record, ctx, results[index])
      end
    end

    # reject! raises while the contexts are in a batch call.
    def call_batch(step, pairs)
      ctxs = pairs.map(&:last)
      ctxs.each { it.in_batch = true }
      results = timed(step) { step.call_batch(pairs.map(&:first), ctxs) }
      batch_contract!(step, results, pairs.size)
      results
    ensure
      ctxs.each { it.in_batch = false }
    end

    # Applies one result of a batch to its record, as single_link and
    # flat_map_link apply what a step returns. An Exception fails it.
    def apply_result(step, counter, downstream, record, ctx, result)
      return fail_observed(step, record, ctx, result) if result.is_a?(Exception)
      return stream_children(step, counter, downstream, record, ctx) { result } if step.kind == :flat_map

      begin
        output = outcome(step, record, ctx, result)
      rescue *Engine::RECOVERABLE => e
        return fail_observed(step, record, ctx, e)
      end
      @observer&.step_out(step.name, output.equal?(DROPPED) ? [] : [output], ctx)
      if ctx.rejected?
        reject_record(record, ctx)
      elsif output.equal?(DROPPED)
        counter.filtered += 1
      else
        counter.output += 1
        downstream.call(output, ctx)
      end
    end

    def batch_contract!(step, results, size)
      return if results.is_a?(Array) && results.size == size

      got = results.is_a?(Array) ? count(results.size, "result") : results.class
      raise ContractError, "#{step.kind} step #{step.name} returned #{got} for a batch of #{count(size, "record")}; " \
                           "return an Array with one result per record"
    end

    def count(number, noun) = "#{number} #{number == 1 ? noun : "#{noun}s"}"

    def forward_child(downstream, child, ctx)
      downstream.call(child, ctx.copy)
    rescue *Engine::RECOVERABLE => e
      raise DownstreamFailure, e
    end

    # Calls a map, filter or reject step. Returns the output record or
    # DROPPED. Raises ContractError if the step breaks its contract. A
    # reject! ends the step; the rescue lives here and in flat_map_link,
    # not in a method of its own, to keep a call off the hot path.
    def evaluate(step, record, ctx)
      result = timed(step) { step.call(record, ctx) }
      return DROPPED if ctx.rejected?

      outcome(step, record, ctx, result)
    rescue Context::Rejected
      raise foreign_rejection unless ctx.rejected?

      DROPPED
    end

    # The output record or DROPPED for what a map, filter or reject step
    # returned.
    def outcome(step, record, ctx, result)
      case step.kind
      when :map then map_result(step, result)
      when :filter then kept(step, record, ctx, result)
      else kept(step, record, ctx, !result)
      end
    end

    # A Rejected for a record that is not rejected comes from the context
    # of another record.
    def foreign_rejection = ContractError.new("reject! was called on the context of another record")

    def timed(step)
      return yield unless @pipeline.profile

      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      begin
        yield
      ensure
        @stats.step_time(step.name, Process.clock_gettime(Process::CLOCK_MONOTONIC) - started)
      end
    end

    def kept(step, record, ctx, keep)
      return record if keep

      ctx.record_rejection(step.reason) if step.reason
      DROPPED
    end

    def map_result(step, result)
      raise ContractError, "map step #{step.name} returned nil" if result.nil?

      result
    end

    def flat_map_contract!(step, result)
      if result.is_a?(Hash)
        raise ContractError, "flat_map step #{step.name} returned a Hash; return [hash] to emit it as one record"
      end
      return if result.respond_to?(:each)

      raise ContractError, "flat_map step #{step.name} must return an Enumerable, got #{result.class}"
    end

    def reject_record(record, ctx)
      rejection = ctx.rejection
      @stats.step_rejected(rejection.step, rejection.reason)
      @outlet.reject(record, ctx)
    end

    # Applies the failure policy first, so the observer sees ctx.failure
    # under :skip.
    def fail_observed(step, record, ctx, error)
      fail_record(step, record, ctx, error)
    ensure
      @observer&.step_out(step.name, [], ctx)
    end

    def fail_record(step, record, ctx, error)
      @stats.step_failed(step.name, error)
      handle_failure(step.name, record, ctx, error)
    end

    # :abort raises the StepError. :skip logs the failure and hands the
    # record to the outlet, which enforces max_failures.
    def handle_failure(name, record, ctx, error)
      step_error = StepError.new(step: name, record_id: ctx.id, position: ctx.position, error:)
      raise step_error, cause: error if @pipeline.on_failure == :abort

      ctx.failure = Failure.new(error:, step: name)
      ctx.logger.error(step_error.message)
      @outlet.fail(record, ctx)
    end

  end
end
