# frozen_string_literal: true

require "spec_helper"

describe "Thread: formatting and inspection" do
  it "concurrency logical operands" do
    result = ze0(<<~'RUBY')
      # `&&` / `||` with a concurrency handle on either side must keep the handle's
      # full identity.
      #
      # zeo's divergence is one probe: a Queue carried through `||` no longer
      # inspects in the `#<Thread::Queue:0x...>` form (the final
      # `inspect.start_with?` answers false). Every other operand shape -- classes,
      # values, nil, locked? -- already matches. (Imported from spinel, where the
      # same file once failed to BUILD, #3484.)
      m = Mutex.new
      p(m.lock && m.locked?)
      m.unlock

      q = Queue.new
      sq = SizedQueue.new(2)
      cv = ConditionVariable.new
      f = Fiber.new { 1 }
      t = Thread.new { 1 }
      t.join

      p (:ok && q).class
      p (:ok && sq).class
      p (:ok && m).class
      p (:ok && cv).class
      p (:ok && f).class
      p (:ok && t).class

      p (q || :ok).class
      p (m || :ok).class
      p (f || :ok).class

      p (m && 1)
      p (f || 2).inspect.start_with?("#<Fiber:")
      p (q && :done)

      # the handle on the left with each of the other operand shapes
      p (m && "s")
      p (m && 1.5)
      p (m && [1])
      p (m && nil).nil?
      p (m && m.locked?)

      # a boxed handle names itself in inspect rather than answering #<Object>
      p (q || 2).inspect.start_with?("#<Thread::Queue:")

      # a falsy left keeps the left, and a nil-valued handle reads falsy
      p (nil && q).nil?
      p (nil || q).class
    RUBY

    _(result).must_answer <<~'OUT'
      true
      Thread::Queue
      Thread::SizedQueue
      Thread::Mutex
      Thread::ConditionVariable
      Fiber
      Thread
      Thread::Queue
      Thread::Mutex
      Fiber
      1
      true
      :done
      "s"
      1.5
      [1]
      true
      false
      true
      true
      Thread::Queue
    OUT
  end

  it "fiber class reflection" do
    result = ze0(<<~'RUBY')
      # A Fiber value answers the reflection protocol like any object: #class names
      # it "Fiber", and is_a?/kind_of?/instance_of?, the `===` case operator, and a
      # case/when all resolve against Fiber and its ancestors.
      x = Fiber.new { Fiber.yield 1 }

      p x.class
      p x.class.name
      puts x.class.to_s

      p x.is_a?(Fiber)
      p x.is_a?(Object)
      p x.kind_of?(Fiber)
      p x.instance_of?(Fiber)
      p x.instance_of?(Object)   # instance_of? is exact: false for a superclass

      p(Fiber === x)
      puts(case x when Fiber then "is fiber" else "no" end)

      # Fiber.current is also a Fiber.
      p Fiber.current.is_a?(Fiber)
    RUBY

    _(result).must_answer <<~'OUT'
      Fiber
      "Fiber"
      Fiber
      true
      true
      true
      true
      false
      true
      is fiber
      true
    OUT
  end

  it "fiber transfer root" do
    result = ze0(<<~'RUBY')
      # Fiber#transfer back to the root fiber (Fiber.current obtained in main).
      # Previously segfaulted: the root fiber has no mmap'd stack/body, and
      # transferring to it hit the "first entry" path that ctx_make's a fresh
      # coroutine on the root's NULL stack. The root must be treated as the
      # already-running coroutine and just resumed from its saved context.

      main = Fiber.current

      f = Fiber.new do
        puts "in fiber"
        v = main.transfer(42)
        puts "fiber resumed with #{v.inspect}"
        main.transfer(99)
        puts "never reached"
      end

      r = f.transfer
      puts "back in main: #{r.inspect}"
      r2 = f.transfer(7)            # resume f where it suspended
      puts "back in main again: #{r2.inspect}"

      # Several round trips through root, value passed each way (while loop,
      # no nested block in the fiber body).
      g = Fiber.new do
        acc = 0
        n = 0
        while n < 3
          got = main.transfer(acc)
          acc += got
          n += 1
        end
        main.transfer(acc)
      end

      p g.transfer        # 0
      p g.transfer(10)    # acc=10 -> yields 10
      p g.transfer(5)     # acc=15 -> yields 15
      p g.transfer(100)   # acc=115
    RUBY

    _(result).must_answer <<~'OUT'
      in fiber
      back in main: 42
      fiber resumed with 7
      back in main again: 99
      0
      10
      15
      115
    OUT
  end

  it "a parked fiber's locals survive a collection" do
    result = ze0(<<~'RUBY')
      # A fiber's captured locals must survive a GC that fires while the
      # fiber is parked. The capture struct holds the only reference to
      # these objects; without a scan hook on it the collector frees them
      # and a later resume reads freed memory (use-after-free). Forcing
      # several collections via GC.start while multiple fibers are parked
      # is what surfaces the corruption.
      class Holder
        attr_reader :data
        def initialize(label)
          @data = "holder_payload_" + label
        end
      end

      def churn(n)
        i = 0
        s = ""
        while i < n
          s = s + i.to_s + ","
          i += 1
        end
        s.length
      end

      results = []

      f1 = Fiber.new do
        h1 = Holder.new("one")
        Fiber.yield
        results.push(h1.data)
      end

      f2 = Fiber.new do
        h2 = Holder.new("two")
        Fiber.yield
        results.push(h2.data)
      end

      f3 = Fiber.new do
        h3 = Holder.new("three")
        Fiber.yield
        results.push(h3.data)
      end

      f1.resume
      f2.resume
      f3.resume

      n = 0
      while n < 20
        churn(200)
        GC.start
        n += 1
      end

      f3.resume
      f1.resume
      f2.resume

      puts results.length
      i = 0
      while i < results.length
        puts results[i]
        i += 1
      end
    RUBY

    _(result).must_answer <<~'OUT'
      3
      holder_payload_three
      holder_payload_one
      holder_payload_two
    OUT
  end

  it "shows the frames it is in" do
    result = ze0(<<~'RUBY')
      # `Thread#backtrace`: the frames another thread stands in, innermost
      # first, and nil once the thread has ended. A start past the outermost
      # frame is nil as well, as `caller` answers.
      def inner = sleep
      def outer = inner

      def shown(rows) = rows.map { |row| row.sub(%r{\A.*/}, "").sub(/:\d+/, ":L") }

      t = Thread.new { outer }
      sleep 0.05
      rows = t.backtrace
      p rows.class
      p shown(rows)
      p t.backtrace(1).size == rows.size - 1
      p t.backtrace(0, 2).size
      p t.backtrace(99)

      where = t.backtrace_locations
      p [where.class, where.first.class, where.first.lineno.is_a?(Integer), where.first.label]
      p shown(where.map(&:to_s))

      p Thread.current.backtrace.class
      p Thread.main.backtrace.class

      t.kill
      t.join
      p t.backtrace
      p t.backtrace_locations

    RUBY

    _(result).must_answer <<~'OUT'
      Array
      ["formatting_test.rb:L:in 'Kernel#sleep'", "formatting_test.rb:L:in 'Object#inner'", "formatting_test.rb:L:in 'Object#outer'", "formatting_test.rb:L:in 'block in <main>'"]
      true
      2
      nil
      [Array, Thread::Backtrace::Location, true, "Kernel#sleep"]
      ["formatting_test.rb:L:in 'Kernel#sleep'", "formatting_test.rb:L:in 'Object#inner'", "formatting_test.rb:L:in 'Object#outer'", "formatting_test.rb:L:in 'block in <main>'"]
      Array
      Array
      nil
      nil
    OUT
  end

  it "thread alloc heavy workers" do
    result = ze0(<<~'RUBY')
      threads = []
      t = 0
      while t < 4
        threads << Thread.new(t) do |tid|
          j = tid
          n = 0
          while j < 100_000
            s = "x" + j.to_s
            n += s.length
            j += 4
          end
          n
        end
        t += 1
      end

      total = 0
      threads.each { |th| total += th.value }
      puts total

      # Regression for the multi-worker STW GC crash: a started green thread used to
      # migrate between OS workers (global requeue + work stealing) while its live
      # frames held compiler-cached addresses of the ORIGINAL worker's __thread data,
      # corrupting both workers' GC shadow stacks. Threads are now pinned to their
      # first worker. The harness runs single-worker; the parallel behaviour is
      # exercised by SPINEL_WORKERS>=3 runs of this same program (issue repro).
    RUBY

    _(result).must_answer "588890\n"
  end

  it "thread pass fairness" do
    result = ze0(<<~'RUBY')
      # Thread.pass from the main thread yields a turn to runnable siblings
      # without draining them to completion. On a preemptive parallel scheduler
      # (CRuby, and zeo's OS threads) the interleaving ORDER is nondeterministic,
      # so this asserts only schedule-independent properties: every entry lands,
      # the sibling's own entries stay in its program order, and main is never
      # starved out of completing its loop.
      log = []
      mx = Mutex.new
      t = Thread.new do
        5.times do |i|
          mx.synchronize { log << i }
          Thread.pass
        end
      end
      3.times do
        mx.synchronize { log << :main }
        Thread.pass
      end
      t.join
      puts log.length
      puts log.count(:main)
      puts log.select { |e| e != :main }.inspect

      # A sibling looping on Thread.pass must not starve main: main reaches here
      # and completes its own loop regardless of how turns interleave.
      spinner = Thread.new { 100.times { Thread.pass } }
      main_turns = 0
      4.times do
        main_turns += 1
        Thread.pass
      end
      puts "main_turns: #{main_turns}"
      spinner.join
      puts "done"
    RUBY

    _(result).must_answer <<~'OUT'
      8
      3
      [0, 1, 2, 3, 4]
      main_turns: 4
      done
    OUT
  end

  it "thread preempt" do
    result = ze0(<<~'RUBY')
      # More CPU-bound threads than OS workers, each a bounded loop with no explicit
      # yield: under the parallel build the monitor must timeslice them (otherwise the
      # excess threads starve), and the bound keeps the program correct and
      # terminating under the cooperative single-thread gate build too. The final
      # values are independent of the interleaving, so the output is deterministic.
      ts = 8.times.map { |i| Thread.new { s = 0; 300000.times { s += 1 }; s + i } }
      puts ts.map(&:value).inspect
    RUBY

    _(result).must_answer "[300000, 300001, 300002, 300003, 300004, 300005, 300006, 300007]\n"
  end

  it "toplevel thread is the main thread" do
    result = ze0(<<~'RUBY')
      # The top level runs on the main Ruby thread: `Thread.current` there IS
      # `Thread.main` -- one object, one native id -- and a spawned thread is
      # neither. Pinned because zeo once ran the top level on a spawned OS thread
      # while the process main thread sat in a join; whether that thread is the
      # PROCESS main thread is a platform fact (macOS: yes, AppKit requires it),
      # and tests/macos/ pins that half.

      puts "same object: #{Thread.current.equal?(Thread.main)}"
      puts "one native id: #{Thread.current.native_thread_id == Thread.main.native_thread_id}"
      puts "native id: #{Thread.main.native_thread_id.is_a?(Integer)}"
      puts "status: #{Thread.main.status}"
      worker = Thread.new { [Thread.current.equal?(Thread.main), Thread.current.native_thread_id == Thread.main.native_thread_id] }
      puts "worker: #{worker.value.inspect}"
      puts "from a fiber: #{Fiber.new { Thread.current.equal?(Thread.main) }.resume}"
      at_exit { puts "at_exit: #{Thread.current.equal?(Thread.main)}" }
    RUBY

    _(result).must_answer <<~'OUT'
      same object: true
      one native id: true
      native id: true
      status: run
      worker: [false, false]
      from a fiber: true
      at_exit: true
    OUT
  end
end
