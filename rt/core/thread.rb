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

  class << self
    attr_accessor :report_on_exception, :abort_on_exception
    attr_reader :current, :main

    def new(*args, &block)
      raise ThreadError, "must be called with a block" unless block

      thread = allocate
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

    # The current thread sleeps until `wakeup`.
    def stop
      @current.send(:wait, nil, true)
      nil
    end

    def kill(thread) = thread.kill

    def exit = @current.kill

    def handle_interrupt(*) = Primitive.zr_unimplemented("Thread.handle_interrupt")

    def pending_interrupt?(*) = Primitive.zr_unimplemented("Thread.pending_interrupt?")

    private

    def boot
      @main = allocate
      @main.send(:main!)
      @current = @main
      @threads << @main
    end

    # Runs the next thread that can run: the run queue's head, else the
    # sleeper whose deadline comes first once it passes. With neither,
    # a deadly wait is a deadlock, and a plain sleep waits forever.
    def switch(deadly = false)
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

    deadline = limit.nil? ? nil : Process.clock_gettime(Process::CLOCK_MONOTONIC, :nanosecond) + (limit * 1e9).to_i
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

  # Fiber-local storage, keyed by the fiber reading it.
  def [](key)
    @locals[Fiber.current]&.[](key.to_sym)
  end

  def []=(key, value)
    (@locals[Fiber.current] ||= {})[key.to_sym] = value
  end

  def key?(key)
    locals = @locals[Fiber.current]
    locals ? locals.key?(key.to_sym) : false
  end

  def keys
    @locals[Fiber.current]&.keys || []
  end

  def fetch(key, *default)
    locals = @locals[Fiber.current] || {}
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

  def priority = 0

  def priority=(value)
    value
  end

  def group = Primitive.zr_unimplemented("Thread#group")

  def backtrace(*) = Primitive.zr_unimplemented("Thread#backtrace")

  def native_thread_id = Primitive.zr_unimplemented("Thread#native_thread_id")

  private

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
    @waiters.dup.each(&:wakeup)
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
    if @pending
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

class Fiber
  class << self
    # A fiber starts with a copy of its maker's storage, its own Hash,
    # or none.
    def new(storage: true, &block)
      f = __new__(&block)
      table = case storage
              when true then current.storage
              when nil, false then {}
              when Hash then storage.dup
              else raise TypeError, "wrong argument type #{storage.class} (expected Hash)"
              end
      Primitive.zr_hidden_set(f, :__storage__, table)
      f
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
  end

  def storage = storage_table.dup

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

class Thread::Mutex
  def initialize
    @owner = nil
    @waiters = []
  end

  def locked? = !@owner.nil?

  def owned? = @owner.equal?(Fiber.current)

  def try_lock
    return false if @owner

    @owner = Fiber.current
    true
  end

  def lock
    raise ThreadError, "deadlock; recursive locking" if owned?

    Thread.current.send(:wait_on, @waiters, nil, true) while @owner
    @owner = Fiber.current
    self
  end

  def unlock
    raise ThreadError, "Attempt to unlock a mutex which is not locked" unless @owner
    raise ThreadError, "Attempt to unlock a mutex which is locked by another thread/fiber" unless owned?

    @owner = nil
    @waiters.first&.wakeup
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
    unlock
    begin
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC, :nanosecond)
      deadline = timeout.nil? ? nil : started + (timeout * 1e9).to_i
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
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC, :nanosecond)
    deadline = timeout.nil? ? nil : started + (timeout * 1e9).to_i
    mutex.unlock
    begin
      woken = Thread.current.send(:wait_on, @waiters, deadline, true)
    ensure
      mutex.lock
    end
    woken ? ((Process.clock_gettime(Process::CLOCK_MONOTONIC, :nanosecond) - started) / 1e9).round : nil
  end

  def signal
    @waiters.first&.wakeup
    self
  end

  def broadcast
    @waiters.dup.each(&:wakeup)
    self
  end
end

class Thread::Queue
  def initialize(items = nil)
    items = Array.try_convert(items) || raise(TypeError, "can't convert #{items.class} into Array") unless items.nil?
    @items = items.nil? ? [] : items.dup
    @closed = false
    @waiters = []
  end

  def push(value)
    raise ClosedQueueError, "queue closed" if @closed

    @items << value
    @waiters.first&.wakeup
    self
  end

  alias << push
  alias enq push

  def pop(non_block = false, timeout: nil)
    raise ArgumentError, "can't set a timeout if non_block is enabled" if non_block && timeout

    deadline = timeout.nil? ? nil : Process.clock_gettime(Process::CLOCK_MONOTONIC, :nanosecond) + (timeout * 1e9).to_i
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
    @waiters.dup.each(&:wakeup)
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
    @pushers.dup.each(&:wakeup)
    value
  end

  def push(value, non_block = false, timeout: nil)
    raise ArgumentError, "can't set a timeout if non_block is enabled" if non_block && timeout

    deadline = timeout.nil? ? nil : Process.clock_gettime(Process::CLOCK_MONOTONIC, :nanosecond) + (timeout * 1e9).to_i
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
    value = super
    @pushers.first&.wakeup
    value
  end

  alias shift pop
  alias deq pop

  def close
    super
    @pushers.dup.each(&:wakeup)
    self
  end

  def num_waiting = @waiters.size + @pushers.size
end

Mutex = Thread::Mutex
ConditionVariable = Thread::ConditionVariable
Queue = Thread::Queue
SizedQueue = Thread::SizedQueue
