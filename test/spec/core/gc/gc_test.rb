# frozen_string_literal: true

require "spec_helper"

describe "GC programs" do
  it "argv gc" do
    result = ze0(<<~'RUBY', argv: ["first", "second", "third", "fourth", "fifth"])

      # sp_argv stores `const char *` pointers into the str-heap (via
      # sp_str_dup_external on main entry). Without explicit GC marking,
      # sp_str_sweep reaps them on the first collect, leaving sp_argv.data
      # entries as dangling pointers that any later `ARGV[i]` read
      # dereferences.
      #
      # Triggering the bug requires:
      #  - Reading ARGV[i] (just the read, not even a method call).
      #  - GC pressure that actually fires sp_gc_collect — string allocs
      #    don't accrue to sp_gc_bytes per sp_str_alloc's threshold note,
      #    so we need object allocations to push past 256 KB.
      #  - Reading ARGV[i] again after GC; the dangling pointer either
      #    segfaults outright or yields freed memory.
      #
      # The fix marks sp_argv.data[*] alongside the regex globals in
      # sp_re_mark_globals, so sp_str_sweep keeps argv strings alive.
      # argv_gc.rb.args feeds five short args so the harness exercises a
      # non-empty ARGV (short strings hit the segfault path under the bug).

      class Trash
        def initialize(n)
          @n = n
          @s = "padding payload " * 64    # ~1 KB heap string per Trash
        end
        attr_reader :n
      end

      # Allocate ~5000 Trash instances (~5 MB) — far past the 256 KB GC
      # threshold — to force sp_gc_collect / sp_str_sweep cycles.
      junk = []
      j = 0
      while j < 5000
        junk << Trash.new(j)
        j = j + 1
      end
      puts junk.length     # 5000

      # Read ARGV[i] after GC. With the bug, sp_argv.data[i] points to
      # freed memory; reading it (and its length) crashes or returns
      # garbage.
      i = 0
      while i < ARGV.length
        puts ARGV[i] + ":" + ARGV[i].length.to_s
        i = i + 1
      end
    RUBY

    _(result).must_answer <<~'OUT'
      5000
      first:5
      second:6
      third:5
      fourth:6
      fifth:5
    OUT
  end

  it "array callforms strbuf cycle" do
    result = ze0(<<~'RUBY')
      # String#<< as an expression on a STRBUF-promoted local; Array slice(i)/
      # slice(range), pop(n)/shift(n), max(n){cmp}/min(n){cmp}, sum(str){blk};
      # blockless cycle(n)/each_entry chains; collect_concat as a flat_map alias.
      s = "ab"
      t = s << "cd"
      p t
      p s
      u = "x"
      p(u << "y" << "z")
      p([10, 20, 30, 40].slice(1))
      p([10, 20, 30, 40].slice(1..3))
      a = [1, 2, 3, 4]
      p a.pop(2)
      p a
      b = [1, 2, 3, 4]
      p b.shift(2)
      p b
      c = [1, :x, "s", 4.0]
      p c.pop(2)
      p([1, 2, 3, 4].max(2) { |x, y| x <=> y })
      p([1, 2, 3, 4].min(2) { |x, y| x <=> y })
      p(["a", "b", "c"].sum("x") { |e| e })
      p [1, 2].cycle(3).to_a
      p [1, 2, 3].each_entry.to_a
      p ["a", :b].cycle(2).to_a
      p [1, 2].cycle(2).map { |x| x * 10 }
      p [1, 2, 3].collect_concat { |x| [x, x * 10] }
      p [[1, 2], [3]].collect_concat { |e| e }
    RUBY

    _(result).must_answer <<~'OUT'
      "abcd"
      "abcd"
      "xyz"
      20
      [20, 30, 40]
      [3, 4]
      [1, 2]
      [1, 2]
      [3, 4]
      ["s", 4.0]
      [4, 3]
      [1, 2]
      "xabc"
      [1, 2, 1, 2, 1, 2]
      [1, 2, 3]
      ["a", :b, "a", :b]
      [10, 20, 10, 20]
      [1, 10, 2, 20, 3, 30]
      [1, 2, 3]
    OUT
  end

  it "array cycle bang forms and values at" do
    result = ze0(<<~'RUBY')
      p [1, 2, 3].cycle(2).to_a
      c = []
      [1, 2].cycle(2) { |x| c << x }
      p c
      p [1, 2].cycle(0).to_a
      p [[1, [2, 3]], [4]].flatten!
      a = [1, 2]
      p a.flatten!
      b = [3, 1, 2]
      b.sort_by! { |x| -x }
      p b
      p [1, 2, 3].values_at(0, 2, 5)
      p [1, 2, 3].values_at(0..1)
      p [1, 2, 3, 4, 5].values_at(3..9)
    RUBY

    _(result).must_answer <<~'OUT'
      [1, 2, 3, 1, 2, 3]
      [1, 2, 1, 2]
      []
      [1, 2, 3, 4]
      nil
      [3, 2, 1]
      [1, 3, nil]
      [1, 2]
      [4, 5, nil, nil, nil, nil, nil]
    OUT
  end

  it "array cycle bounded" do
    result = ze0(<<~'RUBY')
      # <array>.cycle.first(n) / .take(n) consume the infinite cycle by a bounded count.
      # Unbounded forms (cycle.to_a / .each / bare cycle) remain a compile-time reject so
      # they can never hang -- see the note in the PR; they are intentionally not tested
      # here (they do not compile).
      p [1, 2, 3].cycle.first(7)
      p [1, 2, 3].cycle.take(2)
      p ["a", "b"].cycle.first(5)
      p [10, 20, 30].cycle.first(0)
      p [42].cycle.take(4)
      # a negative count is an ArgumentError, matching Enumerable#first/#take
      begin
        [1, 2, 3].cycle.first(-1)
      rescue ArgumentError => e
        p e.message
      end
      begin
        [1, 2, 3].cycle.take(-2)
      rescue ArgumentError => e
        p e.message
      end
      # the finite block form cycle(n) { } is unchanged
      out = []
      [1, 2].cycle(3) { |x| out << x }
      p out
    RUBY

    _(result).must_answer <<~'OUT'
      [1, 2, 3, 1, 2, 3, 1]
      [1, 2]
      ["a", "b", "a", "b", "a"]
      []
      [42, 42, 42, 42]
      "attempt to take negative size"
      "attempt to take negative size"
      [1, 2, 1, 2, 1, 2]
    OUT
  end

  it "array cycle enumerator" do
    result = ze0(<<~'RUBY')
      # Blockless cycle(n) on a poly array is typed as an Enumerator, but the
      # emitter materialized the repeated array instead -- so the consumer read a
      # poly array through sp_Enumerator_to_a and the program died.
      p([].cycle(2).to_a)
      p([1,2].cycle(2).to_a)
      p([].cycle(0).to_a)
      a = [1,:b]
      p a.cycle(2).to_a
      p a.cycle(2).first(3)
      r = []
      a.cycle(2) { |x| r << x }
      p r
    RUBY

    _(result).must_answer <<~'OUT'
      []
      [1, 2, 1, 2]
      []
      [1, :b, 1, :b]
      [1, :b, 1]
      [1, :b, 1, :b]
    OUT
  end

  it "big payloads run the collector" do
    result = ze0(<<~'RUBY')
      # The bytes Strings, Arrays and Hashes hold outside their cells count
      # toward a collection: a program that keeps few cells but makes large
      # payloads collects, so its memory stays bounded, and GC.stat reports
      # the payload held and the count that runs the collector.
      before = GC.stat[:count]
      keep = nil
      200.times { keep = "x" * 8_000_000 }
      p GC.stat[:count] - before > 5, keep.size
      before = GC.stat[:count]
      a = nil
      100.times { a = Array.new(2_000_000, 1) }
      p GC.stat[:count] - before > 3, a.size
      held = GC.stat[:malloc_increase_bytes]
      limit = GC.stat[:malloc_increase_bytes_limit]
      p held.is_a?(Integer), held >= 0, limit >= 16 * 1024 * 1024, held < limit
      keep = a = nil
      GC.start
      p GC.stat[:malloc_increase_bytes] < 64 * 1024 * 1024

    RUBY

    _(result).must_answer <<~'OUT'
      true
      8000000
      true
      2000000
      true
      true
      true
      true
      true
    OUT
  end

  it "blockless cycle enumerator" do
    result = ze0(<<~'RUBY')
      class Nums
        include Enumerable
        def initialize(*xs); @xs = xs; end
        def each; @xs.each { |x| yield x }; end
      end
      p(Nums.new(1, 2).cycle.first(5))
      r001 = (Nums.new(1, 2).cycle.class rescue $!.class); p r001
      p [1,2].cycle.class
      p [1,2].cycle(2).class
    RUBY

    _(result).must_answer <<~'OUT'
      [1, 2, 1, 2, 1]
      Enumerator
      Enumerator
      Enumerator
    OUT
  end

  it "bound method gc" do
    result = ze0(<<~'RUBY')
      # GC: a Method captures `self`, and the captured receiver may
      # be reachable only through the Method itself. The auto-generated
      # `sp_Method_gc_scan` walks `iv_self_obj` via `sp_gc_mark`, so
      # the receiver survives any GC cycle that runs before `bm.call`.
      #
      # Counter has only an int ivar, which would normally make it a
      # value-type class — but `detect_method_taken_classes` excludes it
      # so `self` stays a heap-allocated pointer that the Method can
      # safely hold.

      class Counter
        def initialize(start)
          @n = start
        end
        def add(x)
          @n + x
        end
        def own_bm
          method(:add)
        end
      end

      def make_bm
        c = Counter.new(100)
        c.own_bm  # the only handle to `c` is via the returned Method
      end

      bm = make_bm
      1000.times { String.new("garbage" * 100) }
      puts bm.call(7)
    RUBY

    _(result).must_answer "107\n"
  end

  it "cycle block value position" do
    result = ze0(<<~'RUBY')
      # Array#cycle(n) { } with its return value captured: the statement loop
      # runs against a hoisted receiver and the expression evaluates to nil
      # (a valued break still routes through the break wrapper).
      x = [1, 2, 3].cycle(2) { |y| }
      p x
      seen = []
      r = [4, 5].cycle(3) { |y| seen << y }
      p r
      p seen
      b = [1, 2].cycle { |y| break y * 100 if y == 2 }
      p b
    RUBY

    _(result).must_answer <<~'OUT'
      nil
      nil
      [4, 5, 4, 5, 4, 5]
      200
    OUT
  end

  it "cycle is collected without being asked" do
    result = ze0(<<~'RUBY', env: {"ZEO_GC" => "1"})
      # The collector only exists under `ZEO_GC=1`; without it `GC.start` bumps a
      # counter and nothing is reclaimed, so both answers read false. CRuby always
      # collects, so the oracle needs no counterpart.
      # The cycle this program builds on purpose, and the census the
      # `ZEO_RT_GCCHECK=1` leg gates against. A cycle alive at exit is not a
      # defect: it is a ring the program never broke. What the leg gates is a
      # CHANGE to the line below.
      #
      # The golden's whole subject: it allocates rings until the trigger fires. The residue is the last generation, still live at exit.

      # The collector runs on its own once the live registry has grown enough --
      # nothing here calls `GC.start`. Before this, a program that never asked
      # collected nothing, however much garbage it built.
      #
      # The trigger is ARMED at the allocation and FIRED at the next `check_ints`
      # safepoint, never at the allocation itself. An allocation can happen inside a
      # container's own guard -- growing a Hash while its lock is held -- and
      # collecting there hands the pass a locked node it has to read. The checkpoint
      # sites hold no guard by construction, which a debug assertion states.
      #
      # The threshold moves with the heap: it is re-aimed after every pass at what
      # survived plus half again, so a program with a genuinely large LIVE heap
      # collects on growth rather than every time the registry compacts. Only the
      # survivor count a compaction already computed is read, so the trigger costs
      # no scan of its own.
      #
      # An automatic collection takes the SAME entry an explicit `GC.start` does, so
      # the two cannot drift: `GC.disable` gates both, both bump `GC.count`, and
      # both sweep the finalizers a reclaimed cycle just made due. CRuby counts its
      # automatic collections too.
      class Node
        attr_accessor :peer
      end

      def churn(seen = nil)
        a = Node.new
        b = Node.new
        a.peer = b
        b.peer = a
        seen[a] = true if seen
        nil
      end

      watch = ObjectSpace::WeakMap.new
      churn(watch)
      before = GC.count
      40_000.times { churn }

      # The count moved without the program asking, and the watched cycle is gone.
      p GC.count > before
      p watch.size == 0

      # The exit census is what `ZEO_RT_GCCHECK=1` writes, and it has to be the same
      # every run or it gates nothing. What the automatic trigger leaves behind is
      # the LAST generation, and how big that is depends on exactly where the
      # trigger fired -- it moved between 1002 and 1010 objects under load. One
      # explicit pass at the end reclaims all of it, so the census is empty and
      # stable. The two answers above are the subject; the residue never was.
      GC.start
    RUBY

    _(result).must_answer <<~'OUT'
      true
      true
    OUT
  end

  it "cycle is reclaimed" do
    result = ze0(<<~'RUBY', env: {"ZEO_GC" => "1"})
      # This golden needs zeo's cycle collector armed (`ZEO_GC=1`), which is what
      # the harness sets when this sidecar is present. The oracle needs no
      # counterpart: CRuby always collects.
      # zeo's heap is reference counted, so a cycle's counts never reach zero and
      # the collector is what reclaims one. It is off by default because recording
      # every allocation into the registry it walks costs +1.54% geomean over the
      # bench corpus, and a program that never makes a cycle should not pay for
      # one. Turning it on by default is a separate decision with its own number.
      # The cycle this program builds on purpose, and the census it leaves
      # behind. A cycle alive at exit is not a defect: it is a ring the
      # program never broke, so the census below is recorded as an
      # observation rather than gated on.
      #
      # The golden's whole subject: three Node rings built on purpose and never broken.

      # At exit: cycle leak: 3 objects (Node x3)
      # zeo's heap is reference counted, so a cycle's counts never reach zero and
      # nothing in it is ever dropped. The cycle collector reconciles those counts
      # against an allocation registry instead of tracing from roots -- zeo has no
      # enumerable root set and never will -- and reclaims what nothing outside the
      # registry refers to.
      #
      # `ObjectSpace::WeakMap` is the honest probe. A finalizer is not: zeo runs
      # finalizers for everything still alive at exit, so `define_finalizer` on a
      # cycle prints at exit on both sides whether or not the cycle was collected.
      # A weak reference reports what actually happened -- both implementations
      # clear the entry only when the object is really gone.
      #
      # Every shape is built inside a method that has returned, so no local is
      # holding it. The survivors are held on purpose, and are the half that
      # matters most: a collector that reclaims a live object is far worse than one
      # that misses a dead one.
      #
      # Four of these arrived from `tests/gaps/a_cycle_can_still_leak.rb`, which is
      # gone: a captured proc cell, a Range endpoint, a per-object singleton, and an
      # ivar on a bare value. Their causes are recorded beside each one, because
      # each was a different mechanism rather than four instances of one bug.
      seen = ObjectSpace::WeakMap.new
      $held = []

      class Node
        attr_accessor :peer, :tag
        def initialize(tag = nil) = @tag = tag
      end
      class ArraySub < Array; end
      class HashSub < Hash; end
      class Boom < StandardError
        attr_accessor :peer
      end
      Pair = Struct.new(:peer)

      def pair(seen)
        a = Node.new
        b = Node.new
        a.peer = b
        b.peer = a
        seen[a] = true
        seen[b] = true
        nil
      end

      def self_loop(seen)
        a = Node.new
        a.peer = a
        seen[a] = true
        nil
      end

      def chain(seen)
        ns = Array.new(4) { Node.new }
        ns.each_with_index { |n, i| n.peer = ns[(i + 1) % 4] }
        ns.each { |n| seen[n] = true }
        nil
      end

      def through_array(seen)
        a = []
        a << a
        seen[a] = true
        nil
      end

      def through_hash(seen)
        h = {}
        h[:self] = h
        k = []
        h[k] = k
        seen[h] = true
        seen[k] = true
        nil
      end

      def through_containers(seen)
        n = Node.new
        n.peer = { list: [n] }
        seen[n] = true
        nil
      end

      def through_a_value_subclass(seen)
        a = ArraySub.new
        a << a
        h = HashSub.new
        h[:me] = h
        seen[a] = true
        seen[h] = true
        nil
      end

      def through_an_exception(seen)
        e = Boom.new("x")
        e.peer = e
        seen[e] = true
        nil
      end
      # Deliberately absent: a cycle closed through `Exception#cause`. zeo reclaims
      # it; CRuby keeps the most recently raised exception reachable from its own VM
      # error slot, so the oracle answers one more than zeo does and the shape is
      # not portable. The `cause` slot is still enumerated like every other hidden
      # one -- the corpus's own raising goldens exercise it under the collector's
      # debug over-count check.

      def through_a_struct(seen)
        s = Pair.new(nil)
        s.peer = s
        seen[s] = true
        nil
      end

      def through_an_invented_ivar(seen)
        n = Node.new
        n.instance_variable_set(:@invented, n)
        seen[n] = true
        nil
      end

      def through_a_string_leaf(seen)
        n = Node.new
        n.peer = ["a#{1}b", n]
        seen[n] = true
        nil
      end

      # `Object.new` keeps its ivars in a name-keyed map rather than in struct
      # fields, because the top level's `self` has no compile-time class whose ivar
      # list codegen could have materialized.
      def through_a_bare_object(seen)
        o = Object.new
        o.instance_variable_set(:@peer, o)
        seen[o] = true
        nil
      end

      # A `Struct.new` the compiler cannot see is a run-time instance, whose
      # members AND ivars are both mutable owned slots. `Pair` above is the
      # compile-time twin, which is a generated class instead.
      def through_a_runtime_struct(seen)
        k = Struct.new(:peer)
        s = k.new(nil)
        s.peer = s
        m = Struct.new(:tag).new(1)
        m.instance_variable_set(:@peer, m)
        seen[s] = true
        seen[m] = true
        nil
      end

      def through_runtime_class(seen)
        k = Class.new { attr_accessor :peer }
        x = k.new
        y = k.new
        x.peer = y
        y.peer = x
        seen[x] = true
        nil
      end

      # A compiled block's captured cell, which is where `obj.callback = -> { obj }`
      # -- the canonical ruby leak -- closes. The environment lives inside an
      # `Arc<dyn Fn>` that no reflection can open, so the proc holds a copy of it
      # beside the closure purely so the walk can enumerate the cells.
      def through_a_captured_cell(seen)
        n = Node.new
        n.peer = -> { n }
        seen[n] = true
        nil
      end

      # The same cell shared by two procs: reported once by each, which is what the
      # over-count check is there to catch if it is ever reported twice by one.
      def through_two_procs_sharing_a_cell(seen)
        n = Node.new
        n.peer = [-> { n }, -> { n }]
        seen[n] = true
        nil
      end

      # A block's lexical `self`, which is a capture the closure does not hold at
      # all -- it rides beside the body so `instance_exec` can rebind it.
      def through_a_block_self(seen)
        n = Node.new
        n.peer = proc { @anything }
        seen[n] = true
        nil
      end

      # A Range holds its endpoints with no interior mutability at all -- it is
      # frozen in ruby, and the `Arc` buys sharing and object identity, nothing
      # else. So it reports edges the sweep cannot clear, exactly as a Proc does.
      # Only a Range that COULD be in a cycle is registered: `1..n` owns nothing.
      def through_a_range_endpoint(seen)
        a = []
        a << (a..nil)
        seen[a] = true
        nil
      end

      # A per-object singleton files its methods in a side table keyed by the
      # receiver's ADDRESS, which is unique only while the receiver lives. The pin
      # that stops a later value inheriting those methods is a WEAK reference: it
      # holds the allocation, so the address stays reserved, without holding the
      # value.
      def through_a_per_object_singleton(seen)
        n = Node.new
        def n.only_mine = 1
        n.peer = n
        seen[n] = true
        nil
      end

      # An ivar on a bare value is the other table with that shape, and the same
      # weak pin.
      def through_an_ivar_on_a_bare_value(seen)
        a = []
        a << a
        a.instance_variable_set(:@tag, 1)
        seen[a] = true
        nil
      end

      # -- the survivors ---------------------------------------------------------

      def held_by_a_global(seen)
        a = Node.new
        a.peer = a
        $held << a
        seen[a] = true
        nil
      end

      def held_by_a_container(seen, keep)
        a = Node.new
        b = Node.new
        a.peer = b
        b.peer = a
        keep << a
        seen[a] = true
        seen[b] = true
        nil
      end

      # CRuby scans the machine stack conservatively, so a pointer a returned frame
      # left behind can keep a dead object alive for a while. Overwriting that stack
      # is what makes the oracle's answer deterministic; zeo needs no such help,
      # because a reference count is exact.
      def scrub(n) = n.zero? ? [0] * 512 : scrub(n - 1)

      keep = []
      pair(seen)
      self_loop(seen)
      chain(seen)
      through_array(seen)
      through_hash(seen)
      through_containers(seen)
      through_a_value_subclass(seen)
      through_an_exception(seen)
      through_a_struct(seen)
      through_an_invented_ivar(seen)
      through_a_string_leaf(seen)
      through_runtime_class(seen)
      through_a_bare_object(seen)
      through_a_runtime_struct(seen)
      through_a_captured_cell(seen)
      through_two_procs_sharing_a_cell(seen)
      through_a_block_self(seen)
      through_a_range_endpoint(seen)
      through_a_per_object_singleton(seen)
      through_an_ivar_on_a_bare_value(seen)
      held_by_a_global(seen)
      held_by_a_container(seen, keep)

      scrub(60)
      GC.start
      GC.start

      # 1 global cycle + 2 objects reached from `keep`
      p seen.size
      p $held.size
      p keep.size
      p keep[0].peer.peer.equal?(keep[0])
      p $held[0].peer.equal?($held[0])

      # The survivors are intact, not merely present: a collector that emptied a
      # live object would show up here rather than as a crash.
      live = Node.new("live")
      live.peer = live
      p live.tag
      GC.start
      p live.tag
      p live.peer.equal?(live)
    RUBY

    _(result).must_answer <<~'OUT'
      3
      1
      1
      true
      true
      "live"
      "live"
      true
    OUT
  end

  it "cycle is reclaimed beside live threads" do
    result = ze0(<<~'RUBY', env: {"ZEO_GC" => "1"})
      # This golden needs the cycle collector armed: without `ZEO_GC=1` zeo has no
      # collector at all and both counts read 2. CRuby always collects, so the oracle
      # needs no counterpart.

      # Reference-count reconciliation reads every node's owner count and compares
      # it against the edges it can enumerate. A thread mutating the heap while that
      # runs would make the two disagree, and the pass would read a live node as
      # garbage -- the one direction that can corrupt. So a collection stops every
      # other Ruby thread first, and before this it simply refused to run whenever
      # it was not alone.
      #
      # Both shapes below leaked under `ZEO_GC=1`: one busy worker thread was enough
      # to make `GC.start` a no-op.
      #
      # The threads park at a `check_ints` checkpoint, never at an allocation site.
      # An allocation can happen inside a container's own guard -- growing a Hash
      # while its lock is held -- and stopping the world there would hand the
      # collector a locked node it has to read.
      #
      # A request that cannot stop the world in time is ABANDONED rather than
      # waited on, which is why the elapsed check is here: a thread that never
      # reaches a checkpoint must cost a bounded pause and a missed collection, not
      # a hang. That is exactly what leaked before, so it is never a regression.
      class Node
        attr_accessor :peer
      end

      def scrub(n) = n.zero? ? [0] * 512 : scrub(n - 1)

      def pair(seen)
        a = Node.new
        b = Node.new
        a.peer = b
        b.peer = a
        seen[a] = true
        seen[b] = true
        nil
      end

      def timed
        t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        yield
        Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0
      end

      # Busy workers: they reach a checkpoint on every loop iteration.
      busy = ObjectSpace::WeakMap.new
      workers = 3.times.map { Thread.new { 20_000.times.sum { |j| j % 7 } } }
      pair(busy)
      scrub(60)
      elapsed = timed do
        GC.start
        GC.start
      end
      puts "busy collected=#{busy.size == 0} bounded=#{elapsed < 3.0}"
      p workers.map(&:value).uniq.size

      # A sleeping thread parks too: `Kernel#sleep` re-checks its interrupts on
      # every wake, so the request reaches it immediately rather than at its
      # deadline.
      sleeping = ObjectSpace::WeakMap.new
      napper = Thread.new { sleep 3 }
      pair(sleeping)
      scrub(60)
      elapsed = timed do
        GC.start
        GC.start
      end
      puts "sleeping collected=#{sleeping.size == 0} bounded=#{elapsed < 3.0}"
      napper.join
    RUBY

    _(result).must_answer <<~'OUT'
      busy collected=true bounded=true
      1
      sleeping collected=true bounded=true
    OUT
  end

  it "define finalizer runs at gc for a collected object" do
    result = ze0(<<~'RUBY')
      def register = ObjectSpace.define_finalizer(Object.new, proc { |id| puts "collected" })
      register
      GC.start
      puts "after gc"
    RUBY

    _(result).must_answer <<~'OUT'
      collected
      after gc
    OUT
  end

  it "disabled collector grows the heap" do
    result = ze0(<<~'RUBY')
      # While GC.disable holds, the heap grows instead of collecting when its
      # cells run out, so GC.count does not move; GC.enable lets it collect
      # again.
      p GC.disable
      before = GC.count
      kept = Array.new(300_000) { Object.new }
      p GC.count == before, kept.size
      p GC.disable
      p GC.enable, GC.enable
      GC.start
      p GC.count > before

    RUBY

    _(result).must_answer <<~'OUT'
      false
      true
      300000
      true
      true
      false
      true
    OUT
  end

  it "empty array cycle" do
    result = ze0(<<~'RUBY')
      p([].cycle(2) { |x| p x })
      p([].cycle { |x| p x })
      p([].cycle(0).to_a)
      p([].cycle(2).class)
      v = [].cycle(2).to_a
      p v
      p([1].cycle(2) { |x| p x })
    RUBY

    _(result).must_answer <<~'OUT'
      nil
      nil
      []
      Enumerator
      []
      1
      1
      nil
    OUT
  end

  it "enumerable zip compact cycle chain over range and hash" do
    result = ze0(<<~'RUBY')
      p (1..3).zip([4, 5, 6], [7, 8, 9])
      p (1..5).compact
      p (1..3).chain([4, 5]).to_a
      seen = []
      (1..3).cycle(2) { |x| seen << x }
      p seen
      p({ a: 1, b: 2 }.zip([10, 20]))
      p({ a: 1 }.rehash)
      p "hello".tr_s("l", "r")
      p "aabbcc".tr_s("a-c", "x")
      s = "hello"
      p s.tr_s!("l", "r")
      p s
      p "clean".scrub!
    RUBY

    _(result).must_answer <<~'OUT'
      [[1, 4, 7], [2, 5, 8], [3, 6, 9]]
      [1, 2, 3, 4, 5]
      [1, 2, 3, 4, 5]
      [1, 2, 3, 1, 2, 3]
      [[[:a, 1], 10], [[:b, 2], 20]]
      {a: 1}
      "hero"
      "x"
      "hero"
      "hero"
      "clean"
    OUT
  end

  it "enumerator cycle size" do
    result = ze0(<<~'RUBY')
      p [1, 2].cycle.size
      p [1, 2].cycle(2).size
      p [1, 2].cycle(0).size
      p [].cycle.size
    RUBY

    _(result).must_answer <<~'OUT'
      Infinity
      4
      0
      0
    OUT
  end

  it "fiber capture no leak to sibling" do
    result = ze0(<<~'RUBY')
      # #564 (Ori Pekelman). Fiber.new block bodies that capture a
      # local push a `_hcell_<name>_<n>` entry onto
      # @heap_promoted_names so the capturing function's emit sees
      # `(*_hcell_<name>_<n>)` instead of `lv_<name>`. The list was
      # never reset at method boundaries, so a sibling method
      # defined later in the same compilation unit (e.g. a top-level
      # `def do_work(client)` called from inside the fiber body)
      # also saw `(*_hcell_<name>_<n>)` in its own body emit and
      # the link failed with `'_hcell_<name>_0' undeclared`.
      #
      # Fix: save / restore @heap_promoted_names length around each
      # top-level method body emit so the cells only live in the
      # C scope that actually allocates them.

      def spawn_for(client)
        f = Fiber.new do
          do_work(client)
        end
        f
      end

      def do_work(client)
        puts "client=" + client.to_s
      end

      f = spawn_for(42)
      f.resume
    RUBY

    _(result).must_answer "client=42\n"
  end

  it "finalizer runs after a collection the program did not ask for" do
    result = ze0(<<~'RUBY')
      # A finalizer runs once its object is collected, whether the program
      # called GC.start or the allocator collected on its own: ruby runs it
      # at the next safe point after the collection, so a program that waits
      # for one sees it before it exits.

      $collected = 0
      def register = ObjectSpace.define_finalizer(Object.new, proc { |_id| $collected += 1 })
      register
      rounds = 0
      while $collected == 0 && rounds < 2_000
        Array.new(10_000) { Object.new }
        rounds += 1
      end
      p $collected
      p rounds < 2_000


    RUBY

    _(result).must_answer <<~'OUT'
      1
      true
    OUT
  end

  it "gc churn" do
    result = ze0(<<~'RUBY')
      # Allocation and collection under the linked runtime: the heap survives a
      # forced collection and the surviving objects keep their contents.
      kept = []
      2000.times { |i| kept << "row #{i}" if (i % 200).zero? }
      20_000.times { "garbage".dup }
      GC.start
      p kept
      puts kept.size
    RUBY

    _(result).must_answer <<~'OUT'
      ["row 0", "row 200", "row 400", "row 600", "row 800", "row 1000", "row 1200", "row 1400", "row 1600", "row 1800"]
      10
    OUT
  end

  it "gc count after start" do
    result = ze0(<<~'RUBY')
      # GC.count is the number of GCs run and GC.stat carries a :count key; after
      # an explicit GC.start both must be positive. zeo answers 0 and its stat hash
      # has no :count row.
      GC.start
      puts (GC.count > 0).inspect
      puts GC.stat.key?(:count).inspect
      puts GC.stat(:count).class
    RUBY

    _(result).must_answer <<~'OUT'
      true
      true
      Integer
    OUT
  end

  it "gc enable disable previous state" do
    result = ze0(<<~'RUBY')
      p GC.disable
      p GC.disable
      p GC.enable
      p GC.enable
    RUBY

    _(result).must_answer <<~'OUT'
      false
      true
      true
      false
    OUT
  end

  it "gc full cycle space bound" do
    result = ze0(<<~'RUBY', path: "core/gc/gc_full_cycle_space_bound.rb")
      # The adaptive full-cycle interval bounds the TIME between full sweeps and
      # nothing bounded the SPACE. Once the cadence has ratcheted up, a phase that
      # promotes heavily piles garbage onto an old list nothing walks: full_runs
      # stops, old_bytes climbs to many times the live set, and the object threshold
      # retunes off that inflated total (#4076). Two phases are needed -- the first
      # ratchets the cadence honestly, the second changes the promotion rate under it.
      RETAIN = 1_000
      WARM   = 20_000
      N      = 8_000
      HOLD   = 16
      ITERS  = 40

      retained = []
      RETAIN.times { |i| retained.push(Array.new(64, i * 1.0)) }
      WARM.times { Array.new(64, 0.0) }

      ITERS.times do |i|
        bufs = []
        HOLD.times { |h| bufs.push(Array.new(N, h * 1.0)) }
        j = 0
        while j < N
          bufs[j % HOLD][j] += 1.0
          j += 397
        end
        bufs = nil
      end

      # Before the space bound this run reached full=5 with old at 14.7 MB; with it,
      # full=8 and old at 5.9 MB against a live set of about 1 MB.
      g = GC.stat
      puts "live set: " + retained.length.to_s
      puts "full sweeps kept running: " + (g["full_runs"] > 6 ? "yes" : "no")
      puts "old generation bounded: " + (g["old_bytes"] < 10_000_000 ? "yes" : "no")
    RUBY

    _(result).must_answer "live set: 1000\n", stderr: "core/gc/gc_full_cycle_space_bound.rb:32:in '<main>': undefined method '>' for nil (NoMethodError)\n\nputs \"full sweeps kept running: \" + (g[\"full_runs\"] > 6 ? \"yes\" : \"no\")\n                                                    ^\n", status: 1
  end

  it "gc latest gc info key" do
    result = ze0(<<~'RUBY')
      GC.start
      p GC.latest_gc_info(:major_by).class
      p GC.latest_gc_info(:state).class
    RUBY

    _(result).must_answer <<~'OUT'
      Symbol
      Symbol
    OUT
  end

  it "gc mark stack growth" do
    result = ze0(<<~'RUBY')
      # A live set far larger than the mark stack's initial size (1024 cells):
      # the walk has to stay iterative rather than recursing per object.
      heap = []
      20_000.times { |i| heap << [i, i * 2] }
      GC.start
      p heap.size
      p heap[0]
      p heap[19_999]
      p heap.sum { |pair| pair[1] } == 20_000 * 19_999

    RUBY

    _(result).must_answer <<~'OUT'
      20000
      [0, 0]
      [19999, 39998]
      true
    OUT
  end

  it "gc poly local int" do
    result = ze0(<<~'RUBY')
      # A poly local holding a non-pointer (int) value must be marked
      # tag-aware: rooting routes through sp_mark_rbval, which skips INT
      # rather than dereferencing the boxed integer as a pointer.
      class A; def v; 1; end; end
      def churn(k); s = ""; i = 0; while i < k; s = s + i.to_s + ","; i += 1; end; s.length; end
      arr = [A.new, 100 + 1]
      x = arr[1]
      GC.start
      churn(8000)
      GC.start
      p x
    RUBY

    _(result).must_answer "101\n"
  end

  it "gc poly local root" do
    result = ze0(<<~'RUBY')
      # A poly (sp_RbVal) local assigned from a method whose return type
      # unifies to poly must be GC-rooted, or a collection while it's live
      # frees the object it holds (use-after-free).
      class A; def v=(x); @v = x; end; def v; @v; end; end
      class B; def v=(x); @v = x; end; def v; @v; end; end
      def pick(n)
        if n == 0
          A.new
        else
          B.new
        end
      end
      def churn(k); s = ""; i = 0; while i < k; s = s + i.to_s + ","; i += 1; end; s.length; end
      obj = pick(1)
      obj.v = "keep_" + 5.to_s
      GC.start
      churn(8000)
      GC.start
      puts obj.v
    RUBY

    _(result).must_answer "keep_5\n"
  end

  it "gc poly local setjmp" do
    result = ze0(<<~'RUBY')
      # A poly local live across a rescue (setjmp scope) with a GC: it must
      # be both volatile (longjmp-stable) and GC-rooted.
      class A; def v=(x); @v = x; end; def v; @v; end; end
      class B; def v=(x); @v = x; end; def v; @v; end; end
      def pick(n); n == 0 ? A.new : B.new; end
      def churn(k); s = ""; i = 0; while i < k; s = s + i.to_s + ","; i += 1; end; s.length; end
      obj = pick(1)
      obj.v = "keep_" + 9.to_s
      begin
        GC.start
        churn(8000)
        raise "boom"
      rescue => e
        GC.start
      end
      puts obj.v
    RUBY

    _(result).must_answer "keep_9\n"
  end

  it "gc root call args" do
    result = ze0(<<~'RUBY')
      # Regression for #1057: a call's argument temporaries must stay GC-
      # rooted across evaluation of its sibling arguments. Each case puts a
      # fresh heap string in the slot gcc evaluates first (the last one)
      # beside a sibling whose evaluation triggers a collection. Without
      # rooting, the fresh string is freed mid-call and the callee reads
      # reused/garbage memory.

      def churn_gc(x)
        GC.start
        i = 0
        s = ""
        while i < 8000
          s = s + i.to_s + ","
          i += 1
        end
        x
      end

      def join2(a, b)
        a + "|" + b
      end

      class Joiner
        def join2(a, b)
          a + "|" + b
        end
      end

      # top-level method call
      puts join2(churn_gc("A"), "B_" + 1.to_s)
      # instance method call
      puts Joiner.new.join2(churn_gc("C"), "D_" + 2.to_s)
      # sprintf / string interpolation
      label = "E"
      puts "[#{churn_gc("F")}|#{label + "_" + 3.to_s}]"
    RUBY

    _(result).must_answer <<~'OUT'
      A|B_1
      C|D_2
      [F|E_3]
    OUT
  end

  it "gc root heap param" do
    result = ze0(<<~'RUBY')
      # A heap-typed (poly / string) method parameter must stay GC-rooted
      # across a collection triggered inside the method, so a later read of it
      # (e.g. sp_poly_to_s in a %s interpolation arg) is not a use-after-free.
      # Regression for #1068 (follow-up to #1057).
      def gc_then
        GC.start
        i = 0
        s = ""
        while i < 6000
          s = s + i.to_s + ","
          i += 1
        end
        "G"
      end

      def wrap(body)
        "#{gc_then}-#{body}"
      end

      wrap(42)                  # int call site forces `body` to a poly param
      puts wrap("P_" + 7.to_s)  # string call site
    RUBY

    _(result).must_answer "G-P_7\n"
  end

  it "gc rooted builders" do
    result = ze0(<<~'RUBY')
      # GC roots for runtime array builders and their string arguments. Each of
      # these allocates per element while building (or while walking a pattern
      # that is itself a fresh unrooted interpolation temp), so enough entries
      # trigger a collection MID-BUILD: the result array, its pushed names, or
      # the argument string got swept under the walk (spin test crashed with
      # double-free/SIGSEGV once test/ held ~50 files).
      dir = "gc_glob_probe.tmp"
      Dir.mkdir(dir) unless Dir.exist?(dir)
      80.times { |i| File.write("#{dir}/t#{i}.rb", "puts 1\n") }

      # Dir.glob through a fresh interpolated pattern (the #2178 shape)
      names = Dir.glob("#{dir}/*.rb")
      puts names.length
      puts names.include?("#{dir}/t79.rb")

      # Dir.entries on the same tree
      puts Dir.entries(dir).length

      80.times { |i| File.delete("#{dir}/t#{i}.rb") }
      Dir.rmdir(dir)

      # scan: many matches from a fresh temp receiver
      puts ("ab " * 500).scan(/a./).length
      puts ("x1 y2 " * 300).scan(/([a-z])(\d)/).length

      # rpartition via regexp on a fresh temp
      p ("k-" * 200 + "end").rpartition(/k-/)[2]

      # combination/repeated_combination allocate one array per emitted row
      puts (1..9).to_a.combination(4).to_a.length
      puts [1, 2, 3, 4].repeated_combination(4).to_a.length
    RUBY

    _(result).must_answer <<~'OUT'
      80
      true
      82
      500
      600
      "end"
      126
      35
    OUT
  end

  it "gc stat answers every key ruby names" do
    result = ze0(<<~'RUBY')
      # GC.stat answers every key CRuby's collector names, in its order, fills a
      # Hash it is given, and refuses a key it does not know.
      stats = GC.stat
      p stats.keys
      p stats.values.all?(Integer)
      p stats[:heap_available_slots] >= stats[:heap_live_slots]
      p stats[:total_allocated_objects] >= stats[:total_freed_objects]
      into = {}
      p GC.stat(into).equal?(into), into.size == stats.size
      p GC.stat(:count).class
      p((GC.stat(:nope) rescue $!))
      p((GC.stat("count") rescue $!))

    RUBY

    _(result).must_answer <<~'OUT'
      [:count, :time, :marking_time, :sweeping_time, :heap_allocated_pages, :heap_empty_pages, :heap_allocatable_slots, :heap_available_slots, :heap_live_slots, :heap_free_slots, :heap_final_slots, :heap_marked_slots, :heap_eden_pages, :total_allocated_pages, :total_freed_pages, :total_allocated_objects, :total_freed_objects, :malloc_increase_bytes, :malloc_increase_bytes_limit, :minor_gc_count, :major_gc_count, :compact_count, :read_barrier_faults, :total_moved_objects, :remembered_wb_unprotected_objects, :remembered_wb_unprotected_objects_limit, :old_objects, :old_objects_limit, :oldmalloc_increase_bytes, :oldmalloc_increase_bytes_limit]
      true
      true
      true
      true
      true
      Integer
      #<ArgumentError: unknown key: nope>
      #<TypeError: non-hash or symbol given>
    OUT
  end

  it "gc threshold no runaway" do
    result = ze0(<<~'RUBY', path: "core/gc/gc_threshold_no_runaway.rb")
      # The collector recomputes its live-byte counter from the live set and THEN
      # sweeps, so a dead object's finalizer subtracted buffer bytes the fresh total
      # had never counted. Churning large arrays walked the counter below zero; the
      # retune read the wrapped value and set a threshold near SIZE_MAX, after which
      # `bytes >= threshold` never fires again -- the collector switched itself off
      # for the life of the process and RSS grew without bound (#4073).
      #
      # The live set here is a handful of tiny pairs. What matters is that the
      # threshold stays a real number and the heap stays bounded. GC.stat's keys are
      # spinel's own, like gc_stat_string_heap.rb's.
      N     = 20_000
      ITERS = 400

      live = []
      ITERS.times do |i|
        s = Array.new(N, 0.0)
        sbin = Array.new(N, 0)
        cnt = Array.new(256, 0)
        j = 0
        while j < N
          b = (j & 255)
          sbin[j] = b
          s[j] = b * 0.5
          cnt[b] += 1
          j += 197
        end
        live.push([cnt[0], s[0]]) if (i % 64).zero?
      end

      g = GC.stat
      puts "retained: " + live.length.to_s
      puts "threshold positive: " + (g["threshold"] > 0 ? "yes" : "no")
      puts "collector still running: " + (g["cycle"] > 8 ? "yes" : "no")
      puts "heap bounded: " + (g["bytes"] < 400_000_000 ? "yes" : "no")
    RUBY

    _(result).must_answer "retained: 7\n", stderr: "core/gc/gc_threshold_no_runaway.rb:32:in '<main>': undefined method '>' for nil (NoMethodError)\n\nputs \"threshold positive: \" + (g[\"threshold\"] > 0 ? \"yes\" : \"no\")\n                                              ^\n", status: 1
  end

  it "generator element cycle" do
    result = ze0(<<~'RUBY')
      # An extension-field element is a fixed-width array of field elements, and its
      # add is a generator over the two operands. The generator's own value comes
      # from the very methods its result feeds, so answering "array of anything" on
      # the round before those settle makes the accumulator poly, which makes these
      # parameters poly, which makes `a[i]` poly -- and the cycle has no way back to
      # the Integer array it really is.
      module F
        def self.add(a, b)
          (a + b) % 97
        end
      end

      module E
        def self.zero
          [0, 0, 0, 0]
        end

        def self.add(a, b)
          Array.new(4) { |i| F.add(a[i], b[i]) }
        end

        def self.scale(a, s)
          Array.new(4) { |i| F.add(a[i], s) }
        end
      end

      def run(n, alphas)
        acc = E.zero
        i = 0
        while i < n
          acc = E.add(acc, E.scale(alphas[i % alphas.length], i))
          i += 1
        end
        acc
      end

      alphas = Array.new(3) { |k| [k, k + 1, k + 2, k + 3] }
      p run(50, alphas)
    RUBY

    _(result).must_answer "[13, 63, 16, 66]\n"
  end

  it "heap grows past its first arena table" do
    result = ze0(<<~'RUBY')
      # The arena table doubles when full, so a heap of more arenas than the
      # table first held keeps every object, and the count of slots follows.
      # A collection at every allocation (ZR_GC_STRESS) checks the roots over
      # a heap small enough to finish.
      n = ENV["ZR_GC_STRESS"] ? 20_000 : 2_200_000
      strings = Array.new(n) { |i| i.to_s }
      before = GC.stat[:heap_available_slots]
      p strings.size == n, strings[0], strings[n / 2] == (n / 2).to_s, strings[-1] == (n - 1).to_s
      p strings.each_with_index.all? { |s, i| s == i.to_s }
      p GC.stat[:heap_available_slots] >= before
      strings = nil
      GC.start
      p GC.stat[:count] > 0

    RUBY

    _(result).must_answer <<~'OUT'
      true
      "0"
      true
      true
      true
      true
      true
    OUT
  end

  it "include validates module and cycles" do
    result = ze0(<<~'RUBY')
      # `include` validates: a Class argument is a TypeError ("wrong argument
      # type Class (expected Module)") and a cyclic or self include is an
      # ArgumentError ("cyclic include detected"). zeo accepts all three
      # silently. (Found by the 2026-08-24 probe sweep.)
      begin
        Class.new.include(Class.new)
        puts "class included"
      rescue TypeError => e
        puts e.message
      end
      m = Module.new
      n = Module.new { include m }
      begin
        m.include(n)
        puts "cycle included"
      rescue ArgumentError => e
        puts e.message
      end
      begin
        m.include(m)
        puts "self included"
      rescue ArgumentError => e
        puts e.message
      end
    RUBY

    _(result).must_answer <<~'OUT'
      wrong argument type Class (expected Module)
      cyclic include detected
      cyclic include detected
    OUT
  end

  it "inspect result survives gc" do
    result = ze0(<<~'RUBY')
      # An #inspect built in a temporary string builder must hand back a string of
      # its own, not the builder's buffer.
      #
      # The builders are sp_String objects; their buffer carries the 0xfd marker,
      # which tells sp_gc_mark "the owner holds this, skip it". Once the helper
      # returns, nothing holds the owner: the builder is unreachable, the next
      # collection frees it, and the `const char *` the caller rooted points at freed
      # memory. Holding the result across a GC.start read it back.

      def churn
        a = []
        300.times { |i| a.push("filler #{i}") }
        a.length
      end

      def through_gc(s)
        churn
        GC.start
        churn
        GC.start
        s
      end

      p through_gc("abc".match(/b/).inspect)
      p through_gc([[1, 2], [3]].inspect)
      p through_gc([["a"], ["b"]].inspect)
      p through_gc([[1.5], [2.5]].inspect)
      p through_gc([[:a], [:b]].inspect)
      p through_gc([[1, "x"], [nil]].inspect)
      p through_gc({ 1 => 2, 3 => 4 }.inspect)

      # the same result kept in a container rather than a local
      box = []
      box.push("a1b2".match(/(\d)(\w)/).inspect)
      box.push([[7, 8]].inspect)
      churn
      GC.start
      churn
      GC.start
      p box
    RUBY

    _(result).must_answer <<~'OUT'
      "#<MatchData \"b\">"
      "[[1, 2], [3]]"
      "[[\"a\"], [\"b\"]]"
      "[[1.5], [2.5]]"
      "[[:a], [:b]]"
      "[[1, \"x\"], [nil]]"
      "{1 => 2, 3 => 4}"
      ["#<MatchData \"1b\" 1:\"1\" 2:\"b\">", "[[7, 8]]"]
    OUT
  end

  it "payloads envs and blocks under pressure" do
    result = ze0(<<~'RUBY')
      # Large payloads, kept Envs, escaped blocks, kept each adapters and
      # Struct values together across many collections keep their contents.
      Point = Struct.new(:x, :y)
      keepers = []
      adapters = []
      class Bag
        include Enumerable
        def each(&b) = (@b = b; [1, 2, 3].each(&b))
        def replay = [4].each(&@b)
      end
      big = []
      200.times do |i|
        s = "x" * 100_000
        s << i.to_s
        big << s if i % 20 == 0
        keepers << proc { |v| [i, v, s.size] } if i % 50 == 0
        bag = Bag.new
        bag.select { |v| v > 1 }
        adapters << bag if i % 50 == 0
        Point.new(i, [i] * 1000)
        Array.new(5000) { |k| k.to_s }
      end
      GC.start
      p big.map(&:size), big.map { |s| s[-3..] }, keepers.map { |k| k.call(7) }, adapters.map(&:replay)
      p GC.stat[:count] > 3, Point.new(1, 2).to_a, keepers.size, ObjectSpace.each_object(Bag).count >= 4
      pairs = (1..50_000).map { |i| [i, i.to_s] }
      h = pairs.to_h
      GC.start
      p h.size, h[25_000], h.keys.sum, pairs.last, h.select { |k, v| k % 10_000 == 0 }.keys

    RUBY

    _(result).must_answer <<~'OUT'
      [100001, 100002, 100002, 100002, 100002, 100003, 100003, 100003, 100003, 100003]
      ["xx0", "x20", "x40", "x60", "x80", "100", "120", "140", "160", "180"]
      [[0, 7, 100001], [50, 7, 100002], [100, 7, 100003], [150, 7, 100003]]
      [[4], [4], [4], [4]]
      true
      [1, 2]
      4
      true
      50000
      "25000"
      1250025000
      [50000, "50000"]
      [10000, 20000, 30000, 40000, 50000]
    OUT
  end

  it "poly dispatch recv gc root" do
    result = ze0(<<~'RUBY')
      # The receiver temporary of a polymorphic send (the `switch (cls_id)`
      # dispatch) must be GC-rooted: it can be the only live reference to the
      # receiver, methods do not root their own self, and a collection triggered
      # by allocation inside the callee then frees the receiver while its method
      # is still running (#3476). Each go/add below collects and then allocates
      # before reading an ivar, so the freed receiver's storage is handed out
      # again and the stale read is a crash rather than a value that happens to
      # survive -- without the second step this passes on Linux either way and
      # only ASAN or macOS sees the use-after-free.
      class Holder
        def initialize(params = {})
          @params = params
        end

        def go
          GC.start                                   # frees the unrooted receiver
          junk = Array.new(64) { |j| Holder.new(k: [j]) }   # hands its slot out again
          (@params[:k] || []).length + junk.length - 64
        end

        def add(x)
          GC.start
          junk = Array.new(64) { |j| Holder.new(k: [j]) }
          (@params[:k] || []).length + x + junk.length - 64
        end
      end

      class Other
        def go
          0
        end

        def add(x)
          x
        end
      end

      def pick
        return Other.new if false  # gives the call site a union receiver type
        Holder.new(k: [1, 2, 3])
      end

      r = 0
      i = 0
      while i < 50
        r += pick.go               # receiver lives only as the dispatch temporary
        r += pick.add(10)          # same, through the with-args dispatch
        i += 1
      end
      puts "ok r=#{r}"
    RUBY

    _(result).must_answer "ok r=800\n"
  end

  it "poly each receiver gc root" do
    result = ze0(<<~'RUBY')
      # The poly (runtime-dispatch) `each` codegen stored the iterated
      # collection in an unrooted temp:
      #
      #     sp_RbVal _t = <receiver>;   // e.g. a method that builds an array
      #     for (...) sp_PtrArray_get((sp_PtrArray *)_t.v.p, i) ...
      #
      # When the receiver is a freshly built heap array referenced only by
      # that temp (the `@article.comments` shape -- a new PtrArray of records)
      # and the loop body allocates, a GC firing mid-iteration freed the
      # unrooted array; the next element fetch then read a dangling pointer,
      # surfacing as a SIGSEGV in sp_obj_cls_id_of under load. The GC.start
      # inside the loop makes that collection deterministic here.
      class Box
        def initialize(name); @name = name; end
        def name; @name; end
        def rename(x); @name = x; end   # self-mutating -> heap, not a value type
      end

      class Bag
        def initialize; @items = []; end
        def add(b); @items.push(b); end

        # Build a FRESH array on every call; the ternary widens the return
        # type to poly so `each` takes the runtime-dispatch codegen path.
        def items
          fresh = []
          @items.each { |x| fresh.push(x) }
          fresh.empty? ? [] : fresh
        end
      end

      bag = Bag.new
      5.times { |i| bag.add(Box.new("item-" + i.to_s)) }

      out = []
      bag.items.each do |b|
        GC.start          # collect mid-iteration; unrooted receiver array freed here
        out.push(b.name)
      end
      puts out.join(",")
    RUBY

    _(result).must_answer "item-0,item-1,item-2,item-3,item-4\n"
  end

  it "poly gc" do
    result = ze0(<<~'RUBY')
      class Trash
        def initialize(n)
          @n = n
          @s = "padding payload " * 64
        end
      end

      class Holder
        def initialize(value)
          @value = value
        end

        attr_reader :value
      end

      def make_poly_array
        value = "array-" + 123.to_s
        [value, 1]
      end

      def make_holder
        value = "ivar-" + 456.to_s
        Holder.new(value)
      end

      values = make_poly_array
      holder = make_holder
      Holder.new(1)

      junk = []
      i = 0
      while i < 5000
        junk << Trash.new(i)
        i = i + 1
      end

      puts junk.length
      puts values[0]
      puts holder.value
    RUBY

    _(result).must_answer <<~'OUT'
      5000
      array-123
      ivar-456
    OUT
  end

  it "proc call blk gc root" do
    result = ze0(<<~'RUBY')
      # Regression for the sp_proc_call heap-use-after-free: a method keeping a real
      # &blk param (no yield -- the dead Thread.new branch capturing blk forces the
      # escaping sp_Proc path) held the proc box only in an untracked C parameter,
      # and the call site's hoisted proc temp was unrooted too. A GC inside the
      # block body then swept the box and the next blk.call read freed memory.
      # Both call shapes are covered: a toplevel def and a module class method
      # (they lower the &blk argument through different codegen paths).

      def each_i(n, &blk)
        Thread.new { blk.call(0) }.join if n < 0
        i = 0
        while i < n
          blk.call(i)
          i += 1
        end
      end

      module Parallel
        def self.each_index(n, &blk)
          Thread.new { blk.call(0) }.join if n < 0
          i = 0
          while i < n
            blk.call(i)
            i += 1
          end
        end
      end

      acc = Array.new(5, 0.0)
      each_i(5) do |i|
        GC.start
        acc[i] += 1.5 * i
      end
      Parallel.each_index(5) do |i|
        GC.start
        acc[i] += 2.5 * i
      end
      tot = 0.0
      i = 0
      while i < 5; tot += acc[i]; i += 1; end
      puts "tot=#{tot}"
    RUBY

    _(result).must_answer "tot=40.0\n"
  end

  it "proc return catch no leak" do
    result = ze0(<<~'RUBY')
      # A non-local return out of a `catch` block must restore the catch stack as it
      # unwinds home, so the catch slot is not leaked. A later `throw` with no live
      # catch must raise UncaughtThrowError rather than matching the stale slot and
      # longjmping into the home method's freed frame.
      def home
        pr = proc { return 1 }
        catch(:tag) do
          pr.call
        end
        :done
      end
      p home
      begin
        throw :tag, 5
        puts "WRONG: no error"
      rescue => e
        puts "uncaught: #{e.class}"
      end
    RUBY

    _(result).must_answer <<~'OUT'
      1
      uncaught: UncaughtThrowError
    OUT
  end

  it "range cycle block" do
    result = ze0(<<~'RUBY')
      # Range#cycle block form: the counted form repeats the materialized int
      # range n times; the argless form cycles forever until a block break.
      # (cycle joined the range->int-array redispatch list, and the array cycle
      # emitter now serves the argless endless form too.)
      a = []
      (1..3).cycle(2) { |x| a << x }
      p a

      b = []
      (0...3).cycle(1) { |x| b << x * 10 }
      p b

      n = 0
      (1..5).cycle { |x| n += x; break if n > 20 }
      p n

      # argless Array#cycle (the same emitter gap)
      m = 0
      [1, 2, 3].cycle { |x| m += x; break if m > 10 }
      p m
    RUBY

    _(result).must_answer <<~'OUT'
      [1, 2, 3, 1, 2, 3]
      [0, 10, 20]
      21
      12
    OUT
  end

  it "sequential top level begin blocks do not leak handling state" do
    result = ze0(<<~'RUBY')
      # Guards `zeo_rt::handling`'s push/pop discipline: three INDEPENDENT
      # `begin` blocks in sequence, the last a bare re-raise with nothing
      # currently being handled -- if an earlier block's `pop_handling` were
      # ever skipped (e.g. on an unusual exit path), this would incorrectly
      # re-raise a STALE exception instead of falling back to a fresh
      # `RuntimeError`.

      begin
        raise "first"
      rescue => e
        puts "1: #{e.send(:message)}"
      end
      begin
        raise "second"
      rescue => e
        puts "2: #{e.send(:message)}"
      end
      begin
        raise
      rescue => e
        puts "3: [#{e.send(:message)}]"
      end
    RUBY

    _(result).must_answer <<~'OUT'
      1: first
      2: second
      3: []
    OUT
  end

  it "std stream singleton gc" do
    result = ze0(<<~'RUBY')
      # A standard stream stored into a GC-scanned slot.
      #
      # The three standard streams are singletons in static storage, not GC
      # allocations. Reads of $stdout / $stderr compile straight to the accessor and
      # only ever dereference the result, so nothing scanned ever held one -- until
      # an assignment stores it into a real global slot, which the globals hook
      # marks. The collector decides what a pointer is from the byte before it, found
      # whatever .bss happened to sit there, fabricated a header and called the scan
      # pointer read out of it.
      #
      # Whether that faults is luck: the byte before is whatever the linker put
      # there. This test is deterministic anyway -- SPINEL_GC_VERIFY names the object
      # on the mark path regardless of whether the walk survives.

      $stderr = $stdout
      GC.start
      puts "stderr assigned"

      $stdout = $stderr
      GC.start
      puts "stdout assigned"

      # a collection with real garbage to sweep, so the mark walk is not trivial
      1000.times { |i| s = "row #{i}" ; s.upcase }
      GC.start
      puts "after churn"

      # the streams still work as streams
      $stderr.puts "written"
      $stdout.flush
      p $stderr == $stdout

      # a stream held in an ordinary local and an array survives a collection too:
      # the same pointer, now reachable from a scanned container
      out = $stdout
      box = [$stdout, $stderr]
      GC.start
      out.puts "through a local"
      p box.length
    RUBY

    _(result).must_answer <<~'OUT'
      stderr assigned
      stdout assigned
      after churn
      written
      true
      through a local
      2
    OUT
  end

  it "struct inspect cycle" do
    result = ze0(<<~'RUBY')
      # The cycle this program builds on purpose, and the census it leaves
      # behind. A cycle alive at exit is not a defect: it is a ring the
      # program never broke, so the census below is recorded as an
      # observation rather than gated on.
      #
      # A Struct holding itself, which is what the golden inspects.
      # At exit: cycle leak: 1 objects (S x1)
      S = Struct.new(:x)
      s = S.new(nil)
      s.x = s
      p s
    RUBY

    _(result).must_answer "#<struct S x=#<struct S:...>>\n"
  end

  it "weakmap prunes a collected key at gc" do
    result = ze0(<<~'RUBY')
      # A key with no other strong reference is pruned once collected.

      m = ObjectSpace::WeakMap.new
      m[Object.new] = "gone"
      GC.start
      p m.keys.length
      p m.length
      # an immediate key is held strongly and never expires; keep the value
      # strongly referenced so only key liveness is under test
      m2 = ObjectSpace::WeakMap.new
      val = Object.new
      m2[42] = val
      GC.start
      p m2[42].equal?(val)
    RUBY

    _(result).must_answer <<~'OUT'
      0
      0
      true
    OUT
  end
end
