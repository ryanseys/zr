# frozen_string_literal: true

require "spec_helper"

describe "Fiber programs" do
  it "inspect names the block's file and line and the fiber's status" do
    result = zr(<<~'RUBY')
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
      #<Fiber:X core/fiber/fiber_test.rb:8 (created)>
      #<Fiber:X (suspended by resuming)>
      #<Fiber:X core/fiber/fiber_test.rb:8 (suspended by resuming)>
      #<Fiber:X core/fiber/fiber_test.rb:9 (suspended)>
      #<Fiber:X core/fiber/fiber_test.rb:8 (terminated)>
      true
      #<Fiber:X(&:itself) (created)>
      false
      true
    OUT
  end

  it "kill unwinds through ensure, raise carries in, and a resumed or cross-thread resume says so" do
    result = zr(<<~'RUBY')
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

  it "a non-blocking fiber's reads and writes reach the scheduler's io_read and io_write with a buffer" do
    result = zr(<<~'RUBY', files: {"fiber_scheduler/scheduler.rb" => fixture("core/fiber/scheduler.rb")})
      # A non-blocking fiber's reads and writes reach its scheduler's io_read,
      # io_write, io_pread and io_pwrite with an IO::Buffer, in the sizes io.c
      # reads and writes with. This runtime reads and writes itself and hands
      # the scheduler only io_wait, so a scheduler that logs its hooks sees none.
      require_relative "fiber_scheduler/scheduler"
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
      # The writer closes once the reader has taken "more" and waits in
      # `read`: a Queue says so with no clock, where a sleep raced the
      # reader on a loaded machine.
      log = []
      sched = nil
      Thread.new do
        sched = Logged.new
        Fiber.set_scheduler(sched)
        r, w = IO.pipe
        taken = Thread::Queue.new
        Fiber.schedule { log << r.read(5); log << r.gets; log << r.readpartial(10); taken << true; log << r.read }
        Fiber.schedule { w.write("hello"); w.sync = false; w.print("line\n"); w.flush; w.syswrite("more"); taken.pop; w.close }
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
      ["hello", "line\n", "more", "", "# A non", "A no", "abc"]
      [:io_read, IO, 5, false, true, 0, 0]
      [:io_write, IO, 5, "hello", 0, 0]
      [:io_write, IO, 5, "line\n", 0, 0]
      [:io_write, IO, 4, "more", 0, 0]
      [:io_read, IO, 5, false, true, 0, 0]
      [:io_read, IO, 8192, false, true, 0, 0]
      [:io_read, IO, 1024, false, true, 0, 0]
      [:io_read, IO, 1024, false, true, 0, 0]
      [:io_read, File, 7, false, true, 0, 0]
      [:io_pread, 2, 0, 0]
      [:io_pwrite, 1, 0, 0]
      [:io_write, File, 3, "abc", 0, 0]
      [:io_read, File, 3, false, true, 0, 0]
      [:io_read, File, 1024, false, true, 0, 0]
    OUT
  end

  it "a scheduler takes sleep, a pipe, a Mutex, a Queue, a wait, a timeout and a resolve" do
    result = zr(<<~'RUBY', files: {"fiber_scheduler/scheduler.rb" => fixture("core/fiber/scheduler.rb")})
      # A thread with a fiber scheduler hands each blocking operation of its
      # non-blocking fibers to the scheduler: sleep, a pipe read and write, a
      # Mutex, a Queue, a Thread#value, Process.wait, Timeout.timeout,
      # getaddrinfo and a close. The scheduler is CRuby's own test scheduler
      # (test/fiber/scheduler.rb at ruby 4.0.6), unedited.
      require_relative "fiber_scheduler/scheduler"
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

  it "allocate makes a fiber that refuses to run, and a subclass makes its fiber through super" do
    result = zr(<<~'RUBY')
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
    result = zr(<<~'RUBY', files: {"fiber_scheduler/scheduler.rb" => fixture("core/fiber/scheduler.rb")})
      # A non-blocking fiber hands open(2), close(2) of a stream that writes,
      # stat(2), access(2) and unlink(2) to its scheduler's
      # blocking_operation_wait, as an object of an unnamed class whose #call
      # runs the operation once. IO reads and writes go to io_read and
      # io_write, and a hook's negative errno raises.
      require_relative "fiber_scheduler/scheduler"
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
          path = File.join(Dir.tmpdir, "zr_blocking_#{$$}")
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
    result = zr(<<~'RUBY')
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

    _(result).must_answer <<~'OUT', stderr: <<~'ERR'
      true
      [:sleep]
      :close
      "Scheduler must implement #block"
      #<RuntimeError: No scheduler is available!>
    OUT
      core/fiber/fiber_test.rb:16: warning: Scheduler should implement #fiber_interrupt
    ERR
  end

  it "transferred fiber ends in its threads root" do
    result = zr(<<~'RUBY')
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
