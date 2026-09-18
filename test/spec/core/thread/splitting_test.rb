# frozen_string_literal: true

require "spec_helper"

describe "Thread: splitting and joining" do
  it "blocked thread is asleep" do
    result = ze0(<<~'RUBY')
      # A thread waiting on a blocking primitive is "sleep", not "run". zeo used to
      # answer "run" for every one of them, because only the `Thread.stop` latch
      # said "sleep" -- and that latch cannot be reused, since the stop loop spins
      # on it.

      # Wait until `t` reaches a settled word, so the reading is not a race.
      def settle(t)
        200.times do
          break unless t.status == "run"
          sleep 0.005
        end
        [t.status, t.stop?]
      end

      q = Queue.new
      p settle(Thread.new { q.pop })

      m = Mutex.new
      m.lock
      p settle(Thread.new { m.lock })

      p settle(Thread.new { sleep 30 })

      r, w = IO.pipe
      p settle(Thread.new { r.read(1) })

      sq = SizedQueue.new(1)
      sq.push(:one)
      p settle(Thread.new { sq.push(:two) })

      # `Thread.stop` still reads the same way, and so does a running thread.
      stopped = Thread.new { Thread.stop }
      p settle(stopped)

      running = Thread.new { loop {} }
      p [running.status, running.stop?]

      # A finished thread, for contrast.
      done = Thread.new { 1 }
      done.join
      p [done.status, done.stop?]

      # The MAIN thread is not exempt: another thread reading it while it sleeps
      # sees "sleep" too.
      main = Thread.main
      seen = Thread.new do
        sleep 0.005 while main.status == "run"
        main.status
      end
      sleep 0.2
      p seen.value

      # A dead thread answers for itself with nobody joining it: killed is false,
      # killed by a raise is nil.
      killed = Thread.new { sleep 30 }
      sleep 0.05
      killed.kill
      raised = Thread.new { sleep 30 }
      raised.report_on_exception = false
      sleep 0.05
      raised.raise(RuntimeError, "boom")
      sleep 0.2
      p [killed.status, killed.alive?]
      p [raised.status, raised.alive?]

      [running, stopped].each(&:kill)
    RUBY

    _(result).must_answer <<~'OUT'
      ["sleep", true]
      ["sleep", true]
      ["sleep", true]
      ["sleep", true]
      ["sleep", true]
      ["sleep", true]
      ["run", false]
      [false, true]
      "sleep"
      [false, false]
      [nil, false]
    OUT
  end

  it "closing a queue wakes a blocked consumer with nil" do
    result = ze0(<<~'RUBY')
      q = Queue.new
      consumer = Thread.new do
        v = q.pop
        if v.nil?
          :got_nil
        else
          :got_value
        end
      end
      closer = Thread.new { q.close }
      puts consumer.value
      closer.join
    RUBY

    _(result).must_answer "got_nil\n"
  end

  it "concurrency handle nil" do
    result = ze0(<<~'RUBY')
      # `nil?` on a slot typed as a concurrency handle answered a compile-time false,
      # on the reasoning that a live handle is never NULL. The slot holding one can
      # be, though: `@t = nil` then `if @t.nil?` folded to false, so the guarded
      # `Thread.new` never ran and every later call went through the NULL still in
      # the ivar -- a segfault in Thread#alive? / #kill rather than a thread.
      class A
        def initialize
          @t = nil
        end

        def go
          if @t.nil?
            @t = Thread.new { sleep(0.05) }
          end
          puts "thread created"
        end

        attr_reader :t
      end

      a = A.new
      p a.t.nil?
      a.go
      p a.t.nil?
      p a.t.class
      p a.t.alive?
      a.t.kill
      puts "thread ok"

      # the guard also has to stay false once it is set, so a second call is a no-op
      a.go

      # the same slot shape for the other three handles
      class B
        def initialize
          @q = nil
          @m = nil
          @c = nil
        end

        def fill
          @q = Queue.new if @q.nil?
          @m = Mutex.new if @m.nil?
          @c = ConditionVariable.new if @c.nil?
        end

        def report
          p [@q.nil?, @m.nil?, @c.nil?]
        end

        attr_reader :q, :m
      end

      b = B.new
      b.report
      b.fill
      b.report
      b.q.push(1)
      p b.q.pop
      p b.m.locked?

      # a local, which takes the same arm
      t = nil
      p t.nil?
      t = Thread.new { 1 }
      p t.nil?
      t.join
      puts "done"
    RUBY

    _(result).must_answer <<~'OUT'
      true
      thread created
      false
      Thread
      true
      thread ok
      thread created
      [true, true, true]
      [false, false, false]
      1
      false
      true
      false
      done
    OUT
  end

  it "freezing in one thread is visible after join" do
    result = ze0(<<~'RUBY')
      # Threads share the heap (no Ractor boundary): a freeze in one is the
      # same AtomicBool every other execution context reads.

      s = "x"
      t = Thread.new { s.freeze }
      t.join
      puts s.frozen?
    RUBY

    _(result).must_answer "true\n"
  end

  it "method that only recurses hands the turn on" do
    result = ze0(<<~'RUBY')
      # A thread that only recurses has no loop, so no back edge of compiled
      # Ruby and no kernel iterator: the poll at each method's entry is where
      # it hands the turn on. The worker's five steps land before the burner
      # is done, as they do under ruby's timer thread.

      def burn(depth) = depth.zero? ? 1 : burn(depth - 1) + burn(depth - 1)

      steps = []
      burner = Thread.new { burn(25); steps << :done }
      worker = Thread.new { 5.times { steps << :step; sleep 0.01 } }
      worker.join
      burner.join
      p steps

    RUBY

    _(result).must_answer "[:step, :step, :step, :step, :step, :done]\n"
  end

  it "queue producer consumer rendezvous with close" do
    result = ze0(<<~'RUBY')
      # pop blocks the thread until a value or closure arrives; a closed empty
      # queue pops nil (`thread_sync.c:1034`).

      q = Queue.new
      producer = Thread.new do
        q.push 1
        q.push 2
        q.close
      end
      consumer = Thread.new do
        total = 0
        loop do
          v = q.pop
          break if v.nil?
          total += v
        end
        total
      end
      producer.join
      puts consumer.value
    RUBY

    _(result).must_answer "3\n"
  end

  it "sized queue and try lock" do
    result = ze0(<<~'RUBY')
      # SizedQueue back-pressure and Mutex#try_lock on the cooperative scheduler.

      # A SizedQueue(2) whose producer pushes 5 items: #push blocks once two are
      # buffered until the consumer pops, so the queue never exceeds its bound.
      q = SizedQueue.new(2)
      p q.max                    # 2
      p q.class                  # SizedQueue
      p q.is_a?(Queue)           # true (SizedQueue < Queue)
      producer = Thread.new do
        5.times { |i| q.push(i) }
        q.close
      end
      got = []
      while (v = q.pop)
        got << v
      end
      producer.join
      p got                      # [0, 1, 2, 3, 4]

      # spare-capacity ops: <<-chaining, size, pop, max
      s = SizedQueue.new(3)
      p s.empty?                 # true
      s << "a" << "b"
      p s.size                   # 2
      p s.pop                    # "a"
      p s.max                    # 3

      # max= raises the bound
      s.max = 5
      p s.max                    # 5

      # Mutex#try_lock acquires only when free
      m = Mutex.new
      p m.try_lock               # true
      p m.try_lock               # false (already held)
      m.unlock
      p m.try_lock               # true again
      m.unlock
    RUBY

    _(result).must_answer <<~'OUT'
      2
      Thread::SizedQueue
      true
      [0, 1, 2, 3, 4]
      true
      2
      "a"
      3
      5
      true
      false
      true
    OUT
  end

  it "sized queue back pressure try lock and thread namespacing" do
    result = ze0(<<~'RUBY')
      # SizedQueue bounds #push; Mutex#try_lock is non-blocking; and the whole
      # Thread::* family reports its CRuby-faithful qualified name.

      p Queue
      p SizedQueue
      p Mutex
      q = SizedQueue.new(2)
      p q.class
      p q.is_a?(Queue)
      p q.max
      producer = Thread.new do
        5.times { |i| q.push(i) }
        q.close
      end
      got = []
      while (v = q.pop)
        got << v
      end
      producer.join
      p got
      s = SizedQueue.new(3)
      s << "a" << "b"
      p s.size
      s.max = 5
      p s.max
      m = Mutex.new
      p m.try_lock
      p m.try_lock
      m.unlock
      p m.try_lock
      m.unlock
    RUBY

    _(result).must_answer <<~'OUT'
      Thread::Queue
      Thread::SizedQueue
      Thread::Mutex
      Thread::SizedQueue
      true
      2
      [0, 1, 2, 3, 4]
      2
      5
      true
      false
      true
    OUT
  end

  it "spinner with no back edge of its own hands the turn on" do
    result = ze0(<<~'RUBY')
      # A thread that only computes hands the turn on wherever it loops: at a
      # `next` or `redo` that jumps back before the loop's end, and inside the
      # runtime's own iterators, whose bodies have no back edge of compiled
      # Ruby at all. The worker gets its turn, and a kill reaches each spinner.

      Thread.report_on_exception = false
      spinners = [
        Thread.new { while true; next; end },
        Thread.new { while true; redo; end },
        Thread.new { 10_000_000_000.times { } },
        Thread.new { 0.upto(10_000_000_000) { } },
        Thread.new { 10_000_000_000.downto(0) { } },
        Thread.new { a = [1] * 1_000_000; while true; a.each { }; a.map { }; a.select { }; end },
        Thread.new { h = (1..100_000).to_h { |i| [i, i] }; while true; h.each { }; end },
      ]
      worker = Thread.new { 21 + 21 }
      p worker.value
      spinners.each(&:kill).each(&:join)
      p spinners.map(&:alive?)

    RUBY

    _(result).must_answer <<~'OUT'
      42
      [false, false, false, false, false, false, false]
    OUT
  end

  it "spinning thread cannot starve a sibling" do
    result = ze0(<<~'RUBY')
      # THE parallel-default headline: a compute-only spinner in one thread
      # cannot starve a sibling, because both run on independent OS threads. The
      # worker computes its value concurrently while the spinner loops; the
      # program only finishes once the spinner is killed.

      Thread.report_on_exception = false
      spinner = Thread.new { loop { } }
      worker = Thread.new { 21 + 21 }
      p worker.value
      spinner.kill
      spinner.join
      p spinner.alive?
    RUBY

    _(result).must_answer <<~'OUT'
      42
      false
    OUT
  end

  it "thread condvar" do
    result = ze0(<<~'RUBY')
      # ConditionVariable on the cooperative scheduler: #wait releases the mutex and
      # parks until #signal/#broadcast wakes the waiter, which re-acquires the mutex.

      m = Mutex.new
      cv = ConditionVariable.new
      ready = false
      log = []
      worker = Thread.new do
        m.synchronize do
          cv.wait(m) until ready
        end
        log << :worked
      end
      Thread.pass                 # let the worker reach cv.wait
      m.synchronize do
        ready = true
        cv.signal
      end
      worker.join
      log << :done
      p log                       # [:worked, :done]
      p ready                     # true

      # broadcast wakes every waiter
      m3 = Mutex.new
      cv3 = ConditionVariable.new
      go = false
      done = []
      ws = (1..3).map do |i|
        Thread.new do
          m3.synchronize { cv3.wait(m3) until go }
          done << i
        end
      end
      Thread.pass                 # all three reach cv3.wait
      m3.synchronize { go = true; cv3.broadcast }
      ws.each(&:join)
      p done.sort                 # [1, 2, 3]
    RUBY

    _(result).must_answer <<~'OUT'
      [:worked, :done]
      true
      [1, 2, 3]
    OUT
  end

  it "thread extended" do
    result = ze0(<<~'RUBY')
      # Thread.current / .main / .pass
      p Thread.current.class
      p Thread.current == Thread.main
      p Thread.pass

      # name, value, status
      t = Thread.new { 20 + 22 }
      t.name = "worker"
      p t.name
      p t.value          # joins, returns the block's result
      p t.status         # false once finished cleanly
      p Thread.main.status

      # fiber-local storage (Thread#[]) and thread variables are distinct
      Thread.current[:tag] = "root"
      p Thread.current[:tag]
      p Thread.current.key?(:tag)
      # (The oracle runs under bundler/setup, whose logger leaves a fiber-local
      # key of its own behind; it is not this program's.)
      p Thread.current.keys.grep_v(/logger/)
      Thread.current.thread_variable_set(:count, 3)
      p Thread.current.thread_variable_get(:count)
      p Thread.current.thread_variable?(:count)
      p Thread.current.thread_variables.grep_v(/logger/)

      # report_on_exception defaults true and is settable
      p Thread.current.report_on_exception
      Thread.current.report_on_exception = false
      p Thread.current.report_on_exception

      # Poly receiver: a Thread held in an Array dispatches the same rows.
      workers = [Thread.new { 1 }, Thread.new { 2 }]
      workers.each(&:join)
      p workers.map(&:status)
    RUBY

    _(result).must_answer <<~'OUT'
      Thread
      true
      nil
      "worker"
      42
      false
      "run"
      "root"
      true
      [:tag]
      3
      true
      [:count]
      true
      false
      [false, false]
    OUT
  end

  it "thread join and value via dynamic dispatch" do
    result = ze0(<<~'RUBY')
      # The threads live in an Array, so `join`/`value` dispatch dynamically
      # (the runtime Thread table), not the static codegen fast path.

      threads = 3.times.map { |i| Thread.new { i * 10 } }
      threads.each(&:join)
      p threads.map(&:value)
    RUBY

    _(result).must_answer "[0, 10, 20]\n"
  end

  it "thread local" do
    result = ze0(<<~'RUBY')
      # Thread-local storage (Thread#[] / #[]= / #key?, symbol keys), #status, and
      # Thread.main on the cooperative scheduler. Each thread has its own storage.

      Thread.current[:user] = "alice"
      p Thread.current[:user]          # "alice"
      p Thread.current[:missing]       # nil
      p Thread.current.key?(:user)     # true
      p Thread.current.key?(:nope)     # false

      # each thread gets its own storage
      t = Thread.new do
        Thread.current[:user] = "bob"
        Thread.current[:user]
      end
      p t.value                        # "bob"
      p Thread.current[:user]          # "alice" (the main thread's slot is unaffected)

      # #status
      p Thread.current.status          # "run"
      done = Thread.new { 1 + 1 }
      done.join
      p done.status                    # false (finished normally)

      # Thread.main / identity ==
      p Thread.main == Thread.current  # true
      p Thread.new { 1 } != Thread.current  # true (distinct instances)
    RUBY

    _(result).must_answer <<~'OUT'
      "alice"
      nil
      true
      false
      "bob"
      "alice"
      "run"
      false
      true
      true
    OUT
  end

  it "thread mutex" do
    result = ze0(<<~'RUBY')
      # Mutex on the cooperative scheduler: #synchronize wraps the block in lock/unlock,
      # and lock/unlock/locked?/owned?/try_lock behave as in CRuby.

      # synchronize protects a shared counter across threads (created in a map, joined
      # via &:join, so a Thread carried in a poly slot dispatches #join correctly)
      m = Mutex.new
      counter = 0
      threads = (1..5).map { Thread.new { 10.times { m.synchronize { counter += 1 } } } }
      threads.each(&:join)
      p counter                 # 50

      # explicit lock / unlock / locked? / owned?
      m2 = Mutex.new
      p m2.locked?              # false
      m2.lock
      p m2.locked?              # true
      p m2.owned?               # true
      m2.unlock
      p m2.locked?              # false

      # try_lock acquires only when free
      p m2.try_lock             # true
      p m2.try_lock             # false (we already hold it)
      m2.unlock

      # synchronize returns the block's value
      r = m2.synchronize { 7 * 6 }
      p r                       # 42
    RUBY

    _(result).must_answer <<~'OUT'
      50
      false
      true
      true
      false
      true
      false
      42
    OUT
  end

  it "thread name" do
    result = ze0(<<~'RUBY')
      # Thread#name / #name= name a thread; the default is nil.
      t = Thread.new { 1 }
      p t.name                      # nil
      t.name = "worker"
      p t.name                      # "worker"
      t.join

      # the main thread can be named too
      p Thread.main.name            # nil
      Thread.current.name = "main-thread"
      p Thread.current.name         # "main-thread"
    RUBY

    _(result).must_answer <<~'OUT'
      nil
      "worker"
      nil
      "main-thread"
    OUT
  end

  it "thread queue" do
    result = ze0(<<~'RUBY')
      # Queue producer/consumer on the cooperative scheduler (Phase 0). A blocking
      # #pop parks the caller until a #push hands it a value; #close drains remaining
      # poppers with nil. Results are FIFO (deterministic); thread interleaving order
      # is timing-dependent in CRuby, so only values/counts are asserted.

      # a producer thread; the main thread consumes and blocks on the empty queue
      q = Queue.new
      prod = Thread.new do
        5.times { |i| q.push(i * 10) }
        q.close
      end
      got = []
      while (v = q.pop)
        got << v
      end
      prod.join
      p got                 # [0, 10, 20, 30, 40]
      p q.closed?           # true

      # a consumer thread receives every pushed value, in FIFO order
      q2 = Queue.new
      out = []
      cons = Thread.new do
        3.times { out << q2.pop }
      end
      [1, 2, 3].each { |x| q2.push(x) }
      cons.join
      p out                 # [1, 2, 3]

      # size / empty? / closed? / << chaining
      q3 = Queue.new
      p q3.empty?           # true
      q3 << "a" << "b" << "c"
      p q3.size             # 3
      p q3.empty?           # false
      p q3.pop              # "a"
      p q3.size             # 2
    RUBY

    _(result).must_answer <<~'OUT'
      [0, 10, 20, 30, 40]
      true
      [1, 2, 3]
      true
      3
      false
      "a"
      2
    OUT
  end

  it "thread sized queue" do
    result = ze0(<<~'RUBY')
      # SizedQueue on the cooperative scheduler: #push blocks when the queue is at its
      # capacity until a #pop frees a slot. FIFO values are deterministic; thread
      # interleaving order is not asserted.

      q = SizedQueue.new(2)
      p q.max                    # 2
      producer = Thread.new do
        5.times { |i| q.push(i) }
        q.close
      end
      got = []
      while (v = q.pop)
        got << v
      end
      producer.join
      p got                      # [0, 1, 2, 3, 4]

      # size / << chaining / pop on a SizedQueue with spare capacity
      s = SizedQueue.new(3)
      p s.empty?                 # true
      s << "a" << "b"
      p s.size                   # 2
      p s.pop                    # "a"
      p s.size                   # 1
      p s.max                    # 3
    RUBY

    _(result).must_answer <<~'OUT'
      2
      [0, 1, 2, 3, 4]
      true
      2
      "a"
      1
      3
    OUT
  end

  it "thread value through container" do
    result = ze0(<<~'RUBY')
      # A Thread (modelled as a single-threaded Fiber) carried through a container:
      # #value/#join must dispatch on the boxed Fiber, not degrade to nil (#1261).
      ts = (1..3).map { |i| Thread.new { i * 10 } }
      p ts.map { |t| t.value }
      p ts[0].value            # idempotent: re-reading a finished thread's value
      arr = [Thread.new { 99 }]
      p arr[0].value
      m = Mutex.new
      n = 0
      m.synchronize { n += 1 }
      puts n
    RUBY

    _(result).must_answer <<~'OUT'
      [10, 20, 30]
      10
      99
      1
    OUT
  end

  it "threads" do
    result = ze0(<<~'RUBY')
      # Thread / Mutex / Queue -- green-thread concurrency

      # join-synchronized ordering
      t = Thread.new do
        puts "in thread"
      end
      t.join
      puts "after join"

      # constructor args bind to block params; value returns the result
      puts Thread.new(20, 22) { |a, b| a + b }.value

      # an uncaught exception re-raises at join
      bad = Thread.new { raise "thread boom" }
      begin
        bad.join
      rescue RuntimeError => e
        puts "joined error: #{e.send(:message)}"
      end

      # a mutex-protected shared counter across two threads
      m = Mutex.new
      count = 0
      t1 = Thread.new { 500.times { m.synchronize { count += 1 } } }
      t2 = Thread.new { 500.times { m.synchronize { count += 1 } } }
      t1.join
      t2.join
      puts count

      # mutex error semantics
      mu = Mutex.new
      begin
        mu.unlock
      rescue ThreadError => e
        puts e.send(:message)
      end
      mu.lock
      begin
        mu.lock
      rescue ThreadError => e
        puts e.send(:message)
      end
      mu.unlock

      # queue producer/consumer rendezvous
      q = Queue.new
      producer = Thread.new do
        q.push 1
        q.push 2
        q.push 3
        q.close
      end
      consumer = Thread.new do
        total = 0
        loop do
          v = q.pop
          break if v.nil?
          total += v
        end
        total
      end
      producer.join
      puts consumer.value

      # push to a closed queue raises
      begin
        q.push 99
      rescue ClosedQueueError => e
        puts e.send(:message)
      end
    RUBY

    _(result).must_answer <<~'OUT', stderr: "#<Thread:0xADDR core/thread/splitting_test.rb:14 run> terminated with exception (report_on_exception is true):\ncore/thread/splitting_test.rb:14:in 'block in <main>': thread boom (RuntimeError)\n"
      in thread
      after join
      42
      joined error: thread boom
      1000
      Attempt to unlock a mutex which is not locked
      deadlock; recursive locking
      6
      queue closed
    OUT
  end

  it "three threads join out of creation order" do
    result = ze0(<<~'RUBY')
      t1 = Thread.new { 1 }
      t2 = Thread.new { 2 }
      t3 = Thread.new { 3 }
      puts t3.value + t1.value + t2.value
    RUBY

    _(result).must_answer "6\n"
  end

  it "wait converts its timeout before it parks" do
    result = ze0(<<~'RUBY')
      # Every wait reads its timeout before it parks, and two rules apply: a
      # sleep takes a time interval, which refuses a negative one, while a
      # limit (a queue's timeout, a join's) takes what rb_to_float takes and
      # answers at once when the limit has passed.
      def t = yield rescue [$!.class, $!.message]

      m = Thread::Mutex.new
      p t { m.synchronize { m.sleep(:x) } }
      p t { m.synchronize { m.sleep("2") } }
      p t { m.synchronize { m.sleep(-1) } }
      cv = Thread::ConditionVariable.new
      p t { m.synchronize { cv.wait(m, :x) } }

      q = Thread::Queue.new
      p t { q.pop(timeout: :x) }
      p t { q.pop(timeout: "2") }
      p t { q.pop(timeout: -1) }

      s = Thread::SizedQueue.new(1)
      s << 1
      p t { s.push(2, timeout: :x) }
      p t { s.push(2, timeout: -1) }

      p t { Thread.new { 1 }.join(:x) }
      p t { Thread.new { 1 }.join("2") }

    RUBY

    _(result).must_answer <<~'OUT'
      [TypeError, "can't convert Symbol into time interval"]
      [TypeError, "can't convert String into time interval"]
      [ArgumentError, "time interval must not be negative"]
      [TypeError, "can't convert Symbol into time interval"]
      [TypeError, "can't convert Symbol into Float"]
      [TypeError, "no implicit conversion to float from string"]
      nil
      [TypeError, "can't convert Symbol into Float"]
      nil
      [TypeError, "can't convert Symbol into Float"]
      [TypeError, "no implicit conversion to float from string"]
    OUT
  end
end
