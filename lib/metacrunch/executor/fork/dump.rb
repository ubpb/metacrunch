# frozen_string_literal: true

module Metacrunch
  module Executor
    class Fork
      # Marshal for the frames of a worker, with clear errors for what it
      # cannot dump.
      module Dump

        RESULT_RULE = "with --workers, records, mark and rejection values and ctx.store must be Marshal-able"

        module_function

        # Returns the dumped frame and its error. Exceptions Marshal cannot
        # dump are replaced (see exception). If a record, a mark or rejection
        # value or a store cannot be dumped, the frame ends before that
        # event, and an Error that names its position becomes the frame's
        # error.
        def frame(frame)
          [Marshal.dump(frame), frame[:error]]
        rescue TypeError
          repaired(frame.merge(error: exception(frame[:error]), events: frame[:events].map { dumpable_failure(it) }))
        end

        # error itself if Marshal can dump it. Else a copy it can dump: a
        # StepError keeps its class and message with a replaced cause, any
        # other exception becomes a WorkerError. Both keep the backtrace.
        def exception(error)
          return error if error.nil? || dumpable?(error)

          cause = exception(error.cause)
          if error.is_a?(StepError) && error.cause
            copy = StepError.new(step: error.step, record_id: error.record_id, position: error.position,
                                 error: error.cause)
            copy = with_cause(copy, cause, error.backtrace)
            return copy if dumpable?(copy)
          end
          with_cause(WorkerError.new(error.class.name, error.message), cause, error.backtrace)
        end

        # The index of the first value Marshal cannot dump and its TypeError,
        # or nil.
        def first_undumpable(values)
          values.each_with_index do |value, index|
            Marshal.dump(value)
          rescue TypeError => e
            return [index, e]
          end
          nil
        end

        def dumpable?(value)
          Marshal.dump(value)
          true
        rescue TypeError
          false
        end

        def repaired(frame)
          [Marshal.dump(frame), frame[:error]]
        rescue TypeError
          events = frame[:events]
          index, error = first_undumpable(events)
          position = events[index][2].position
          message = "record at position #{position} cannot be sent from a worker: #{error.message}"
          cut = Error.new("#{message}; #{RESULT_RULE}")
          [Marshal.dump(frame.merge(events: events.first(index), error: cut)), cut]
        end

        # A :fail event whose failure holds an exception Marshal cannot dump
        # gets a replacement.
        def dumpable_failure(event)
          kind, record, state = event
          failure = kind == :fail ? state.failure : nil
          return event if failure.nil? || dumpable?(failure.error)

          [kind, record, state.with(failure: failure.with(error: exception(failure.error)))]
        end

        # Gives a new exception a cause (only raise can set one) and a
        # backtrace.
        def with_cause(exception, cause, backtrace)
          raise exception, cause:
        rescue exception.class => e
          e.set_backtrace(backtrace) if backtrace
          e
        end

      end
    end
  end
end
