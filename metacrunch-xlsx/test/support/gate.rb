# frozen_string_literal: true

# Holds a thread inside a call until the test lets it go on, so that the test
# can interrupt it there.
class Gate

  def initialize
    @waiting = Queue.new
    @go = Queue.new
  end

  # Called by the thread that is held.
  def hold
    @waiting << true
    @go.pop
  end

  # Waits until a thread is held; false after 5 seconds without one.
  def held? = !@waiting.pop(timeout: 5).nil?

  def open = @go << true

end
