# frozen_string_literal: true

require "spec_helper"

describe "Thread: blocks and yields" do
  it "a module method's &blk parameter is captured by the Thread.new block" do
    result = zr(<<~'RUBY')
      # A method's &block parameter is reachable from a Thread.new / Fiber.new block
      # in that method's body. The block runs as an independent closure on its own
      # fiber stack, so the method must keep its &blk as a real Proc, and the call
      # site must pass the block. This holds for a class or module method too.

      # module (class-)method: &blk captured by a Thread.new block
      module M
        def self.f(&blk)
          t = Thread.new { blk.call(0) }
          t.join
        end
      end
      M.f { |i| puts "got #{i}" }            # got 0

    RUBY

    _(result).must_answer <<~'OUT'
      got 0
    OUT
  end

  it "an instance method's &blk parameter is captured through a thread the same way" do
    result = zr(<<~'RUBY')
      # A method's &block parameter is reachable from a Thread.new / Fiber.new block
      # in that method's body. The block runs as an independent closure on its own
      # fiber stack, so the method must keep its &blk as a real Proc, and the call
      # site must pass the block. This holds for a class or module method too.

      # instance method: same capture through a thread
      class C
        def run(&blk)
          t = Thread.new { blk.call(7) }
          t.join
        end
      end
      C.new.run { |i| puts "run #{i}" }      # run 7

    RUBY

    _(result).must_answer <<~'OUT'
      run 7
    OUT
  end

  it "a positional parameter ahead of &blk is forwarded into the thread with it" do
    result = zr(<<~'RUBY')
      # A method's &block parameter is reachable from a Thread.new / Fiber.new block
      # in that method's body. The block runs as an independent closure on its own
      # fiber stack, so the method must keep its &blk as a real Proc, and the call
      # site must pass the block. This holds for a class or module method too.

      # a positional parameter ahead of &blk, forwarded into the thread
      module N
        def self.g(prefix, &blk)
          t = Thread.new { blk.call(prefix) }
          t.join
        end
      end
      N.g("x") { |s| puts "pre #{s}" }       # pre x

    RUBY

    _(result).must_answer <<~'OUT'
      pre x
    OUT
  end

  it "Fiber.new captures the &blk parameter as Thread.new does" do
    result = zr(<<~'RUBY')
      # A method's &block parameter is reachable from a Thread.new / Fiber.new block
      # in that method's body. The block runs as an independent closure on its own
      # fiber stack, so the method must keep its &blk as a real Proc, and the call
      # site must pass the block. This holds for a class or module method too.

      # Fiber.new capture of the &blk param
      module F
        def self.h(&blk)
          fib = Fiber.new { blk.call(3) }
          fib.resume
        end
      end
      F.h { |i| puts "fib #{i}" }            # fib 3

    RUBY

    _(result).must_answer <<~'OUT'
      fib 3
    OUT
  end

  it "a &blk assigned to a local and called later still reaches the thread" do
    result = zr(<<~'RUBY')
      # A method's &block parameter is reachable from a Thread.new / Fiber.new block
      # in that method's body. The block runs as an independent closure on its own
      # fiber stack, so the method must keep its &blk as a real Proc, and the call
      # site must pass the block. This holds for a class or module method too.

      # class-method &blk used as a value (assigned to a local, then called): the
      # call site must still pass the block proc
      module V
        def self.take(&blk)
          p = blk
          p.call(9)
        end
      end
      V.take { |i| puts "val #{i}" }         # val 9

    RUBY

    _(result).must_answer <<~'OUT'
      val 9
    OUT
  end

  it "a value-returning &blk sums across two invocations inside threads" do
    result = zr(<<~'RUBY')
      # A method's &block parameter is reachable from a Thread.new / Fiber.new block
      # in that method's body. The block runs as an independent closure on its own
      # fiber stack, so the method must keep its &blk as a real Proc, and the call
      # site must pass the block. This holds for a class or module method too.

      # class-method &blk with a value-returning call, summed across two invocations
      module S
        def self.calc(&blk)
          blk.call(1) + blk.call(2)
        end
      end
      puts S.calc { |i| i * 10 }             # 30

    RUBY

    _(result).must_answer <<~'OUT'
      30
    OUT
  end

  it "a &blk read inside a block lifted to a standalone proc still resolves" do
    result = zr(<<~'RUBY')
      # A method's &block parameter is reachable from a Thread.new / Fiber.new block
      # in that method's body. The block runs as an independent closure on its own
      # fiber stack, so the method must keep its &blk as a real Proc, and the call
      # site must pass the block. This holds for a class or module method too.

      # &blk read inside a block that is *lifted* to a standalone proc (passed to a
      # method that keeps a real &block param): the same capture-escape as the
      # Thread case, so the method must keep a heap &blk too
      def taker(&t)
        t
      end

      def outer(&blk)
        pr = taker { blk.call(4) }
        pr.call
      end
      outer { |i| puts "lift #{i}" }         # lift 4

    RUBY

    _(result).must_answer <<~'OUT'
      lift 4
    OUT
  end

  it "a class method reached through a module singleton accessor passes its &blk on" do
    result = zr(<<~'RUBY')
      # A method's &block parameter is reachable from a Thread.new / Fiber.new block
      # in that method's body. The block runs as an independent closure on its own
      # fiber stack, so the method must keep its &blk as a real Proc, and the call
      # site must pass the block. This holds for a class or module method too.

      # a class method reached through a module singleton accessor must also pass
      # the block proc -- Stage-1: the accessor is bound to exactly one constant
      module Reg1
        class << self
          attr_accessor :handler
        end
      end

      class H1
        def self.run(x, &blk)
          t = Thread.new { blk.call(x) }
          t.join
        end
      end

      Reg1.handler = H1
      Reg1.handler.run(5) { |v| puts "reg1 #{v}" }   # reg1 5

    RUBY

    _(result).must_answer <<~'OUT'
      reg1 5
    OUT
  end

  it "an accessor written with two distinct constants passes each one's &blk" do
    result = zr(<<~'RUBY')
      # A method's &block parameter is reachable from a Thread.new / Fiber.new block
      # in that method's body. The block runs as an independent closure on its own
      # fiber stack, so the method must keep its &blk as a real Proc, and the call
      # site must pass the block. This holds for a class or module method too.

      # Stage-2: the accessor is written with two distinct constants, so the call
      # dispatches over the stored class -- each branch passes the same block proc
      module Reg2
        class << self
          attr_accessor :handler
        end
      end

      class H2a
        def self.run(x, &blk)
          t = Thread.new { blk.call(x + 1) }
          t.join
        end
      end

      class H2b
        def self.run(x, &blk)
          t = Thread.new { blk.call(x + 2) }
          t.join
        end
      end

      Reg2.handler = H2a
      Reg2.handler.run(10) { |v| puts "reg2a #{v}" } # reg2a 11
      Reg2.handler = H2b
      Reg2.handler.run(10) { |v| puts "reg2b #{v}" } # reg2b 12
    RUBY

    _(result).must_answer <<~'OUT'
      reg2a 11
      reg2b 12
    OUT
  end

  it "fiber driven entirely inside a thread" do
    result = zr(<<~'RUBY')
      # The fiber table is per-OS-thread; a fiber created and resumed inside
      # one Thread works because both operations run on that same OS thread.

      t = Thread.new do
        ff = Fiber.new do |x|
          Fiber.yield x + 1
          99
        end
        a = ff.resume(1)
        b = ff.resume
        a + b
      end
      puts t.value
    RUBY

    _(result).must_answer "101\n"
  end

  it "fiber nested block" do
    result = zr(<<~'RUBY')
      # A Fiber / Enumerator.new body may contain a nested block (3.times { |i| },
      # arr.each { |x| }, destructuring { |a, b| }). The body lowers to a flat C
      # function and the nested block is inlined into it, so the block's parameters
      # (i / x / a, b) and any locals it writes must exist in that function.

      f1 = Fiber.new do
        3.times do |i|
          Fiber.yield i
        end
      end
      p f1.resume
      p f1.resume
      p f1.resume

      f2 = Fiber.new do
        total = 0
        [1, 2, 3, 4].each do |n|
          sq = n * n
          total += sq
          Fiber.yield total
        end
      end
      p f2.resume
      p f2.resume
      p f2.resume
      p f2.resume

      # Enumerator.new generator with a nested block.
      e = Enumerator.new do |y|
        3.times do |i|
          y << i * 100
        end
      end
      p e.next
      p e.next
      p e.next

      # Two-parameter (destructuring) nested block.
      f3 = Fiber.new do
        [[1, 2], [3, 4]].each do |a, b|
          Fiber.yield a + b
        end
      end
      p f3.resume
      p f3.resume
    RUBY

    _(result).must_answer <<~'OUT'
      0
      1
      2
      1
      5
      14
      30
      0
      100
      200
      3
      7
    OUT
  end

  it "fiber nested block capture" do
    result = zr(<<~'RUBY')
      # A capture assigned inside a NESTED block within a Fiber / proc body now
      # propagates to the enclosing scope. Capture detection (a_collect_used /
      # proc_collect_used) descends into nested blocks, so an enclosing local
      # written there is celled, while the nested block's own params/locals stay
      # block-local. Covers value (Integer), heap rebind (String / Array), and the
      # proc form.

      # Integer accumulated inside a nested block
      acc = 0
      Fiber.new do
        3.times { |i| acc += i + 1 }
        Fiber.yield
      end.resume
      p acc                       # 6

      # String rebound inside a nested block
      total = "x"
      Fiber.new do
        2.times { |i| total = total + i.to_s }
        Fiber.yield
      end.resume
      puts total                  # x01

      # Array rebound (literal) inside a nested block
      out = [0]
      Fiber.new do
        [10, 20].each { |n| out = [n, n] }
        Fiber.yield
      end.resume
      p out                       # [20, 20]

      # Nested block's own param/local is not mistaken for a capture
      seen = 0
      Fiber.new do
        [5, 6].each { |x| tmp = x * 2; seen += tmp }
        Fiber.yield
      end.resume
      p seen                      # 22

      # proc capturing through a nested block (propagation via side effect)
      def make
        n = 0
        bump = proc { 4.times { |k| n += k } }
        [bump, proc { n }]
      end
      bump, get = make
      bump.call
      p get.call                  # 6
    RUBY

    _(result).must_answer <<~'OUT'
      6
      x01
      [20, 20]
      22
      6
    OUT
  end

  it "fiber new with proc arg" do
    result = zr(<<~'RUBY')
      # `Fiber.new(&proc)` -- the block arriving as a proc argument rather than a
      # literal block, the same conversion Thread.new already makes.
      stepper = proc do
        Fiber.yield 1
        Fiber.yield 2
        3
      end
      f = Fiber.new(&stepper)
      p f.resume
      p f.resume
      p f.resume

      begin
        Fiber.new(&nil)
      rescue ArgumentError => e
        puts e.message
      end
    RUBY

    _(result).must_answer <<~'OUT'
      1
      2
      3
      tried to create Proc object without a block
    OUT
  end

  it "fiber reassign capture" do
    result = zr(<<~'RUBY')
      # A Fiber / proc body that REBINDS a captured heap object (String / Array /
      # Hash / object) to a new value now propagates that reassignment to the
      # enclosing scope, matching value-type captures. Heap captures ride a typed-
      # pointer cell, so `s = "new"` writes through the shared cell. In-place
      # mutation of a non-rebound capture (`buf << x`) still works by pointer.

      # String rebind
      s = "old"
      Fiber.new { s = "new"; Fiber.yield }.resume
      puts s

      # Array rebind
      arr = [1]
      Fiber.new { arr = [9, 9]; Fiber.yield }.resume
      p arr

      # Hash rebind
      h = {a: 1}
      Fiber.new { h = {b: 2, c: 3}; Fiber.yield }.resume
      p h

      # In-place mutation of a non-rebound capture still propagates by pointer
      buf = "x"
      Fiber.new { buf << "y"; Fiber.yield }.resume
      puts buf

      acc = []
      Fiber.new { acc << 42; Fiber.yield }.resume
      p acc

      # Rebind AND in-place mutate the same captured string
      t = "a"
      Fiber.new { t << "b"; t = t + "c"; Fiber.yield }.resume
      puts t

      # Object rebind
      Point = Struct.new(:x)
      pt = Point.new(1)
      Fiber.new { pt = Point.new(99); Fiber.yield }.resume
      p pt.x

      # Two procs sharing a reassigned capture (propagation via side effect, to
      # avoid the unrelated array-destructured-proc .call return-typing path).
      def make
        v = "old"
        list = [1]
        [proc { v = "new"; list = [9, 9] }, proc { puts v; p list }]
      end
      setter, reader = make
      reader.call
      setter.call
      reader.call
    RUBY

    _(result).must_answer <<~'OUT'
      new
      [9, 9]
      {b: 2, c: 3}
      xy
      [42]
      abc
      99
      old
      [1]
      new
      [9, 9]
    OUT
  end

  it "fiber shared capture" do
    result = zr(<<~'RUBY')
      # A Fiber (or Enumerator.new) block that assigns an enclosing value-type local
      # now shares it: the write reaches the outer scope (a heap cell, like an escaping
      # proc captures), so it is no longer silently lost. A captured heap object is
      # already shared by pointer, so in-place mutation reaches the outer scope too.

      # integer accumulator
      acc = 0
      f = Fiber.new { acc += 1; Fiber.yield acc }
      p f.resume          # 1
      p acc               # 1 -- the write propagated

      # accumulate across resumes
      sum = 0
      g = Fiber.new do
        sum += 10
        Fiber.yield sum
        sum += 20
        Fiber.yield sum
      end
      p g.resume          # 10
      p sum               # 10
      p g.resume          # 30
      p sum               # 30

      # poly local reassigned to a different type
      v = 0
      k = Fiber.new { v = "hi"; Fiber.yield v }
      p k.resume          # "hi"
      p v                 # "hi"

      # heap object: in-place mutation is shared by pointer
      s = ""
      m = Fiber.new { s << "ab"; Fiber.yield s.length }
      p m.resume          # 2
      p s                 # "ab"

      arr = []
      n = Fiber.new { arr << 1 << 2; Fiber.yield arr.length }
      p n.resume          # 2
      p arr               # [1, 2]

      # read-only capture still works
      base = 100
      r = Fiber.new { Fiber.yield(base + 1); Fiber.yield(base + 2) }
      p r.resume          # 101
      p r.resume          # 102

      # Enumerator.new generator sharing an outer counter
      calls = 0
      e = Enumerator.new do |y|
        calls += 1
        y << calls
        calls += 1
        y << calls
      end
      p e.next            # 1
      p e.next            # 2
      p calls             # 2
    RUBY

    _(result).must_answer <<~'OUT'
      1
      1
      10
      10
      30
      30
      "hi"
      "hi"
      2
      "ab"
      2
      [1, 2]
      101
      102
      1
      2
      2
    OUT
  end

  it "fiber works inside a ractor" do
    result = zr(<<~'RUBY')
      # The fiber table is thread-pinned and a Ractor is its own OS thread --
      # create and drive entirely within it.

      r = Ractor.new do
        f = Fiber.new do
          Fiber.yield 1
          2
        end
        a = f.resume
        b = f.resume
        a + b
      end
      puts r.value
    RUBY

    _(result).must_answer "3\n", stderr: <<~'ERR'
      core/thread/blocks_test.rb:4: warning: Ractor API is experimental and may change in future versions of Ruby.
    ERR
  end

  it "fiber yield at the root raises a fiber error" do
    result = zr(<<~'RUBY')
      begin
        Fiber.yield(1)
      rescue FiberError => e
        puts e.send(:message)
      end
    RUBY

    _(result).must_answer "attempt to yield on a not resumed fiber\n"
  end

  it "fiber yield from a deep method call stack" do
    result = zr(<<~'RUBY')
      # The zr-fiber shim's raison d'etre: suspension from inside a chain
      # of ordinary compiled method frames that never saw a yielder.

      class Chain
        def a; b; end
        def b; c; end
        def c
          Fiber.yield :from_deep
          :done
        end
      end
      ch = Chain.new
      f = Fiber.new { ch.a }
      puts f.resume
      puts f.resume
    RUBY

    _(result).must_answer "from_deep\ndone\n"
  end

  it "fiber yield through a real escaping block" do
    result = zr(<<~'RUBY')
      # The hardest suspension shape: Fiber.yield fires inside a real Proc
      # (the block each_twice invokes), unwinding through the Proc's closure
      # frame AND each_twice's own method frame to the resumer.

      class Iter
        def each_twice
          yield 1
          yield 2
        end
      end
      it = Iter.new
      f = Fiber.new do
        it.each_twice do |n|
          Fiber.yield n
        end
        :done
      end
      puts f.resume
      puts f.resume
      puts f.resume
    RUBY

    _(result).must_answer <<~'OUT'
      1
      2
      done
    OUT
  end

  it "fiber yields values in order then returns the body value and dies" do
    result = zr(<<~'RUBY')
      f = Fiber.new do
        Fiber.yield 1
        Fiber.yield 2
        3
      end
      puts f.alive?
      puts f.resume
      puts f.resume
      puts f.resume
      puts f.alive?
    RUBY

    _(result).must_answer <<~'OUT'
      true
      1
      2
      3
      false
    OUT
  end

  it "mutex synchronize returns the block value and always unlocks" do
    result = zr(<<~'RUBY')
      mu = Mutex.new
      r = mu.synchronize { 42 }
      puts r
      puts mu.locked?
      begin
        mu.synchronize { raise "inside" }
      rescue RuntimeError => e
        puts "rescued: #{e.send(:message)}"
      end
      puts mu.locked?
    RUBY

    _(result).must_answer <<~'OUT'
      42
      false
      rescued: inside
      false
    OUT
  end

  it "proc concurrent call poly ret" do
    result = zr(<<~'RUBY')
      # Concurrent Proc#call return values are not corrupted across threads. A
      # poly-returning proc stashes its boxed result in the _sp_proc_poly_ret slot
      # (and poly arguments ride _sp_proc_poly_args); those slots were
      # process-global, so concurrent calls from several threads raced on them and
      # read each other's values -- intermittently wrong results, flagged
      # deterministically by ThreadSanitizer. The slots are per-worker (SP_TLS)
      # now, which is safe because no safepoint poll (the only migration /
      # preemption point) lies between the callee's store and the call-site read.
      # The loops stay allocation-free so the test exercises only the slots.

      # poly return: float for even, integer for odd -- a cross-thread mixup shows
      # up as a wrong value or a wrong type
      pr = ->(i) { i.even? ? i * 0.5 : i * 3 }

      nthreads = 4
      total_n = 80000
      threads = []
      t = 0
      while t < nthreads
        threads << Thread.new(t) do |tid|
          errs = 0
          j = tid
          while j < total_n
            v = pr.call(j)
            if j.even?
              errs += 1 unless v == j * 0.5
            else
              errs += 1 unless v == j * 3
            end
            j += nthreads
          end
          errs
        end
        t += 1
      end

      total = 0
      threads.each { |th| total += th.value }
      puts total.zero? ? "poly ret ok" : "poly ret corrupted: #{total}"
    RUBY

    _(result).must_answer "poly ret ok\n"
  end

  it "proc return fiber isolation" do
    result = zr(<<~'RUBY')
      # Proc-return home chains are per-fiber: interleaving non-local returns across
      # the main fiber and a Fiber must not corrupt either chain. Each `worker` call
      # is a self-contained non-local return; the fiber yields between them while the
      # main fiber also performs its own returns.
      def worker(n)
        proc { return n * 10 }.call
      end
      results = []
      f = Fiber.new do
        results << worker(1)
        Fiber.yield
        results << worker(2)
      end
      results << worker(3)
      f.resume
      results << worker(4)
      f.resume
      results << worker(5)
      p results
    RUBY

    _(result).must_answer "[30, 10, 40, 20, 50]\n"
  end

  it "proc return home survives fiber suspension" do
    result = zr(<<~'RUBY')
      # The ec-swap's home-stack slice, oracle-verified: a method running
      # inside a fiber suspends mid-body, and after resumption its
      # return-proc still unwinds to it (the home stayed alive across the
      # suspension because the whole stack was parked, not shared); a proc
      # that ESCAPES its dead activation still gets the LocalJumpError.

      def maker
        pr = proc { return :via_proc }
        Fiber.yield :suspended
        pr.call
        :after_call
      end
      f = Fiber.new { maker }
      p f.resume
      p f.resume
      def escape_maker
        proc { return :late }
      end
      f2 = Fiber.new do
        pr = escape_maker
        begin
          pr.call
        rescue LocalJumpError => e
          "LJE: #{e.message}"
        end
      end
      p f2.resume
    RUBY

    _(result).must_answer <<~'OUT'
      :suspended
      :via_proc
      "LJE: unexpected return"
    OUT
  end

  it "ractor" do
    result = zr(<<~'RUBY', path: "zr/ractor.rb")
      # `Ractor.new` is decided by the SITE: the block is the ractor's body and
      # is moved in whole, so it never reaches the send road. The isolation
      # verdict rides on the Proc, which is why a captured name refuses here and
      # not where the proc was written.

      r = Ractor.new(20) { |n| n + 1 }
      p r.value

      named = Ractor.new(name: "worker") { 7 }
      p named.name
      p named.value

      sink = Ractor.new do
        a = Ractor.receive
        b = Ractor.receive
        a * b
      end
      sink.send(6)
      sink.send(7)
      p sink.value

      doubler = ->(x) { x + x }
      p Ractor.new(4, &doubler).value

      def spawn(&blk) = Ractor.new(10, &blk)
      p spawn { |x| x + 5 }.value

      outer = 1
      bad = proc { outer + 1 }
      begin
        Ractor.new(&bad)
      rescue ArgumentError => e
        puts e.message
      end

      begin
        Ractor.new(&nil)
      rescue ArgumentError => e
        puts e.message
      end
    RUBY

    _(result).must_answer <<~'OUT', stderr: <<~'ERR'
      21
      "worker"
      7
      42
      8
      15
      can not isolate a Proc because it accesses outer variables (outer).
      must be called with a block
    OUT
      zr/ractor.rb:6: warning: Ractor API is experimental and may change in future versions of Ruby.
    ERR
  end

  it "ractor block isolates at runtime" do
    result = zr(<<~'RUBY')
      # `Ractor.new { ... }` -- isolation is CRuby's runtime verdict, not zr's
      # compile-time one.
      #
      # A block that touches an outer local or the enclosing object's ivars
      # compiles. Ruby answers differently for each:
      #
      #   - an OUTER LOCAL is an `ArgumentError` from `Ractor.new` itself, raised
      #     after the arguments have been evaluated;
      #   - an `@ivar` is not a Proc problem at all. Ruby isolates the Proc and
      #     rebinds its `self` to the RACTOR, so the read is an ivar of a shareable
      #     object and raises `Ractor::IsolationError` INSIDE the ractor, surfacing
      #     as `Ractor::RemoteError` at `#value`;
      #   - a receiverless call to an enclosing-class method is a plain `NameError`
      #     for the same reason: `self` is a Ractor, which has no such method.
      Warning[:experimental] = false
      # A ractor that aborts also prints `#<Thread:0x...> terminated with exception`
      # on stderr, and the address makes that unpinnable in a golden. Silenced here
      # so the test compares the part that is deterministic; zr does not print the
      # report at all, which is a separate (recorded) divergence.
      Thread.report_on_exception = false

      def arg = (puts "the argument still ran"; 1)

      outer = 5
      begin
        Ractor.new(arg) { outer }
      rescue => e
        p e.class
        p e.message
      end

      class Holder
        def initialize
          @n = 7
        end

        def cause_of
          yield.value
          "no raise"
        rescue Ractor::RemoteError => e
          [e.cause.class.to_s, e.cause.message]
        end

        def report
          p cause_of { Ractor.new { @n } }
          p cause_of { Ractor.new { @n = 3 } }
          p cause_of { Ractor.new { defined?(@n) } }
          p cause_of { Ractor.new { instance_variable_get(:@n) } }
          p cause_of { Ractor.new { instance_variable_set(:@n, 1) } }
          p cause_of { Ractor.new { helper } }
        end

        def helper = "helped"
      end

      Holder.new.report

      # `self` inside the block, and the two reflective reads ruby permits there.
      r = Ractor.new { [self.class.to_s, Ractor.shareable?(self), instance_variables] }
      p r.value

      # A block that touches neither still runs, and its argument crosses.
      p Ractor.new(3) { |n| n * 2 }.value

      # The MAIN ractor is untouched: an ordinary ivar read of a shareable receiver
      # is only an error from a non-main ractor.
      p Holder.new.instance_variable_get(:@n)
      FROZEN = Object.new.freeze
      p FROZEN.instance_variables
    RUBY

    _(result).must_answer <<~'OUT'
      the argument still ran
      ArgumentError
      "can not isolate a Proc because it accesses outer variables (outer)."
      ["Ractor::IsolationError", "can not access instance variables of shareable objects from non-main Ractors"]
      ["Ractor::IsolationError", "can not access instance variables of shareable objects from non-main Ractors"]
      ["Ractor::IsolationError", "can not access instance variables of shareable objects from non-main Ractors"]
      ["Ractor::IsolationError", "can not access instance variables of shareable objects from non-main Ractors"]
      ["Ractor::IsolationError", "can not access instance variables of shareable objects from non-main Ractors"]
      ["NameError", "undefined local variable or method 'helper' for an instance of Ractor"]
      ["Ractor", true, []]
      6
      7
      []
    OUT
  end

  it "ractor block reading an enclosing ivar raises inside the ractor" do
    result = zr(<<~'RUBY')
      # Ruby isolates the Proc and rebinds its `self` to the RACTOR, so `@n` is
      # an ivar of a shareable object -- `Ractor::IsolationError` in the ractor,
      # surfacing as `Ractor::RemoteError` at `#value`.


      Thread.report_on_exception = false
      class Holder
        def initialize = @n = 7
        def go
          Ractor.new { @n }.value
        rescue Ractor::RemoteError => e
          puts "cause: #{e.cause.class}: #{e.cause.send(:message)}"
        end
      end
      Holder.new.go
    RUBY

    _(result).must_answer <<~'OUT', stderr: <<~'ERR'
      cause: Ractor::IsolationError: can not access instance variables of shareable objects from non-main Ractors
    OUT
      core/thread/blocks_test.rb:10: warning: Ractor API is experimental and may change in future versions of Ruby.
    ERR
  end

  it "ractor new with proc arg" do
    result = zr(<<~'RUBY')
      # `Ractor.new(&proc)` -- a dynamic proc converts like any `&` block
      # argument, and its isolability is decided at Ractor.new TIME with CRuby's
      # plain ArgumentError (only a literal block gets zr's earlier static
      # check). The proc carries its capture verdict from its creation site.
      pred = proc { |x| x * 2 }
      puts Ractor.new(21, &pred).value

      # The forwarded-block shapes (grepfruit's `Ractor.new(port, &)`).
      def spawn_worker(&blk)
        Ractor.new(10, &blk)
      end
      puts spawn_worker { |x| x + 5 }.value

      def create_worker(&)
        Ractor.new(3, &)
      end
      puts create_worker { |x| x - 1 }.value

      # The ivar-held shape (pbt's `Ractor.new(val, &@predicate)`).
      class Runner
        def initialize(&blk)
          @predicate = blk
        end

        def run(val)
          Ractor.new(val, &@predicate)
        end
      end
      puts Runner.new { |v| v * v }.run(7).value

      # A lambda converts the same way.
      doubler = ->(x) { x + x }
      puts Ractor.new(4, &doubler).value

      # A proc that captures an outer variable refuses at Ractor.new time,
      # catchably -- never at the proc's creation.
      outer = 1
      bad = proc { outer + 1 }
      begin
        Ractor.new(&bad)
      rescue ArgumentError => e
        puts e.message
      end

      # `&nil` is "no block" -- the missing-block ArgumentError.
      begin
        Ractor.new(&nil)
      rescue ArgumentError => e
        puts e.message
      end
    RUBY

    _(result).must_answer <<~'OUT', stderr: <<~'ERR'
      42
      15
      2
      49
      8
      can not isolate a Proc because it accesses outer variables (outer).
      must be called with a block
    OUT
      core/thread/blocks_test.rb:6: warning: Ractor API is experimental and may change in future versions of Ruby.
    ERR
  end

  it "shareable proc copies only what cannot change" do
    result = zr(<<~'RUBY')
      # `Ractor.shareable_proc` copies the outer locals its block reads, so it
      # holds only locals that cannot change: each one bound once in its own
      # scope, and holding a shareable value. It refuses a block that writes an
      # outer local, and one whose self is not shareable; the Proc it answers is
      # frozen, and no Binding reaches its scope.
      def try(label)
        r = yield
        puts "#{label}: #{r.inspect}"
      rescue Exception => e
        puts "#{label}: #{e.class}: #{e.message}"
      end

      def param(name) = Ractor.shareable_proc { name }
      try("a parameter") { [param(:x).call, param(:x).frozen?, Ractor.shareable?(param(:x))] }

      def assigned_once
        v = :once
        Ractor.shareable_proc { v }
      end
      try("bound once") { assigned_once.call }

      def assigned_twice
        v = :a
        v = :b
        Ractor.shareable_proc { v }
      end
      try("bound twice") { assigned_twice }

      def assigned_after
        v = :a
        pr = Ractor.shareable_proc { v }
        v = :b
        pr
      end
      try("bound again after") { assigned_after }

      def param_then_assigned(v)
        v = 1
        Ractor.shareable_proc { v }
      end
      try("a parameter bound again") { param_then_assigned(0) }

      def in_a_loop
        i = 0
        while i < 1
          v = 5
          i += 1
        end
        Ractor.shareable_proc { v }
      end
      try("bound once in a loop") { in_a_loop.call }

      def two_arms(c)
        if c then v = 1 else v = 2 end
        Ractor.shareable_proc { v }
      end
      try("bound in two arms") { two_arms(true) }

      def another_block_writes
        v = 1
        [1].each { v = 2 }
        Ractor.shareable_proc { v }
      end
      try("written by another block") { another_block_writes }

      def named_group
        /(?<w>a)/ =~ "a"
        Ractor.shareable_proc { w }
      end
      try("a named group") { named_group }

      def unshareable
        v = []
        Ractor.shareable_proc { v }
      end
      try("an unshareable value") { unshareable }

      def frozen_array
        v = [1, 2].freeze
        Ractor.shareable_proc { v }.call
      end
      try("a frozen array") { frozen_array }

      def writes_inside
        v = 1
        Ractor.shareable_proc { v = 2 }
      end
      try("writes an outer local") { writes_inside }

      def writes_nested
        a = 1
        Ractor.shareable_proc { [1].each { a = 2 } }
      end
      try("a nested block writes it") { writes_nested }

      def writes_two
        zeta = 1
        alpha = 1
        Ractor.shareable_proc { alpha = 2; zeta = 3 }
      end
      try("writes two") { writes_two }

      def both_rebound
        zeta = 1
        zeta = 2
        alpha = 1
        alpha = 2
        Ractor.shareable_proc { [zeta, alpha] }
      end
      try("two bound twice") { both_rebound }

      def mixed
        alpha = []
        zeta = 1
        zeta = 2
        Ractor.shareable_proc { [alpha, zeta] }
      end
      try("one unshareable, one bound twice") { mixed }

      try("self by default") { Ractor.shareable_proc { self }.call }
      try("self: 5") { Ractor.shareable_proc(self: 5) { self }.call }
      try("self: []") { Ractor.shareable_proc(self: []) { self } }
      try("an unknown keyword") { Ractor.shareable_proc(foo: 1) { } }
      try("no block") { Ractor.shareable_proc }

      def lam(name) = Ractor.shareable_lambda { name }
      try("a lambda") { [lam(:q).lambda?, lam(:q).call] }
      pr = proc { 1 }
      try("a passed proc") { s = Ractor.shareable_proc(&pr); [s.equal?(pr), pr.frozen?, s.frozen?, s.lambda?] }
      try("a passed proc to shareable_lambda") { Ractor.shareable_lambda(&pr).lambda? }

      class Table
        def initialize = @t = { a: 1 }
      end
      def getter(name) = Ractor.shareable_proc { @t[name] }
      t = Table.new
      t.define_singleton_method(:a, &getter(:a))
      try("as a method") { t.a }

      def nested(n) = Ractor.shareable_proc { [1].map { n } }
      try("read by a nested block") { nested(3).call }
      def two_out(n) = [1].map { Ractor.shareable_proc { n } }.first
      try("two scopes out") { two_out(4).call }
      def each_made = [1, 2].map { |i| Ractor.shareable_proc { i } }.map(&:call)
      try("one a block call") { each_made }

      def copies(n)
        pr = Ractor.shareable_proc { n }
        [pr.dup.frozen?, pr.clone.frozen?]
      end
      try("dup and clone") { copies(1) }
      try("binding") { Ractor.shareable_proc { }.binding }
      try("dup's binding") { Ractor.shareable_proc { }.dup.binding.class }

    RUBY

    _(result).must_answer <<~'OUT'
      a parameter: [:x, true, true]
      bound once: :once
      bound twice: Ractor::IsolationError: cannot make a shareable Proc because the outer variable 'v' may be reassigned.
      bound again after: Ractor::IsolationError: cannot make a shareable Proc because the outer variable 'v' may be reassigned.
      a parameter bound again: Ractor::IsolationError: cannot make a shareable Proc because the outer variable 'v' may be reassigned.
      bound once in a loop: 5
      bound in two arms: Ractor::IsolationError: cannot make a shareable Proc because the outer variable 'v' may be reassigned.
      written by another block: Ractor::IsolationError: cannot make a shareable Proc because the outer variable 'v' may be reassigned.
      a named group: Ractor::IsolationError: cannot make a shareable Proc because it can refer unshareable object "a" from variable 'w'
      an unshareable value: Ractor::IsolationError: cannot make a shareable Proc because it can refer unshareable object [] from variable 'v'
      a frozen array: [1, 2]
      writes an outer local: ArgumentError: can not make a Proc shareable because it accesses outer variables (v).
      a nested block writes it: ArgumentError: can not make a Proc shareable because it accesses outer variables (a).
      writes two: ArgumentError: can not make a Proc shareable because it accesses outer variables (zeta, alpha).
      two bound twice: Ractor::IsolationError: cannot make a shareable Proc because the outer variable 'alpha' may be reassigned.
      one unshareable, one bound twice: Ractor::IsolationError: cannot make a shareable Proc because it can refer unshareable object [] from variable 'alpha'
      self by default: nil
      self: 5: 5
      self: []: Ractor::IsolationError: self should be shareable: []
      an unknown keyword: ArgumentError: unknown keyword: :foo
      no block: ArgumentError: tried to create Proc object without a block
      a lambda: [true, :q]
      a passed proc: [false, false, true, false]
      a passed proc to shareable_lambda: false
      as a method: 1
      read by a nested block: [3]
      two scopes out: 4
      one a block call: [1, 2]
      dup and clone: [false, true]
      binding: ArgumentError: Can't create Binding from isolated Proc
      dup's binding: Binding
    OUT
  end

  it "Thread.new(&proc) converts the block argument the way every other call site converts one" do
    result = zr(<<~'RUBY')
      # `Thread.new(&proc)` -- drb starts its main loop that way. The block argument
      # converts exactly as it does at every other call site.
      def worker(n) = (puts "worker #{n}")

      Thread.new(3, &method(:worker)).join

      blk = proc { |a, b| puts "proc #{a}#{b}" }
      Thread.new(1, 2, &blk).join

      q = Queue.new
      Thread.new(&-> { q << :from_lambda }).join
      p q.pop

      # A Symbol converts through `Symbol#to_proc`, so the thread argument becomes
      # the receiver.
      Thread.new("shout", &:upcase).join
      p Thread.new("shout", &:upcase).value

      # `&nil` is "no block", which `Thread.new` rejects the same way a missing
      # literal one is rejected.
      begin
        Thread.new(&nil)
      rescue ThreadError => e
        puts e.message
      end
      begin
        Thread.new
      rescue ThreadError => e
        puts e.message
      end
    RUBY

    _(result).must_answer <<~'OUT'
      worker 3
      proc 12
      :from_lambda
      "SHOUT"
      must be called with a block
      must be called with a block
    OUT
  end

  it "value answers the block's result, and the arguments bind to the block's parameters" do
    result = zr(<<~'RUBY')
      v = Thread.new(20, 22) { |a, b| a + b }.value
      puts v
    RUBY

    _(result).must_answer "42\n"
  end

  it "a Mutex yielded to a block inside Thread.new survives the proc ABI and the ensure funnel" do
    result = zr(<<~'RUBY')
      # A Mutex yielded to a block from inside Thread.new. A block argument can be
      # any runtime handle (Mutex, IO, Thread, Queue, Dir, ...), not only a string,
      # array, hash or object. The block gets the same handle, and the value of
      # Mutex#synchronize (with its ensure) comes back as the block's value.
      def race(label)
        h = { "a" => 0 }
        lock = Mutex.new
        ts = 2.times.map do
          Thread.new do
            yield(lock, h)
          end
        end
        ts.each(&:join)
        puts "#{label}: #{h["a"]}"
      end

      race("counter") { |lock, h| lock.synchronize { h["a"] += 1 } }

      # the same handle yielded WITHOUT a thread still works
      def direct
        lock = Mutex.new
        yield(lock)
      end
      direct { |l| puts l.class.to_s }

      # other handle kinds through the same path
      def with_queue
        q = Queue.new
        yield(q)
        q.size
      end
      puts with_queue { |q| q.push(1); q.push(2) }
    RUBY

    _(result).must_answer <<~'OUT'
      counter: 2
      Thread::Mutex
      2
    OUT
  end

  it "yield inside thread body" do
    result = zr(<<~'RUBY')
      # yield inside a Thread body sees the enclosing method's block
      def run
        t = Thread.new { yield 5 }
        t.value
      end
      p(run { |x| x * 2 })

      def run2
        t = Thread.new do
          r = nil
          loop { r = yield(5); break }
          r
        end
        t.value
      end
      p(run2 { |x| x * 2 })

      def run3
        ts = 2.times.map { |i| Thread.new { yield i } }
        ts.map(&:value)
      end
      p(run3 { |x| x * 10 })

      def run4(&blk)
        t = Thread.new { blk.call(7) }
        t.value
      end
      p(run4 { |x| x + 1 })

      def plain
        yield 3
      end
      p(plain { |x| x * 4 })
    RUBY

    _(result).must_answer <<~'OUT'
      10
      10
      [0, 10]
      8
      12
    OUT
  end
end
