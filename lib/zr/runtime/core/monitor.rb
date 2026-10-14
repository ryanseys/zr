# frozen_string_literal: true

# Thread::Monitor: a reentrant lock over a Mutex, in the core since ruby
# 4.1 (thread_sync.rb), and Monitor names it. The owner may enter again;
# the lock releases at the outermost exit. MonitorMixin is ruby's own
# monitor.rb, which rubygems loads as ruby starts.
class Thread::Monitor
  def initialize
    Primitive.attr! :hidden
    @mutex = Thread::Mutex.new
    @owner = nil
    @count = 0
  end

  def try_enter
    if @owner.equal?(Fiber.current)
      @count += 1
      return true
    end
    return false unless @mutex.try_lock

    @owner = Fiber.current
    @count = 1
    true
  end

  def enter
    if @owner.equal?(Fiber.current)
      @count += 1
    else
      @mutex.lock
      @owner = Fiber.current
      @count = 1
    end
    nil
  end

  def exit
    mon_check_owner
    @count -= 1
    return nil if @count > 0

    @owner = nil
    @mutex.unlock
    nil
  end

  def synchronize
    enter
    begin
      yield
    ensure
      self.exit
    end
  end

  def mon_locked? = @mutex.locked?

  def mon_owned? = @mutex.locked? && @owner.equal?(Fiber.current)

  def mon_check_owner
    raise ThreadError, +"current fiber not owner" unless @owner.equal?(Fiber.current)

    nil
  end

  def new_cond = ConditionVariable.new(self)

  # Releases the whole monitor for the wait and restores the nesting
  # count after: true when signalled, false on the timeout.
  def wait_for_cond(cond, timeout)
    count = @count
    @owner = nil
    @count = 0
    begin
      !cond.wait(@mutex, timeout).nil?
    ensure
      @owner = Fiber.current
      @count = count
    end
  end

  # Written in Ruby in ruby too, so a program sees its instance variables.
  class ConditionVariable
    Primitive.attr! :ivars

    def wait(timeout = nil)
      @monitor.mon_check_owner
      @monitor.wait_for_cond(@cond, timeout)
    end

    def wait_while
      while yield
        wait
      end
    end

    def wait_until
      until yield
        wait
      end
    end

    def signal
      @monitor.mon_check_owner
      @cond.signal
    end

    def broadcast
      @monitor.mon_check_owner
      @cond.broadcast
    end

    private

    def initialize(monitor) # :nodoc:
      @monitor = monitor
      @cond = Thread::ConditionVariable.new
    end
  end
end

Monitor = Thread::Monitor
