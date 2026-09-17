# frozen_string_literal: true

require "spec_helper"

describe "Thread programs" do
  it "armed gvl holder blocked in fifo open does not stall its siblings" do
    _(ze0(<<~'RUBY', env: {"ZEO_GVL" => "1"})).must_answer "\"through the fifo\\n\"\n"
      # File.open's open(2) ITSELF blocks on a FIFO until the other end
      # shows up -- the reason the release wraps the open, not just reads.
      # Without it the reader parks inside the armed Gvl and main can never
      # open the write end: a deadlock, and this test hangs.


      fifo = File.join(ENV["TMPDIR"] || "/tmp", "zeo_fifo_probe_#{Process.pid}")
      system("mkfifo", fifo)
      reader = Thread.new { File.open(fifo, "r") { |f| f.gets } }
      sleep 0.2
      File.open(fifo, "w") { |f| f.puts "through the fifo" }
      p reader.value
      File.delete(fifo)
    RUBY
  end

  it "armed read family parks per call without stalling the writer" do
    result = ze0(<<~'RUBY', env: {"ZEO_GVL" => "1"})
      # The with_file seam beyond gets: readline and a LENGTHED read(n)
      # each park on the pipe in their own Gvl-released section, with main
      # feeding the pipe in stages between sleeps -- two consecutive
      # blocking reads on one fd, each of which must release.


      r, w = IO.pipe
      consumer = Thread.new do
        first = r.readline
        rest = r.read(4)
        [first, rest]
      end
      sleep 0.2
      w.puts "line"
      sleep 0.1
      w.write "tail"
      first, rest = consumer.value
      p first
      p rest
      r.close
      w.close
    RUBY

    _(result).must_answer <<~'OUT'
      "line\n"
      "tail"
    OUT
  end

  it "bundle misc c 09" do
    result = ze0(<<~'RUBY', path: "core/thread/bundle_misc_c_09.rb")
      # Bundled tests:
      #   - fiber_storage_basic
      #   - fiber_storage_current_alias
      #   - fiber_storage_gc_root

      # === fiber_storage_basic ===
      def t_fiber_storage_basic
        Fiber[:user_id] = 42
        puts Fiber[:user_id]
        
        Fiber[:user_id] = 43
        puts Fiber[:user_id]
        
        # Unset key reads as nil.
        v = Fiber[:not_set]
        if v.nil?
          puts "nil_ok"
        else
          puts "nil_unexpected"
        end
      end
      t_fiber_storage_basic

      # === fiber_storage_current_alias ===
      def t_fiber_storage_current_alias
        # `Fiber.current[:k]` and `Fiber.current[:k] = v` are aliases for
        # `Fiber[:k]` and `Fiber[:k] = v` — both target the same storage Hash
        # on the currently-running fiber.
        
        Fiber.current[:via_current] = 100
        puts Fiber[:via_current]                       # 100 — reads via Fiber[]
        
        Fiber[:via_bare] = 200
        puts Fiber.current[:via_bare]                  # 200 — reads via Fiber.current[]
      end
      t_fiber_storage_current_alias

      # === fiber_storage_gc_root ===
      def t_fiber_storage_gc_root
        # Regression: sp_fiber_root.storage must survive GC. sp_fiber_root
        # is a static (not sp_gc_alloc'd) so its scan never runs via the
        # heap walker. Without explicit marking in sp_re_mark_globals, the
        # SymPolyHash allocated by `Fiber[:k] = v` at top level gets
        # prematurely collected on the next cycle.
        #
        # Force GC by allocating many sp_gc_alloc'd objects (arrays of
        # strings, each becoming garbage on the next iteration) to push
        # sp_gc_bytes past the 256KB threshold. Then verify the storage
        # value still reads back.
        
        Fiber[:answer] = 42
        
        i = 0
        while i < 10000
          # Each iteration allocates a fresh PolyArray + a String element;
          # both are GC-tracked (sp_gc_alloc), so this drives sp_gc_bytes
          # past the auto-collect threshold within the loop.
          garbage = ["garbage_" + i.to_s, "more_" + i.to_s, "still_" + i.to_s]
          i = i + 1
        end
        
        # If sp_fiber_root.storage wasn't marked, the SymPolyHash holding
        # :answer would have been freed and read would return nil.
        v = Fiber[:answer]
        if v == 42
          puts "survived"
        else
          puts "lost"
        end
      end
      t_fiber_storage_gc_root

    RUBY

    _(result).must_answer <<~'OUT', stderr: "core/thread/bundle_misc_c_09.rb:30:in 'Object#t_fiber_storage_current_alias': undefined method '[]=' for an instance of Fiber (NoMethodError)\n\n  Fiber.current[:via_current] = 100\n               ^^^^^^^^^^^^^^^^\n\tfrom core/thread/bundle_misc_c_09.rb:36:in '<main>'\n", status: 1
      42
      43
      nil_ok
    OUT
  end

  it "bundle misc c 10" do
    result = ze0(<<~'RUBY')
      # Bundled tests:
      #   - fiber_storage_inherits
      #   - fiber_storage_persists
      #   - fiber_storage_siblings

      # === fiber_storage_inherits ===
      def t_fiber_storage_inherits
        # Parent fiber's storage is snapshot-copied into a child fiber at
        # Fiber.new time. Subsequent writes on either side are independent
        # (shallow copy).
        Fiber[:user] = "alice"
        
        f = Fiber.new do
          # Inherited at creation.
          puts Fiber[:user]
          # Local write — does not leak back to parent.
          Fiber[:user] = "bob"
          puts Fiber[:user]
        end
        f.resume
        
        # Parent's value is unchanged by the child's write.
        puts Fiber[:user]
      end
      t_fiber_storage_inherits

      # === fiber_storage_persists ===
      def t_fiber_storage_persists
        # Storage values persist across yield/resume cycles within the same
        # fiber. Mirrors the existing fiber_ivar_persists_across_yield test
        # but exercises the storage path instead of ivars.
        f = Fiber.new do
          Fiber[:n] = 1
          Fiber.yield
          # After resume, the previous storage write is still visible.
          Fiber[:n] = Fiber[:n] + 1
          Fiber.yield
          Fiber[:n] = Fiber[:n] + 1
          puts Fiber[:n]
        end
        
        f.resume   # sets :n = 1
        f.resume   # bumps to 2, yields
        f.resume   # bumps to 3, prints 3
      end
      t_fiber_storage_persists

      # === fiber_storage_siblings ===
      def t_fiber_storage_siblings
        # Sibling fibers have independent storage. A write in one does not
        # affect the other even if they share a parent.
        Fiber[:tag] = "parent"
        
        a = Fiber.new do
          Fiber[:tag] = "a"
          puts Fiber[:tag]
        end
        
        b = Fiber.new do
          # b was created BEFORE a ran, so it inherited "parent", not "a".
          puts Fiber[:tag]
          Fiber[:tag] = "b"
          puts Fiber[:tag]
        end
        
        a.resume
        b.resume
        
        # Parent's storage still reads "parent" — neither child leaked back.
        puts Fiber[:tag]
      end
      t_fiber_storage_siblings

    RUBY

    _(result).must_answer <<~'OUT'
      alice
      bob
      alice
      3
      a
      parent
      b
      parent
    OUT
  end

  it "clearing a sized queue wakes its pushers" do
    result = ze0(<<~'RUBY')
      # SizedQueue#clear empties the queue and wakes every thread waiting to
      # push, as rb_szqueue_clear does.

      q = SizedQueue.new(1)
      q << 1
      pusher = Thread.new { q << 2; :pushed }
      Thread.pass until pusher.status == "sleep"
      q.clear
      p pusher.value, q.size, q.pop
      p Thread::SizedQueue.instance_method(:clear).owner

    RUBY

    _(result).must_answer <<~'OUT'
      :pushed
      1
      2
      Thread::SizedQueue
    OUT
  end

  it "concurrency class constants" do
    result = ze0(<<~'RUBY')
      # The concurrency classes answer as VALUES, and a SizedQueue is a real
      # subclass of Queue.
      #
      # zeo's divergence: a SizedQueue instance answers `is_a?(SizedQueue)` and
      # `instance_of?(SizedQueue)` FALSE while `is_a?(Queue)` stays true -- the
      # instance carries Queue's class id (SizedQueue shares Queue's runtime
      # representation, told apart only by its bound). Everything else here
      # (constants as values, #name, #class, superclass) already matches.
      # (Imported from spinel, which had the same observable, #3466.)
      p Queue, Mutex, Thread, Fiber, ConditionVariable, SizedQueue
      p Queue.new.class
      p SizedQueue.new(2).class
      p Mutex.new.class
      p Fiber.new { 1 }.class
      p Mutex.name, Thread.name, SizedQueue.name
      q = SizedQueue.new(2)
      p q.max
      p q.is_a?(SizedQueue), q.instance_of?(SizedQueue), q.is_a?(Queue)
      u = Queue.new
      p u.is_a?(SizedQueue), u.instance_of?(Queue), u.is_a?(Queue)
      p SizedQueue.superclass, Queue.superclass, Mutex.superclass
      p Fiber.ancestors.first(2)
    RUBY

    _(result).must_answer <<~'OUT'
      Thread::Queue
      Thread::Mutex
      Thread
      Fiber
      Thread::ConditionVariable
      Thread::SizedQueue
      Thread::Queue
      Thread::SizedQueue
      Thread::Mutex
      Fiber
      "Thread::Mutex"
      "Thread"
      "Thread::SizedQueue"
      2
      true
      true
      true
      false
      true
      true
      Thread::Queue
      Object
      Object
      [Fiber, Object]
    OUT
  end

  it "concurrency path2" do
    result = ze0(<<~'RUBY')
      # Queue and Mutex methods on a dynamically-typed (Poly) receiver: held in an
      # Array/Hash/ivar so the compiler can't statically know the type and must
      # dispatch through the runtime method table (Path-2).

      # A Queue stored in an Array element -- `each`'s block param is Poly.
      qs = [Queue.new]
      qs.each do |q|
        q.push(10)
        q << 20
        q.enq(30)
      end
      q = qs.first
      p q.length
      p q.size
      p q.empty?
      p q.pop
      p q.pop
      p q.closed?
      q.close
      p q.closed?
      p q.pop            # closed + one left -> 30
      p q.pop            # closed + empty -> nil

      # A Mutex stored in a Hash value -- Poly receiver again.
      locks = { m: Mutex.new }
      m = locks[:m]
      p m.locked?
      p m.owned?
      result = m.synchronize do
        p m.locked?
        p m.owned?
        42
      end
      p result
      p m.locked?

      # send-based dispatch also lands on Path-2.
      p q.send(:size)
      p m.send(:locked?)
    RUBY

    _(result).must_answer <<~'OUT'
      3
      3
      false
      10
      20
      false
      true
      30
      nil
      false
      false
      true
      true
      42
      false
      0
      false
    OUT
  end

  it "condition variable" do
    result = ze0(<<~'RUBY')
      # ConditionVariable — thread coordination paired with a Mutex.

      cv = ConditionVariable.new
      # (Class#name is `Thread::ConditionVariable` upstream; zeo simplifies the
      # nested `Thread::*` sync classes to top-level, exactly as it does for Mutex.)
      p cv.class.name.include?("ConditionVariable")   # true

      # signal / broadcast return self, and are no-ops with no waiters.
      p cv.signal.equal?(cv)             # true
      p cv.broadcast.equal?(cv)          # true

      # wait with a short timeout returns without a signaller (times out).
      m = Mutex.new
      m.synchronize { cv.wait(m, 0.01) }
      puts "timed out and returned"

      # Producer/consumer handoff: the worker waits until the main broadcasts.
      mutex = Mutex.new
      ready = false
      worker = Thread.new do
        mutex.synchronize do
          until ready
            cv.wait(mutex)
          end
        end
        puts "worker observed ready"
      end

      # Let the worker reach its wait, then flip the flag and wake it.
      mutex.synchronize do
        ready = true
        cv.broadcast
      end
      worker.join
      puts "done"
    RUBY

    _(result).must_answer <<~'OUT'
      true
      true
      true
      timed out and returned
      worker observed ready
      done
    OUT
  end

  it "container read missing arms" do
    result = ze0(<<~'RUBY')
      # Three shapes of the same gap: a value whose type is only known at run time
      # reaches an emitter keyed on the static type, finds no arm, and either raises
      # NoMethodError naming exactly what the receiver is, or answers the slot's
      # default.

      # `h[k] ||= v` USED AS A VALUE. The store test has to be spelled per slot type:
      # an mrb_int's nil is SP_INT_NIL, not 0, so a plain `!x` both skipped the store
      # on an absent key and would overwrite a legitimately stored 0. The statement
      # form always spelled it correctly; the value form did not.
      h = { 0 => 0, 1 => 7 }
      p(h[5] ||= 5)
      p h
      p(h[0] ||= 99)     # 0 is truthy in Ruby: no store
      p h
      p(h[1] ||= 99)
      p(h[9] ||= 0)
      p h

      s = { "a" => "x" }
      p(s["b"] ||= "y")
      p(s["a"] ||= "z")
      p s

      # compact / flatten on an Array read out of a container. uniq had a poly arm
      # and these did not.
      g = { 0 => [1, nil, 2], 1 => [[3], [4, nil]] }
      p g[0].compact
      p g[0].flatten
      p g[1].flatten
      p g[0].uniq
      p g[0].size

      rows = [[1, nil, 2]]
      p rows[0].compact

      # delete_prefix / delete_suffix on a String arriving through a poly slot. The
      # poly String surface covered only the zero-argument transforms.
      f = Fiber.new { Fiber.yield("t=1.5"); nil }
      v = f.resume
      p v.delete_prefix("t=")
      p v.delete_suffix("1.5")
      p v.upcase

      box = { "k" => "pre-body-post" }
      p box["k"].delete_prefix("pre-")
      p box["k"].delete_suffix("-post")
    RUBY

    _(result).must_answer <<~'OUT'
      5
      {0 => 0, 1 => 7, 5 => 5}
      0
      {0 => 0, 1 => 7, 5 => 5}
      7
      0
      {0 => 0, 1 => 7, 5 => 5, 9 => 0}
      "y"
      "x"
      {"a" => "x", "b" => "y"}
      [1, 2]
      [1, nil, 2]
      [3, 4, nil]
      [1, nil, 2]
      3
      [1, 2]
      "1.5"
      "t="
      "T=1.5"
      "body-post"
      "pre-body"
    OUT
  end

  it "each threads bare reraise sees its own handled exception" do
    result = ze0(<<~'RUBY')
      # Each thread's bare `raise` must re-raise its OWN handled exception, never
      # a sibling's -- the per-thread handling stack keeps the two isolated.

      t1 = Thread.new do
        begin
          raise "from t1"
        rescue RuntimeError => e
          begin
            raise
          rescue RuntimeError => inner
            puts "t1 re-raised: #{inner.send(:message)}"
          end
        end
      end
      t1.join
      t2 = Thread.new do
        begin
          raise "from t2"
        rescue RuntimeError => e
          begin
            raise
          rescue RuntimeError => inner
            puts "t2 re-raised: #{inner.send(:message)}"
          end
        end
      end
      t2.join
    RUBY

    _(result).must_answer <<~'OUT'
      t1 re-raised: from t1
      t2 re-raised: from t2
    OUT
  end

  it "external iteration drives a real fiber" do
    result = ze0(<<~'RUBY')
      # The keystone: external iteration over a method-backed enumerator --
      # `next` advances a real fiber, `peek` caches without consuming, the
      # classic `loop { e.next }` idiom terminates via StopIteration and
      # returns the underlying `each`'s result, and a rescued StopIteration
      # exposes `message`/`result`.

      e = [10, 20, 30].each
      r = loop do
        puts e.next
      end
      p r
      e2 = [1].each
      e2.next
      begin
        e2.next
      rescue StopIteration => ex
        puts "rescued: #{ex.message}"
        p ex.result
      end
      g = [7, 8].each
      p g.peek
      p g.peek
      p g.next
      p g.next
    RUBY

    _(result).must_answer <<~'OUT'
      10
      20
      30
      [10, 20, 30]
      rescued: iteration reached an end
      [1]
      7
      7
      7
      8
    OUT
  end

  it "fiber drop teardown" do
    result = ze0(<<~'RUBY')
      # Suspended fibers and abandoned enumerator iterations are torn down
      # without running their `ensure` bodies -- at process end, at thread end,
      # and when a re-init row (`rewind`) discards a suspended iteration
      # mid-program. CRuby parity: a never-finished fiber runs no ensure.

      e = [1, 2, 3].to_enum
      p e.next
      e.rewind
      p e.next

      f = Fiber.new do
        Fiber.yield :a
      ensure
        puts "F-ENSURE"
      end
      p f.resume

      t = Thread.new do
        g = Fiber.new do
          Fiber.yield :b
        ensure
          puts "T-ENSURE"
        end
        p g.resume
      end
      t.join

      puts "done"
    RUBY

    _(result).must_answer <<~'OUT'
      1
      1
      :a
      :b
      done
    OUT
  end

  it "fiber extended" do
    result = ze0(<<~'RUBY')
      # Fiber.current has a stable identity (the root fiber at the top level)
      p Fiber.current.class
      p Fiber.current.equal?(Fiber.current)

      # Fiber storage: Fiber[] / Fiber[]= on the current fiber, inherited at creation
      Fiber[:level] = "outer"
      seen = []
      f = Fiber.new do
        seen << Fiber[:level]        # inherits "outer"
        Fiber[:level] = "inner"      # private write
        seen << Fiber[:level]
        seen << Fiber.current.equal?(f)
        Fiber.yield
      end
      f.resume
      p seen
      p Fiber[:level]                # root still sees "outer"

      # Fiber#storage is nil until first write, then a Hash; only on the current fiber
      root = Fiber.current
      p root.storage                 # {level: "outer"} now
      other = Fiber.new { Fiber.yield }
      other.resume
      begin
        other.storage                # not the current fiber -> ArgumentError
      rescue ArgumentError => e
        puts e.message
      end

      # Fiber#kill terminates a suspended fiber and returns the fiber itself
      k = Fiber.new { Fiber.yield 1; Fiber.yield 2 }
      p k.resume
      p k.kill.equal?(k)
      p k.alive?

      # Fiber#raise injects an exception at the suspended yield point
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
      Fiber
      true
      ["outer", "inner", true]
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

  it "fiber gc root isolation" do
    result = ze0(<<~'RUBY')
      # Cooperative fibers each hold their own GC roots. Pre-fix the
      # single shared sp_gc_roots[] / sp_gc_nroots pair meant that a
      # fiber switch via non-LIFO yields / Fiber.transfer let one
      # fiber's pushes clobber another fiber's slots in the global
      # array, so a GC pass triggered from the second fiber could
      # collect the first fiber's live locals.
      #
      # Each fiber's saved root region is now memcpy'd in/out of the
      # global view on every switch, isolating the per-fiber stacks
      # from each other. Issue #636.

      class Holder
        attr_reader :data
        def initialize(label)
          @data = "holder_" + label
        end
      end

      # Build a small amount of garbage on every iteration to coax the
      # allocator into running a GC pass while fibers are suspended.
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
        # If h1 got collected during f2's churn, this read would
        # segfault or return garbage.
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

      # Resume each fiber once — they push their roots and yield.
      f1.resume
      f2.resume
      f3.resume

      # Now hammer the allocator. Any of the three fibers' h1/h2/h3
      # locals that were clobbered will surface as stale memory.
      n = 0
      while n < 50
        churn(20)
        n += 1
      end

      # Resume each fiber — they read their saved local.
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
      holder_three
      holder_one
      holder_two
    OUT
  end

  it "fiber nested fiber" do
    result = ze0(<<~'RUBY')
      # A Fiber / Enumerator.new body may itself create another Fiber / Enumerator.
      # Each body lowers to its own file-scope C function. Previously the inner
      # body was emitted into the shared g_procs buffer while the outer body was
      # still being written there, so the inner function definition landed inside
      # the outer one ("invalid storage class for function"). The body is now built
      # in a local buffer and appended after any inner definitions.

      outer = Fiber.new do
        inner = Fiber.new do
          Fiber.yield 10
        end
        Fiber.yield inner.resume
        Fiber.yield 20
      end
      p outer.resume
      p outer.resume

      # Inner fiber capturing an outer value local.
      base = 100
      cap = Fiber.new do
        inner = Fiber.new do
          Fiber.yield base + 1
          Fiber.yield base + 2
        end
        Fiber.yield inner.resume
        Fiber.yield inner.resume
        Fiber.yield base
      end
      p cap.resume
      p cap.resume
      p cap.resume

      # Three levels deep.
      f3 = Fiber.new do
        g = Fiber.new do
          h = Fiber.new do
            Fiber.yield 1
          end
          Fiber.yield h.resume + 10
        end
        Fiber.yield g.resume + 100
      end
      p f3.resume

      # A nested Enumerator.new generator inside a Fiber.
      ef = Fiber.new do
        e = Enumerator.new do |y|
          y << 7
          y << 8
        end
        Fiber.yield e.next
        Fiber.yield e.next
      end
      p ef.resume
      p ef.resume

      # Nested block AND nested fiber combined.
      combo = Fiber.new do
        acc = 0
        2.times do |i|
          inner = Fiber.new do
            Fiber.yield i * 10
          end
          acc += inner.resume
          Fiber.yield acc
        end
      end
      p combo.resume
      p combo.resume
    RUBY

    _(result).must_answer <<~'OUT'
      10
      20
      101
      102
      100
      111
      7
      8
      0
      10
    OUT
  end

  it "fiber storage nil" do
    result = ze0(<<~'RUBY')
      # Fiber[:k] = nil must compile: fiber storage is poly-valued, so a nil value
      # is carried boxed (not declared as a `void` temp).
      Fiber.new do
        Fiber[:db_conn] = nil
        Fiber[:db_conn] = "conn"
        puts Fiber[:db_conn]
        Fiber[:db_conn] = nil
        puts Fiber[:db_conn].nil?
      end.resume
    RUBY

    _(result).must_answer <<~'OUT'
      conn
      true
    OUT
  end

  it "fiber wide router" do
    result = ze0(<<~'RUBY')
      # A wide, shallow call fan-out inside a fiber: every arm forced inline is
      # absorbed into one frame as a sibling of the others, and the rooted locals
      # cannot share slots, so the frame grows with the BREADTH of the router. The
      # full reproducer (350 arms) overran the 64K fiber stack; this keeps the shape
      # small enough to be a behaviour check.
      def leaf_a(s)
        x = s.upcase
        y = s.downcase
        x.length + y.length
      end

      def leaf_b(s)
        x = s + "!"
        y = x * 2
        y.length
      end

      def leaf_c(s)
        x = [s, s]
        x.map { |v| v.length }.sum
      end

      def router(k, s)
        r = 0
        if k == 0
          r = leaf_a(s)
        elsif k == 1
          r = leaf_b(s)
        elsif k == 2
          r = leaf_c(s)
        else
          r = leaf_a(s) + leaf_b(s) + leaf_c(s)
        end
        r
      end

      f = Fiber.new do
        n = ARGV.length
        puts router(n, "abc")
        puts router(n + 1, "abc")
        puts router(n + 2, "abc")
        puts router(n + 9, "abc")
      end
      f.resume
    RUBY

    _(result).must_answer <<~'OUT'
      6
      8
      6
      20
    OUT
  end

  it "fibers" do
    result = ze0(<<~'RUBY')
      # Fiber -- cooperative stackful coroutines

      # a producer yielding values to its resumer
      producer = Fiber.new do
        Fiber.yield 1
        Fiber.yield 2
        3
      end
      puts producer.alive?
      puts producer.resume
      puts producer.resume
      puts producer.resume
      puts producer.alive?

      # values flow both directions: resume(v) becomes yield's return value
      echo = Fiber.new do |x|
        y = Fiber.yield(x + 1)
        y * 10
      end
      puts echo.resume(5)
      puts echo.resume(7)

      # first-resume arguments bind to the block's parameters
      adder = Fiber.new do |a, b|
        a + b
      end
      puts adder.resume(20, 22)

      # a fiber shares its enclosing scope's locals across suspensions
      total = 0
      worker = Fiber.new do
        total += 1
        Fiber.yield
        total += 10
      end
      worker.resume
      puts total
      worker.resume
      puts total

      # a dead fiber cannot be resumed
      begin
        producer.resume
      rescue FiberError => e
        puts e.send(:message)
      end

      # an exception inside a fiber surfaces at the resumer
      risky = Fiber.new do
        raise "kaboom"
      end
      begin
        risky.resume
      rescue RuntimeError => e
        puts "rescued: #{e.send(:message)}"
      end
      puts risky.alive?
    RUBY

    _(result).must_answer <<~'OUT'
      true
      1
      2
      3
      false
      6
      70
      42
      1
      11
      attempt to resume a terminated fiber
      rescued: kaboom
      false
    OUT
  end

  it "gc first thread threshold" do
    _(ze0(<<~'RUBY', path: "core/thread/gc_first_thread_threshold.rb")).must_answer "", stderr: "core/thread/gc_first_thread_threshold.rb:27:in '<main>': undefined method '>=' for nil (NoMethodError)\n\np after >= before\n        ^^\n", status: 1
      # Creating the first Thread sizes the object-heap collection budget for the
      # worker pool. It used to MULTIPLY the current threshold by the pool size --
      # and the pool is min(cores, SPINEL_WORKERS), not the thread count the program
      # asked for, so the damage scaled with the machine. A program that had already
      # grown its heap before starting a thread got N x whatever the adaptive
      # threshold had become: 76MB -> 2.4GB on a 32-core box, with no collection
      # involved, and the churn that followed never collected again (#4146).
      #
      # Asserted as properties rather than numbers: the absolute threshold depends on
      # the core count and the allocator's own tuning, and pinning it would make this
      # a test of the machine.

      def th = GC.stat["threshold"]
      def cyc = GC.stat["cycle"]

      # grow the heap first, so the adaptive threshold is well above its base
      keep = []
      600.times { |i| keep << Array.new(4096, i * 1.0) }
      before = th

      Thread.new { 1 + 1 }.join
      after = th

      # The thread allocated nothing, so the threshold must not have been scaled by
      # the pool size. Some headroom for the workers is intended; a multiple of the
      # GROWN threshold is not.
      p after >= before
      p after < before * 2

      # And collection still happens against it: churn well past the threshold and
      # the cycle count has to move.
      c0 = cyc
      3000.times do
        a = Array.new(8192, 1.0)
        a[0] = 2.0
      end
      p cyc > c0

      # The live set is what it was, so the heap is bounded near it rather than
      # climbing to the ceiling.
      p GC.stat["bytes"] < before * 4

      p keep.length
      p keep[0].length
    RUBY
  end

  it "i1007" do
    result = ze0(<<~'RUBY')
      class Server
        def self.run(sfd)
          f = Fiber.new { sfd + 1 }
          f.resume
        end
        def self.work(sfd)
          sfd * 2
        end
      end

      class Worker
        def run(sfd)
          f = Fiber.new { sfd + 1 }
          f.resume
        end
        def work(sfd)
          sfd * 2
        end
      end

      puts Server.run(10)
      puts Server.work(5)
      w = Worker.new
      puts w.run(10)
      puts w.work(5)
    RUBY

    _(result).must_answer <<~'OUT'
      11
      10
      11
      10
    OUT
  end

  it "index opassign in thread block" do
    result = ze0(<<~'RUBY')
      # Index operator-assignment (`arr[i] += x`) on a captured variable inside a
      # block that escapes into a Thread. The block is lifted to a real proc whose
      # result is consumed through the proc-call ABI, so the op-write appears in
      # VALUE position -- which used to be rejected at compile time
      # ("unsupported expression: IndexOperatorWriteNode"). The statement form and
      # the plain `arr[i] = arr[i] + x` spelling always worked; this pins the
      # compound form, including the expression's value (the stored result).

      module P
        def self.each_index(n, nt, &blk)
          ws = []
          w = 0
          while w < nt
            ws << Thread.new(w) { |wid| i = wid; while i < n; blk.call(i); i += nt; end }
            w += 1
          end
          ws.each { |t| t.join }
        end
      end

      a = Array.new(4, 0.0)
      P.each_index(4, 2) { |i| a[i] += 1.5 }
      p a

      # the expression's value is the stored (post-op) result, through a
      # thread-escaping block whose call result is consumed
      r = nil
      b = [10]
      t = Thread.new { r = b[0] += 7 }
      t.join
      p r
      p b

      # hash receiver in value position
      h = { "k" => 10 }
      f = proc { |k| h[k] += 5 }
      p f.call("k")
      p h
    RUBY

    _(result).must_answer <<~'OUT'
      [1.5, 1.5, 1.5, 1.5]
      17
      [17]
      15
      {"k" => 15}
    OUT
  end

  it "issue 2976" do
    result = ze0(<<~'RUBY')
      p Thread.new(7, 8) { |a, b| [a, b] }.value
      p Thread.new(7) { |a| a }.value
      r = (Thread.new(1, 2, 3) { |a, b, c| a + b + c }.value rescue $!.class); p r
      p Thread.new([1, 2]) { |a| a }.value
    RUBY

    _(result).must_answer <<~'OUT'
      [7, 8]
      7
      6
      [1, 2]
    OUT
  end

  it "issue 2977" do
    result = ze0(<<~'RUBY')
      t = Thread.new { 1 }
      t.join
      p t.inspect.start_with?("#<Thread")
      p t.inspect.include?("dead")
      p t.to_s.start_with?("#<Thread")
    RUBY

    _(result).must_answer <<~'OUT'
      true
      true
      true
    OUT
  end

  it "issue 2978" do
    _(ze0(<<~'RUBY')).must_answer "ThreadError\n"
      r = (Thread.new rescue $!.class); p r
    RUBY
  end

  it "issue 3124" do
    result = ze0(<<~'RUBY')
      t = Thread.new { 1 }
      p t.class
      p t.frozen?
      p t.nil?
      t.join
      m = Mutex.new
      p m.class, m.nil?
      q = Queue.new
      p q.class, q.nil?
    RUBY

    _(result).must_answer <<~'OUT'
      Thread
      false
      false
      Thread::Mutex
      false
      Thread::Queue
      false
    OUT
  end

  it "issue 3126" do
    result = ze0(<<~'RUBY')
      t = Thread.new { 1 }
      t.join
      p t.inspect.include?(__FILE__)
      p t.to_s.include?(__FILE__)
      p t.inspect.start_with?("#<Thread:0x")
      p t.inspect.end_with?("dead>")
    RUBY

    _(result).must_answer <<~'OUT'
      true
      true
      true
      true
    OUT
  end

  it "ivar sole thread handoff" do
    result = ze0(<<~'RUBY')
      # Instance variables read and write without locking while one Ruby thread
      # exists. The moment a second one is spawned that has to stop, for objects
      # built BEFORE the spawn as much as after -- so this hammers the same objects
      # from both sides of the handoff.

      class Counter
        attr_accessor :a, :b, :c

        def initialize
          @a = 0
          @b = 0
          @c = 0
        end

        def bump(n)
          @a += n
          @b = @a * 2
          @c = @b - @a
          self
        end

        def total = @a + @b + @c
      end

      # Built and driven while this is the only thread.
      before = Counter.new
      2000.times { |i| before.bump(1) }
      p before.total
      p before.instance_variables

      shared = Array.new(4) { Counter.new }
      lock = Mutex.new

      threads = 4.times.map do |t|
        Thread.new do
          mine = Counter.new
          500.times { mine.bump(1) }
          lock.synchronize { shared[t].bump(mine.a) }
          mine.total
        end
      end
      p threads.map(&:value).sort

      # The pre-spawn object is still correct, and still writable from the main
      # thread now that the fast path is off.
      before.bump(1)
      p before.total
      p shared.map(&:a)

      # A thread that only READS an object the main thread built.
      seen = Thread.new { before.total }.value
      p seen == before.total

      # Ivars invented at runtime interleave correctly across the handoff too.
      before.instance_variable_set(:@late, 7)
      p before.instance_variables
      p Thread.new { before.instance_variable_get(:@late) }.value

      # Objects created INSIDE a thread never took the fast path at all.
      p Thread.new { Counter.new.bump(3).total }.value

      # A CLASS-level `@x` is per-class-object storage on the same fast path, and
      # it is genuinely shared across threads once one is spawned.
      class Registry
        @count = 0
        @names = []

        class << self
          attr_reader :count, :names

          def record(name)
            @count += 1
            @names << name
            @count
          end
        end
      end

      100.times { |i| Registry.record("pre#{i}") }
      p Registry.count

      guard = Mutex.new
      4.times.map do |t|
        Thread.new { 25.times { |i| guard.synchronize { Registry.record("t#{t}-#{i}") } } }
      end.each(&:join)

      p Registry.count
      p Registry.names.length
      p Registry.names.first, Registry.names.last.start_with?("t")
      p Thread.new { Registry.count }.value
    RUBY

    _(result).must_answer <<~'OUT'
      8000
      [:@a, :@b, :@c]
      [2000, 2000, 2000, 2000]
      8004
      [500, 500, 500, 500]
      true
      [:@a, :@b, :@c, :@late]
      7
      12
      100
      200
      200
      "pre0"
      true
      200
    OUT
  end

  it "mutex protected counter across threads is exact" do
    _(ze0(<<~'RUBY')).must_answer "2000\n"
      # THE canonical threading idiom -- Proc-within-Proc (Thread.new wrapping
      # synchronize). The mutex makes the sum exact (2000) regardless of how the
      # two OS threads interleave.

      m = Mutex.new
      count = 0
      t1 = Thread.new { 1000.times { m.synchronize { count += 1 } } }
      t2 = Thread.new { 1000.times { m.synchronize { count += 1 } } }
      t1.join
      t2.join
      puts count
    RUBY
  end

  it "mutex synchronize exits with a break value and unlocks" do
    result = ze0(<<~'RUBY')
      mu = Mutex.new
      r = mu.synchronize { break 5 }
      puts r
      puts mu.locked?
    RUBY

    _(result).must_answer <<~'OUT'
      5
      false
    OUT
  end

  it "opposite order two container ops do not deadlock" do
    _(ze0(<<~'RUBY')).must_answer "no deadlock\n"
      # The lock-ordering probe family: mirrored two-container operations
      # (replace, ==, eql?, <=>, string ==, Encoding.compatible?) hammered
      # from two threads in OPPOSITE orders. Any builtin that holds both
      # containers' locks at once deadlocks here within a few iterations --
      # this pinned the five sequential-snapshot/address-order fixes.

      a = [1] * 50
      b = [2] * 50
      s1 = "x" * 50
      s2 = "y" * 50
      t1 = Thread.new do
        500.times { a.replace(b); a == b; a.eql?(b); a <=> b; s1 == s2; Encoding.compatible?(s1, s2) }
      end
      t2 = Thread.new do
        500.times { b.replace(a); b == a; b.eql?(a); b <=> a; s2 == s1; Encoding.compatible?(s2, s1) }
      end
      t1.join
      t2.join
      puts "no deadlock"
    RUBY
  end

  it "queue and mutex methods on a poly receiver" do
    result = ze0(<<~'RUBY')
      # A Queue/Mutex held in a collection is a dynamically-typed (Poly)
      # receiver, so these methods dispatch through the runtime Path-2 tables
      # rather than the static Path-1 codegen arm. Both must agree.

      qs = [Queue.new]
      qs.each do |q|
        q.push(10)
        q << 20
        q.enq(30)
      end
      q = qs.first
      p q.length
      p q.empty?
      p q.pop
      q.close
      p q.closed?
      p q.pop
      p q.pop

      locks = { m: Mutex.new }
      m = locks[:m]
      p m.locked?
      r = m.synchronize do
        p m.owned?
        42
      end
      p r
      p m.locked?
      p q.send(:size)
    RUBY

    _(result).must_answer <<~'OUT'
      3
      false
      10
      true
      20
      30
      false
      true
      42
      false
      0
    OUT
  end

  it "queue length shovel and empty predicate" do
    result = ze0(<<~'RUBY')
      q3 = Queue.new
      q3 << 5
      q3 << 6
      puts q3.length
      puts q3.empty?
      puts q3.pop
      puts q3.pop
      puts q3.empty?
    RUBY

    _(result).must_answer <<~'OUT'
      2
      false
      5
      6
      true
    OUT
  end

  it "ractor experimental warning" do
    result = ze0(<<~'RUBY', path: "core/thread/ractor_experimental_warning.rb")
      # The Ractor API is experimental, and Ruby says so once -- at the FIRST
      # `Ractor.new`, naming that line, and never again however many Ractors follow.
      # It is an ordinary categorised warning, so `Warning[:experimental] = false`
      # silences it. See the sidecar golden for the one line this prints.

      puts "before"

      # The first one warns, naming ITS line (7 below), not this comment's.
      first = Ractor.new { 1 }
      puts first.value

      # Every later one is silent.
      second = Ractor.new { 2 }
      third = Ractor.new(3) { |n| n }
      puts second.value
      puts third.value

      # The category flag is readable and writable like any other.
      p Warning[:experimental]
      Warning[:experimental] = false
      p Warning[:experimental]
      Warning[:experimental] = true

      # Still silent -- the notice is once per process, not once per setting.
      puts Ractor.new { 4 }.value
    RUBY

    _(result).must_answer <<~'OUT', stderr: "core/thread/ractor_experimental_warning.rb:9: warning: Ractor API is experimental and may change in future versions of Ruby.\n"
      before
      1
      2
      3
      true
      false
      4
    OUT
  end

  it "ractor message passing send and receive" do
    _(ze0(<<~'RUBY', path: "core/thread/ractor_message_passing_send_and_receive.rb")).must_answer "70\n", stderr: "core/thread/ractor_message_passing_send_and_receive.rb:1: warning: Ractor API is experimental and may change in future versions of Ruby.\n"
      worker = Ractor.new do
        msg = Ractor.receive
        msg * 10
      end
      worker.send(7)
      puts worker.value
    RUBY
  end

  it "ractor messages are received in fifo order" do
    _(ze0(<<~'RUBY', path: "core/thread/ractor_messages_are_received_in_fifo_order.rb")).must_answer "123\n", stderr: "core/thread/ractor_messages_are_received_in_fifo_order.rb:1: warning: Ractor API is experimental and may change in future versions of Ruby.\n"
      r = Ractor.new do
        a = Ractor.receive
        b = Ractor.receive
        c = Ractor.receive
        a * 100 + b * 10 + c
      end
      r.send(1)
      r.send(2)
      r.send(3)
      puts r.value
    RUBY
  end

  it "ractor runs in parallel and returns its value" do
    _(ze0(<<~'RUBY', path: "core/thread/ractor_runs_in_parallel_and_returns_its_value.rb")).must_answer "42\n", stderr: "core/thread/ractor_runs_in_parallel_and_returns_its_value.rb:1: warning: Ractor API is experimental and may change in future versions of Ruby.\n"
      r = Ractor.new(20, 22) do |a, b|
        a + b
      end
      puts r.value
    RUBY
  end

  it "several ractors run in parallel and all values collect" do
    _(ze0(<<~'RUBY', path: "core/thread/several_ractors_run_in_parallel_and_all_values_collect.rb")).must_answer "60\n", stderr: "core/thread/several_ractors_run_in_parallel_and_all_values_collect.rb:1: warning: Ractor API is experimental and may change in future versions of Ruby.\n"
      r1 = Ractor.new(1) { |n| n * 10 }
      r2 = Ractor.new(2) { |n| n * 10 }
      r3 = Ractor.new(3) { |n| n * 10 }
      puts r1.value + r2.value + r3.value
    RUBY
  end

  it "sleep forever parks until interrupted" do
    _(ze0(<<~'RUBY')).must_answer "\"woken: done sleeping\"\n"
      # `sleep` with no duration parks until an interrupt arrives, then delivers
      # it normally.

      Thread.report_on_exception = false
      t = Thread.new do
        begin
          sleep
          :never
        rescue => e
          "woken: #{e.message}"
        end
      end
      sleep 0.05
      t.raise("done sleeping")
      p t.value
    RUBY
  end

  it "sleep poly arg" do
    _(ze0(<<~'RUBY')).must_answer "slept\n"
      # sleep with a poly argument (a duration pulled from a heterogeneous hash)
      # must coerce poly -> float for sp_sleep(mrb_float).
      h = { "t" => 0.0, "n" => 2 }
      sleep(h["t"])   # poly value, holds a Float
      puts "slept"
    RUBY
  end

  it "sleep return value" do
    result = ze0(<<~'RUBY')
      # sleep returns the Integer number of seconds slept (0 for a zero duration),
      # not nil. Cover bare, assigned, Kernel-qualified (plain and root-qualified),
      # and arithmetic-consumer forms.
      p sleep(0)
      x = sleep(0)
      p x
      p Kernel.sleep(0)
      p ::Kernel.sleep(0)
      n = sleep(0) + 5
      p n
      p sleep(0.0)
    RUBY

    _(result).must_answer <<~'OUT'
      0
      0
      0
      0
      5
      0
    OUT
  end

  it "thread basic" do
    result = ze0(<<~'RUBY')
      # Thread.new runs a green thread on the cooperative scheduler (Phase 0, N=1):
      # #value returns the block result, #join blocks until it finishes, #alive?
      # reports completion, an unhandled exception is re-raised at #join/#value, and
      # threads carried in an array dispatch #value through the poly slot.
      # (docs/thread-mn-design.md)

      t = Thread.new { 1 + 2 }
      puts t.value                                  # 3
      puts Thread.new { "hi".upcase }.value         # HI

      # join returns the thread; value is idempotent after it finishes
      u = Thread.new { 40 + 2 }
      u.join
      puts u.value                                  # 42
      puts u.alive?                                 # false

      # a side effect is observed after join
      log = []
      Thread.new { log << :ran }.join
      puts log.inspect                              # [:ran]

      # an array of threads, each value collected through the poly slot
      threads = (1..3).map { |i| Thread.new { i * i } }
      puts threads.map { |th| th.value }.inspect    # [1, 4, 9]

      # an unhandled exception is re-raised in the joining thread (silence the
      # at-termination report so the test asserts no stderr)
      Thread.report_on_exception = false
      begin
        Thread.new { raise "boom" }.value
      rescue => e
        puts "#{e.class}: #{e.message}"             # RuntimeError: boom
      end

      # the main thread is itself a live Thread
      puts Thread.current.alive?                     # true
    RUBY

    _(result).must_answer <<~'OUT'
      3
      HI
      42
      false
      [:ran]
      [1, 4, 9]
      RuntimeError: boom
      true
    OUT
  end

  it "thread concurrent alloc" do
    _(ze0(<<~'RUBY')).must_answer "sum=8052000.0\n"
      # Concurrent allocation from multiple threads must be thread-safe and
      # deterministic. Each worker thread allocates a fresh Array per work item
      # (exercising sp_gc_alloc + the container growth paths that adjust the GC
      # byte counters) while its siblings do the same; the shared sp_gc_bytes /
      # pool free-list state used to race at N>1 workers, skewing GC triggers and
      # corrupting the heap. The final sum is a pure function of the inputs, so
      # any run-to-run variation means allocation state was corrupted.
      #
      # The threads write acc at DISJOINT indices (thread w owns i % nt == w) into
      # a preallocated Float array that never grows during the run: each slot is a
      # distinct memory location, so the writes are race-free by construction --
      # this is the documented "safe subset" pattern, and it mirrors how the race
      # was hit in the field. Allocation is the only shared state exercised.
      def alloc_work(i)
        a = Array.new(8, 0.0)
        j = 0
        while j < 8; a[j] = i * 0.5 + j; j += 1; end
        s = 0.0
        j = 0
        while j < 8; s += a[j]; j += 1; end
        s
      end

      n = 2000
      acc = Array.new(n, 0.0)
      nt = 4
      ws = []
      w = 0
      while w < nt
        ws << Thread.new(w) { |wid| i = wid; while i < n; acc[i] = alloc_work(i); i += nt; end }
        w += 1
      end
      ws.each { |t| t.join }
      puts "sum=#{acc.reduce(0.0) { |a, b| a + b }}"
    RUBY
  end

  it "thread gc start" do
    result = ze0(<<~'RUBY')
      # An explicit GC.start in a program that has run threads. The collection has to
      # take the stop-the-world barrier: its parallel sweep hands one slot to each
      # other worker and waits for them, which only happens if they are parked at the
      # barrier. Run straight from the mutator, the collector waited on sweeps nobody
      # would do and the program hung.

      t = Thread.new { 1 + 1 }
      t.join
      GC.start
      p :after_join

      def work(n, threads)
        c = Array.new(n) { Array.new(n, 0.0) }
        mutex = Mutex.new
        done = 0
        threads.times.map do |w|
          Thread.new do
            (0...n).each { |i| c[i][w % n] = (i * w).to_f }
            mutex.synchronize { done += 1 }
          end
        end.each(&:join)
        done
      end

      3.times do
        p work(8, 4)
        GC.start
        junk = (1..200).map { |i| [i.to_s, i] }
        GC.start
        p junk.length
      end
    RUBY

    _(result).must_answer <<~'OUT'
      :after_join
      4
      200
      4
      200
      4
      200
    OUT
  end

  it "thread index is fiber local" do
    result = ze0(<<~'RUBY')
      # Thread#[] / Thread#[]= are FIBER-local storage (thread_variable_get/set are
      # the thread-local pair). A write inside a Fiber must be invisible after the
      # fiber ends. zeo keeps one locals map per thread, so the fiber's write leaks
      # out.
      Thread.current[:v] = 5
      puts Thread.current[:v]

      f = Fiber.new do
        Thread.current[:v] = :fiber_only
        Thread.current[:v]
      end
      puts f.resume.inspect
      puts Thread.current[:v].inspect

      Thread.current.thread_variable_set(:tv, 7)
      g = Fiber.new { Thread.current.thread_variable_get(:tv) }
      puts g.resume
    RUBY

    _(result).must_answer <<~'OUT'
      5
      :fiber_only
      5
      7
    OUT
  end

  it "thread list" do
    result = ze0(<<~'RUBY')
      # Thread.list returns the main thread plus every live spawned thread.
      p Thread.list.size                       # 1 (just main)
      p Thread.list.include?(Thread.current)   # true

      # The three are HELD blocked while they are counted. A thread that has run to
      # the end leaves the registry whether or not anyone joined it, so counting
      # threads that race the count would count luck -- zeo runs real OS threads,
      # where they finish before the next line.
      gate = Queue.new
      threads = (1..3).map { Thread.new { gate.pop } }
      sleep 0.005 until threads.all? { |t| t.status == "sleep" }
      p Thread.list.size                       # 4 (main + 3 blocked)

      3.times { gate << :go }
      threads.each(&:join)
      p Thread.list.size                       # 1 (the spawned threads finished)
      p Thread.list.include?(Thread.main)      # true
    RUBY

    _(result).must_answer <<~'OUT'
      1
      true
      4
      1
      true
    OUT
  end

  it "thread new args" do
    result = ze0(<<~'RUBY')
      # Thread.new(arg) passes the argument as the block's first parameter -- the
      # canonical way to give each thread its own value instead of capturing a shared
      # variable. The argument reaches the block on the thread's first scheduling.
      # (A block whose tail is a poly-typed method call -- e.g. x.upcase -- is a
      # separate emit-fiber value-capture gap, so the values below are captured forms.)

      t = Thread.new(21) { |n| n * 2 }
      p t.value                                   # 42

      p Thread.new("hi") { |x| x + "!" }.value    # "hi!"

      # the classic loop: each thread gets its own i, not a shared captured one
      results = (1..5).map { |i| Thread.new(i) { |n| n * n } }
      p results.map(&:value)                      # [1, 4, 9, 16, 25]

      # the argument captured by value, observed through a side effect
      seen = []
      Thread.new(:tag) { |n| seen << n }.join
      p seen                                      # [:tag]

      # no argument -> the param is nil
      p Thread.new { |n| n.inspect }.value        # "nil"
    RUBY

    _(result).must_answer <<~'OUT'
      42
      "hi!"
      [1, 4, 9, 16, 25]
      [:tag]
      "nil"
    OUT
  end

  it "thread new value" do
    result = ze0(<<~'RUBY')
      t = Thread.new { 21 * 2 }
      puts t.value

      s = Thread.new { "hi" + "!" }
      puts s.value
    RUBY

    _(result).must_answer <<~'OUT'
      42
      hi!
    OUT
  end
end
