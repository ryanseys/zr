# frozen_string_literal: true

# Threads are green: each one runs on a fiber of its own, all on one OS
# thread. Control moves between them where a thread blocks (join,
# sleep, a Queue, a Mutex, Thread.stop, Thread.pass), and at a safe
# point of compiled code once the timer has fired: every 100 ms after a
# second thread starts (lib/zr/runtime/kernel/send.rb, zr_preempt). The
# core library's own Ruby has no safe points, so each of its methods
# runs whole. The class keeps the running thread, the run queue, and
# the sleepers with a deadline.
class Thread
  @report_on_exception = true
  @abort_on_exception = false
  @queue = []
  @sleepers = []
  @threads = []
  # The threads parked on a descriptor: `[fd, events, thread]` rows,
  # which the scheduler polls when no thread can run.
  @io_waiters = []
  Primitive.zr_undef_alloc(self)
  # rb_uninterruptible's mask: every interrupt waits.
  UNINTERRUPTIBLE = { Object => :never }.freeze
  private_constant :UNINTERRUPTIBLE

  # The scheduler's state is Thread's own: a subclass that reads it
  # reads Thread's.
  class << self
    def report_on_exception = equal?(Thread) ? @report_on_exception : Thread.report_on_exception

    # The flags read back as true or false, as RTEST stores them.
    def report_on_exception=(value)
      return Thread.report_on_exception = value unless equal?(Thread)

      @report_on_exception = value ? true : false
    end

    def abort_on_exception = equal?(Thread) ? @abort_on_exception : Thread.abort_on_exception

    def abort_on_exception=(value)
      return Thread.abort_on_exception = value unless equal?(Thread)

      @abort_on_exception = value ? true : false
    end

    def current = equal?(Thread) ? @current : Thread.current

    def main = equal?(Thread) ? @main : Thread.main

    # thread_s_new: initialize runs (a subclass's can give its own block to
    # super), and then the thread must have been set up.
    def new(*args, &block)
      thread = Primitive.zr_class_build(self)
      thread.send(:initialize, *args, &block)
      raise ThreadError, "uninitialized thread - check #{self}#initialize" unless thread.send(:initialized?)

      thread.send(:start, caller(1, 1)&.first)
      thread
    end

    # thread_start: no initialize of a subclass runs.
    def start(*args, &block)
      raise ArgumentError, +"tried to create Proc object without a block" unless block

      thread = Primitive.zr_class_build(self)
      Thread.instance_method(:initialize).bind_call(thread, *args, &block)
      thread.send(:start, caller(1, 1)&.first)
      thread
    end

    alias fork start

    def list = equal?(Thread) ? @threads.dup : Thread.list

    def pass
      return Thread.pass unless equal?(Thread)

      @queue << @current
      switch
      nil
    end

    # Whether nothing else could run: no other task is waiting for a
    # turn and none is asleep.
    def alone?
      Primitive.attr! :hidden
      @queue.empty? && @sleepers.empty? && @io_waiters.empty?
    end

    # The current thread sleeps until `wakeup`. With no other thread
    # to wake it, CRuby says so before it parks.
    def stop
      return Thread.stop unless equal?(Thread)

      raise ThreadError, +"stopping only thread\n\tnote: use sleep to stop forever" if @threads.size <= 1

      @current.send(:wait, nil, true, resume: true)
      nil
    end

    def kill(thread)
      raise TypeError, "wrong argument type #{conversion_name(thread)} (expected VM/thread)" unless thread.is_a?(Thread)

      thread.kill
    end

    def exit = current.kill

    # `handle_interrupt(Class => :never) { }`: while the block runs,
    # an exception of a class the mask names waits; it arrives when
    # the mask goes.
    def handle_interrupt(mask)
      raise ArgumentError, +"block is needed." unless block_given?

      mask = Hash.try_convert(given = mask) or raise TypeError, "no implicit conversion of #{conversion_name(given)} into Hash"
      raise ArgumentError, +"unknown mask signature" unless mask.each_value.all? { |v| %i[immediate on_blocking never].include?(v) }

      current.send(:push_mask, mask)
      begin
        # An exception that waits and that the new mask lets through
        # arrives before the block runs (rb_thread_s_handle_interrupt).
        current.send(:interrupted)
        yield
      ensure
        current.send(:pop_mask)
      end
    end

    def pending_interrupt?(error = nil) = current.pending_interrupt?(error)

    # rb_uninterruptible: the block runs with every interrupt held back,
    # and after it only those that need no blocking call arrive.
    def uninterruptible
      Primitive.attr! :hidden
      return yield unless Primitive.zr_threaded

      thread = current
      thread.send(:push_mask, UNINTERRUPTIBLE)
      begin
        yield
      ensure
        thread.send(:pop_mask)
      end
    end

    # Where a call that can block starts, as blocking_region_begin: an
    # exception that waits for a blocking call (:on_blocking) arrives.
    def blocking_point
      Primitive.attr! :hidden
      return unless Primitive.zr_threaded

      thread = current
      thread.send(:at_blocking) if thread.pending_interrupt?
    end

    # Whether a deadlock goes unreported: every thread then waits for
    # good, where a signal's handler may still wake one.
    def ignore_deadlock = equal?(Thread) ? @ignore_deadlock == true : Thread.ignore_deadlock

    def ignore_deadlock=(value)
      return Thread.ignore_deadlock = value unless equal?(Thread)

      @ignore_deadlock = value ? true : false
    end

    # Each frame outward from the caller's caller, as a Location.
    # Takes no keywords, and needs a block before it walks.
    def each_caller_location(start = 1, length = nil, **keywords)
      raise ArgumentError, "unknown keyword#{'s' if keywords.size > 1}: #{keywords.keys.map(&:inspect).join(', ')}" unless keywords.empty?
      raise LocalJumpError, +"no block given" unless block_given?

      caller_locations(start + 1, length)&.each { |location| yield location }
      nil
    end

    private

    # A timeout in seconds, as `rb_time_interval` takes one: every
    # wait converts it before it parks.
    def interval(timeout)
      Primitive.attr! :hidden
      raise TypeError, "can't convert #{timeout.nil? ? 'nil' : timeout.class} into time interval" unless timeout.is_a?(Numeric)
      raise ArgumentError, +"time interval must not be negative" if timeout.negative?
      raise RangeError, +"NaN out of Time range" if timeout.is_a?(Float) && timeout.nan?

      timeout.to_f
    end

    # A limit in seconds, as `rb_to_float` takes one: a wait that
    # takes a limit rather than an interval reads it this way, and a
    # limit that has passed returns immediately. A String gives a
    # number that no conversion reads.
    def seconds(limit)
      Primitive.attr! :hidden
      raise TypeError, +"no implicit conversion to float from string" if limit.is_a?(String)
      raise TypeError, "no implicit conversion to float from #{limit}" if limit == true || limit == false
      raise TypeError, +"can't convert nil into Float" if limit.nil?

      # rb_num2dbl: an object that is no Numeric converts with to_f.
      unless limit.is_a?(Numeric)
        converted = Primitive.zr_check_call(limit, :to_f)
        raise TypeError, "can't convert #{conversion_name(limit)} into Float" if converted.nil?
        raise TypeError, "can't convert #{conversion_name(limit)} to Float (#{conversion_name(limit)}#to_f gives #{conversion_name(converted)})" unless converted.is_a?(Float)

        limit = converted
      end
      # A NaN limit waits for nothing, as Queue#pop and Thread#join take it.
      limit = limit.to_f
      limit.nan? ? 0.0 : limit
    end

    # Wakes the waiters that still sleep, `count` of them at the most.
    # A thread that is awake already has its turn coming, and a dead
    # one takes none; so one item pushed wakes one more waiter, not
    # the same one twice.
    def rouse(waiters, count = waiters.size)
      Primitive.attr! :hidden
      woken = 0
      atomically do
        waiters.each do |thread|
          break if woken >= count
          next unless thread.send(:sleeping?)

          thread.wakeup
          woken += 1
        end
      end
      nil
    end

    # The ids are above the process's own, and no two threads share
    # one.
    def next_native_id
      Primitive.attr! :hidden
      @native_ids = (@native_ids || Primitive.zr_process_id) + 1
    end

    # rb_thread_terminate_all: as the program ends, each other thread is
    # killed and runs the ensure clauses of its current fiber; a fiber it
    # left suspended never runs again.
    def terminate_all
      Primitive.attr! :hidden
      others = @threads.reject { |thread| thread.equal?(@current) || !thread.alive? }
      # The main thread is done, as the others' ensure clauses see it.
      Primitive.zr_hidden_set(@main, :ended, true) if @current.equal?(@main)
      others.each(&:kill)
      others.each do |thread|
        thread.join
      rescue Exception # rubocop:disable Lint/RescueException
        nil
      end
      nil
    end

    # A forked child has only the thread that forked, which is its main
    # thread after the fork; all other threads stay in the parent.
    def after_fork
      Primitive.attr! :hidden
      @threads.each { |thread| Primitive.zr_hidden_set(thread, :status, :dead) unless thread.equal?(@current) }
      @threads = [@current]
      @queue = []
      @sleepers = []
      @io_waiters = []
      @main = @current
      Primitive.zr_fiber_after_fork
      Primitive.zr_autoload_after_fork
      Primitive.zr_poll_after_fork
    end

    def boot
      @main = Primitive.zr_class_build(self)
      @main.send(:main!)
      @current = @main
      @threads << @main
    end

    # A safe point in compiled Ruby comes here when the kernel's poll
    # word is set (lib/zr/runtime/kernel/send.rb), so a thread that only computes
    # cannot starve its siblings. A thread with nobody waiting keeps its
    # turn. A tick that lands while the scheduler itself is choosing --
    # its polling of the waiters iterates, and every iteration is a
    # safe point -- is no turn: a switch inside a switch would queue a
    # thread that is parked, and lose it. Nor is one that lands while
    # the thread is finishing: queued, it would come back alive. Nor is
    # one that lands after a wait began and before its switch: the
    # thread sleeps already, and queued it would run with its deadline
    # still standing. The finalizers that a collection queued run here,
    # past these checks, since one may wait for another thread; one that
    # finds a check failing waits for the timer's next tick.
    def preempt
      return nil if @switching || @atomic || Primitive.zr_hidden_get(@current, :status) != :run

      Primitive.zr_finalizers_due
      wake_due
      return nil if @queue.empty? || !@current.send(:quantum_spent?)

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
      due = @sleepers.select { |deadline, _| deadline <= now }
      @sleepers = @sleepers.reject { |deadline, _| deadline <= now }
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
      @switching = true
      from = @current
      while (to = @queue.shift).nil?
        if !@io_waiters.empty?
          poll_waiters
          wake_due
        elsif @sleepers.empty?
          @switching = false
          return deadlock if deadly && !@ignore_deadlock

          @switching = true
          Primitive.zr_nanosleep(1_000_000_000)
        elsif (to = next_sleeper)
          break
        end
      end
      @switching = false
      to.send(:take_over, from) unless to.equal?(from)
      from.send(:interrupted)
    end

    # The sleeper whose deadline comes first, once it passes; nil when a
    # signal cut the wait short, since its handler may have woken
    # another thread.
    def next_sleeper
      @sleepers.sort! { |a, b| a[0] <=> b[0] }
      deadline, thread = @sleepers.first
      left = deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC, :nanosecond)
      return nil if left > 0 && !Primitive.zr_nanosleep(left)

      @sleepers.shift
      thread.send(:timed_out)
      thread
    end

    # One wait on every descriptor that a thread parks on, for as long as
    # the first sleeper allows: each thread whose descriptor became ready
    # wakes. A wait that a signal cut short wakes no thread, and the
    # calling loop looks at the run queue again.
    def poll_waiters
      Primitive.attr! :hidden
      deadline = @sleepers.map(&:first).min
      left = deadline && [((deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC, :nanosecond)) / 1_000_000.0).ceil, 0].max
      waiters = @io_waiters.dup
      ready = Primitive.zr_io_wait_fds(waiters.map { |fd, _, _| fd }, waiters.map { |_, events, _| events }, left || -1)
      if ready.is_a?(Integer)
        # A descriptor closed under its waiter: every waiter looks again.
        waiters.each { |_, _, thread| thread.wakeup if thread.send(:sleeping?) }
        return
      end
      waiters.zip(ready).each do |(_, _, thread), events|
        thread.wakeup if events.positive? && thread.send(:sleeping?)
      end
    end

    def watch(fd, events, thread)
      Primitive.attr! :hidden
      @io_waiters << [fd, events, thread]
    end

    def unwatch(thread)
      Primitive.attr! :hidden
      atomically { @io_waiters.reject! { |_, _, waiter| waiter.equal?(thread) } }
    end

    # A change to a list that the scheduler or a waiter list keeps runs
    # whole, as ruby's C runs under its lock. The core's own Array methods
    # are compiled Ruby, and a preemption in the middle of one would let
    # another thread change the same list.
    def atomically
      Primitive.attr! :hidden
      return yield if @atomic

      @atomic = true
      begin
        yield
      ensure
        @atomic = false
      end
    end

    # rb_notify_fd_close: each other thread that waits on `fd` gets an
    # IOError.
    def fd_closed(fd)
      Primitive.attr! :hidden
      @io_waiters.dup.each do |waited, _, thread|
        thread.raise(IOError, +"stream closed in another thread") if waited == fd && !thread.equal?(@current)
      end
    end

    def deadlock
      error = Primitive.zr_fatal_class.new(+"No live threads left. Deadlock?" << deadlock_report)
      raise error if @current.equal?(@main)

      @main.raise(error)
      switch
    end

    # debug_deadlock_check: each live thread, the threads that join it,
    # and where it waits.
    def deadlock_report
      Primitive.attr! :hidden
      live = @threads.select(&:alive?)
      out = +"\n#{live.size} threads, #{live.count { |t| t.send(:sleeping?) }} sleeps " \
             "current:#{address(@current)} main thread:#{address(@main)}\n"
      live.each do |thread|
        out << "* #{thread.inspect}\n   rb_thread_t:#{address(thread)} native:N/A int:0"
        thread.send(:joiners).each { |joiner| out << "\n    depended by: tb_thread_id:#{address(joiner)}" }
        frames = Primitive.zr_fiber_backtrace_m(thread.send(:local_fiber), 0, -1)
        out << "\n   " << frames.to_a.join("\n   ") << "\n"
      end
      out
    end

    def address(thread) = Primitive.zr_obj_head(thread)[/0x\h+/]

    def enqueue(thread)
      atomically { @queue << thread unless @queue.include?(thread) }
    end

    def dequeue(thread)
      atomically { @queue.delete(thread) }
    end

    def sleep_until(thread, deadline)
      @sleepers << [deadline, thread]
    end

    def awake(thread)
      atomically { @sleepers.reject! { |_, sleeper| sleeper.equal?(thread) } }
    end

    # A thread that ends leaves every list that could wake it.
    def forget(thread)
      atomically { @threads.delete(thread) }
      awake(thread)
      unwatch(thread)
    end
  end

  def initialize(*args, &block)
    Kernel.raise ThreadError, "already initialized thread - #{@block.source_location&.join(":")}" if @block
    Kernel.raise ThreadError, +"must be called with a block" unless block

    # thread_create_core: a thread starts in its creator's group, which
    # must not be frozen. A thread with none set is in the default group,
    # which this leaves unnamed: a program that never names ThreadGroup
    # does not have it.
    creator = Thread.current
    group = creator && Primitive.zr_hidden_get(creator, :group)
    Kernel.raise ThreadError, +"can't start a new thread (frozen ThreadGroup)" if group&.frozen?

    @group = group
    @block = block
    @args = args
    @status = :created
    @value = nil
    @exception = nil
    @locals = {}
    @variables = {}
    # A subclass's initialize may name the thread before it calls super.
    @name = nil unless defined?(@name)
    @report_on_exception = Thread.report_on_exception
    @abort_on_exception = false
    @killed = false
    @aborting = false
    @pending = nil
    # thread_create_core: the creator's handle_interrupt masks hold in the
    # new thread too, until it pushes its own.
    creator_masks = creator && Primitive.zr_hidden_get(creator, :masks)
    @masks = creator_masks.dup if creator_masks
    # ... and its priority.
    @priority = creator.priority if creator
    @kill_tag = Object.new
    @waiters = []
  end

  attr_reader :report_on_exception, :abort_on_exception

  def report_on_exception=(value)
    @report_on_exception = value ? true : false
  end

  def abort_on_exception=(value)
    @abort_on_exception = value ? true : false
  end
  attr_reader :name

  # rb_thread_setname: StringValueCStr allows no NUL character, then the
  # name must be ASCII compatible.
  def name=(name)
    unless name.nil?
      text = Primitive.zr_str_operand(name)
      compatible = text.encoding.ascii_compatible?
      Kernel.raise ArgumentError, +"string contains null byte" if compatible ? text.include?("\0") : text.codepoints.include?(0)
      Kernel.raise ArgumentError, "ASCII incompatible encoding (#{text.encoding})" unless compatible
    end
    @name = name.nil? ? nil : text
    name
  end

  # The main thread that has ended its program reads as dead, though it
  # still waits for the other threads to end (`terminate_all`).
  def alive? = @status != :dead && !@ended

  def stop? = @status == :dead || @status == :sleep || @ended == true

  # Whether the scheduler parks this thread, whatever `status` shows.
  def sleeping?
    Primitive.attr! :hidden
    @status == :sleep
  end

  # A killed thread that still runs its ensure clauses is aborting, unless
  # it sleeps there.
  def status
    return false if @ended

    case @status
    when :dead then @exception ? nil : false
    when :sleep then +"sleep"
    else @killed ? +"aborting" : +"run"
    end
  end

  def join(limit = nil)
    Kernel.raise ThreadError, +"Target thread must not be current thread" if equal?(Thread.current)
    Kernel.raise ThreadError, +"Target thread must not be main thread" if equal?(Thread.main) && !Thread.current.equal?(Thread.main)

    deadline = join_deadline(limit)
    while alive?
      return nil if deadline && Process.clock_gettime(Process::CLOCK_MONOTONIC, :nanosecond) >= deadline

      Thread.current.send(:wait_on, @waiters, deadline, true, self)
    end
    Kernel.raise @exception if @exception
    self
  end

  # thread_join_m: no limit, or one past what a timespec holds, waits
  # without end; a limit of zero or less waits for nothing.
  private def join_deadline(limit)
    Primitive.attr! :hidden
    return nil if limit.nil?

    seconds = Thread.send(:seconds, limit)
    return nil if seconds >= TIMESPEC_SECONDS_MAX

    Process.clock_gettime(Process::CLOCK_MONOTONIC, :nanosecond) + (seconds.clamp(0.0, nil) * 1e9).to_i
  end

  TIMESPEC_SECONDS_MAX = 9.223372036854775807e18
  private_constant :TIMESPEC_SECONDS_MAX

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
      kill_here
    else
      @killed = true
      wakeup
    end
    self
  end

  alias exit kill
  alias terminate kill

  # The exception is made here, with its cause from this thread's `$!`
  # (rb_exception_setup), and raised in the thread. A dead thread ignores
  # it. The value is nil, as ruby's.
  def raise(*args, **opts)
    return nil if @status == :dead

    exception = Exception.send(:setup, args, opts)
    # A thread that raises on itself queues the exception too, so a mask
    # may hold it back.
    Kernel.raise(exception) if equal?(Thread.current) && !masked?(exception)
    @raised_first = !@killed
    @pending = exception
    wakeup
    nil
  end

  def wakeup
    Kernel.raise ThreadError, +"killed thread" if @status == :dead

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
    key = local_key(key)
    @locals[local_fiber]&.[](key)
  end

  # A nil value removes the key, as rb_thread_local_aset does.
  def []=(key, value)
    key = local_key(key)
    Kernel.raise FrozenError.new("can't modify frozen thread locals", receiver: self) if frozen?
    return @locals[local_fiber]&.delete(key) && nil if value.nil?

    (@locals[local_fiber] ||= {})[key] = value
  end

  def key?(key)
    key = local_key(key)
    locals = @locals[local_fiber]
    locals ? locals.key?(key) : false
  end

  def keys
    @locals[local_fiber]&.keys || []
  end

  def fetch(*args)
    raise ArgumentError, "wrong number of arguments (given #{args.size}, expected 1..2)" unless args.size.between?(1, 2)

    key = local_key(args.first)
    default = args.drop(1)
    locals = @locals[local_fiber] || {}
    # rb_thread_fetch: the KeyError's receiver is the thread.
    Kernel.raise KeyError.new("key not found: #{key.inspect}", receiver: self, key: key) unless block_given? || default.any? || locals.key?(key)
    return locals.fetch(key, *default) unless block_given?

    Primitive.zr_warn_here_m("block supersedes default value argument") unless default.empty?
    locals.fetch(key) { |k| yield k }
  end

  def thread_variable_get(key) = @variables[local_key(key)]

  def thread_variable_set(key, value)
    key = local_key(key)
    Kernel.raise FrozenError.new("can't modify frozen thread locals", receiver: self) if frozen?

    @variables[key] = value
  end

  # True for a key whose value is not nil.
  def thread_variable?(key) = !@variables[local_key(key)].nil?

  # rb_check_id: a Symbol, a String or what to_str gives, as its Symbol;
  # any other key is a TypeError.
  def local_key(key)
    Primitive.attr! :hidden
    return key if key.is_a?(Symbol)

    text = key.is_a?(String) ? key : String.try_convert(key)
    Kernel.raise TypeError, "#{key.inspect} is not a symbol nor a string" if text.nil?

    text.to_sym
  end
  private :local_key

  # Whether initialize set the thread up (Thread.new checks).
  def initialized?
    Primitive.attr! :hidden
    !@block.nil?
  end
  private :initialized?

  def thread_variables = @variables.keys

  # A frozen Thread still runs: CRuby keeps a thread's state in C fields,
  # which freezing leaves alone. zr keeps it in instance variables, so
  # freezing marks the thread instead, and the locals' writers check it.
  def freeze
    Primitive.attr! :hidden
    Primitive.zr_state_set(self, :__frozen__, true)
    self
  end

  def frozen?
    Primitive.attr! :hidden
    Primitive.zr_hidden_get(self, :__frozen__) == true
  end

  # A wait that only another thread can end, which counts toward a
  # deadlock, shows as sleep_forever (thread_status_name's detail).
  def inspect
    head = Primitive.zr_obj_head(self)
    head = "#{head}@#{@name}" if @name
    head = "#{head} #{@site}" if @site
    "#{head} #{@forever && sleeping? && !@ended ? 'sleep_forever' : status || 'dead'}>"
  end

  # The threads that wait in a join of this one.
  def joiners
    Primitive.attr! :hidden
    @waiters.dup
  end

  alias to_s inspect

  # The priority scales a thread's turn, as CRuby's time quantum shifts by
  # it: a thread of priority n > 0 keeps its turn for 2**n timer ticks.
  # A tick is the shortest turn, so a negative priority runs as 0.
  def priority = @priority || 0

  # A timer tick of this thread's turn: whether its quantum is spent.
  def quantum_spent?
    Primitive.attr! :hidden
    @ticks = (@ticks || 0) + 1
    @ticks >= 1 << priority.clamp(0, 3)
  end

  # rb_thread_priority_set: NUM2INT, clamped to -3..3.
  def priority=(value)
    @priority = Primitive.zr_index_operand_m(value).clamp(-3, 3)
  end

  def group = @group || ThreadGroup::Default

  # The frames of the thread, innermost first, and nil after it has
  # ended. The current thread returns them from the calling line, as
  # `caller` does; another thread is read where it is parked.
  # The current thread's frames start at this method's own, as ruby's
  # do. A Range selects from all of them.
  def backtrace(start = 0, length = nil)
    return length.nil? ? caller(start) : caller(start, length) if equal?(Thread.current)
    return nil unless alive?
    return Primitive.zr_fiber_backtrace_m(local_fiber, 0, -1)&.[](start) if Range === start

    Primitive.zr_fiber_backtrace_m(local_fiber, start, length.nil? ? -1 : length)
  end

  def set_trace_func(hook) = TracePoint.send(:trace_func, hook, self, false)

  def add_trace_func(hook)
    raise TypeError, +"trace_func needs to be Proc" unless hook.is_a?(Proc)

    TracePoint.send(:trace_func, hook, self, true)
  end

  def backtrace_locations(start = 0, length = nil)
    return length.nil? ? caller_locations(start) : caller_locations(start, length) if equal?(Thread.current)

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

  # Whether `fiber` is the thread's own; @fiber is where the thread
  # stopped.
  def root?(fiber)
    Primitive.attr! :hidden
    fiber.equal?(@root)
  end

  # A kill ends the thread where it runs. In a fiber that the thread
  # resumed, it ends that fiber first, each ensure on the way running,
  # and goes on in the fiber that resumed it, as ruby's kill crosses
  # fibers.
  def kill_here
    Primitive.attr! :hidden
    @killed = true
    # The unwind runs the ensure clauses, which a later switch must not
    # interrupt again.
    @aborting = true
    fiber = Fiber.current
    resumer = Primitive.zr_fiber_prev_m(fiber) unless root?(fiber)
    tag = resumer && Primitive.zr_hidden_get(fiber, :__kill__)
    throw @kill_tag unless tag

    Primitive.zr_hidden_set(resumer, :__action__, :thread_kill)
    throw tag
  end

  def at_blocking
    Primitive.attr! :hidden
    @blocking = true
    interrupted
  ensure
    @blocking = false
  end

  def push_mask(mask)
    Primitive.attr! :hidden
    (@masks ||= []) << mask
  end

  # The mask is removed, and anything it kept back arrives now.
  def pop_mask
    Primitive.attr! :hidden
    @masks.pop
    interrupted
  end

  # Whether an exception waits rather than arrives: the innermost mask
  # that includes its class decides. `:on_blocking` lets it through while
  # the thread waits in a blocking call.
  def masked?(exception)
    Primitive.attr! :hidden
    return false if @masks.nil?

    @masks.reverse_each do |mask|
      mask.each { |klass, how| return !(how == :immediate || (how == :on_blocking && @blocking)) if klass === exception }
    end
    false
  end

  def main!
    Primitive.attr! :hidden
    initialize { nil }
    @status = :run
    @root = @fiber = Fiber.current
    @site = nil
    @armed = true
  end

  def start(site)
    Primitive.attr! :hidden
    @site = site && site[0, site.index(":in ")]
    # A thread's own fiber blocks, as every thread's root fiber does.
    @root = @fiber = Fiber.new(blocking: true) { body }
    # The fiber heads a thread of its own, so every fiber made on it
    # belongs to this thread.
    Primitive.zr_fiber_rehome(@fiber)
    Primitive.zr_preempt_arm(Thread, :preempt)
    Thread.send(:enqueue, self)
    Primitive.zr_hidden_get(Thread, :threads) << self
  end

  # The fiber's block: the thread's block, with a kill caught and an
  # exception kept for `join`. When it ends, the joiners wake and the
  # next thread runs; this fiber never runs again.
  def body
    Primitive.attr! :hidden
    @status = :run
    TracePoint.send(:thread_event, :thread_begin, self)
    begin
      Primitive.zr_catch(@kill_tag, proc do
        # A kill or an exception that another thread sent arrives only
        # while the catch and the rescue are active. One that came before
        # waits for them here, and after them no body is left to stop.
        @armed = true
        begin
          throw @kill_tag if @killed
          Kernel.raise @pending if @pending
          begin
            @value = @block.call(*@args)
          ensure
            close_scheduler
          end
        ensure
          @armed = false
        end
      end)
    rescue Exception => e
      @exception = e
      # thread_start_func_2 reports no SystemExit.
      report(e) if @report_on_exception && !e.is_a?(SystemExit)
    end
    # After the scheduler is closed and before the joiners wake, which
    # is where thread_start_func_2 fires it, whether the body ended or
    # raised.
    TracePoint.send(:thread_event, :thread_end, self)
    finish
    # A thread that forked is the child's main thread, so its end ends the
    # child, as the main thread's end does.
    Primitive.zr_proc_child_exit(@exception) if equal?(Thread.main)
    # thread_do_start: a SystemExit, or any exception under abort_on_exception
    # or $DEBUG, goes on in the main thread.
    Thread.main.raise(@exception) if @exception && (@abort_on_exception || Thread.abort_on_exception || $DEBUG || @exception.is_a?(SystemExit))
    Thread.send(:switch)
    Primitive.zr_unimplemented(+"a finished thread that runs again")
  end

  def scheduler
    Primitive.attr! :hidden
    @scheduler
  end

  def scheduler=(scheduler)
    Primitive.attr! :hidden
    @scheduler = scheduler
  end

  # rb_fiber_scheduler_close: `scheduler_close`, else `close`, runs the
  # scheduler's fibers to their end, and the thread has none after.
  def close_scheduler
    Primitive.attr! :hidden
    scheduler = @scheduler or return
    begin
      if scheduler.respond_to?(:scheduler_close)
        scheduler.scheduler_close
      elsif scheduler.respond_to?(:close)
        scheduler.close
      end
    ensure
      @scheduler = nil
    end
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
    Primitive.zr_hidden_set(Thread, :current, self)
    @status = :run
    @ticks = 0
    Primitive.zr_hidden_set(from, :fiber, Fiber.current)
    Primitive.zr_fiber_scheduler_switch(@fiber)
  end

  # Back from a switch: a kill or an exception another thread sent
  # takes effect now.
  def interrupted
    Primitive.attr! :hidden
    return unless @armed

    # The interrupts arrive in the order they were sent: an exception
    # sent before a kill ends the thread as that exception. One sent while
    # the kill unwinds replaces it, as an exception raised in an ensure
    # replaces the error that ran it.
    if @pending && !masked?(@pending) && (!@killed || @raised_first || @aborting)
      e = @pending
      @pending = nil
      Kernel.raise e
    end
    kill_here if @killed && !@aborting
  end

  # Sleep until `wakeup`, or until `deadline` nanoseconds on the
  # monotonic clock. A deadly wait counts toward a deadlock.
  # Sleeps until woken or the deadline; returns false on the deadline.
  def wait(deadline, deadly, resume: false)
    Primitive.attr! :hidden
    @status = :sleep
    @forever = deadly && deadline.nil?
    @timed_out = false
    Thread.send(:sleep_until, self, deadline) if deadline
    begin
      @blocking = true
      # An exception held for a blocking call arrives as the wait starts.
      interrupted if @pending
      Thread.send(:switch, deadly && deadline.nil?)
    ensure
      @blocking = false
      # Still asleep: a signal's handler raised while this thread waited.
      if @status == :sleep
        @status = :run
        Thread.send(:awake, self)
      end
    end
    # Woken for a signal: its commands run here. A sleep then goes on
    # sleeping; any other wait returns, and its caller checks again what
    # it waits for.
    if @signalled
      @signalled = false
      Signal.send(:deliver)
      return wait(deadline, deadly, resume: true) if resume && !@timed_out
    end
    !@timed_out
  end

  # A signal came while another thread ran: the main thread runs its
  # commands, so it wakes if it sleeps.
  def signalled
    Primitive.attr! :hidden
    return nil unless @status == :sleep

    @signalled = true
    wakeup
    nil
  end

  # rb_thread_wait_for_single_fd: the events of `events` that `fd` came
  # ready for, 0 once `deadline` (nanoseconds on the monotonic clock)
  # passes, or the negated errno.
  def wait_io(fd, events, deadline)
    Primitive.attr! :hidden
    ready = wait_fds([fd], [events], deadline)
    ready.is_a?(Integer) ? ready : ready.first
  end

  # The events each descriptor of `fds` came ready for, from its row of
  # `events`; all zero once `deadline` passes; or the negated errno. A
  # thread alone waits in the system call itself; among others it parks,
  # and the scheduler polls for it while no thread can run. A wakeup
  # does not end the wait; a raise or a kill does.
  def wait_fds(fds, events, deadline)
    Primitive.attr! :hidden
    loop do
      left = deadline && [((deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC, :nanosecond)) / 1_000_000.0).ceil, 0].max
      alone = !Primitive.zr_threaded || Thread.send(:alone?)
      ready = Primitive.zr_io_wait_fds(fds, events, alone ? (left || -1) : 0)
      return ready if ready.is_a?(Integer) || ready.any?(&:positive?) || left&.zero?
      next if alone

      fds.zip(events) { |fd, wanted| Thread.send(:watch, fd, wanted, self) }
      begin
        wait(deadline, false)
      ensure
        Thread.send(:unwatch, self)
      end
    end
  end

  # One park on `fd`: it ends when the scheduler finds `fd` ready, or when
  # another thread wakes this one. The caller checks again what it
  # waits for.
  def park_io(fd, events)
    Primitive.attr! :hidden
    Thread.send(:watch, fd, events, self)
    wait(nil, false)
  ensure
    Thread.send(:unwatch, self)
  end

  # Wait on a list whose owner wakes its members. A non-blocking fiber
  # waits through its scheduler, which hears what it waits on.
  def wait_on(list, deadline, deadly, blocker = list)
    Primitive.attr! :hidden
    scheduler = Fiber.current_scheduler
    return Fiber.send(:block_on, scheduler, list, blocker, deadline) if scheduler

    list << self
    begin
      wait(deadline, deadly)
    ensure
      Thread.send(:atomically) { list.delete(self) }
    end
  end

  def timed_out
    Primitive.attr! :hidden
    @status = :run
    @timed_out = true
  end

  send(:boot)
end

# The value that `Process.detach` returns: a separate thread that waits
# for the child, so no zombie stays. Both are defined here, where Thread
# exists; CRuby gives the class no `new` of its own.
class Process::Waiter < Thread
  attr_reader :pid

  class << self
    undef_method :new
  end
end

module Process
  def detach(pid)
    pid = Integer.send(:int_operand, pid)
    waiter = Primitive.zr_class_build(Waiter)
    Primitive.zr_hidden_set(waiter, :pid, pid)
    # detach_process_watcher: a pid that is no child ends the thread
    # with nil, and the thread keeps the pid as its :pid thread-local.
    waiter.send(:initialize) do
      Process.wait2(pid)&.last
    rescue Errno::ECHILD
      nil
    end
    waiter.send(:start, nil)
    waiter[:pid] = pid
    waiter
  end
  module_function :detach
end

# Every thread is in one group; a group lists the threads of its own
# that still live, and an enclosed group takes no more.
class ThreadGroup
  def add(thread)
    raise TypeError, "wrong argument type #{conversion_name(thread)} (expected VM/thread)" unless thread.is_a?(Thread)
    raise ThreadError, +"can't move to the frozen thread group" if frozen?
    raise ThreadError, +"can't move to the enclosed thread group" if enclosed?
    raise ThreadError, +"can't move from the frozen thread group" if thread.group.frozen?
    raise ThreadError, +"can't move from the enclosed thread group" if thread.group.enclosed?

    Primitive.zr_hidden_set(thread, :group, self)
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
  # A fiber that waits through its scheduler, as a thread waits in a
  # waiter list: waking it tells the scheduler to unblock it, once.
  class Blocked
    def initialize(scheduler, blocker, fiber)
      @scheduler = scheduler
      @blocker = blocker
      @fiber = fiber
      @woken = false
    end

    def status = @woken ? +"run" : +"sleep"

    def woken? = @woken

    def wakeup
      return self if @woken

      @woken = true
      @scheduler.unblock(@blocker, @fiber)
      self
    end
  end
  private_constant :Blocked

  # A fiber starts with a copy of its maker's storage, its own copy of
  # the Hash it is given, or none yet for nil. Its block runs inside a
  # catch, so a kill throws to that tag: every ensure on the way runs
  # and no rescue sees it. rb_fiber_initialize_kw checks the storage,
  # then the block, then whether the fiber was made already.
  def initialize(blocking: false, pool: nil, storage: true, &block)
    table = storage.equal?(true) ? Fiber.current.storage : Fiber.send(:checked_storage, storage)&.dup
    Kernel.raise ArgumentError, +"tried to create Proc object without a block" unless block

    tag = Object.new
    # The first resume's keywords reach the block as keywords.
    # Only keywords given go on: an empty `**` would keep a lone Array
    # whole.
    __make__ { |*args, **kw| Primitive.zr_catch(tag, proc { kw.empty? ? block.call(*args) : block.call(*args, **kw) }) }
    Primitive.zr_hidden_set(self, :__kill__, tag)
    Primitive.zr_hidden_set(self, :__block__, block)
    Primitive.zr_hidden_set(self, :__storage__, table)
    Primitive.zr_hidden_set(self, :__blocking__, blocking ? true : false)
  end

  class << self
    # 1 while the current fiber blocks, as CRuby counts the thread's
    # blocking fibers, and false while it does not.
    def blocking? = current.blocking? ? 1 : false

    # The block runs with the current fiber blocking.
    def blocking
      fiber = current
      return yield(fiber) if fiber.blocking?

      Primitive.zr_hidden_set(fiber, :__blocking__, true)
      begin
        yield fiber
      ensure
        Primitive.zr_hidden_set(fiber, :__blocking__, false)
      end
    end

    # The current thread's scheduler, which its non-blocking fibers hand
    # their blocking operations to.
    def scheduler = Thread.current.send(:scheduler)

    # The scheduler, while the current fiber does not block.
    def current_scheduler = current.blocking? ? nil : scheduler

    # rb_fiber_scheduler_set: the hooks every scheduler needs, checked;
    # the previous scheduler closed, so its fibers finish under it.
    def set_scheduler(scheduler)
      unless scheduler.nil?
        %i[block unblock kernel_sleep io_wait].each do |hook|
          raise ArgumentError, "Scheduler must implement ##{hook}" unless scheduler.respond_to?(hook)
        end
        Primitive.zr_warn_here_m("Scheduler should implement #fiber_interrupt") unless scheduler.respond_to?(:fiber_interrupt)
      end
      Thread.current.send(:close_scheduler)
      Thread.current.send(:scheduler=, scheduler)
    end

    def schedule(...)
      scheduler = Thread.current.send(:scheduler) or raise RuntimeError, +"No scheduler is available!"

      scheduler.fiber(...)
    end

    # rb_nogvl with RB_NOGVL_OFFLOAD_SAFE: a call that may block, such as
    # open(2) or close(2), which a non-blocking fiber's scheduler runs on
    # its own terms through blocking_operation_wait. The call runs here
    # where the scheduler has no such hook or never runs the operation.
    def offloaded(&work)
      Primitive.attr! :hidden
      scheduler = current_scheduler
      return work.call unless scheduler.respond_to?(:blocking_operation_wait)

      operation = blocking_operation.new
      operation.send(:queue, work)
      scheduler.blocking_operation_wait(operation)
      operation.send(:finish) { work.call }
    end

    # Fiber::Scheduler::BlockingOperation, a class CRuby keeps unnamed:
    # `call` runs the operation once.
    def blocking_operation
      Primitive.attr! :hidden
      Primitive.zr_hidden_get(self, :__blocking_operation__) ||
        Primitive.zr_hidden_set(self, :__blocking_operation__, Class.new do
          def call
            raise RuntimeError, +"Blocking operation has already been executed!" unless @status == :queued
            raise RuntimeError, +"Blocking operation has no function to execute!" if @work.nil?

            @status = :executing
            @result = @work.call
            @status = :completed
            nil
          end

          private

          def queue(work)
            @work = work
            @status = :queued
          end

          # The operation's result, or the block's return value when the
          # operation never ran. In both cases it does not run again.
          def finish
            queued = @status == :queued
            @work = nil
            queued ? yield : @result
          end
        end)
    end
    private :offloaded, :blocking_operation

    # `Fiber.yield`: back to the resumer. What comes back is the next
    # resume's value, or the kill or the exception left for the fiber.
    def yield(*args) = take_action(__yield__(*args))

    # A read makes no storage.
    def [](key)
      key = storage_key(key)
      Primitive.zr_hidden_get(current, :__storage__)&.[](key)
    end

    # A nil value removes the key, as fiber_storage_set does.
    def []=(key, value)
      key = storage_key(key)
      return Primitive.zr_hidden_get(current, :__storage__)&.delete(key) && nil if value.nil?

      current.send(:storage_table)[key] = value
    end

    private

    # fiber_storage_validate: nil, or an unfrozen Hash keyed by Symbols.
    def checked_storage(storage)
      Primitive.attr! :hidden
      return nil if storage.nil?
      raise TypeError, +"storage must be a hash" unless storage.is_a?(Hash)
      raise FrozenError, +"storage must not be frozen" if storage.frozen?

      storage.each_key do |key|
        raise TypeError, "wrong argument type #{conversion_name(key)} (expected Symbol)" unless key.is_a?(Symbol)
      end
      storage
    end

    # A non-blocking fiber waits through its scheduler: it joins `list`
    # as a waiter the list's owner wakes with the scheduler's `unblock`.
    # Whether it was woken before `deadline`.
    def block_on(scheduler, list, blocker, deadline)
      Primitive.attr! :hidden
      waiter = Blocked.new(scheduler, blocker, current)
      list << waiter
      begin
        timeout = deadline && [(deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC, :nanosecond)) / 1e9, 0.0].max
        scheduler.block(blocker, timeout)
      ensure
        Thread.send(:atomically) { list.delete(waiter) }
      end
      waiter.woken?
    end

    # The main thread's scheduler runs its fibers to their end before
    # the program's exit handlers, as rb_ec_teardown closes it.
    def finalize_scheduler
      Primitive.attr! :hidden
      Thread.main.send(:close_scheduler)
    end

    def storage_key(key)
      return key.to_sym if key.is_a?(String)
      # rb_check_id: what to_str gives.
      text = String.try_convert(key) unless key.is_a?(Symbol)
      return text.to_sym if text
      raise TypeError, "#{key.inspect} is not a symbol nor a string" unless key.is_a?(Symbol)

      key
    end

    # Back in the current fiber after it yielded or transferred away:
    # the value it was handed, or the kill or the exception left for it.
    def take_action(value)
      Primitive.attr! :hidden
      action = Primitive.zr_hidden_get(current, :__action__)
      return value if action.nil?

      Primitive.zr_hidden_set(current, :__action__, nil)
      Thread.current.send(:kill_here) if action == :thread_kill
      Kernel.throw(Primitive.zr_hidden_get(current, :__kill__)) if action == :kill
      Kernel.raise(action)
    end
  end

  # `kill`: the fiber leaves where it yielded, running every ensure on
  # the way. A fiber that never ran ends where it is.
  def kill
    return self unless alive?
    return self if Primitive.zr_fiber_unborn_p(self) && Primitive.zr_fiber_terminate(self)

    # The root fiber of a thread other than the main one: the kill ends
    # the thread.
    thread = Thread.current
    thread.send(:kill_here) if thread.send(:root?, self) && !thread.equal?(Thread.main)
    # The main thread's own fiber has no tag: it ignores its own kill,
    # and another thread's resume of it is refused.
    tag = Primitive.zr_hidden_get(self, :__kill__)
    return self if tag.nil? && thread.send(:root?, self)

    if equal?(Fiber.current)
      Kernel.throw(tag)
    else
      deliver(:kill)
    end
    self
  end

  # `resume`: runs the fiber until it yields or ends. A kill of the
  # thread that ended the fiber goes on here.
  def resume(...) = Fiber.send(:take_action, __resume__(...))

  # `transfer`: control moves to the fiber, which comes back with the
  # kill or the exception left for it, if any.
  def transfer(*args) = Fiber.send(:take_action, __transfer__(*args))

  # `raise`: the exception arrives in the fiber where it yielded, and
  # the return value is what the fiber does next.
  def raise(*args, **opts)
    exception = Exception.send(:setup, args, opts)
    Kernel.raise FiberError, +"cannot raise exception on unborn fiber" if Primitive.zr_fiber_unborn_p(self)
    return Kernel.raise(exception) if equal?(Fiber.current)

    deliver(exception)
  end

  # The frame records where the fiber is: none before it starts or after
  # it ends.
  def backtrace(start = 0, length = nil)
    return caller(start, length) if equal?(Fiber.current)
    return [] if !alive? || Primitive.zr_fiber_unborn_p(self)

    Primitive.zr_fiber_backtrace_m(self, start, length.nil? ? -1 : length)
  end

  def backtrace_locations(start = 0, length = nil)
    backtrace(start, length)&.map { |row| Thread::Backtrace::Location.new(row) }
  end

  def inspect = Primitive.zr_fiber_inspect_m(self, Primitive.zr_hidden_get(self, :__block__))

  alias to_s inspect

  # A fiber that Fiber.new made blocks when it was told to; a thread's
  # own fiber always blocks.
  def blocking? = Primitive.zr_hidden_get(self, :__blocking__) != false

  def storage
    Kernel.raise ArgumentError, +"Fiber storage can only be accessed from the Fiber it belongs to" unless equal?(Fiber.current)

    # nil until a key is set.
    Primitive.zr_hidden_get(self, :__storage__)&.dup
  end

  def storage=(hash)
    Primitive.zr_warn_here_m("Fiber#storage= is experimental and may be removed in the future!")
    Kernel.raise ArgumentError, +"Fiber storage can only be accessed from the Fiber it belongs to" unless equal?(Fiber.current)

    Primitive.zr_hidden_set(self, :__storage__, Fiber.send(:checked_storage, hash)&.dup)
  end

  private

  # fiber_raise: the action reaches the fiber this one resumed, if any;
  # the current fiber raises it, a fiber that transferred away is
  # transferred to, and one that yielded is resumed.
  def deliver(action)
    Primitive.attr! :hidden
    return Kernel.raise(action) if equal?(Fiber.current)

    resumed = Primitive.zr_fiber_resuming_m(self)
    # A kill of a fiber that resumed another ends that one first; this one
    # ends as control comes back to it.
    if resumed && action == :kill
      Primitive.zr_hidden_set(self, :__action__, :kill)
      return resumed.kill
    end
    return resumed.send(:deliver, action) if resumed

    Primitive.zr_hidden_set(self, :__action__, action)
    begin
      Primitive.zr_fiber_transferred_away_p(self) ? transfer : resume
    rescue FiberError
      # The fiber did not run, so the action is not left for it.
      Primitive.zr_hidden_set(self, :__action__, nil)
      Kernel.raise
    end
  end

  def storage_table
    Primitive.attr! :hidden
    Primitive.zr_hidden_get(self, :__storage__) || Primitive.zr_hidden_set(self, :__storage__, {})
  end
end

# A mutex keeps its owner and its waiters in core-only state, which
# `freeze` does not freeze: a frozen Mutex still locks, as CRuby's
# C fields let it.
class Thread::Mutex
  def initialize
    Primitive.zr_state_set(self, :__owner__, nil)
    Primitive.zr_state_set(self, :__waiters__, [])
    nil
  end

  def locked? = !owner.nil?

  def owned? = owner.equal?(Fiber.current)

  def try_lock
    return false if locked?

    Primitive.zr_state_set(self, :__owner__, Fiber.current)
    Primitive.zr_state_set(self, :__thread__, Thread.current)
    true
  end

  def lock
    raise ThreadError, +"deadlock; recursive locking" if owned?

    Thread.current.send(:wait_on, waiters, nil, true, self) while locked?
    Primitive.zr_state_set(self, :__owner__, Fiber.current)
    Primitive.zr_state_set(self, :__thread__, Thread.current)
    self
  end

  def unlock
    raise ThreadError, +"Attempt to unlock a mutex which is not locked" unless locked?
    raise ThreadError, +"Attempt to unlock a mutex which is locked by another thread/fiber" unless owned?

    Primitive.zr_state_set(self, :__owner__, nil)
    # A forked child keeps the parent's waiters, which are dead in it.
    waiters.reject! { |waiter| waiter.is_a?(Thread) && !waiter.alive? }
    waiters.first&.wakeup
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
    # The duration is checked before the lock is released.
    Thread.send(:interval, timeout) unless timeout.nil?
    unlock
    begin
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC, :nanosecond)
      deadline = timeout.nil? ? nil : started + (Thread.send(:interval, timeout) * 1e9).to_i
      scheduler = Fiber.current_scheduler
      woken = scheduler ? (scheduler.kernel_sleep(timeout); true) : Thread.current.send(:wait, deadline, true)
      woken ? ((Process.clock_gettime(Process::CLOCK_MONOTONIC, :nanosecond) - started) / 1e9).round : nil
    ensure
      lock
    end
  end

  private

  # The fiber that has the lock, or nil. A thread that ends releases
  # every lock it had (rb_threadptr_unlock_all_locking_mutexes), so a
  # lock whose thread has ended is free. The thread that is ending is
  # still the current one while it wakes its waiters, and a lock it
  # takes then is its own.
  def owner
    Primitive.attr! :hidden
    fiber = Primitive.zr_hidden_get(self, :__owner__)
    thread = Primitive.zr_hidden_get(self, :__thread__)
    return fiber if fiber.nil? || thread.nil? || thread.equal?(Thread.current) || thread.alive?

    Primitive.zr_state_set(self, :__owner__, nil)
    nil
  end

  # The threads waiting for the lock; an allocated mutex locks as a new
  # one does.
  def waiters
    Primitive.attr! :hidden
    Primitive.zr_hidden_get(self, :__waiters__) || Primitive.zr_state_set(self, :__waiters__, [])
  end
end

class Thread::ConditionVariable
  def initialize
    @waiters = []
    nil
  end

  # The value that Mutex#sleep returns: the seconds slept, or nil on the timeout.
  def wait(mutex, timeout = nil)
    Primitive.attr! :ruby
    # rb_condvar_wait sends sleep(timeout) to what it is given; a Mutex
    # of the core is waited on here.
    return mutex.__send__(:sleep, timeout) unless mutex.is_a?(Thread::Mutex)

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
  # An allocated queue has waiters but no items, as struct rb_queue does.
  def self.allocate
    Primitive.attr! :hidden
    Primitive.zr_class_allocate(self).tap { |queue| queue.send(:waiters) }
  end

  # The first items convert through to_a, as rb_to_array takes them.
  def initialize(items = nil)
    unless items.nil? || items.is_a?(Array)
      raise TypeError, "can't convert #{conversion_name(items)} into Array" unless items.respond_to?(:to_a)

      converted = items.to_a
      raise TypeError, "can't convert #{conversion_name(items)} to Array (#{conversion_name(items)}#to_a gives #{conversion_name(converted)})" unless converted.is_a?(Array)

      items = converted
    end
    @items = items.nil? ? [] : items.dup
    @waiters = []
    nil
  end

  def push(value)
    raise ClosedQueueError, +"queue closed" if closed?

    items << value
    Thread.send(:rouse, waiters, 1)
    self
  end

  alias << push
  alias enq push

  def pop(non_block = false, timeout: nil)
    Primitive.attr! :ruby
    raise ArgumentError, +"can't set a timeout if non_block is enabled" if non_block && timeout

    deadline = timeout.nil? ? nil : Process.clock_gettime(Process::CLOCK_MONOTONIC, :nanosecond) + (Thread.send(:seconds, timeout) * 1e9).to_i
    while items.empty?
      # queue_do_pop: a pop that may not wait fails before a closed queue's nil.
      raise ThreadError, +"queue empty" if non_block
      return nil if closed?
      return nil if deadline && Process.clock_gettime(Process::CLOCK_MONOTONIC, :nanosecond) >= deadline

      Thread.current.send(:wait_on, waiters, deadline, true)
    end
    items.shift
  end

  alias shift pop
  alias deq pop

  def close
    @closed = true
    Thread.send(:rouse, waiters.dup)
    self
  end

  def closed? = @closed == true

  def empty? = items.empty?

  def size = items.size

  alias length size

  def clear
    items.clear
    self
  end

  def num_waiting = waiters.size

  # A queue takes messages and gives them away, so a frozen one could do
  # neither: ruby refuses to freeze one at all. A SizedQueue is a queue,
  # and the refusal names whichever class it is.
  def freeze
    raise TypeError, "cannot freeze #{Primitive.zr_any_to_s(self)}"
  end

  private

  # check_array: an allocated queue has no items until initialize.
  def items
    Primitive.attr! :hidden
    @items or raise TypeError, "#{inspect} not initialized"
  end

  def waiters
    Primitive.attr! :hidden
    @waiters ||= []
  end
end

class Thread::Queue
  # A queue's waiters belong to the queue, so ruby takes copying away.
  undef_method :initialize_copy

  def marshal_dump = raise(TypeError, "can't dump #{self.class}")
end

class Thread::ConditionVariable
  # Its waiters belong to it too, so ruby takes copying away.
  undef_method :initialize_copy

  def marshal_dump = raise(TypeError, "can't dump #{self.class}")
end

class Thread::SizedQueue < Thread::Queue
  def initialize(max)
    max = Primitive.zr_index_operand_m(max)
    raise ArgumentError, +"queue size must be positive" unless max > 0

    super()
    @max = max
    @pushers = []
    nil
  end

  def max = @max || 0

  def max=(value)
    value = Primitive.zr_index_operand_m(value)
    raise ArgumentError, +"queue size must be positive" unless value > 0

    @max = value
    Thread.send(:rouse, pushers.dup)
    value
  end

  def push(object, non_block = false, timeout: nil)
    Primitive.attr! :ruby
    value = object
    raise ArgumentError, +"can't set a timeout if non_block is enabled" if non_block && timeout

    deadline = timeout.nil? ? nil : Process.clock_gettime(Process::CLOCK_MONOTONIC, :nanosecond) + (Thread.send(:seconds, timeout) * 1e9).to_i
    while items.size >= max
      raise ClosedQueueError, +"queue closed" if closed?
      raise ThreadError, +"queue full" if non_block
      return nil if deadline && Process.clock_gettime(Process::CLOCK_MONOTONIC, :nanosecond) >= deadline

      Thread.current.send(:wait_on, pushers, deadline, true)
    end
    super(value)
  end

  alias << push
  alias enq push

  def pop(non_block = false, timeout: nil)
    Primitive.attr! :ruby
    value = super
    Thread.send(:rouse, pushers, 1)
    value
  end

  alias shift pop
  alias deq pop

  def close
    super
    Thread.send(:rouse, pushers.dup)
    self
  end

  # Room for every pusher, so each one waiting wakes, as rb_szqueue_clear
  # wakes them.
  def clear
    super
    Thread.send(:rouse, pushers.dup)
    self
  end

  def num_waiting = waiters.size + pushers.size

  private

  def pushers
    Primitive.attr! :hidden
    @pushers ||= []
  end
end

Mutex = Thread::Mutex
ConditionVariable = Thread::ConditionVariable
Queue = Thread::Queue
SizedQueue = Thread::SizedQueue
