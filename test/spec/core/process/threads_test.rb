# frozen_string_literal: true

require "spec_helper"

describe "Process: threads, fibers and ractors" do
  it "fiber current storage kill and raise" do
    result = zr(<<~'RUBY')
      p Fiber.current.equal?(Fiber.current)
      Fiber[:level] = "outer"
      seen = []
      f = Fiber.new do
        seen << Fiber[:level]
        Fiber[:level] = "inner"
        seen << Fiber[:level]
        Fiber.yield
      end
      f.resume
      p seen
      p Fiber[:level]
      p Fiber.current.storage
      other = Fiber.new { Fiber.yield }
      other.resume
      begin
        other.storage
      rescue ArgumentError => e
        puts e.message
      end
      k = Fiber.new { Fiber.yield 1; Fiber.yield 2 }
      p k.resume
      p k.kill.equal?(k)
      p k.alive?
      r = Fiber.new do
        begin
          Fiber.yield "one"
        rescue => e
          Fiber.yield "rescued: #{e.message}"
        end
      end
      p r.resume
      p r.raise("boom")
    RUBY

    _(result).must_answer <<~'OUT'
      true
      ["outer", "inner"]
      "outer"
      {level: "outer"}
      Fiber storage can only be accessed from the Fiber it belongs to
      1
      true
      false
      "one"
      "rescued: boom"
    OUT
  end

  it "fiber kill" do
    result = zr(<<~'RUBY')
      # Fiber#kill terminates a fiber, running its ensure blocks. The kill signal
      # unwinds through ensure clauses but is NOT caught by user rescue clauses, and
      # the fiber does not resume past the kill point.

      # Suspended fiber: ensure runs, the fiber is left dead, kill returns the fiber.
      h = Fiber.new do
        begin
          Fiber.yield 1
          Fiber.yield 2
        ensure
          puts "h ensure ran"
        end
      end
      h.resume
      p h.kill.is_a?(Fiber)   # kill returns the fiber
      p h.alive?              # now terminated

      # kill is idempotent: a dead fiber stays dead.
      h.kill
      p h.alive?

      # A bare rescue does NOT swallow the kill; only the ensure runs, and execution
      # does not continue past the kill point.
      r = Fiber.new do
        begin
          Fiber.yield 1
          Fiber.yield 2
        rescue => e
          puts "SHOULD NOT RESCUE: #{e.class}"
        ensure
          puts "r ensure ran"
        end
        puts "SHOULD NOT REACH"
      end
      r.resume
      r.kill
      p r.alive?

      # kill on an unstarted fiber: the body never runs.
      u = Fiber.new { puts "SHOULD NOT RUN" }
      u.kill
      p u.alive?

      # The kill handling must not disturb ordinary rescue in a fiber body.
      n = Fiber.new do
        begin
          raise "normal"
        rescue => e
          Fiber.yield "rescued #{e.message}"
        end
      end
      p n.resume
    RUBY

    _(result).must_answer <<~'OUT'
      h ensure ran
      true
      false
      false
      r ensure ran
      false
      false
      "rescued normal"
    OUT
  end

  it "fiber transfer and kill" do
    result = zr(<<~'RUBY')
      # Fiber#transfer round-tripping through the root fiber, Fiber#[]/#[]= storage,
      # the FiberError guards, and Fiber#kill running ensure blocks.
      main = Fiber.current

      f = Fiber.new do
        acc = 0
        n = 0
        while n < 3
          got = main.transfer(acc)
          acc += got
          n += 1
        end
        main.transfer(acc)
      end
      p f.transfer        # 0
      p f.transfer(10)    # 10
      p f.transfer(5)     # 15
      p f.transfer(100)   # 115

      # Inheritable fiber-local storage.
      Fiber[:tag] = :outer
      g = Fiber.new { Fiber[:tag] }
      p g.resume          # :outer

      # A fiber entered via #transfer has no resumer, so Fiber.yield raises.
      begin
        ft = Fiber.new { |x| Fiber.yield x }
        ft.transfer(1)
      rescue FiberError => e
        puts "transfer-yield: #{e.message}"
      end

      # Resuming a fiber still running below us is a double resume.
      $f1 = nil
      $f2 = nil
      $f1 = Fiber.new { $f2.resume }
      $f2 = Fiber.new { $f1.resume }
      begin
        $f1.resume
      rescue FiberError => e
        puts "double-resume: #{e.message}"
      end

      # #kill runs ensure, is not caught by a bare rescue, and leaves the fiber dead.
      h = Fiber.new do
        begin
          Fiber.yield 1
          Fiber.yield 2
        rescue => e
          puts "SHOULD NOT RESCUE"
        ensure
          puts "ensure ran"
        end
      end
      h.resume
      p h.kill.is_a?(Fiber)
      p h.alive?
      puts "done"
    RUBY

    _(result).must_answer <<~'OUT'
      0
      10
      15
      115
      :outer
      transfer-yield: attempt to yield on a not resumed fiber
      double-resume: attempt to resume a resumed fiber (double resume)
      ensure ran
      true
      false
      done
    OUT
  end

  it "one threads bad dispatch no longer kills the other threads" do
    result = zr(<<~'RUBY')
      # A failing thread surfaces its error at its OWN join; the healthy worker
      # completes normally, unaffected.

      class Plain
      end
      worker = Thread.new { 21 * 2 }
      bad = Thread.new { Plain.new.send(:missing_in_thread) }
      begin
        bad.join
      rescue NoMethodError => e
        puts "joined the failure"
      end
      puts worker.value
    RUBY

    _(result).must_answer <<~'OUT', stderr: <<~'ERR'
      joined the failure
      42
    OUT
      #<Thread:0xADDR core/process/threads_test.rb:7 run> terminated with exception (report_on_exception is true):
      core/process/threads_test.rb:7:in 'block in <main>': undefined method 'missing_in_thread' for an instance of Plain (NoMethodError)

      bad = Thread.new { Plain.new.send(:missing_in_thread) }
                                  ^^^^^
    ERR
  end

  it "thread kill raise" do
    result = zr(<<~'RUBY')
      # Thread#kill terminates a thread, running its ensure blocks; Thread#raise
      # injects an exception caught by the thread's rescue. A thread is blocked on a
      # Queue so the delivery point is deterministic (Thread.pass runs it to the
      # blocking #pop). CRuby's Thread.pass is only a hint, so this asserts the
      # documented semantics rather than a per-run interleaving.
      Thread.report_on_exception = false

      # #kill runs the ensure of a blocked thread
      q = Queue.new
      log = []
      t = Thread.new do
        begin
          log << :started
          q.pop
          log << :unreached
        ensure
          log << :ensure_ran
        end
      end
      Thread.pass
      t.kill
      t.join
      p log                  # [:started, :ensure_ran]
      p t.alive?             # false

      # #raise injects an exception the thread rescues
      q2 = Queue.new
      r = Thread.new do
        begin
          q2.pop
          "no"
        rescue => e
          "caught: #{e.message}"
        end
      end
      Thread.pass
      r.raise("boom")
      p r.value              # "caught: boom"

      # killing a never-run thread just marks it dead (no body, no ensure)
      u = Thread.new { q.pop }
      u.kill
      u.join
      p u.alive?             # false

      # #kill returns the thread; #exit / #terminate are aliases
      v = Thread.new { q.pop }
      p v.kill.equal?(v)     # true
      v.join
    RUBY

    _(result).must_answer <<~'OUT'
      [:started, :ensure_ran]
      false
      "caught: boom"
      false
      true
    OUT
  end

  it "thread list kill raise" do
    result = zr(<<~'RUBY')
      # Thread.list (the live-thread registry) and Thread#kill/#raise.
      Thread.report_on_exception = false

      p Thread.list.size                       # 1 (just main)
      p Thread.list.include?(Thread.current)   # true
      # The three are HELD blocked while they are counted. A thread that has run to
      # the end leaves the registry whether or not anyone joined it, so counting
      # racing threads would count luck.
      gate = Queue.new
      threads = (1..3).map { Thread.new { gate.pop } }
      sleep 0.005 until threads.all? { |t| t.status == "sleep" }
      p Thread.list.size                       # 4 (main + 3 blocked)
      3.times { gate << :go }
      threads.each(&:join)
      p Thread.list.size                       # 1 (spawns finished)
      p Thread.list.include?(Thread.main)      # true

      # #kill runs the ensure of a thread blocked on an empty Queue.
      q = Queue.new
      log = []
      t = Thread.new do
        begin
          log << :started
          q.pop
          log << :unreached
        ensure
          log << :ensure_ran
        end
      end
      Thread.pass
      t.kill
      t.join
      p log                                    # [:started, :ensure_ran]
      p t.alive?                               # false

      # #raise injects an exception the thread rescues.
      q2 = Queue.new
      r = Thread.new do
        begin
          q2.pop
          "no"
        rescue => e
          "caught: #{e.message}"
        end
      end
      Thread.pass
      r.raise("boom")
      p r.value                                # "caught: boom"

      # #kill returns the thread; #exit / #terminate are aliases.
      v = Thread.new { q.pop }
      p v.kill.equal?(v)                       # true
      v.join
      puts "done"
    RUBY

    _(result).must_answer <<~'OUT'
      1
      true
      4
      1
      true
      [:started, :ensure_ran]
      false
      "caught: boom"
      true
      done
    OUT
  end

  it "thread registry and kill raise" do
    result = zr(<<~'RUBY')
      # Thread.list (main plus live spawns, joined ones pruned) and
      # Thread.list.include? by identity; Thread#kill unwinding a blocked thread
      # through its ensure; Thread#raise injecting a rescuable exception; #kill
      # returning the thread; #exit/#terminate aliases.

      Thread.report_on_exception = false
      p Thread.list.size
      p Thread.list.include?(Thread.current)
      # The three are held blocked while they are counted: a thread that
      # has already run to the end leaves `Thread.list` whether or not
      # anyone joined it, so counting racing threads counts luck.
      gate = Queue.new
      ts = (1..3).map { Thread.new { gate.pop } }
      sleep 0.005 until ts.all? { |t| t.status == "sleep" }
      p Thread.list.size
      3.times { gate << :go }
      ts.each(&:join)
      p Thread.list.size

      q = Queue.new
      ready = Queue.new
      log = []
      t = Thread.new do
        begin
          log << :started
          ready << :ok
          q.pop
          log << :unreached
        ensure
          log << :ensure_ran
        end
      end
      ready.pop
      t.kill
      t.join
      p log
      p t.alive?

      q2 = Queue.new
      r = Thread.new do
        begin
          ready << :ok
          q2.pop
          "no"
        rescue => e
          "caught: #{e.message}"
        end
      end
      ready.pop
      r.raise("boom")
      p r.value

      v = Thread.new { q.pop }
      p v.kill.equal?(v)
      v.join
    RUBY

    _(result).must_answer <<~'OUT'
      1
      true
      4
      1
      [:started, :ensure_ran]
      false
      "caught: boom"
      true
    OUT
  end

  it "thread stop status" do
    result = zr(<<~'RUBY')
      t = Thread.new { Thread.stop }
      sleep 0.1
      p t.status
      t.run
      t.kill
      t.join
      p t.status
    RUBY

    _(result).must_answer <<~'OUT'
      "sleep"
      false
    OUT
  end

  it "waiting for a child lets other threads run" do
    result = zr(<<~'RUBY')
      # A thread that waits for a child parks on the pipe SIGCHLD writes to,
      # so its siblings run while the child does: Process.wait, detach, and a
      # read on a pipe each let a sleeping thread tick.
      ticks = 0
      t = Thread.new { 30.times { sleep 0.01; ticks += 1 } }
      pid = spawn("sleep 0.25")
      Process.wait(pid)
      p ticks >= 10
      t.join
      pid = spawn("sleep 0.2")
      w = Process.detach(pid)
      n = 0
      until w.join(0.01)
        n += 1
      end
      p n >= 5, w.value.success?
      r, wr = IO.pipe
      reader = Thread.new { r.gets }
      ticks2 = 0
      Thread.new { 5.times { sleep 0.01; ticks2 += 1 }; wr.puts "done" }
      p reader.value, ticks2

    RUBY

    _(result).must_answer <<~'OUT'
      true
      true
      true
      "done\n"
      5
    OUT
  end
end
