# frozen_string_literal: true

module Examples
  # A sink around another sink: writes every mark of the records it gets to
  # a TSV issue report, then hands the records on. A sink receives the
  # contexts when write and write_batch take a second parameter. The wrapped
  # sink must have write_batch(records, ctxs), as JsonLines::Writer has.
  #
  # Marks of rejected and failed records are not reported here: those
  # records go to the rejects and failures sinks, with their marks.
  class IssueReport

    HEADER = "id\tposition\tstep\treason\tvalue\n"

    def initialize(path, sink)
      @path = path
      @sink = sink
    end

    def open(context)
      @file = File.open(@path, "w")
      @file.write(HEADER)
      @sink.open(context) if @sink.respond_to?(:open)
    end

    def write(record, ctx)
      write_batch([record], [ctx])
    end

    def write_batch(records, ctxs)
      ctxs.each { report(it) }
      @sink.write_batch(records, ctxs)
    end

    def close
      @sink.close if @sink.respond_to?(:close)
    ensure
      @file&.close
    end

    private

    def report(ctx)
      ctx.marks.each do |mark|
        @file.write("#{[ctx.id, ctx.position, mark.step, mark.reason, mark.value].join("\t")}\n")
      end
    end

  end
end
