# frozen_string_literal: true

require "spec_helper"

describe "Thread: raising and rescuing" do
  it "begin rescue ensure and retry work inside threads" do
    result = ze0(<<~'RUBY')
      t1 = Thread.new do
        begin
          raise "in thread"
        rescue RuntimeError => e
          "rescued"
        ensure
          x = 1
        end
      end
      puts t1.value
      t2 = Thread.new do
        attempts = 0
        begin
          attempts += 1
          raise "flaky" if attempts < 3
          attempts
        rescue RuntimeError
          retry
        end
      end
      puts t2.value
    RUBY

    _(result).must_answer <<~'OUT'
      rescued
      3
    OUT
  end

  it "blockless thread and fiber raise" do
    result = ze0(<<~'RUBY')
      # A blockless `Thread.new`/`Fiber.new` raises at runtime in real Ruby
      # (thread.c:1034) rather than being a static error, and both are
      # rescuable -- so the program must compile and run.

      def err
        yield
      rescue => e
        "#{e.class}: #{e.message}"
      end
      puts err { Thread.new }
      puts err { Fiber.new }
      t = Thread.new { 7 }
      p t.value
    RUBY

    _(result).must_answer <<~'OUT'
      ThreadError: must be called with a block
      ArgumentError: tried to create Proc object without a block
      7
    OUT
  end

  it "catch in fiber body" do
    result = ze0(<<~'RUBY')
      # catch/throw used inside a fiber body (and a poly-valued catch) must compile.
      r = catch(:done) do
        f = Fiber.new do
          catch(:inner) { Fiber.yield }   # poly block value (Fiber.yield); :inner never thrown
        end
        f.resume
        throw :done, "main-throw"
      end
      puts r
      # poly-typed catch whose throw arm fires with an int
      v = catch(:x) do
        [1].each { |i| throw :x, 99 }
        Fiber.new { Fiber.yield }
        nil
      end
      p v
    RUBY

    _(result).must_answer <<~'OUT'
      main-throw
      99
    OUT
  end

  it "fiber exception boundary" do
    result = ze0(<<~'RUBY')
      # #1474: a fiber's begin/rescue handlers must not leak across the fiber
      # boundary. Each case previously crashed (cross-stack longjmp) or mis-routed.

      # (b) fiber yields inside begin/rescue; resumer then raises with an outer handler
      out = []
      begin
        f = Fiber.new do
          begin
            out << "b:enter"
            Fiber.yield
          rescue => e
            out << "b:fiber-rescue(#{e.message})"
          end
        end
        f.resume
        out << "b:before-raise"
        raise "b-main"
      rescue => e
        out << "b:OUTER(#{e.message})"
      end
      puts out.join(" ")

      # (a) unhandled raise inside a fiber propagates to the resume site
      begin
        g = Fiber.new { raise "a-fiber" }
        g.resume
      rescue => e
        puts "a:caught(#{e.message})"
      end

      # (c) fiber yields mid-rescue; resumer enters its own begin; re-resume; fiber raises
      log = []
      h = Fiber.new do
        begin
          Fiber.yield
          raise "c-x"
        rescue => e
          log << "c:fiber-rescue(#{e.message})"
        end
      end
      h.resume
      begin
        log << "c:main-begin"
      rescue
      end
      h.resume
      puts log.join(" ")
    RUBY

    _(result).must_answer <<~'OUT'
      b:enter b:before-raise b:OUTER(b-main)
      a:caught(a-fiber)
      c:main-begin c:fiber-rescue(c-x)
    OUT
  end

  it "fiber raise" do
    result = ze0(<<~'RUBY')
      # Fiber#raise injects an exception at the fiber's suspension point. The argument
      # forms mirror Kernel#raise. A handled raise lets the fiber continue; an
      # unhandled one propagates to the caller of #raise.

      # Rescued inside the fiber: the suspended Fiber.yield raises, the rescue runs,
      # and the fiber yields again / returns normally.
      f = Fiber.new do
        begin
          Fiber.yield 1
        rescue => e
          Fiber.yield "rescued: #{e.message}"
        end
        :done
      end
      p f.resume            # 1
      p f.raise("boom")     # "rescued: boom"
      p f.resume            # :done

      # (Class, message), unhandled: propagates to the #raise caller; fiber dies.
      g = Fiber.new { Fiber.yield 1 }
      g.resume
      begin
        g.raise(RuntimeError, "up")
      rescue => e
        puts "caught #{e.class}: #{e.message}"
      end
      p g.alive?

      # A class with no message.
      h = Fiber.new { Fiber.yield 1 }
      h.resume
      begin
        h.raise(ArgumentError)
      rescue ArgumentError
        puts "caught ArgumentError"
      end

      # A pre-built exception object.
      i = Fiber.new { Fiber.yield 1 }
      i.resume
      begin
        i.raise(TypeError.new("obj msg"))
      rescue => e
        puts "caught #{e.class}: #{e.message}"
      end

      # raise with no argument -> RuntimeError.
      j = Fiber.new { Fiber.yield 1 }
      j.resume
      begin
        j.raise
      rescue RuntimeError
        puts "caught bare RuntimeError"
      end
    RUBY

    _(result).must_answer <<~'OUT'
      1
      "rescued: boom"
      :done
      caught RuntimeError: up
      false
      caught ArgumentError
      caught TypeError: obj msg
      caught bare RuntimeError
    OUT
  end

  it "kernel catch throw sleep via dynamic dispatch" do
    result = ze0(<<~'RUBY')
      # `send`/`&:` force dynamic dispatch through the Kernel table rather than
      # the static codegen fast path.

      p send(:catch, :done) { throw :done, 42 }
      p [1, 2, 3].map { |x| catch(:skip) { throw :skip, -1 if x == 2; x } }
      send(:sleep, 0)
      puts "slept"
    RUBY

    _(result).must_answer <<~'OUT'
      42
      [1, -1, 3]
      slept
    OUT
  end

  it "main thread is a raise target" do
    result = ze0(<<~'RUBY')
      # A sibling raising into MAIN: delivered at main's next checkpoint --
      # here, waking its sleep -- and rescuable like any other raise.

      main = Thread.main
      t = Thread.new { sleep 0.05; main.raise("to-main") }
      begin
        sleep 5
        puts "overslept"
      rescue => e
        puts "main caught: #{e.message}"
      end
      t.join
    RUBY

    _(result).must_answer "main caught: to-main\n"
  end

  it "mutex error semantics match cruby" do
    result = ze0(<<~'RUBY')
      mu = Mutex.new
      begin
        mu.unlock
      rescue ThreadError => e
        puts e.send(:message)
      end
      mu.lock
      puts mu.locked?
      puts mu.owned?
      begin
        mu.lock
      rescue ThreadError => e
        puts e.send(:message)
      end
      mu.unlock
      puts mu.locked?
    RUBY

    _(result).must_answer <<~'OUT'
      Attempt to unlock a mutex which is not locked
      true
      true
      deadlock; recursive locking
      false
    OUT
  end

  it "mutex synchronize ensure" do
    result = ze0(<<~'RUBY')
      # Mutex#synchronize releases the lock with ensure semantics: on normal exit, on
      # an exception raised in the block (re-raised to the caller), on a `return` out
      # of the block, and on a non-local unwind (throw) passing through it.
      m = Mutex.new

      # normal completion: the block's value is returned, lock released
      puts m.synchronize { 1 + 2 }
      puts m.locked?

      # exception in the block: re-raised, lock released
      begin
        m.synchronize { raise "boom" }
      rescue => e
        puts "rescued: #{e.message}"
      end
      puts m.locked?

      # throw unwinding through synchronize: lock released
      res = catch(:done) { m.synchronize { throw :done, 42 } }
      puts "caught: #{res}"
      puts m.locked?

      # return out of the block: lock released, value returned from the method
      def grab(mx)
        mx.synchronize { return 99 }
      end
      puts grab(m)
      puts m.locked?

      # nested synchronize on two mutexes
      a = Mutex.new
      b = Mutex.new
      a.synchronize { b.synchronize { puts "nested ok" } }
      puts a.locked?
      puts b.locked?
    RUBY

    _(result).must_answer <<~'OUT'
      3
      false
      rescued: boom
      false
      caught: 42
      false
      99
      false
      nested ok
      false
      false
    OUT
  end

  it "negative sleep is an argument error" do
    result = ze0(<<~'RUBY')
      # `sleep(-1)` raises ArgumentError "time interval must not be negative";
      # zeo raises TypeError with a conversion message. (Found by the 2026-08-24
      # probe sweep.)
      begin
        sleep(-1)
      rescue StandardError => e
        puts "#{e.class}: #{e.message}"
      end
    RUBY

    _(result).must_answer "ArgumentError: time interval must not be negative\n"
  end

  it "no method error propagates out of fibers and ractors" do
    result = ze0(<<~'RUBY')
      class Bare; end
      f = Fiber.new { Bare.new.send(:nope) }
      begin
        f.resume
      rescue NoMethodError
        puts "rescued in resumer"
      end
      puts f.alive?
      r = Ractor.new { Bare.new.send(:nope) }
      begin
        r.value
      rescue Ractor::RemoteError => e
        puts "rescued at value: #{e.cause.class}"
      end
    RUBY

    _(result).must_answer <<~'OUT', stderr: "core/thread/exceptions_test.rb:9: warning: Ractor API is experimental and may change in future versions of Ruby.\n#<Thread:0xADDR run> terminated with exception (report_on_exception is true):\ncore/thread/exceptions_test.rb:9:in 'block in <main>': undefined method 'nope' for an instance of Bare (NoMethodError)\n\nr = Ractor.new { Bare.new.send(:nope) }\n                         ^^^^^\n"
      rescued in resumer
      false
      rescued at value: NoMethodError
    OUT
  end

  it "push to a closed queue raises closed queue error" do
    result = ze0(<<~'RUBY')
      qq = Queue.new
      qq.close
      puts qq.closed?
      begin
        qq.push 1
      rescue ClosedQueueError => e
        puts e.send(:message)
      end
    RUBY

    _(result).must_answer <<~'OUT'
      true
      queue closed
    OUT
  end

  it "queue argument validation" do
    result = ze0(<<~'RUBY')
      # Queue-family argument surfaces: `Queue#pop(true)` takes the non_block
      # flag and raises ThreadError ("queue empty") on an empty queue; zeo's row
      # takes no arguments at all. `SizedQueue.new(0)` raises ArgumentError
      # ("queue size must be positive"); zeo mints the queue. (Found by the
      # 2026-08-24 probe sweep.)
      begin
        Queue.new.pop(true)
      rescue ThreadError => e
        puts "#{e.class}: #{e.message}"
      end
      begin
        SizedQueue.new(0)
        puts "sized queue minted"
      rescue ArgumentError => e
        puts e.message
      end
    RUBY

    _(result).must_answer <<~'OUT'
      ThreadError: queue empty
      queue size must be positive
    OUT
  end

  it "ractor reports its uncaught exception" do
    result = ze0(<<~'RUBY')
      # A ractor that dies of an uncaught exception REPORTS it on stderr as it
      # terminates, and `#value` raising `Ractor::RemoteError` is a separate
      # mechanism -- a program sees both.
      #
      # CRuby runs a ractor's body on a thread, so what it prints is that thread's
      # own banner followed by the ordinary uncaught report. zeo printed nothing:
      # `ractor::finish` recorded the outcome and no one reported it, so a ractor
      # that died without anyone calling `#value` failed silently. The banner
      # carries no origin where `Thread#inspect`'s does, because a ractor's thread
      # was not created by `Thread.new` and has no call site to name.
      #
      # `Thread.report_on_exception` governs it, as it governs a thread's. The
      # address in the banner is process-random on both sides and the harness
      # normalizes it.
      Warning[:experimental] = false

      r = Ractor.new { raise "boom" }
      begin
        r.value
      rescue Ractor::RemoteError => e
        puts "value raised #{e.class}: #{e.cause.class}"
      end

      Thread.report_on_exception = false
      quiet = Ractor.new { raise ArgumentError, "hushed" }
      begin
        quiet.value
      rescue Ractor::RemoteError => e
        puts "quiet raised #{e.class}: #{e.cause.message}"
      end
      Thread.report_on_exception = true

      # One that nobody ever asks about still reports.
      Ractor.new { raise NotImplementedError, "unattended" }
      sleep 0.2
      puts "done"
    RUBY

    _(result).must_answer <<~'OUT', stderr: "#<Thread:0xADDR run> terminated with exception (report_on_exception is true):\ncore/thread/exceptions_test.rb:17:in 'block in <main>': boom (RuntimeError)\n#<Thread:0xADDR run> terminated with exception (report_on_exception is true):\ncore/thread/exceptions_test.rb:34:in 'block in <main>': unattended (NotImplementedError)\n"
      value raised Ractor::RemoteError: RuntimeError
      quiet raised Ractor::RemoteError: hushed
      done
    OUT
  end

  it "raise inside a fiber backtraces only the fibers own frames" do
    result = ze0(<<~'RUBY')
      # The ec-swap's frame slice, oracle-verified: the fiber starts on a
      # FRESH backtrace stack, so a raise through a method inside it sees
      # exactly [the method, the fiber block] -- none of main's frames --
      # and `caller` at the block top is empty.

      def deep_raise
        raise "boom"
      end
      f = Fiber.new do
        begin
          deep_raise
        rescue => e
          e.backtrace.length
        end
      end
      p f.resume
      f2 = Fiber.new { caller.length }
      p f2.resume
    RUBY

    _(result).must_answer <<~'OUT'
      2
      0
    OUT
  end

  it "raise into sleep wakes the sleeper immediately" do
    result = ze0(<<~'RUBY')
      # The timeout-gem shape: a thread parked in a LONG sleep is raisable
      # and wakes now, not at the sleep's natural end. Threshold-based (well
      # under the 10s the sleep would otherwise take), never order-based.

      Thread.report_on_exception = false
      start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      t = Thread.new do
        begin
          sleep 10
          :overslept
        rescue => e
          e.message
        end
      end
      sleep 0.05
      t.raise("wake up")
      v = t.value
      elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start
      p v
      p elapsed < 5
    RUBY

    _(result).must_answer <<~'OUT'
      "wake up"
      true
    OUT
  end

  it "rescue bind in fiber body" do
    result = ze0(<<~'RUBY')
      # `rescue => e` inside a Fiber body binds the exception local in the
      # fiber body's own function. Regression: the binding was attributed to
      # the enclosing scope, so `_fiber_body_N` referenced an undeclared lv_e.
      fib = Fiber.new do
        begin
          raise "fib boom"
        rescue => fe
          Fiber.yield "fib: #{fe.message}"
        end
        "fib done"
      end
      puts fib.resume
      puts fib.resume

      # Distinct names bound by two rescues within one fiber body.
      g = Fiber.new do
        begin; raise "one"; rescue => e1; Fiber.yield "a: #{e1.message}"; end
        begin; raise "two"; rescue => e2; Fiber.yield "b: #{e2.message}"; end
        "g done"
      end
      puts g.resume
      puts g.resume
      puts g.resume
      puts "after"
    RUBY

    _(result).must_answer <<~'OUT'
      fib: fib boom
      fib done
      a: one
      b: two
      g done
      after
    OUT
  end

  it "retired scheduler knobs are silently ignored" do
    result = ze0(<<~'RUBY', argv: ["--no-gvl"], env: {"ZEO_THREADS" => "not-a-number"})
      # `ZEO_THREADS`/`--no-gvl` configure nothing -- threads are always real OS
      # threads. A value, even a malformed one, is silently ignored rather than a
      # startup error, so existing scripts keep running.



      puts 1
    RUBY

    _(result).must_answer "1\n"
  end

  it "thread ensure inside block" do
    result = ze0(<<~'RUBY')
      t = [0].map do |w|
        Thread.new do
          w.to_s
        ensure
          nil
        end
      end
      p t.map(&:value)

      u = [1, 2].map do |w|
        Thread.new do
          begin
            w * 2
          ensure
            nil
          end
        end
      end
      p u.map(&:value)

      v = Thread.new do
        1.to_s
      ensure
        nil
      end
      p v.value

      f = [3].map do |w|
        Fiber.new do
          Fiber.yield w
        ensure
          nil
        end
      end
      p f.map(&:resume)

      r = [4].map do |w|
        Thread.new do
          begin
            w
          rescue StandardError
            nil
          end
        end
      end
      p r.map(&:value)
    RUBY

    _(result).must_answer <<~'OUT'
      ["0"]
      [2, 4]
      "1"
      [3]
      [4]
    OUT
  end

  it "thread raise main" do
    result = ze0(<<~'RUBY')
      # Thread#raise aimed at the MAIN thread from a sibling: the main thread is
      # a first-class interrupt target (delivered at its next interruption
      # checkpoint), and the rescue swallows it exactly as under CRuby. The
      # output pins "ok" either way -- delivery timing may land the raise inside
      # the begin (rescued) or leave it pending past program end -- so the test
      # asserts "delivers-or-ignores without crashing", not the exact timing.
      Thread.report_on_exception = false
      begin
        t = Thread.new { Thread.main.raise("to-main") }
        t.join
        sleep 0.2
      rescue => e
        # CRuby lands here; spinel's no-op never raises.
      end
      puts "ok"
    RUBY

    _(result).must_answer "ok\n"
  end

  it "thread raise on current is synchronous" do
    result = ze0(<<~'RUBY')
      # `Thread#raise` on the CURRENT thread raises synchronously -- the rescue
      # around the call catches it. zeo defers it like a cross-thread interrupt,
      # so the rescue misses and the exception escapes afterwards. (Found by the
      # 2026-08-24 probe sweep.)
      begin
        Thread.current.raise(ArgumentError, "self-raise")
        puts "not reached"
      rescue ArgumentError => e
        puts "caught #{e.message}"
      end
      puts "after"
    RUBY

    _(result).must_answer <<~'OUT'
      caught self-raise
      after
    OUT
  end

  it "thread report on exception" do
    result = ze0(<<~'RUBY')
      # A thread that dies of an uncaught exception says so on stderr as it
      # terminates, naming itself. That report and the re-raise at `#join` are
      # SEPARATE mechanisms -- a program can see both, or silence the report and
      # still get the re-raise. See the sidecar golden for what reaches stderr.

      # --- reported, AND re-raised at join -----------------------------------------
      loud = Thread.new { raise "reported" }
      begin
        loud.join
      rescue RuntimeError => e
        puts "joined: #{e.message}"
      end

      # --- silenced per thread: the re-raise survives ------------------------------
      # The thread waits for a go-ahead, so the flag is definitely set before it
      # can raise -- setting it on an already-running thread is a race.
      gate = Queue.new
      quiet = Thread.new do
        gate.pop
        raise "silent"
      end
      quiet.report_on_exception = false
      gate.push(:go)
      begin
        quiet.value
      rescue RuntimeError => e
        puts "joined: #{e.message}"
      end
      p quiet.report_on_exception

      # --- the class-level default seeds threads spawned AFTER it ------------------
      p Thread.report_on_exception
      Thread.report_on_exception = false
      p Thread.report_on_exception
      born_quiet = Thread.new { raise "inherited silence" }
      p born_quiet.report_on_exception
      begin
        born_quiet.join
      rescue RuntimeError => e
        puts "joined: #{e.message}"
      end

      # Back on, and a fresh thread is loud again.
      Thread.report_on_exception = true
      loud_again = Thread.new { raise "loud again" }
      begin
        loud_again.join
      rescue RuntimeError => e
        puts "joined: #{e.message}"
      end

      # --- a killed thread reports nothing: it dies silently by design -------------
      # It parks on an empty Queue, the deterministic point a pending kill lands.
      Thread.report_on_exception = true
      idle = Queue.new
      killed = Thread.new { idle.pop }
      killed.kill
      p killed.join.equal?(killed)
      p killed.value

      # --- a thread that finishes normally reports nothing -------------------------
      Thread.report_on_exception = true
      p Thread.new { 1 + 1 }.value

      puts "done"
    RUBY

    _(result).must_answer <<~'OUT', stderr: "#<Thread:0xADDR core/thread/exceptions_test.rb:7 run> terminated with exception (report_on_exception is true):\ncore/thread/exceptions_test.rb:7:in 'block in <main>': reported (RuntimeError)\n#<Thread:0xADDR core/thread/exceptions_test.rb:45 run> terminated with exception (report_on_exception is true):\ncore/thread/exceptions_test.rb:45:in 'block in <main>': loud again (RuntimeError)\n"
      joined: reported
      joined: silent
      false
      true
      false
      false
      joined: inherited silence
      joined: loud again
      true
      nil
      2
      done
    OUT
  end

  it "uncaught exception in a ractor wraps in remote error at value" do
    result = ze0(<<~'RUBY')
      # The port model relays the failure as CRuby does: a
      # `Ractor::RemoteError` whose `#cause` is the original exception.

      bad = Ractor.new do
        raise "ractor boom"
      end
      begin
        bad.value
      rescue Ractor::RemoteError => e
        puts "rescued: #{e.send(:message)} / #{e.cause.class} / #{e.cause.send(:message)}"
      end
    RUBY

    _(result).must_answer <<~'OUT', stderr: "core/thread/exceptions_test.rb:4: warning: Ractor API is experimental and may change in future versions of Ruby.\n#<Thread:0xADDR run> terminated with exception (report_on_exception is true):\ncore/thread/exceptions_test.rb:5:in 'block in <main>': ractor boom (RuntimeError)\n"
      rescued: thrown by remote Ractor. / RuntimeError / ractor boom
    OUT
  end

  it "uncaught exception in a thread reraises at join and value" do
    result = ze0(<<~'RUBY')
      # CRuby stores the exception and re-raises it in whoever joins
      # (`thread.c:1195`). The no-join report_on_exception stderr warning is
      # a documented skip.

      bad = Thread.new { raise "thread boom" }
      begin
        bad.join
      rescue RuntimeError => e
        puts "joined error: #{e.send(:message)}"
      end
      bad2 = Thread.new { raise "thread boom2" }
      begin
        bad2.value
      rescue RuntimeError => e
        puts "valued error: #{e.send(:message)}"
      end
    RUBY

    _(result).must_answer <<~'OUT', stderr: "#<Thread:0xADDR core/thread/exceptions_test.rb:5 run> terminated with exception (report_on_exception is true):\ncore/thread/exceptions_test.rb:5:in 'block in <main>': thread boom (RuntimeError)\n#<Thread:0xADDR core/thread/exceptions_test.rb:11 run> terminated with exception (report_on_exception is true):\ncore/thread/exceptions_test.rb:11:in 'block in <main>': thread boom2 (RuntimeError)\n"
      joined error: thread boom
      valued error: thread boom2
    OUT
  end
end
