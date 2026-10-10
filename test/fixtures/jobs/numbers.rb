# frozen_string_literal: true

require_relative "lib/printing_sink"

# Multiplies numbers, rejects negative ones and fails on zero.
Metacrunch.job "numbers" do
  params do
    param :factor, Integer, default: 1, desc: "Multiplier"
    param :skip_errors, :bool, default: false, desc: "Skip records that fail"
    args :numbers, min: 1, desc: "Numbers to process"
  end

  source(params.numbers.map { Integer(it) })

  reject("Negative", &:negative?)
  map { |number| number.zero? ? raise(ZeroDivisionError, "zero is not allowed") : number * params.factor }

  sink PrintingSink.new
  on_error :skip if params.skip_errors
end
