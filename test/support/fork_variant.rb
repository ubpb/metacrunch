# frozen_string_literal: true

# Runs the tests of an engine test class a second time, with the steps in
# two worker processes and batches of three records, so batch boundaries
# fall inside the data: Executor::Fork must give the results of inline
# runs. inline_only names the tests that cannot run with workers (an
# observer, state shared with a step, a step that opens in this process,
# exact stats after an abort in the middle of a batch).
module ForkVariant

  # Fails a test that leaves a child process behind.
  module NoWorkerLeft

    def teardown
      super
      Process.waitpid(-1, Process::WNOHANG)

      flunk("a worker process is left")
    rescue Errno::ECHILD
      nil
    end

  end

  def self.define(test_class, inline_only: [])
    variant = Class.new(test_class) do
      include NoWorkerLeft

      def executor = Metacrunch::Executor::Fork.new(workers: 2, batch_size: 3)
    end
    inline_only.each { variant.undef_method(it) }
    test_class.const_set(:Fork, variant)
  end

end
