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
    if @owner.equal?(Thread.current)
      @count += 1
      return true
    end
    return false unless @mutex.try_lock

    @owner = Thread.current
    @count = 1
    true
  end

  alias try_mon_enter try_enter
  alias mon_try_enter try_enter

  def enter
    if @owner.equal?(Thread.current)
      @count += 1
    else
      @mutex.lock
      @owner = Thread.current
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

  def mon_owned? = @mutex.locked? && @owner.equal?(Thread.current)

  def mon_check_owner
    raise ThreadError, "current thread not owner" unless @owner.equal?(Thread.current)

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
      @owner = Thread.current
      @count = count
    end
  end
end

module MonitorMixin
  class ConditionVariable
    def initialize(monitor)
      @monitor = monitor
      @cond = Thread::ConditionVariable.new
    end

    def wait(timeout = nil)
      @monitor.mon_check_owner
      @monitor.wait_for_cond(@cond, timeout)
    end

    def wait_while
      wait while yield
    end

    def wait_until
      wait until yield
    end

    def signal
      @monitor.mon_check_owner
      @cond.signal
    end

    def broadcast
      @monitor.mon_check_owner
      @cond.broadcast
    end
  end

  def self.extend_object(object)
    super
    object.send(:mon_initialize)
  end

  def initialize(...)
    super
    mon_initialize
  end

  def mon_initialize
    @mon_data = ::Monitor.new
  end

  def mon_try_enter = mon_data.try_enter

  alias try_mon_enter mon_try_enter

  def mon_enter = mon_data.enter

  def mon_exit
    mon_check_owner
    mon_data.exit
  end

  def mon_locked? = mon_data.mon_locked?

  def mon_owned? = mon_data.mon_owned?

  def mon_synchronize(&block) = mon_data.synchronize(&block)

  alias synchronize mon_synchronize

  def new_cond = ConditionVariable.new(mon_data)

  private

  def mon_check_owner = mon_data.mon_check_owner

  def mon_data
    raise ThreadError, "monitor is not initialized; call mon_initialize first" unless defined?(@mon_data)

    @mon_data
  end
end
