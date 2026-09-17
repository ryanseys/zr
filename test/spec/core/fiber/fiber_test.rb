# frozen_string_literal: true

require "spec_helper"

describe "Fiber programs" do
  it "fiber inspects with its block and status" do
    result = ze0(<<~'RUBY', path: "core/fiber/a_fiber_inspects_with_its_block_and_status.rb")
      # Fiber#inspect names the block's file and line and the fiber's status,
      # as fiber_to_s writes it. A fiber that resumed another is suspended by
      # resuming it; a thread's own fiber has no block.

      def shown(fiber) = fiber.inspect.sub(/0x\h+/, "X")

      root = Fiber.current
      outer = Fiber.new do
        inner = Fiber.new do
          puts shown(root), shown(outer)
          Fiber.yield
        end
        inner.resume
        puts shown(inner)
      end
      puts shown(outer)
      outer.resume
      puts shown(outer), outer.to_s == outer.inspect
      puts shown(Fiber.new(&:itself))
      p Fiber.singleton_methods.include?(:new), Fiber.public_instance_methods(false).include?(:inspect)

    RUBY

    _(result).must_answer <<~'OUT'
      #<Fiber:X core/fiber/a_fiber_inspects_with_its_block_and_status.rb:8 (created)>
      #<Fiber:X (suspended by resuming)>
      #<Fiber:X core/fiber/a_fiber_inspects_with_its_block_and_status.rb:8 (suspended by resuming)>
      #<Fiber:X core/fiber/a_fiber_inspects_with_its_block_and_status.rb:9 (suspended)>
      #<Fiber:X core/fiber/a_fiber_inspects_with_its_block_and_status.rb:8 (terminated)>
      true
      #<Fiber:X(&:itself) (created)>
      false
      true
    OUT
  end

  it "fiber kills raises and stays on its thread" do
    result = ze0(<<~'RUBY')
      # A fiber and a thread as CRuby has them: kill unwinds a fiber through
      # its ensure, raise carries an exception into it, a fiber resumed twice
      # or from another thread says so, a thread's locals belong to the fiber
      # that thread runs, and a frozen Mutex still locks.
      def t = yield rescue [$!.class, $!.message]

      Thread.report_on_exception = false

      log = []
      f = Fiber.new do
        Fiber.yield
      ensure
        log << :ensured
      end
      f.resume
      p t { [f.kill.class, f.alive?, log] }

      g = Fiber.new do
        Fiber.yield
      rescue StandardError => e
        :"rescued-#{e.message}"
      end
      g.resume
      p t { g.raise("boom") }
      p t { Fiber.new { :never }.raise("early") }
      p t { Fiber.new { :never }.kill.alive? }

      h = Fiber.new { Fiber.new { h.resume }.resume }
      p t { h.resume }
      k = Fiber.new { Fiber.yield }
      k.resume
      p t { Thread.new { k.resume }.value }

      th = Thread.new { sleep 0.02; Thread.current[:a] }
      th[:a] = 1
      p t { th.value }, t { th.key?(:a) }, t { Thread.current[:a] }

      m = Thread::Mutex.new.freeze
      p t { [m.frozen?, m.lock.class, m.locked?, m.unlock.class] }
      p t { Thread.current.priority = 3; Thread.current.priority }, t { Thread.current.native_thread_id.is_a?(Integer) }
      p t { Thread.pending_interrupt? }, t { Thread.current.group.class }, t { ThreadGroup::Default.class }

    RUBY

    _(result).must_answer <<~'OUT'
      [Fiber, false, [:ensured]]
      :"rescued-boom"
      [FiberError, "cannot raise exception on unborn fiber"]
      false
      [FiberError, "attempt to resume a resumed fiber (double resume)"]
      [FiberError, "fiber called across threads"]
      1
      true
      nil
      [true, Thread::Mutex, true, Thread::Mutex]
      3
      true
      false
      ThreadGroup
      ThreadGroup
    OUT
  end

  it "fiber scheduler reads and writes through its buffer hooks" do
    result = ze0(<<~'RUBY', files: {"a_fiber_scheduler_takes_every_blocking_operation/scheduler.rb" => "# frozen_string_literal: true\n\n# This is an example and simplified scheduler for test purposes.\n# - It is not efficient for a large number of file descriptors as it uses\n#   IO.select().\n# - It does not correctly handle multiple calls to `wait` with the same file\n#   descriptor and overlapping events.\n# - Production fiber schedulers should use epoll/kqueue/etc. Consider using the\n#   [`io-event`](https://github.com/socketry/io-event) gem instead of this\n#   scheduler if you want something simple to build on.\n\nrequire 'fiber'\nrequire 'socket'\n\nbegin\n  require 'io/nonblock'\nrescue LoadError\n  # Ignore.\nend\n\nclass Scheduler\n  experimental = Warning[:experimental]\n  begin\n    Warning[:experimental] = false\n    IO::Buffer.new(0)\n  ensure\n    Warning[:experimental] = experimental\n  end\n\n  def initialize(fiber = Fiber.current)\n    @fiber = fiber\n\n    @readable = {}\n    @writable = {}\n    @waiting = {}\n\n    @closed = false\n\n    @lock = Thread::Mutex.new\n    @blocking = Hash.new.compare_by_identity\n    @ready = []\n\n    @urgent = IO.pipe\n  end\n\n  attr :readable\n  attr :writable\n  attr :waiting\n\n  def transfer\n    @fiber.transfer\n  end\n\n  def next_timeout\n    _fiber, timeout = @waiting.min_by{|key, value| value}\n\n    if timeout\n      offset = timeout - current_time\n\n      if offset < 0\n        return 0\n      else\n        return offset\n      end\n    end\n  end\n\n  def run_once\n    readable = writable = nil\n\n    begin\n      readable, writable = IO.select(@readable.keys + [@urgent.first], @writable.keys, [], next_timeout)\n    rescue IOError\n      # Ignore - this can happen if the IO is closed while we are waiting.\n    end\n\n    # puts \"readable: \#{readable}\" if readable&.any?\n    # puts \"writable: \#{writable}\" if writable&.any?\n\n    selected = {}\n\n    readable&.each do |io|\n      if fiber = @readable.delete(io)\n        @writable.delete(io) if @writable[io] == fiber\n        selected[fiber] = IO::READABLE\n      elsif io == @urgent.first\n        @urgent.first.read_nonblock(1024)\n      end\n    end\n\n    writable&.each do |io|\n      if fiber = @writable.delete(io)\n        @readable.delete(io) if @readable[io] == fiber\n        selected[fiber] = selected.fetch(fiber, 0) | IO::WRITABLE\n      end\n    end\n\n    selected.each do |fiber, events|\n      fiber.transfer(events)\n    end\n\n    if @waiting.any?\n      time = current_time\n      waiting, @waiting = @waiting, {}\n\n      waiting.each do |fiber, timeout|\n        if fiber.alive?\n          if timeout <= time\n            fiber.transfer\n          else\n            @waiting[fiber] = timeout\n          end\n        end\n      end\n    end\n\n    if @ready.any?\n      ready = nil\n\n      @lock.synchronize do\n        ready, @ready = @ready, []\n      end\n\n      ready.each do |fiber|\n        fiber.transfer if fiber.alive?\n      end\n    end\n  end\n\n  def run\n    # $stderr.puts [__method__, Fiber.current].inspect\n\n    # Use Thread.handle_interrupt like Async::Scheduler does\n    # This defers signal processing, which is the root cause of the gRPC bug\n    # See: https://github.com/socketry/async/blob/main/lib/async/scheduler.rb\n    Thread.handle_interrupt(::SignalException => :never) do\n      while @readable.any? or @writable.any? or @waiting.any? or @blocking.any?\n        run_once\n\n        break if Thread.pending_interrupt?\n      end\n    end\n  end\n\n  # A fiber scheduler hook, invoked when the scheduler goes out of scope.\n  def scheduler_close\n    close(true)\n  end\n\n  # If the `scheduler_close` hook does not exist, this method `close` will be\n  # invoked instead when the fiber scheduler goes out of scope. This is legacy\n  # behaviour, you should almost certainly use `scheduler_close`. The reason for\n  # this, is `scheduler_close` is called when the scheduler goes out of scope,\n  # while `close` may be called by the user.\n  def close(internal = false)\n    # $stderr.puts [__method__, Fiber.current].inspect\n\n    unless internal\n      if Fiber.scheduler == self\n        return Fiber.set_scheduler(nil)\n      end\n    end\n\n    if @closed\n      raise \"Scheduler already closed!\"\n    end\n\n    self.run\n  ensure\n    if @urgent\n      @urgent.each(&:close)\n      @urgent = nil\n    end\n\n    @closed ||= true\n\n    # We freeze to detect any unintended modifications after the scheduler is closed:\n    self.freeze\n  end\n\n  def closed?\n    @closed\n  end\n\n  def current_time\n    Process.clock_gettime(Process::CLOCK_MONOTONIC)\n  end\n\n  # This hook is invoked by `Timeout.timeout` and related code.\n  def timeout_after(duration, klass, message, &block)\n    fiber = Fiber.current\n\n    self.fiber do\n      sleep(duration)\n\n      if fiber&.alive?\n        fiber.raise(klass, message)\n      end\n    end\n\n    begin\n      yield(duration)\n    ensure\n      fiber = nil\n    end\n  end\n\n  # This hook is invoked by `Process.wait`, `system`, and backticks.\n  def process_wait(pid, flags)\n    # $stderr.puts [__method__, pid, flags, Fiber.current].inspect\n\n    # This is a very simple way to implement a non-blocking wait:\n    Thread.new do\n      Process::Status.wait(pid, flags)\n    end.value\n  end\n\n  # This hook is invoked by `IO#read` and `IO#write` in the case that `io_read`\n  # and `io_write` hooks are not available. This implementation is not\n  # completely general, in the sense that calling `io_wait` multiple times with\n  # the same `io` and `events` will not work, which is okay for tests but not\n  # for real code. Correct fiber schedulers should not have this limitation.\n  def io_wait(io, events, duration)\n    # $stderr.puts [__method__, io, events, duration, Fiber.current].inspect\n\n    fiber = Fiber.current\n\n    unless (events & IO::READABLE).zero?\n      @readable[io] = fiber\n      readable = true\n    end\n\n    unless (events & IO::WRITABLE).zero?\n      @writable[io] = fiber\n      writable = true\n    end\n\n    if duration\n      @waiting[fiber] = current_time + duration\n    end\n\n    @fiber.transfer\n  ensure\n    @waiting.delete(fiber) if duration\n    @readable.delete(io) if readable\n    @writable.delete(io) if writable\n  end\n\n  # This hook is invoked by `IO.select`. Using a thread ensures that the\n  # operation does not block the fiber scheduler.\n  def io_select(...)\n    # Emulate the operation using a non-blocking thread:\n    Thread.new do\n      IO.select(...)\n    end.value\n  end\n\n  # This hook is invoked by `IO#close`. Using a separate IO object\n  # demonstrates that the close operation is asynchronous.\n  def io_close(descriptor)\n    Fiber.blocking{IO.for_fd(descriptor.to_i).close}\n    return true\n  end\n\n  # This hook is invoked by `Kernel#sleep` and `Thread::Mutex#sleep`.\n  def kernel_sleep(duration = nil)\n    # $stderr.puts [__method__, duration, Fiber.current].inspect\n\n    self.block(:sleep, duration)\n\n    return true\n  end\n\n  # This hook is invoked by blocking options such as `Thread::Mutex#lock`,\n  # `Thread::Queue#pop` and `Thread::SizedQueue#push`, which are unblocked by\n  # other threads/fibers. To unblock a blocked fiber, you should call `unblock`\n  # with the same `blocker` and `fiber` arguments.\n  def block(blocker, timeout = nil)\n    # $stderr.puts [__method__, blocker, timeout].inspect\n\n    fiber = Fiber.current\n\n    if timeout\n      @waiting[fiber] = current_time + timeout\n      begin\n        @fiber.transfer\n      ensure\n        # Remove from @waiting in the case #unblock was called before the timeout expired:\n        @waiting.delete(fiber)\n      end\n    else\n      @blocking[fiber] = true\n      begin\n        @fiber.transfer\n      ensure\n        @blocking.delete(fiber)\n      end\n    end\n  end\n\n  # This method is invoked from a thread or fiber to unblock a fiber that is\n  # blocked by `block`. It is expected to be thread safe.\n  def unblock(blocker, fiber)\n    # $stderr.puts [__method__, blocker, fiber].inspect\n    # $stderr.puts blocker.backtrace.inspect\n    # $stderr.puts fiber.backtrace.inspect\n\n    @lock.synchronize do\n      @ready << fiber\n    end\n\n    io = @urgent.last\n    io.write_nonblock('.')\n  end\n\n  class FiberInterrupt\n    def initialize(fiber, exception)\n      @fiber = fiber\n      @exception = exception\n    end\n\n    def alive?\n      @fiber.alive?\n    end\n\n    def transfer\n      @fiber.raise(@exception)\n    end\n  end\n\n  def fiber_interrupt(fiber, exception)\n    @lock.synchronize do\n      @ready << FiberInterrupt.new(fiber, exception)\n    end\n\n    io = @urgent.last\n    io.write_nonblock('.')\n  end\n\n  # This hook is invoked by `Fiber.schedule`. Strictly speaking, you should use\n  # it to create scheduled fibers, but it is not required in practice;\n  # `Fiber.new` is usually sufficient.\n  def fiber(&block)\n    fiber = Fiber.new(blocking: false, &block)\n\n    fiber.transfer\n\n    return fiber\n  end\n\n  # This hook is invoked by `Addrinfo.getaddrinfo`. Using a thread ensures that\n  # the operation does not block the fiber scheduler, since `getaddrinfo` is\n  # usually provided by `libc` and is blocking.\n  def address_resolve(hostname)\n    Thread.new do\n      Addrinfo.getaddrinfo(hostname, nil).map(&:ip_address).uniq\n    end.value\n  end\n\n  def blocking_operation_wait(work)\n    thread = Thread.new{work.call}\n\n    thread.join\n\n    thread = nil\n  ensure\n    thread&.kill\n  end\nend\n\n# This scheduler class implements `io_read` and `io_write` hooks which require\n# `IO::Buffer`.\nclass IOBufferScheduler < Scheduler\n  EAGAIN = -Errno::EAGAIN::Errno\n\n  def io_read(io, buffer, length, offset)\n    total = 0\n    io.nonblock = true\n\n    while true\n      result = blocking{buffer.read(io, 0, offset)}\n\n      if result > 0\n        total += result\n        offset += result\n        break if total >= length\n      elsif result == 0\n        break\n      elsif result == EAGAIN\n        if length > 0\n          self.io_wait(io, IO::READABLE, nil)\n        else\n          return result\n        end\n      elsif result < 0\n        return result\n      end\n    end\n\n    return total\n  end\n\n  def io_write(io, buffer, length, offset)\n    total = 0\n    io.nonblock = true\n\n    while true\n      result = blocking{buffer.write(io, 0, offset)}\n\n      if result > 0\n        total += result\n        offset += result\n        break if total >= length\n      elsif result == 0\n        break\n      elsif result == EAGAIN\n        if length > 0\n          self.io_wait(io, IO::WRITABLE, nil)\n        else\n          return result\n        end\n      elsif result < 0\n        return result\n      end\n    end\n\n    return total\n  end\n\n  def io_pread(io, buffer, from, length, offset)\n    total = 0\n    io.nonblock = true\n\n    while true\n      result = blocking{buffer.pread(io, from, 0, offset)}\n\n      if result > 0\n        total += result\n        offset += result\n        from += result\n        break if total >= length\n      elsif result == 0\n        break\n      elsif result == EAGAIN\n        if length > 0\n          self.io_wait(io, IO::READABLE, nil)\n        else\n          return result\n        end\n      elsif result < 0\n        return result\n      end\n    end\n\n    return total\n  end\n\n  def io_pwrite(io, buffer, from, length, offset)\n    total = 0\n    io.nonblock = true\n\n    while true\n      result = blocking{buffer.pwrite(io, from, 0, offset)}\n\n      if result > 0\n        total += result\n        offset += result\n        from += result\n        break if total >= length\n      elsif result == 0\n        break\n      elsif result == EAGAIN\n        if length > 0\n          self.io_wait(io, IO::WRITABLE, nil)\n        else\n          return result\n        end\n      elsif result < 0\n        return result\n      end\n    end\n\n    return total\n  end\n\n  def blocking(&block)\n    Fiber.blocking(&block)\n  end\nend\n\nclass IOScheduler < Scheduler\n  def operations\n    @operations ||= []\n  end\n\n  def io_write(io, buffer, length, offset)\n    descriptor = io.fileno\n    string = buffer.get_string\n\n    self.operations << [:io_write, descriptor, string]\n\n    Fiber.blocking do\n      buffer.write(io, 0, offset)\n    end\n  end\nend\n\nclass IOErrorScheduler < Scheduler\n  def io_read(io, buffer, length, offset)\n    return -Errno::EBADF::Errno\n  end\n\n  def io_write(io, buffer, length, offset)\n    return -Errno::EINVAL::Errno\n  end\nend\n\n# This scheduler has a broken implementation of `unblock`` in the sense that it\n# raises an exception. This is used to test the behavior of the scheduler when\n# unblock raises an exception.\nclass BrokenUnblockScheduler < Scheduler\n  def unblock(blocker, fiber)\n    super\n\n    raise \"Broken unblock!\"\n  end\nend\n\n# This scheduler has a broken implementation of `unblock` in the sense that it\n# sleeps. This is used to test the behavior of the scheduler when unblock\n# messes with the internal thread state in an unexpected way.\nclass SleepingUnblockScheduler < Scheduler\n  # This method is invoked when the thread is exiting.\n  def unblock(blocker, fiber)\n    super\n\n    # This changes the current thread state to `THREAD_RUNNING` which causes `thread_join_sleep` to hang.\n    sleep(0.1)\n  end\nend\n\n# This scheduler has a broken implementation of `kernel_sleep` in the sense that\n# it invokes a blocking sleep which can cause a deadlock in some cases.\nclass SleepingBlockingScheduler < Scheduler\n  def kernel_sleep(duration = nil)\n    # Deliberaly sleep in a blocking state which can trigger a deadlock if the implementation is not correct.\n    Fiber.blocking{sleep 0.0001}\n\n    self.block(:sleep, duration)\n\n    return true\n  end\nend\n"})
      # A non-blocking fiber's reads and writes reach its scheduler's io_read,
      # io_write, io_pread and io_pwrite with an IO::Buffer, in the sizes io.c
      # reads and writes with. This runtime reads and writes itself and hands
      # the scheduler only io_wait, so a scheduler that logs its hooks sees none.
      require_relative "a_fiber_scheduler_takes_every_blocking_operation/scheduler"
      require "tmpdir"
      class Logged < IOBufferScheduler
        attr_reader :calls
        def initialize(*) = (super; @calls = [])
        def io_read(io, buffer, length, offset)
          @calls << [:io_read, io.class, buffer.size, buffer.external?, buffer.locked?, length, offset]
          super
        end
        def io_write(io, buffer, length, offset)
          @calls << [:io_write, io.class, buffer.size, buffer.get_string(offset, [buffer.size - offset, 12].min), length, offset]
          super
        end
        def io_pread(io, buffer, from, length, offset)
          @calls << [:io_pread, from, length, offset]
          super
        end
        def io_pwrite(io, buffer, from, length, offset)
          @calls << [:io_pwrite, from, length, offset]
          super
        end
      end
      log = []
      sched = nil
      Thread.new do
        sched = Logged.new
        Fiber.set_scheduler(sched)
        r, w = IO.pipe
        Fiber.schedule { log << r.read(5); log << r.gets; log << r.readpartial(10); log << r.read }
        Fiber.schedule { w.write("hello"); w.sync = false; w.print("line\n"); w.flush; w.syswrite("more"); sleep 0.01; w.close }
        Fiber.schedule do
          File.open(__FILE__) { |f| log << f.read(7); log << f.pread(4, 2) }
          path = File.join(Dir.tmpdir, "hooks#{$$}")
          File.open(path, "w") { |f| f.write("abc"); f.pwrite("Z", 1) }
          log << File.read(path)
          File.delete(path)
        end
      end.join
      p log
      sched.calls.each { |c| p c }

    RUBY

    _(result).must_answer <<~'OUT'
      ["hello", "line\n", "more", "# A non", "A no", "abc", ""]
      [:io_read, IO, 5, false, true, 0, 0]
      [:io_write, IO, 5, "hello", 0, 0]
      [:io_write, IO, 5, "line\n", 0, 0]
      [:io_write, IO, 4, "more", 0, 0]
      [:io_read, IO, 5, false, true, 0, 0]
      [:io_read, IO, 8192, false, true, 0, 0]
      [:io_read, IO, 1024, false, true, 0, 0]
      [:io_read, File, 7, false, true, 0, 0]
      [:io_pread, 2, 0, 0]
      [:io_pwrite, 1, 0, 0]
      [:io_write, File, 3, "abc", 0, 0]
      [:io_read, File, 3, false, true, 0, 0]
      [:io_read, File, 1024, false, true, 0, 0]
      [:io_read, IO, 1024, false, true, 0, 0]
    OUT
  end

  it "fiber scheduler takes every blocking operation" do
    result = ze0(<<~'RUBY', files: {"a_fiber_scheduler_takes_every_blocking_operation/scheduler.rb" => "# frozen_string_literal: true\n\n# This is an example and simplified scheduler for test purposes.\n# - It is not efficient for a large number of file descriptors as it uses\n#   IO.select().\n# - It does not correctly handle multiple calls to `wait` with the same file\n#   descriptor and overlapping events.\n# - Production fiber schedulers should use epoll/kqueue/etc. Consider using the\n#   [`io-event`](https://github.com/socketry/io-event) gem instead of this\n#   scheduler if you want something simple to build on.\n\nrequire 'fiber'\nrequire 'socket'\n\nbegin\n  require 'io/nonblock'\nrescue LoadError\n  # Ignore.\nend\n\nclass Scheduler\n  experimental = Warning[:experimental]\n  begin\n    Warning[:experimental] = false\n    IO::Buffer.new(0)\n  ensure\n    Warning[:experimental] = experimental\n  end\n\n  def initialize(fiber = Fiber.current)\n    @fiber = fiber\n\n    @readable = {}\n    @writable = {}\n    @waiting = {}\n\n    @closed = false\n\n    @lock = Thread::Mutex.new\n    @blocking = Hash.new.compare_by_identity\n    @ready = []\n\n    @urgent = IO.pipe\n  end\n\n  attr :readable\n  attr :writable\n  attr :waiting\n\n  def transfer\n    @fiber.transfer\n  end\n\n  def next_timeout\n    _fiber, timeout = @waiting.min_by{|key, value| value}\n\n    if timeout\n      offset = timeout - current_time\n\n      if offset < 0\n        return 0\n      else\n        return offset\n      end\n    end\n  end\n\n  def run_once\n    readable = writable = nil\n\n    begin\n      readable, writable = IO.select(@readable.keys + [@urgent.first], @writable.keys, [], next_timeout)\n    rescue IOError\n      # Ignore - this can happen if the IO is closed while we are waiting.\n    end\n\n    # puts \"readable: \#{readable}\" if readable&.any?\n    # puts \"writable: \#{writable}\" if writable&.any?\n\n    selected = {}\n\n    readable&.each do |io|\n      if fiber = @readable.delete(io)\n        @writable.delete(io) if @writable[io] == fiber\n        selected[fiber] = IO::READABLE\n      elsif io == @urgent.first\n        @urgent.first.read_nonblock(1024)\n      end\n    end\n\n    writable&.each do |io|\n      if fiber = @writable.delete(io)\n        @readable.delete(io) if @readable[io] == fiber\n        selected[fiber] = selected.fetch(fiber, 0) | IO::WRITABLE\n      end\n    end\n\n    selected.each do |fiber, events|\n      fiber.transfer(events)\n    end\n\n    if @waiting.any?\n      time = current_time\n      waiting, @waiting = @waiting, {}\n\n      waiting.each do |fiber, timeout|\n        if fiber.alive?\n          if timeout <= time\n            fiber.transfer\n          else\n            @waiting[fiber] = timeout\n          end\n        end\n      end\n    end\n\n    if @ready.any?\n      ready = nil\n\n      @lock.synchronize do\n        ready, @ready = @ready, []\n      end\n\n      ready.each do |fiber|\n        fiber.transfer if fiber.alive?\n      end\n    end\n  end\n\n  def run\n    # $stderr.puts [__method__, Fiber.current].inspect\n\n    # Use Thread.handle_interrupt like Async::Scheduler does\n    # This defers signal processing, which is the root cause of the gRPC bug\n    # See: https://github.com/socketry/async/blob/main/lib/async/scheduler.rb\n    Thread.handle_interrupt(::SignalException => :never) do\n      while @readable.any? or @writable.any? or @waiting.any? or @blocking.any?\n        run_once\n\n        break if Thread.pending_interrupt?\n      end\n    end\n  end\n\n  # A fiber scheduler hook, invoked when the scheduler goes out of scope.\n  def scheduler_close\n    close(true)\n  end\n\n  # If the `scheduler_close` hook does not exist, this method `close` will be\n  # invoked instead when the fiber scheduler goes out of scope. This is legacy\n  # behaviour, you should almost certainly use `scheduler_close`. The reason for\n  # this, is `scheduler_close` is called when the scheduler goes out of scope,\n  # while `close` may be called by the user.\n  def close(internal = false)\n    # $stderr.puts [__method__, Fiber.current].inspect\n\n    unless internal\n      if Fiber.scheduler == self\n        return Fiber.set_scheduler(nil)\n      end\n    end\n\n    if @closed\n      raise \"Scheduler already closed!\"\n    end\n\n    self.run\n  ensure\n    if @urgent\n      @urgent.each(&:close)\n      @urgent = nil\n    end\n\n    @closed ||= true\n\n    # We freeze to detect any unintended modifications after the scheduler is closed:\n    self.freeze\n  end\n\n  def closed?\n    @closed\n  end\n\n  def current_time\n    Process.clock_gettime(Process::CLOCK_MONOTONIC)\n  end\n\n  # This hook is invoked by `Timeout.timeout` and related code.\n  def timeout_after(duration, klass, message, &block)\n    fiber = Fiber.current\n\n    self.fiber do\n      sleep(duration)\n\n      if fiber&.alive?\n        fiber.raise(klass, message)\n      end\n    end\n\n    begin\n      yield(duration)\n    ensure\n      fiber = nil\n    end\n  end\n\n  # This hook is invoked by `Process.wait`, `system`, and backticks.\n  def process_wait(pid, flags)\n    # $stderr.puts [__method__, pid, flags, Fiber.current].inspect\n\n    # This is a very simple way to implement a non-blocking wait:\n    Thread.new do\n      Process::Status.wait(pid, flags)\n    end.value\n  end\n\n  # This hook is invoked by `IO#read` and `IO#write` in the case that `io_read`\n  # and `io_write` hooks are not available. This implementation is not\n  # completely general, in the sense that calling `io_wait` multiple times with\n  # the same `io` and `events` will not work, which is okay for tests but not\n  # for real code. Correct fiber schedulers should not have this limitation.\n  def io_wait(io, events, duration)\n    # $stderr.puts [__method__, io, events, duration, Fiber.current].inspect\n\n    fiber = Fiber.current\n\n    unless (events & IO::READABLE).zero?\n      @readable[io] = fiber\n      readable = true\n    end\n\n    unless (events & IO::WRITABLE).zero?\n      @writable[io] = fiber\n      writable = true\n    end\n\n    if duration\n      @waiting[fiber] = current_time + duration\n    end\n\n    @fiber.transfer\n  ensure\n    @waiting.delete(fiber) if duration\n    @readable.delete(io) if readable\n    @writable.delete(io) if writable\n  end\n\n  # This hook is invoked by `IO.select`. Using a thread ensures that the\n  # operation does not block the fiber scheduler.\n  def io_select(...)\n    # Emulate the operation using a non-blocking thread:\n    Thread.new do\n      IO.select(...)\n    end.value\n  end\n\n  # This hook is invoked by `IO#close`. Using a separate IO object\n  # demonstrates that the close operation is asynchronous.\n  def io_close(descriptor)\n    Fiber.blocking{IO.for_fd(descriptor.to_i).close}\n    return true\n  end\n\n  # This hook is invoked by `Kernel#sleep` and `Thread::Mutex#sleep`.\n  def kernel_sleep(duration = nil)\n    # $stderr.puts [__method__, duration, Fiber.current].inspect\n\n    self.block(:sleep, duration)\n\n    return true\n  end\n\n  # This hook is invoked by blocking options such as `Thread::Mutex#lock`,\n  # `Thread::Queue#pop` and `Thread::SizedQueue#push`, which are unblocked by\n  # other threads/fibers. To unblock a blocked fiber, you should call `unblock`\n  # with the same `blocker` and `fiber` arguments.\n  def block(blocker, timeout = nil)\n    # $stderr.puts [__method__, blocker, timeout].inspect\n\n    fiber = Fiber.current\n\n    if timeout\n      @waiting[fiber] = current_time + timeout\n      begin\n        @fiber.transfer\n      ensure\n        # Remove from @waiting in the case #unblock was called before the timeout expired:\n        @waiting.delete(fiber)\n      end\n    else\n      @blocking[fiber] = true\n      begin\n        @fiber.transfer\n      ensure\n        @blocking.delete(fiber)\n      end\n    end\n  end\n\n  # This method is invoked from a thread or fiber to unblock a fiber that is\n  # blocked by `block`. It is expected to be thread safe.\n  def unblock(blocker, fiber)\n    # $stderr.puts [__method__, blocker, fiber].inspect\n    # $stderr.puts blocker.backtrace.inspect\n    # $stderr.puts fiber.backtrace.inspect\n\n    @lock.synchronize do\n      @ready << fiber\n    end\n\n    io = @urgent.last\n    io.write_nonblock('.')\n  end\n\n  class FiberInterrupt\n    def initialize(fiber, exception)\n      @fiber = fiber\n      @exception = exception\n    end\n\n    def alive?\n      @fiber.alive?\n    end\n\n    def transfer\n      @fiber.raise(@exception)\n    end\n  end\n\n  def fiber_interrupt(fiber, exception)\n    @lock.synchronize do\n      @ready << FiberInterrupt.new(fiber, exception)\n    end\n\n    io = @urgent.last\n    io.write_nonblock('.')\n  end\n\n  # This hook is invoked by `Fiber.schedule`. Strictly speaking, you should use\n  # it to create scheduled fibers, but it is not required in practice;\n  # `Fiber.new` is usually sufficient.\n  def fiber(&block)\n    fiber = Fiber.new(blocking: false, &block)\n\n    fiber.transfer\n\n    return fiber\n  end\n\n  # This hook is invoked by `Addrinfo.getaddrinfo`. Using a thread ensures that\n  # the operation does not block the fiber scheduler, since `getaddrinfo` is\n  # usually provided by `libc` and is blocking.\n  def address_resolve(hostname)\n    Thread.new do\n      Addrinfo.getaddrinfo(hostname, nil).map(&:ip_address).uniq\n    end.value\n  end\n\n  def blocking_operation_wait(work)\n    thread = Thread.new{work.call}\n\n    thread.join\n\n    thread = nil\n  ensure\n    thread&.kill\n  end\nend\n\n# This scheduler class implements `io_read` and `io_write` hooks which require\n# `IO::Buffer`.\nclass IOBufferScheduler < Scheduler\n  EAGAIN = -Errno::EAGAIN::Errno\n\n  def io_read(io, buffer, length, offset)\n    total = 0\n    io.nonblock = true\n\n    while true\n      result = blocking{buffer.read(io, 0, offset)}\n\n      if result > 0\n        total += result\n        offset += result\n        break if total >= length\n      elsif result == 0\n        break\n      elsif result == EAGAIN\n        if length > 0\n          self.io_wait(io, IO::READABLE, nil)\n        else\n          return result\n        end\n      elsif result < 0\n        return result\n      end\n    end\n\n    return total\n  end\n\n  def io_write(io, buffer, length, offset)\n    total = 0\n    io.nonblock = true\n\n    while true\n      result = blocking{buffer.write(io, 0, offset)}\n\n      if result > 0\n        total += result\n        offset += result\n        break if total >= length\n      elsif result == 0\n        break\n      elsif result == EAGAIN\n        if length > 0\n          self.io_wait(io, IO::WRITABLE, nil)\n        else\n          return result\n        end\n      elsif result < 0\n        return result\n      end\n    end\n\n    return total\n  end\n\n  def io_pread(io, buffer, from, length, offset)\n    total = 0\n    io.nonblock = true\n\n    while true\n      result = blocking{buffer.pread(io, from, 0, offset)}\n\n      if result > 0\n        total += result\n        offset += result\n        from += result\n        break if total >= length\n      elsif result == 0\n        break\n      elsif result == EAGAIN\n        if length > 0\n          self.io_wait(io, IO::READABLE, nil)\n        else\n          return result\n        end\n      elsif result < 0\n        return result\n      end\n    end\n\n    return total\n  end\n\n  def io_pwrite(io, buffer, from, length, offset)\n    total = 0\n    io.nonblock = true\n\n    while true\n      result = blocking{buffer.pwrite(io, from, 0, offset)}\n\n      if result > 0\n        total += result\n        offset += result\n        from += result\n        break if total >= length\n      elsif result == 0\n        break\n      elsif result == EAGAIN\n        if length > 0\n          self.io_wait(io, IO::WRITABLE, nil)\n        else\n          return result\n        end\n      elsif result < 0\n        return result\n      end\n    end\n\n    return total\n  end\n\n  def blocking(&block)\n    Fiber.blocking(&block)\n  end\nend\n\nclass IOScheduler < Scheduler\n  def operations\n    @operations ||= []\n  end\n\n  def io_write(io, buffer, length, offset)\n    descriptor = io.fileno\n    string = buffer.get_string\n\n    self.operations << [:io_write, descriptor, string]\n\n    Fiber.blocking do\n      buffer.write(io, 0, offset)\n    end\n  end\nend\n\nclass IOErrorScheduler < Scheduler\n  def io_read(io, buffer, length, offset)\n    return -Errno::EBADF::Errno\n  end\n\n  def io_write(io, buffer, length, offset)\n    return -Errno::EINVAL::Errno\n  end\nend\n\n# This scheduler has a broken implementation of `unblock`` in the sense that it\n# raises an exception. This is used to test the behavior of the scheduler when\n# unblock raises an exception.\nclass BrokenUnblockScheduler < Scheduler\n  def unblock(blocker, fiber)\n    super\n\n    raise \"Broken unblock!\"\n  end\nend\n\n# This scheduler has a broken implementation of `unblock` in the sense that it\n# sleeps. This is used to test the behavior of the scheduler when unblock\n# messes with the internal thread state in an unexpected way.\nclass SleepingUnblockScheduler < Scheduler\n  # This method is invoked when the thread is exiting.\n  def unblock(blocker, fiber)\n    super\n\n    # This changes the current thread state to `THREAD_RUNNING` which causes `thread_join_sleep` to hang.\n    sleep(0.1)\n  end\nend\n\n# This scheduler has a broken implementation of `kernel_sleep` in the sense that\n# it invokes a blocking sleep which can cause a deadlock in some cases.\nclass SleepingBlockingScheduler < Scheduler\n  def kernel_sleep(duration = nil)\n    # Deliberaly sleep in a blocking state which can trigger a deadlock if the implementation is not correct.\n    Fiber.blocking{sleep 0.0001}\n\n    self.block(:sleep, duration)\n\n    return true\n  end\nend\n"})
      # A thread with a fiber scheduler hands each blocking operation of its
      # non-blocking fibers to the scheduler: sleep, a pipe read and write, a
      # Mutex, a Queue, a Thread#value, Process.wait, Timeout.timeout,
      # getaddrinfo and a close. The scheduler is CRuby's own test scheduler
      # (test/fiber/scheduler.rb at ruby 4.0.6), unedited.
      require_relative "a_fiber_scheduler_takes_every_blocking_operation/scheduler"
      require "timeout"
      log = []
      thread = Thread.new do
        scheduler = Scheduler.new
        Fiber.set_scheduler(scheduler)
        p [Fiber.scheduler.class, Fiber.current_scheduler, Fiber.blocking?]

        Fiber.schedule { log << :a1; sleep 0.02; log << :a2 }
        Fiber.schedule { log << :b1; sleep 0.01; log << :b2 }

        r, w = IO.pipe
        Fiber.schedule { log << [:read, r.read(5)] }
        Fiber.schedule { sleep 0.03; w.write("hello"); w.close }

        m = Thread::Mutex.new
        q = Thread::Queue.new
        Fiber.schedule { m.synchronize { sleep 0.01; log << :locked_first } }
        Fiber.schedule { m.synchronize { log << :locked_second } }
        Fiber.schedule { log << [:popped, q.pop] }
        Fiber.schedule { q << :item }

        Fiber.schedule { log << [:joined, Thread.new { sleep 0.01; :t }.value] }
        Fiber.schedule do
          pid = Process.spawn("exit 7")
          Process.wait(pid)
          log << [:status, $?.exitstatus]
        end
        Fiber.schedule do
          Timeout.timeout(0.01) { sleep 1 }
        rescue Timeout::Error => e
          log << [:timeout, e.class]
        end
        Fiber.schedule { log << [:resolved, Addrinfo.getaddrinfo("localhost", 80).map(&:ip_address).uniq.sort.first] }
        Fiber.schedule { log << [:current, Fiber.current_scheduler.class, Fiber.blocking { Fiber.current_scheduler }] }
      end
      thread.join
      p log.sort_by(&:to_s)
      p Fiber.scheduler
    RUBY

    _(result).must_answer <<~'OUT'
      [Scheduler, nil, 1]
      [[:current, Scheduler, nil], [:joined, :t], [:popped, :item], [:read, "hello"], [:resolved, "127.0.0.1"], [:status, 7], [:timeout, Timeout::Error], :a1, :a2, :b1, :b2, :locked_first, :locked_second]
      nil
    OUT
  end

  it "fiber subclass makes its fiber through super" do
    result = ze0(<<~'RUBY')
      # Fiber.new is Class#new: allocate makes a fiber that refuses to run, and
      # initialize checks the storage, then the block, then whether the fiber
      # was made already, as rb_fiber_initialize_kw does. A subclass makes its
      # fiber through super.

      class Doubler < Fiber
        def initialize(x)
          super() { Fiber.yield(x * 2); x * 3 }
        end
      end
      d = Doubler.new(4)
      p d.resume, d.resume, d.class
      f = Fiber.allocate
      [-> { f.resume }, -> { f.alive? }, -> { Fiber.new }, -> { Fiber.new {}.send(:initialize) {} },
       -> { Fiber.new(storage: 1) {} }, -> { Fiber.new(storage: {"a" => 1}) {} }, -> { Fiber.new(storage: {}.freeze) {} },
       -> { Fiber.new(storage: false) {} }].each do |bad|
        bad.call
      rescue => e
        p e
      end
      Fiber[:k] = 1
      p Fiber.new { Fiber[:k] }.resume, Fiber.new(storage: nil) { Fiber[:k] }.resume, Fiber.new(storage: {k: 2}) { Fiber[:k] }.resume
      p Fiber.new(blocking: true) { Fiber.current.blocking? }.resume, Fiber.new(pool: nil) { 1 }.resume
      p Fiber.instance_method(:initialize).owner, Fiber.singleton_methods.include?(:new), Fiber.respond_to?(:new)
      p Fiber.new { 1 }.dup.alive? rescue p $!

    RUBY

    _(result).must_answer <<~'OUT'
      8
      12
      Doubler
      #<FiberError: uninitialized fiber>
      #<FiberError: uninitialized fiber>
      #<ArgumentError: tried to create Proc object without a block>
      #<RuntimeError: cannot initialize twice>
      #<TypeError: storage must be a hash>
      #<TypeError: wrong argument type String (expected Symbol)>
      #<FrozenError: storage must not be frozen>
      #<TypeError: storage must be a hash>
      1
      nil
      2
      true
      1
      Fiber
      false
      true
      #<FiberError: uninitialized fiber>
    OUT
  end

  it "scheduler runs the calls that may block" do
    result = ze0(<<~'RUBY', files: {"a_fiber_scheduler_takes_every_blocking_operation/scheduler.rb" => "# frozen_string_literal: true\n\n# This is an example and simplified scheduler for test purposes.\n# - It is not efficient for a large number of file descriptors as it uses\n#   IO.select().\n# - It does not correctly handle multiple calls to `wait` with the same file\n#   descriptor and overlapping events.\n# - Production fiber schedulers should use epoll/kqueue/etc. Consider using the\n#   [`io-event`](https://github.com/socketry/io-event) gem instead of this\n#   scheduler if you want something simple to build on.\n\nrequire 'fiber'\nrequire 'socket'\n\nbegin\n  require 'io/nonblock'\nrescue LoadError\n  # Ignore.\nend\n\nclass Scheduler\n  experimental = Warning[:experimental]\n  begin\n    Warning[:experimental] = false\n    IO::Buffer.new(0)\n  ensure\n    Warning[:experimental] = experimental\n  end\n\n  def initialize(fiber = Fiber.current)\n    @fiber = fiber\n\n    @readable = {}\n    @writable = {}\n    @waiting = {}\n\n    @closed = false\n\n    @lock = Thread::Mutex.new\n    @blocking = Hash.new.compare_by_identity\n    @ready = []\n\n    @urgent = IO.pipe\n  end\n\n  attr :readable\n  attr :writable\n  attr :waiting\n\n  def transfer\n    @fiber.transfer\n  end\n\n  def next_timeout\n    _fiber, timeout = @waiting.min_by{|key, value| value}\n\n    if timeout\n      offset = timeout - current_time\n\n      if offset < 0\n        return 0\n      else\n        return offset\n      end\n    end\n  end\n\n  def run_once\n    readable = writable = nil\n\n    begin\n      readable, writable = IO.select(@readable.keys + [@urgent.first], @writable.keys, [], next_timeout)\n    rescue IOError\n      # Ignore - this can happen if the IO is closed while we are waiting.\n    end\n\n    # puts \"readable: \#{readable}\" if readable&.any?\n    # puts \"writable: \#{writable}\" if writable&.any?\n\n    selected = {}\n\n    readable&.each do |io|\n      if fiber = @readable.delete(io)\n        @writable.delete(io) if @writable[io] == fiber\n        selected[fiber] = IO::READABLE\n      elsif io == @urgent.first\n        @urgent.first.read_nonblock(1024)\n      end\n    end\n\n    writable&.each do |io|\n      if fiber = @writable.delete(io)\n        @readable.delete(io) if @readable[io] == fiber\n        selected[fiber] = selected.fetch(fiber, 0) | IO::WRITABLE\n      end\n    end\n\n    selected.each do |fiber, events|\n      fiber.transfer(events)\n    end\n\n    if @waiting.any?\n      time = current_time\n      waiting, @waiting = @waiting, {}\n\n      waiting.each do |fiber, timeout|\n        if fiber.alive?\n          if timeout <= time\n            fiber.transfer\n          else\n            @waiting[fiber] = timeout\n          end\n        end\n      end\n    end\n\n    if @ready.any?\n      ready = nil\n\n      @lock.synchronize do\n        ready, @ready = @ready, []\n      end\n\n      ready.each do |fiber|\n        fiber.transfer if fiber.alive?\n      end\n    end\n  end\n\n  def run\n    # $stderr.puts [__method__, Fiber.current].inspect\n\n    # Use Thread.handle_interrupt like Async::Scheduler does\n    # This defers signal processing, which is the root cause of the gRPC bug\n    # See: https://github.com/socketry/async/blob/main/lib/async/scheduler.rb\n    Thread.handle_interrupt(::SignalException => :never) do\n      while @readable.any? or @writable.any? or @waiting.any? or @blocking.any?\n        run_once\n\n        break if Thread.pending_interrupt?\n      end\n    end\n  end\n\n  # A fiber scheduler hook, invoked when the scheduler goes out of scope.\n  def scheduler_close\n    close(true)\n  end\n\n  # If the `scheduler_close` hook does not exist, this method `close` will be\n  # invoked instead when the fiber scheduler goes out of scope. This is legacy\n  # behaviour, you should almost certainly use `scheduler_close`. The reason for\n  # this, is `scheduler_close` is called when the scheduler goes out of scope,\n  # while `close` may be called by the user.\n  def close(internal = false)\n    # $stderr.puts [__method__, Fiber.current].inspect\n\n    unless internal\n      if Fiber.scheduler == self\n        return Fiber.set_scheduler(nil)\n      end\n    end\n\n    if @closed\n      raise \"Scheduler already closed!\"\n    end\n\n    self.run\n  ensure\n    if @urgent\n      @urgent.each(&:close)\n      @urgent = nil\n    end\n\n    @closed ||= true\n\n    # We freeze to detect any unintended modifications after the scheduler is closed:\n    self.freeze\n  end\n\n  def closed?\n    @closed\n  end\n\n  def current_time\n    Process.clock_gettime(Process::CLOCK_MONOTONIC)\n  end\n\n  # This hook is invoked by `Timeout.timeout` and related code.\n  def timeout_after(duration, klass, message, &block)\n    fiber = Fiber.current\n\n    self.fiber do\n      sleep(duration)\n\n      if fiber&.alive?\n        fiber.raise(klass, message)\n      end\n    end\n\n    begin\n      yield(duration)\n    ensure\n      fiber = nil\n    end\n  end\n\n  # This hook is invoked by `Process.wait`, `system`, and backticks.\n  def process_wait(pid, flags)\n    # $stderr.puts [__method__, pid, flags, Fiber.current].inspect\n\n    # This is a very simple way to implement a non-blocking wait:\n    Thread.new do\n      Process::Status.wait(pid, flags)\n    end.value\n  end\n\n  # This hook is invoked by `IO#read` and `IO#write` in the case that `io_read`\n  # and `io_write` hooks are not available. This implementation is not\n  # completely general, in the sense that calling `io_wait` multiple times with\n  # the same `io` and `events` will not work, which is okay for tests but not\n  # for real code. Correct fiber schedulers should not have this limitation.\n  def io_wait(io, events, duration)\n    # $stderr.puts [__method__, io, events, duration, Fiber.current].inspect\n\n    fiber = Fiber.current\n\n    unless (events & IO::READABLE).zero?\n      @readable[io] = fiber\n      readable = true\n    end\n\n    unless (events & IO::WRITABLE).zero?\n      @writable[io] = fiber\n      writable = true\n    end\n\n    if duration\n      @waiting[fiber] = current_time + duration\n    end\n\n    @fiber.transfer\n  ensure\n    @waiting.delete(fiber) if duration\n    @readable.delete(io) if readable\n    @writable.delete(io) if writable\n  end\n\n  # This hook is invoked by `IO.select`. Using a thread ensures that the\n  # operation does not block the fiber scheduler.\n  def io_select(...)\n    # Emulate the operation using a non-blocking thread:\n    Thread.new do\n      IO.select(...)\n    end.value\n  end\n\n  # This hook is invoked by `IO#close`. Using a separate IO object\n  # demonstrates that the close operation is asynchronous.\n  def io_close(descriptor)\n    Fiber.blocking{IO.for_fd(descriptor.to_i).close}\n    return true\n  end\n\n  # This hook is invoked by `Kernel#sleep` and `Thread::Mutex#sleep`.\n  def kernel_sleep(duration = nil)\n    # $stderr.puts [__method__, duration, Fiber.current].inspect\n\n    self.block(:sleep, duration)\n\n    return true\n  end\n\n  # This hook is invoked by blocking options such as `Thread::Mutex#lock`,\n  # `Thread::Queue#pop` and `Thread::SizedQueue#push`, which are unblocked by\n  # other threads/fibers. To unblock a blocked fiber, you should call `unblock`\n  # with the same `blocker` and `fiber` arguments.\n  def block(blocker, timeout = nil)\n    # $stderr.puts [__method__, blocker, timeout].inspect\n\n    fiber = Fiber.current\n\n    if timeout\n      @waiting[fiber] = current_time + timeout\n      begin\n        @fiber.transfer\n      ensure\n        # Remove from @waiting in the case #unblock was called before the timeout expired:\n        @waiting.delete(fiber)\n      end\n    else\n      @blocking[fiber] = true\n      begin\n        @fiber.transfer\n      ensure\n        @blocking.delete(fiber)\n      end\n    end\n  end\n\n  # This method is invoked from a thread or fiber to unblock a fiber that is\n  # blocked by `block`. It is expected to be thread safe.\n  def unblock(blocker, fiber)\n    # $stderr.puts [__method__, blocker, fiber].inspect\n    # $stderr.puts blocker.backtrace.inspect\n    # $stderr.puts fiber.backtrace.inspect\n\n    @lock.synchronize do\n      @ready << fiber\n    end\n\n    io = @urgent.last\n    io.write_nonblock('.')\n  end\n\n  class FiberInterrupt\n    def initialize(fiber, exception)\n      @fiber = fiber\n      @exception = exception\n    end\n\n    def alive?\n      @fiber.alive?\n    end\n\n    def transfer\n      @fiber.raise(@exception)\n    end\n  end\n\n  def fiber_interrupt(fiber, exception)\n    @lock.synchronize do\n      @ready << FiberInterrupt.new(fiber, exception)\n    end\n\n    io = @urgent.last\n    io.write_nonblock('.')\n  end\n\n  # This hook is invoked by `Fiber.schedule`. Strictly speaking, you should use\n  # it to create scheduled fibers, but it is not required in practice;\n  # `Fiber.new` is usually sufficient.\n  def fiber(&block)\n    fiber = Fiber.new(blocking: false, &block)\n\n    fiber.transfer\n\n    return fiber\n  end\n\n  # This hook is invoked by `Addrinfo.getaddrinfo`. Using a thread ensures that\n  # the operation does not block the fiber scheduler, since `getaddrinfo` is\n  # usually provided by `libc` and is blocking.\n  def address_resolve(hostname)\n    Thread.new do\n      Addrinfo.getaddrinfo(hostname, nil).map(&:ip_address).uniq\n    end.value\n  end\n\n  def blocking_operation_wait(work)\n    thread = Thread.new{work.call}\n\n    thread.join\n\n    thread = nil\n  ensure\n    thread&.kill\n  end\nend\n\n# This scheduler class implements `io_read` and `io_write` hooks which require\n# `IO::Buffer`.\nclass IOBufferScheduler < Scheduler\n  EAGAIN = -Errno::EAGAIN::Errno\n\n  def io_read(io, buffer, length, offset)\n    total = 0\n    io.nonblock = true\n\n    while true\n      result = blocking{buffer.read(io, 0, offset)}\n\n      if result > 0\n        total += result\n        offset += result\n        break if total >= length\n      elsif result == 0\n        break\n      elsif result == EAGAIN\n        if length > 0\n          self.io_wait(io, IO::READABLE, nil)\n        else\n          return result\n        end\n      elsif result < 0\n        return result\n      end\n    end\n\n    return total\n  end\n\n  def io_write(io, buffer, length, offset)\n    total = 0\n    io.nonblock = true\n\n    while true\n      result = blocking{buffer.write(io, 0, offset)}\n\n      if result > 0\n        total += result\n        offset += result\n        break if total >= length\n      elsif result == 0\n        break\n      elsif result == EAGAIN\n        if length > 0\n          self.io_wait(io, IO::WRITABLE, nil)\n        else\n          return result\n        end\n      elsif result < 0\n        return result\n      end\n    end\n\n    return total\n  end\n\n  def io_pread(io, buffer, from, length, offset)\n    total = 0\n    io.nonblock = true\n\n    while true\n      result = blocking{buffer.pread(io, from, 0, offset)}\n\n      if result > 0\n        total += result\n        offset += result\n        from += result\n        break if total >= length\n      elsif result == 0\n        break\n      elsif result == EAGAIN\n        if length > 0\n          self.io_wait(io, IO::READABLE, nil)\n        else\n          return result\n        end\n      elsif result < 0\n        return result\n      end\n    end\n\n    return total\n  end\n\n  def io_pwrite(io, buffer, from, length, offset)\n    total = 0\n    io.nonblock = true\n\n    while true\n      result = blocking{buffer.pwrite(io, from, 0, offset)}\n\n      if result > 0\n        total += result\n        offset += result\n        from += result\n        break if total >= length\n      elsif result == 0\n        break\n      elsif result == EAGAIN\n        if length > 0\n          self.io_wait(io, IO::WRITABLE, nil)\n        else\n          return result\n        end\n      elsif result < 0\n        return result\n      end\n    end\n\n    return total\n  end\n\n  def blocking(&block)\n    Fiber.blocking(&block)\n  end\nend\n\nclass IOScheduler < Scheduler\n  def operations\n    @operations ||= []\n  end\n\n  def io_write(io, buffer, length, offset)\n    descriptor = io.fileno\n    string = buffer.get_string\n\n    self.operations << [:io_write, descriptor, string]\n\n    Fiber.blocking do\n      buffer.write(io, 0, offset)\n    end\n  end\nend\n\nclass IOErrorScheduler < Scheduler\n  def io_read(io, buffer, length, offset)\n    return -Errno::EBADF::Errno\n  end\n\n  def io_write(io, buffer, length, offset)\n    return -Errno::EINVAL::Errno\n  end\nend\n\n# This scheduler has a broken implementation of `unblock`` in the sense that it\n# raises an exception. This is used to test the behavior of the scheduler when\n# unblock raises an exception.\nclass BrokenUnblockScheduler < Scheduler\n  def unblock(blocker, fiber)\n    super\n\n    raise \"Broken unblock!\"\n  end\nend\n\n# This scheduler has a broken implementation of `unblock` in the sense that it\n# sleeps. This is used to test the behavior of the scheduler when unblock\n# messes with the internal thread state in an unexpected way.\nclass SleepingUnblockScheduler < Scheduler\n  # This method is invoked when the thread is exiting.\n  def unblock(blocker, fiber)\n    super\n\n    # This changes the current thread state to `THREAD_RUNNING` which causes `thread_join_sleep` to hang.\n    sleep(0.1)\n  end\nend\n\n# This scheduler has a broken implementation of `kernel_sleep` in the sense that\n# it invokes a blocking sleep which can cause a deadlock in some cases.\nclass SleepingBlockingScheduler < Scheduler\n  def kernel_sleep(duration = nil)\n    # Deliberaly sleep in a blocking state which can trigger a deadlock if the implementation is not correct.\n    Fiber.blocking{sleep 0.0001}\n\n    self.block(:sleep, duration)\n\n    return true\n  end\nend\n"})
      # A non-blocking fiber hands open(2), close(2) of a stream that writes,
      # stat(2), access(2) and unlink(2) to its scheduler's
      # blocking_operation_wait, as an object of an unnamed class whose #call
      # runs the operation once. IO reads and writes go to io_read and
      # io_write, and a hook's negative errno raises.
      require_relative "a_fiber_scheduler_takes_every_blocking_operation/scheduler"
      require "tmpdir"
      ops = []
      Thread.new do
        sched = Class.new(Scheduler) do
          define_method(:blocking_operation_wait) do |op|
            ops << [op.class.name, op.class.superclass, op.respond_to?(:call)]
            Thread.new { op.call }.join
            ops << (op.call rescue $!.message)
          end
        end.new
        Fiber.set_scheduler(sched)
        Fiber.schedule do
          ops << :started
          File.open(__FILE__) { |f| ops << f.gets }
          path = File.join(Dir.tmpdir, "zeo_blocking_#{$$}")
          File.write(path, "x")
          ops << File.exist?(path) << File.size(path)
          File.delete(path)
          ops << :done
        end
        ops << :scheduled
      end.join
      ops.each { |o| p o }
      failures = []
      Thread.new do
        Fiber.set_scheduler(IOErrorScheduler.new)
        r, w = IO.pipe
        Fiber.schedule do
          failures << (r.read(1) rescue $!.class)
          failures << (w.write("x") rescue $!.class)
        end
      end.join
      p failures
      Thread.new do
        Fiber.set_scheduler(IOScheduler.new)
        r, w = IO.pipe
        Fiber.schedule { w.write("abc"); w.syswrite("de"); w.close }
        Fiber.schedule { p r.read }
      end.join


    RUBY

    _(result).must_answer <<~'OUT'
      :started
      [nil, Object, true]
      :scheduled
      "Blocking operation has already been executed!"
      "# A non-blocking fiber hands open(2), close(2) of a stream that writes,\n"
      [nil, Object, true]
      "Blocking operation has already been executed!"
      [nil, Object, true]
      "Blocking operation has already been executed!"
      [nil, Object, true]
      "Blocking operation has already been executed!"
      [nil, Object, true]
      "Blocking operation has already been executed!"
      true
      [nil, Object, true]
      "Blocking operation has already been executed!"
      1
      [nil, Object, true]
      "Blocking operation has already been executed!"
      :done
      [Errno::EBADF, Errno::EINVAL]
      "abcde"
    OUT
  end

  it "set scheduler checks and closes the scheduler" do
    result = ze0(<<~'RUBY', path: "core/fiber/set_scheduler_checks_and_closes_the_scheduler.rb")
      # Fiber.set_scheduler checks the hooks a scheduler needs and warns of
      # fiber_interrupt; Fiber.schedule runs the fiber hook, a sleep in it
      # reaches kernel_sleep, and setting nil closes the scheduler.
      class S
        def initialize; @ready = []; @log = []; end
        attr_reader :log
        def kernel_sleep(d = nil) = (@log << :sleep; Fiber.yield)
        def block(blocker, timeout = nil) = (@log << :block; Fiber.yield)
        def unblock(blocker, fiber) = (@log << :unblock; @ready << fiber)
        def io_wait(io, events, timeout) = (@log << :io_wait; events)
        def fiber(&b) = Fiber.new(blocking: false, &b).tap(&:resume)
        def close = (@log << :close)
        def run; end
      end
      s = S.new
      Fiber.set_scheduler(s)
      p Fiber.scheduler.equal?(s)
      Fiber.schedule { sleep 1; :x }
      p s.log
      Fiber.set_scheduler(nil)
      p s.log.last
      begin
        Fiber.set_scheduler(Object.new)
      rescue ArgumentError => e
        p e.message
      end
      p((Fiber.schedule {} rescue $!))
    RUBY

    _(result).must_answer <<~'OUT', stderr: "core/fiber/set_scheduler_checks_and_closes_the_scheduler.rb:16: warning: Scheduler should implement #fiber_interrupt\n"
      true
      [:sleep]
      :close
      "Scheduler must implement #block"
      #<RuntimeError: No scheduler is available!>
    OUT
  end

  it "transferred fiber ends in its threads root" do
    result = ze0(<<~'RUBY')
      # A fiber that ends after a transfer goes back to its thread's own root
      # fiber, and Fiber#raise transfers to a fiber that transferred away.
      root = Fiber.current
      log = []
      a = Fiber.new(blocking: false) { log << :a1; root.transfer; log << :a2 }
      a.transfer
      log << :back
      a.transfer
      log << :done
      p log
      t = Thread.new do
        r = Fiber.current
        b = Fiber.new(blocking: false) { log << :b1; r.transfer; log << :b2 }
        b.transfer
        log << :tback
        b.transfer
        log << :tdone
      end
      t.join
      p log
      r, w = IO.pipe
      t2 = Thread.new { IO.select([r], [], [], 0.01) }
      p t2.value
      root = Fiber.current
      f = Fiber.new { begin; root.transfer; rescue => e; p [:rescued, e.message]; end; :ended }
      f.transfer
      p f.raise("boom")
    RUBY

    _(result).must_answer <<~'OUT'
      [:a1, :back, :a2, :done]
      [:a1, :back, :a2, :done, :b1, :tback, :b2, :tdone]
      nil
      [:rescued, "boom"]
      :ended
    OUT
  end
end
