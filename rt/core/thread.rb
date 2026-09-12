# Threads are green: each one runs on a fiber of its own, and control
# moves between them only where a thread blocks (join, sleep, a Queue,
# a Mutex, Thread.stop, Thread.pass). A thread runs until it blocks or
# ends; nothing preempts it. The class keeps the running thread, the
# run queue, and the sleepers with a deadline.
class Thread
  @report_on_exception = true
  @abort_on_exception = false
  @queue = []
  @sleepers = []
  @threads = []
  Primitive.zr_undef_alloc(self)

  class << self
    attr_accessor :report_on_exception, :abort_on_exception
    attr_reader :current, :main

    def new(*args, &block)
      raise ThreadError, "must be called with a block" unless block

      thread = Primitive.zr_class_build(self)
      thread.send(:initialize, *args, &block)
      thread.send(:start, caller(1, 1)&.first)
      thread
    end

    alias start new
    alias fork new

    def list = @threads.dup

    def pass
      @queue << @current
      switch
      nil
    end

    # Whether nothing else could run: no other task is waiting for a
    # turn and none is asleep.
    def alone? = @queue.empty? && @sleepers.empty?

    # The current thread sleeps until `wakeup`. With no other thread
    # to wake it, CRuby says so before it parks.
    def stop
      raise ThreadError, "stopping only thread\n\tnote: use sleep to stop forever" if @threads.size <= 1

      @current.send(:wait, nil, true)
      nil
    end

    def kill(thread) = thread.kill

    def exit = @current.kill

    # `handle_interrupt(Class => :never) { }`: while the block runs,
    # an exception of a class the mask names waits; it arrives when
    # the mask goes.
    def handle_interrupt(mask)
      raise ArgumentError, "unknown mask signature" unless mask.is_a?(Hash)
      raise LocalJumpError, "no block given" unless block_given?

      current.send(:push_mask, mask)
      begin
        yield
      ensure
        current.send(:pop_mask)
      end
    end

    def pending_interrupt?(error = nil) = current.pending_interrupt?(error)

    private

    # A timeout in seconds, as `rb_time_interval` takes one: every
    # wait converts it before it parks.
    def interval(timeout)
      Primitive.attr! :hidden
      raise TypeError, "can't convert #{timeout.nil? ? 'nil' : timeout.class} into time interval" unless timeout.is_a?(Numeric)
      raise ArgumentError, "time interval must not be negative" if timeout.negative?

      timeout.to_f
    end

    # A limit in seconds, as `rb_to_float` takes one: a wait that
    # takes a limit rather than an interval reads it this way, and a
    # limit that has passed simply answers at once. A String names a
    # number that no conversion reads.
    def seconds(limit)
      Primitive.attr! :hidden
      raise TypeError, "no implicit conversion to float from string" if limit.is_a?(String)
      raise TypeError, "can't convert #{limit.nil? ? 'nil' : limit.class} into Float" unless limit.is_a?(Numeric)

      limit.to_f
    end

    # Wakes the waiters that still sleep, `count` of them at the most.
    # A thread that is awake already has its turn coming, and a dead
    # one takes none; so one item pushed wakes one more waiter, not
    # the same one twice.
    def rouse(waiters, count = waiters.size)
      Primitive.attr! :hidden
      woken = 0
      waiters.each do |thread|
        break if woken >= count
        next unless thread.status == "sleep"

        thread.wakeup
        woken += 1
      end
      nil
    end

    # The ids stand above the process's own, and no two threads share
    # one.
    def next_native_id
      Primitive.attr! :hidden
      @native_ids = (@native_ids || Primitive.zr_process_id) + 1
    end

    def boot
      @main = Primitive.zr_class_build(self)
      @main.send(:main!)
      @current = @main
      @threads << @main
    end

    # A loop back edge in compiled Ruby comes here once the kernel's
    # count runs out, so a thread that only computes cannot starve its
    # siblings. A thread with nobody waiting keeps its turn.
    def preempt
      wake_due
      return nil if @queue.empty?

      @queue << @current
      switch
      nil
    end

    # Every sleeper whose deadline has passed joins the run queue.
    # `switch` reaches a sleeper only when the run queue empties, which
    # a thread that only computes never lets happen.
    def wake_due
      return nil if @sleepers.empty?

      now = Process.clock_gettime(Process::CLOCK_MONOTONIC, :nanosecond)
      due, rest = @sleepers.partition { |deadline, _| deadline <= now }
      @sleepers = rest
      due.each do |_, thread|
        thread.send(:timed_out)
        enqueue(thread)
      end
      nil
    end

    # Runs the next thread that can run: the run queue's head, else the
    # sleeper whose deadline comes first once it passes. With neither,
    # a deadly wait is a deadlock, and a plain sleep waits forever.
    def switch(deadly = false)
      # The scheduler's own frame is the runtime's, not the program's, so
      # a thread parked here shows the line that waited, as CRuby shows.
      Primitive.attr! :hidden
      from = @current
      to = @queue.shift
      while to.nil?
        if @sleepers.empty?
          return deadlock if deadly

          Primitive.zr_nanosleep(1_000_000_000)
          to = @queue.shift
        else
          to = next_sleeper
        end
      end
      to.send(:take_over, from) unless to.equal?(from)
      from.send(:interrupted)
    end

    def next_sleeper
      @sleepers.sort_by!(&:first)
      deadline, thread = @sleepers.shift
      left = deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC, :nanosecond)
      Primitive.zr_nanosleep(left) if left > 0
      thread.send(:timed_out)
      thread
    end

    def deadlock
      error = Primitive.zr_fatal_class.new("No live threads left. Deadlock?\n")
      raise error if @current.equal?(@main)

      @main.raise(error)
      switch
    end

    def enqueue(thread)
      @queue << thread unless @queue.include?(thread)
    end

    def dequeue(thread)
      @queue.delete(thread)
    end

    def sleep_until(thread, deadline)
      @sleepers << [deadline, thread]
    end

    def awake(thread)
      @sleepers.reject! { |_, sleeper| sleeper.equal?(thread) }
    end

    def forget(thread)
      @threads.delete(thread)
    end
  end

  def initialize(*args, &block)
    Kernel.raise ThreadError, "must be called with a block" unless block

    @block = block
    @args = args
    @status = :created
    @value = nil
    @exception = nil
    @locals = {}
    @variables = {}
    @name = nil
    @report_on_exception = Thread.report_on_exception
    @abort_on_exception = false
    @killed = false
    @pending = nil
    @kill_tag = Object.new
    @waiters = []
  end

  attr_accessor :report_on_exception, :abort_on_exception
  attr_reader :name

  def name=(name)
    @name = name.nil? ? nil : name.to_str
  end

  def alive? = @status != :dead

  def stop? = @status == :dead || @status == :sleep

  def status
    case @status
    when :dead then @exception ? nil : false
    when :sleep then "sleep"
    else "run"
    end
  end

  def join(limit = nil)
    Kernel.raise ThreadError, "Target thread must not be current thread" if equal?(Thread.current)
    Kernel.raise ThreadError, "Target thread must not be main thread" if equal?(Thread.main) && !Thread.current.equal?(Thread.main)

    deadline = limit.nil? ? nil : Process.clock_gettime(Process::CLOCK_MONOTONIC, :nanosecond) + (Thread.send(:seconds, limit) * 1e9).to_i
    while alive?
      return nil if deadline && Process.clock_gettime(Process::CLOCK_MONOTONIC, :nanosecond) >= deadline

      Thread.current.send(:wait_on, @waiters, deadline, true)
    end
    Kernel.raise @exception if @exception
    self
  end

  def value
    join
    @value
  end

  def kill
    return self if @status == :dead

    if @status == :created
      Thread.send(:dequeue, self)
      finish
    elsif equal?(Thread.current)
      Kernel.exit if equal?(Thread.main)
      throw @kill_tag
    else
      @killed = true
      wakeup
    end
    self
  end

  alias exit kill
  alias terminate kill

  def raise(*args)
    exception = args.empty? ? RuntimeError.new("unhandled exception") : make_exception(*args)
    return Kernel.raise(exception) if equal?(Thread.current)
    return self if @status == :dead

    @pending = exception
    wakeup
    self
  end

  def wakeup
    Kernel.raise ThreadError, "killed thread" if @status == :dead

    if @status == :sleep
      @status = :run
      Thread.send(:awake, self)
      Thread.send(:enqueue, self)
    end
    self
  end

  def run
    wakeup
    Thread.pass
    self
  end

  # Fiber-local storage, keyed by the fiber this thread runs, which is
  # the caller's fiber only where the caller is the thread itself.
  def [](key)
    @locals[local_fiber]&.[](key.to_sym)
  end

  def []=(key, value)
    (@locals[local_fiber] ||= {})[key.to_sym] = value
  end

  def key?(key)
    locals = @locals[local_fiber]
    locals ? locals.key?(key.to_sym) : false
  end

  def keys
    @locals[local_fiber]&.keys || []
  end

  def fetch(key, *default)
    locals = @locals[local_fiber] || {}
    return locals.fetch(key.to_sym, *default) unless block_given?

    Primitive.zr_warn_here_m("block supersedes default value argument") unless default.empty?
    locals.fetch(key.to_sym) { |k| yield k }
  end

  def thread_variable_get(key) = @variables[key.to_sym]

  def thread_variable_set(key, value)
    @variables[key.to_sym] = value
  end

  def thread_variable?(key) = @variables.key?(key.to_sym)

  def thread_variables = @variables.keys

  def inspect
    head = Primitive.zr_obj_head(self)
    head = "#{head}@#{@name}" if @name
    head = "#{head} #{@site}" if @site
    "#{head} #{status || 'dead'}>"
  end

  alias to_s inspect

  # Every thread is a green task on the one native thread, so the
  # priority is a number the thread keeps and the scheduler ignores.
  def priority = @priority || 0

  def priority=(value)
    raise TypeError, "no implicit conversion of #{value.nil? ? 'nil' : value.class} into Integer" unless value.is_a?(Numeric)

    @priority = value.to_int
  end

  def group = @group || ThreadGroup::Default

  # The frames the thread stands in, innermost first, and nil once it has
  # ended. This thread answers from the line that asked, as `caller` does;
  # any other thread is read where it parked.
  def backtrace(start = 0, length = nil)
    return caller(start + 1, length) if equal?(Thread.current)
    return nil unless alive?

    Primitive.zr_fiber_backtrace_m(local_fiber, start, length.nil? ? -1 : length)
  end

  def backtrace_locations(start = 0, length = nil)
    backtrace(start, length)&.map { |row| Thread::Backtrace::Location.new(row) }
  end

  # An id of its own for as long as the thread lives, as the native
  # thread of a CRuby thread has.
  def native_thread_id
    return nil if @status == :dead

    @native_thread_id ||= Thread.send(:next_native_id)
  end

  # Whether an exception another thread sent waits for this one.
  def pending_interrupt?(error = nil)
    return false if @pending.nil?

    error.nil? || @pending.is_a?(error)
  end

  private

  def local_fiber
    Primitive.attr! :hidden
    equal?(Thread.current) ? Fiber.current : @fiber
  end

  def push_mask(mask)
    Primitive.attr! :hidden
    (@masks ||= []) << mask
  end

  # The mask goes, and anything it held back arrives now.
  def pop_mask
    Primitive.attr! :hidden
    @masks.pop
    interrupted
  end

  # Whether an exception waits rather than arrives: the innermost mask
  # that names its class decides.
  def masked?(exception)
    Primitive.attr! :hidden
    return false if @masks.nil?

    @masks.reverse_each do |mask|
      mask.each { |klass, how| return how != :immediate if klass === exception }
    end
    false
  end

  def main!
    Primitive.attr! :hidden
    initialize { nil }
    @status = :run
    @fiber = Fiber.current
    @site = nil
  end

  def start(site)
    Primitive.attr! :hidden
    @site = site && site[0, site.index(":in ")]
    @fiber = Fiber.new { body }
    # The fiber heads a thread of its own, so every fiber made on it
    # belongs to this thread.
    @fiber.send(:__rehome__)
    Primitive.zr_preempt_arm(Thread, :preempt)
    Thread.send(:enqueue, self)
    Thread.instance_variable_get(:@threads) << self
  end

  # The fiber's block: the thread's block, with a kill caught and an
  # exception kept for `join`. When it ends, the joiners wake and the
  # next thread runs; this fiber never runs again.
  def body
    Primitive.attr! :hidden
    @status = :run
    begin
      Primitive.zr_catch(@kill_tag, proc do
        Kernel.raise @pending if @pending
        @value = @block.call(*@args)
      end)
    rescue Exception => e
      @exception = e
      report(e) if @report_on_exception
    end
    finish
    Thread.main.raise(@exception) if @exception && (@abort_on_exception || Thread.abort_on_exception)
    Thread.send(:switch)
    Primitive.zr_unimplemented("a finished thread that runs again")
  end

  def finish
    Primitive.attr! :hidden
    @status = :dead
    Thread.send(:forget, self)
    Thread.send(:rouse, @waiters.dup)
  end

  def report(e)
    Primitive.attr! :hidden
    Primitive.zr_warn_line("#{inspect} terminated with exception (report_on_exception is true):")
    Primitive.zr_error_print_m(e)
  end

  # Control comes here from `from`: this thread's own fiber runs, from
  # wherever it stopped.
  def take_over(from)
    Primitive.attr! :hidden
    Thread.instance_variable_set(:@current, self)
    @status = :run
    from.instance_variable_set(:@fiber, Fiber.current)
    Primitive.zr_fiber_scheduler_switch(@fiber)
  end

  # Back from a switch: a kill or an exception another thread sent
  # takes effect now.
  def interrupted
    Primitive.attr! :hidden
    throw @kill_tag if @killed
    if @pending && !masked?(@pending)
      e = @pending
      @pending = nil
      Kernel.raise e
    end
  end

  # Sleep until `wakeup`, or until `deadline` nanoseconds on the
  # monotonic clock. A deadly wait counts toward a deadlock.
  # Sleeps until woken or the deadline; answers false on the deadline.
  def wait(deadline, deadly)
    Primitive.attr! :hidden
    @status = :sleep
    @timed_out = false
    Thread.send(:sleep_until, self, deadline) if deadline
    Thread.send(:switch, deadly && deadline.nil?)
    !@timed_out
  end

  # Wait on a list whose owner wakes its members.
  def wait_on(list, deadline, deadly)
    Primitive.attr! :hidden
    list << self
    begin
      wait(deadline, deadly)
    ensure
      list.delete(self)
    end
  end

  def timed_out
    Primitive.attr! :hidden
    @status = :run
    @timed_out = true
  end

  def make_exception(klass, message = nil, backtrace = nil)
    Primitive.attr! :hidden
    exception = klass.is_a?(String) ? RuntimeError.new(klass) : (message.nil? ? klass.exception : klass.exception(message))
    exception.set_backtrace(backtrace) if backtrace
    exception
  end

  send(:boot)
end

# What `Process.detach` answers: a thread of its own that waits for
# the child, so no zombie stays behind. Both stand here, where Thread
# exists; CRuby leaves the class with no `new` of its own.
class Process::Waiter < Thread
  attr_reader :pid

  class << self
    undef_method :new
  end
end

module Process
  def self.detach(pid)
    pid = Integer.send(:int_operand, pid)
    waiter = Primitive.zr_class_build(Waiter)
    waiter.instance_variable_set(:@pid, pid)
    waiter.send(:initialize) { Process.wait2(pid)&.last }
    waiter.send(:start, nil)
    waiter
  end
end

# Every thread is in one group; a group lists the threads of its own
# that still live, and an enclosed group takes no more.
class ThreadGroup
  def add(thread)
    raise TypeError, "wrong argument type #{thread.class} (expected VM/thread)" unless thread.is_a?(Thread)
    raise ThreadError, "can't move from the enclosed thread group" if thread.group.enclosed?
    raise ThreadError, "can't move to the enclosed thread group" if enclosed?

    thread.instance_variable_set(:@group, self)
    self
  end

  def list = Thread.list.select { |thread| thread.group.equal?(self) }

  def enclose
    @enclosed = true
    self
  end

  def enclosed? = @enclosed ? true : false

  Default = new
end

class Fiber
  class << self
    # A fiber starts with a copy of its maker's storage, its own Hash,
    # or none. Its block runs inside a catch, so a kill throws to that
    # tag: every ensure on the way runs and no rescue sees it.
    def new(storage: true, &block)
      raise ArgumentError, "tried to create Proc object without a block" unless block

      table = case storage
              when true then current.storage
              when nil, false then {}
              when Hash then storage.dup
              else raise TypeError, "wrong argument type #{storage.class} (expected Hash)"
              end
      tag = Object.new
      f = __new__ { |*args| Primitive.zr_catch(tag, proc { block.call(*args) }) }
      Primitive.zr_hidden_set(f, :__kill__, tag)
      Primitive.zr_hidden_set(f, :__storage__, table)
      f
    end

    # `Fiber.yield`: back to the resumer. What comes back is the next
    # resume's value, or the kill or the exception left for the fiber.
    def yield(*args)
      value = __yield__(*args)
      action = Primitive.zr_hidden_get(current, :__action__)
      return value if action.nil?

      Primitive.zr_hidden_set(current, :__action__, nil)
      Kernel.throw(Primitive.zr_hidden_get(current, :__kill__)) if action == :kill
      Kernel.raise(action)
    end

    def [](key)
      current.send(:storage_table)[storage_key(key)]
    end

    def []=(key, value)
      current.send(:storage_table)[storage_key(key)] = value
    end

    private

    def storage_key(key)
      return key.to_sym if key.is_a?(String)
      raise TypeError, "#{key.inspect} is not a symbol nor a string" unless key.is_a?(Symbol)

      key
    end

    # The exception `Fiber#raise` carries, as `rb_make_exception`
    # builds it.
    def make_exception(args)
      Primitive.attr! :hidden
      return RuntimeError.new("unhandled exception") if args.empty?

      klass, message, backtrace = args
      exception = klass.is_a?(String) ? RuntimeError.new(klass) : (message.nil? ? klass.exception : klass.exception(message))
      exception.set_backtrace(backtrace) if backtrace
      exception
    end
  end

  # `kill`: the fiber leaves where it yielded, running every ensure on
  # the way. A fiber that never ran ends where it stands.
  def kill
    return self unless alive?
    return self if __unborn__ && __terminate__

    tag = Primitive.zr_hidden_get(self, :__kill__)
    return self if tag.nil?

    if equal?(Fiber.current)
      Kernel.throw(tag)
    else
      Primitive.zr_hidden_set(self, :__action__, :kill)
      resume
    end
    self
  end

  # `raise`: the exception arrives in the fiber where it yielded, and
  # the answer is what the fiber does next.
  def raise(*args)
    exception = Fiber.send(:make_exception, args)
    Kernel.raise FiberError, "cannot raise exception on unborn fiber" if __unborn__
    return Kernel.raise(exception) if equal?(Fiber.current)

    Primitive.zr_hidden_set(self, :__action__, exception)
    resume
  end

  def storage
    Kernel.raise ArgumentError, "Fiber storage can only be accessed from the Fiber it belongs to" unless equal?(Fiber.current)

    storage_table.dup
  end

  def storage=(hash)
    Primitive.zr_warn_here_m("Fiber#storage= is experimental and may be removed in the future!")
    raise TypeError, "wrong argument type #{hash.class} (expected Hash)" unless hash.is_a?(Hash) || hash.nil?

    Primitive.zr_hidden_set(self, :__storage__, hash ? hash.dup : {})
  end

  private

  def storage_table
    Primitive.zr_hidden_get(self, :__storage__) || Primitive.zr_hidden_set(self, :__storage__, {})
  end
end

# A mutex holds its owner and its waiters in core-only state, which
# `freeze` does not hold still: a frozen Mutex still locks, as CRuby's
# C fields let it.
class Thread::Mutex
  def initialize
    Primitive.zr_state_set(self, :__owner__, nil)
    Primitive.zr_state_set(self, :__waiters__, [])
  end

  def locked? = !Primitive.zr_hidden_get(self, :__owner__).nil?

  def owned? = Primitive.zr_hidden_get(self, :__owner__).equal?(Fiber.current)

  def try_lock
    return false if locked?

    Primitive.zr_state_set(self, :__owner__, Fiber.current)
    true
  end

  def lock
    raise ThreadError, "deadlock; recursive locking" if owned?

    Thread.current.send(:wait_on, Primitive.zr_hidden_get(self, :__waiters__), nil, true) while locked?
    Primitive.zr_state_set(self, :__owner__, Fiber.current)
    self
  end

  def unlock
    raise ThreadError, "Attempt to unlock a mutex which is not locked" unless locked?
    raise ThreadError, "Attempt to unlock a mutex which is locked by another thread/fiber" unless owned?

    Primitive.zr_state_set(self, :__owner__, nil)
    Primitive.zr_hidden_get(self, :__waiters__).first&.wakeup
    self
  end

  def synchronize
    lock
    begin
      yield
    ensure
      unlock
    end
  end

  # Release the lock, sleep, and take it back: the seconds slept, or
  # nil when the timeout ran out.
  def sleep(timeout = nil)
    Primitive.attr! :ruby
    unlock
    begin
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC, :nanosecond)
      deadline = timeout.nil? ? nil : started + (Thread.send(:interval, timeout) * 1e9).to_i
      woken = Thread.current.send(:wait, deadline, true)
      woken ? ((Process.clock_gettime(Process::CLOCK_MONOTONIC, :nanosecond) - started) / 1e9).round : nil
    ensure
      lock
    end
  end
end

class Thread::ConditionVariable
  def initialize
    @waiters = []
  end

  # What Mutex#sleep answers: the seconds slept, or nil on the timeout.
  def wait(mutex, timeout = nil)
    Primitive.attr! :ruby
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC, :nanosecond)
    deadline = timeout.nil? ? nil : started + (Thread.send(:interval, timeout) * 1e9).to_i
    mutex.unlock
    begin
      woken = Thread.current.send(:wait_on, @waiters, deadline, true)
    ensure
      mutex.lock
    end
    woken ? ((Process.clock_gettime(Process::CLOCK_MONOTONIC, :nanosecond) - started) / 1e9).round : nil
  end

  def signal
    Thread.send(:rouse, @waiters, 1)
    self
  end

  def broadcast
    Thread.send(:rouse, @waiters.dup)
    self
  end
end

class Thread::Queue
  # The first items convert through to_a, as rb_to_array takes them.
  def initialize(items = nil)
    unless items.nil? || items.is_a?(Array)
      raise TypeError, "can't convert #{items.class} into Array" unless items.respond_to?(:to_a)

      converted = items.to_a
      raise TypeError, "can't convert #{items.class} to Array (#{items.class}#to_a gives #{converted.class})" unless converted.is_a?(Array)

      items = converted
    end
    @items = items.nil? ? [] : items.dup
    @closed = false
    @waiters = []
  end

  def push(value)
    raise ClosedQueueError, "queue closed" if @closed

    @items << value
    Thread.send(:rouse, @waiters, 1)
    self
  end

  alias << push
  alias enq push

  def pop(non_block = false, timeout: nil)
    Primitive.attr! :ruby
    raise ArgumentError, "can't set a timeout if non_block is enabled" if non_block && timeout

    deadline = timeout.nil? ? nil : Process.clock_gettime(Process::CLOCK_MONOTONIC, :nanosecond) + (Thread.send(:seconds, timeout) * 1e9).to_i
    while @items.empty?
      return nil if @closed
      raise ThreadError, "queue empty" if non_block
      return nil if deadline && Process.clock_gettime(Process::CLOCK_MONOTONIC, :nanosecond) >= deadline

      Thread.current.send(:wait_on, @waiters, deadline, true)
    end
    @items.shift
  end

  alias shift pop
  alias deq pop

  def close
    @closed = true
    Thread.send(:rouse, @waiters.dup)
    self
  end

  def closed? = @closed

  def empty? = @items.empty?

  def size = @items.size

  alias length size

  def clear
    @items.clear
    self
  end

  def num_waiting = @waiters.size

  def freeze = Primitive.zr_unimplemented("Thread::Queue#freeze")
end

class Thread::SizedQueue < Thread::Queue
  attr_reader :max

  def initialize(max)
    raise ArgumentError, "queue size must be positive" unless max.is_a?(Integer) && max > 0

    super()
    @max = max
    @pushers = []
  end

  def max=(value)
    raise ArgumentError, "queue size must be positive" unless value.is_a?(Integer) && value > 0

    @max = value
    Thread.send(:rouse, @pushers.dup)
    value
  end

  def push(object, non_block = false, timeout: nil)
    Primitive.attr! :ruby
    value = object
    raise ArgumentError, "can't set a timeout if non_block is enabled" if non_block && timeout

    deadline = timeout.nil? ? nil : Process.clock_gettime(Process::CLOCK_MONOTONIC, :nanosecond) + (Thread.send(:seconds, timeout) * 1e9).to_i
    while @items.size >= @max
      raise ClosedQueueError, "queue closed" if @closed
      raise ThreadError, "queue full" if non_block
      return nil if deadline && Process.clock_gettime(Process::CLOCK_MONOTONIC, :nanosecond) >= deadline

      Thread.current.send(:wait_on, @pushers, deadline, true)
    end
    super(value)
  end

  alias << push
  alias enq push

  def pop(non_block = false, timeout: nil)
    Primitive.attr! :ruby
    value = super
    Thread.send(:rouse, @pushers, 1)
    value
  end

  alias shift pop
  alias deq pop

  def close
    super
    Thread.send(:rouse, @pushers.dup)
    self
  end

  def num_waiting = @waiters.size + @pushers.size
end

Mutex = Thread::Mutex
ConditionVariable = Thread::ConditionVariable
Queue = Thread::Queue
SizedQueue = Thread::SizedQueue
