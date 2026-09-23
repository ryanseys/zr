# frozen_string_literal: true

# Monitor: a reentrant lock over a Mutex, which ruby loads before the
# program's first line. The owner may enter again; the lock releases at
# the outermost exit. MonitorMixin layers the same over any object.
class Monitor
  def initialize
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

  alias try_mon_enter try_enter
  alias mon_try_enter try_enter

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

  alias mon_enter enter

  def exit
    mon_check_owner
    @count -= 1
    return nil if @count > 0

    @owner = nil
    @mutex.unlock
    nil
  end

  alias mon_exit exit

  def synchronize
    enter
    begin
      yield
    ensure
      self.exit
    end
  end

  alias mon_synchronize synchronize

  def mon_locked? = @mutex.locked?

  def mon_owned? = @mutex.locked? && @owner.equal?(Fiber.current)

  def mon_check_owner
    raise ThreadError, +"current fiber not owner" unless @owner.equal?(Fiber.current)

    nil
  end

  def new_cond = MonitorMixin::ConditionVariable.new(self)

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
end

# monitor.rb, the half CRuby writes in Ruby, whose instance variables a
# program sees as ruby's own shows them.
module MonitorMixin
  Primitive.attr! :ivars

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

  def self.extend_object(obj) # :nodoc:
    super(obj)
    obj.__send__(:mon_initialize)
  end

  def mon_try_enter
    @mon_data.try_enter
  end
  alias try_mon_enter mon_try_enter

  def mon_enter
    @mon_data.enter
  end

  def mon_exit
    mon_check_owner
    @mon_data.exit
  end

  def mon_locked?
    @mon_data.mon_locked?
  end

  def mon_owned?
    @mon_data.mon_owned?
  end

  def mon_synchronize(&b)
    @mon_data.synchronize(&b)
  end
  alias synchronize mon_synchronize

  def new_cond
    unless defined?(@mon_data)
      mon_initialize
      @mon_initialized_by_new_cond = true
    end
    return ConditionVariable.new(@mon_data)
  end

  private

  def initialize(...)
    super
    mon_initialize
  end

  def mon_initialize
    if defined?(@mon_data)
      if defined?(@mon_initialized_by_new_cond)
        return # already initialized.
      elsif @mon_data_owner_object_id == self.object_id
        raise ThreadError, +"already initialized"
      end
    end
    @mon_data = ::Monitor.new
    @mon_data_owner_object_id = self.object_id
  end

  def mon_check_owner
    @mon_data.mon_check_owner
  end
end
