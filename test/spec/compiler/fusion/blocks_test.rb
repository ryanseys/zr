# frozen_string_literal: true

require "spec_helper"

describe "Fusion: blocks and yields" do
  it "block forward recv typed" do
    _(ze0(<<~'RUBY')).must_answer "1-basic\n42\n3-mixed\n  body\n4-thrice\n4-thrice\n4-thrice\n5-arg=7\n150\n7-no-block\ndone\n"
      # Typed-receiver `recv.m { ... }` &block forwarding (Site B).
      #
      # Pre-fix `compile_object_method_expr` dropped the literal block: the
      # call site emitted `sp_Cls_m(rc, 0)` and the binary segfaulted inside
      # `sp_proc_call(NULL, ...)`. Fix: precompute `has_proc` from the
      # callee's param types, pass it to `compile_typed_call_args` as the
      # new `omit_trailing` 4th arg so the &block slot isn't padded with
      # "0", then build a `bp`/`tail` that appends the proc literal after
      # the regular args.

      # 1. Basic: `recv.m { ... }` with arity-0 block.call.
      class App
        def run(&block)
          block.call
        end
      end

      App.new.run { puts "1-basic" }

      # 2. block.call with one int arg, return value used.
      class Doubler
        def apply(x, &block)
          block.call(x)
        end
      end

      puts Doubler.new.apply(21) { |n| n * 2 }

      # 3. Mixed: regular arg + &block, multiple stmts in method body.
      class Logger
        def log(label, &block)
          puts label
          block.call
        end
      end

      Logger.new.log("3-mixed") { puts "  body" }

      # 4. Block invoked multiple times from inside the method.
      class Repeater
        def thrice(&block)
          block.call
          block.call
          block.call
        end
      end

      Repeater.new.thrice { puts "4-thrice" }

      # 5. Block uses interpolation of its own argument. (Closure capture
      #    over outer locals is a separate subsystem — out of scope here.)
      class Wrapper
        def go(n, &block)
          block.call(n)
        end
      end

      Wrapper.new.go(7) { |i| puts "5-arg=#{i}" }

      # 6. Block returns a value used by the method.
      class Picker
        def pick(&block)
          block.call(10) + block.call(20)
        end
      end

      puts Picker.new.pick { |n| n * 5 }

      # 7. Method declares &block, call site provides none. The &block
      #    slot must be filled with NULL — pre-fix `omit_trailing` dropped
      #    the slot from the C call entirely, leaving an arity mismatch
      #    between sp_Optional_maybe(sp_Optional *, sp_Proc *) and
      #    sp_Optional_maybe(_t1).
      class Optional
        def maybe(&block)
          puts "7-no-block"
        end
      end

      Optional.new.maybe

      puts "done"
    RUBY
  end

  it "block given inline call site" do
    result = ze0(<<~'RUBY')
      # Issue #706: block_given? in a yield-using method, called from
      # a site that either omits the block (zero-arg case emits
      # `sp_f(NULL, NULL)`) or supplies a literal block (inline path
      # correctly answers true).
      def f
        puts block_given?
      end
      f
      f { }
    RUBY

    _(result).must_answer <<~'OUT'
      false
      true
    OUT
  end

  it "block next nil typed map" do
    result = ze0(<<~'RUBY')
      # A bare `next` yields nil, even when the block's tail is typed.
      p [1, 2, 3].map { |v| next if v == 2; v }
      p ["a", "b"].map { |v| next if v == "a"; v }
      p [1.5, 2.5].map { |v| next if v > 2; v }
      p 5.times.map { |v| next if v.even?; v }
      p [1, 2, 3].map { |v| next if v == 2; v }.compact
      p({ a: 1, b: 2 }.map { |k, v| next if v == 1; k })

      def each_val
        yield 1
        yield 2
      end
      r = []
      each_val { |v| next if v == 1; r << v }
      p r

      f = proc { |x| next if x; :kept }
      p f.call(true), f.call(false)
      p (1..4).map { |v| next if v == 3; v * 2 }
      p 1.upto(3).map { |v| next if v == 1; v }
    RUBY

    _(result).must_answer <<~'OUT'
      [1, nil, 3]
      [nil, "b"]
      [1.5, nil]
      [nil, 1, nil, 3, nil]
      [1, 3]
      [nil, :b]
      [2]
      nil
      :kept
      [2, 4, nil, 8]
      [nil, 2, 3]
    OUT
  end

  it "fiber yield inside an inline times block" do
    result = ze0(<<~'RUBY')
      f = Fiber.new do
        3.times do |i|
          Fiber.yield i
        end
        :end
      end
      puts f.resume
      puts f.resume
      puts f.resume
      puts f.resume
    RUBY

    _(result).must_answer <<~'OUT'
      0
      1
      2
      end
    OUT
  end

  it "fused block resets its own locals" do
    result = ze0(<<~'RUBY')
      # A name first assigned INSIDE a fused block is fresh on every iteration,
      # even though the splice shares the enclosing scope where it was hoisted.
      out = []
      3.times do |i|
        x = i if i.odd?
        out << x
      end
      p out
      res = []
      (1..4).each do |i|
        seen = true if i > 2
        res << [i, seen]
      end
      p res
      total = 0
      sum = []
      4.times do |i|
        total += i
        tmp = i * 2 if i != 1
        sum << tmp
      end
      p [total, sum]
    RUBY

    _(result).must_answer <<~'OUT'
      [nil, 1, nil]
      [[1, nil], [2, nil], [3, true], [4, true]]
      [6, [0, nil, 4, 6]]
    OUT
  end

  it "inline nested yield ivar self" do
    result = ze0(<<~'RUBY')
      # Nested yield-method inlining: the outer inlined body calls another yielding
      # method on a DIFFERENT receiver, passing its own (renamed) locals as args,
      # and the caller's block reads the caller's ivars. The args must respect the
      # outer inline's rename table and the spliced block body must resolve `self`
      # to the CALLER, not the inner receiver (doom's compute_slide reading @map
      # inside a block passed through each_nearby_linedef -> each_linedef_near).
      class Grid
        def initialize(cells)
          @cells = cells
        end

        def each_cell_near(lo, hi)
          @cells.each { |c| yield c if c >= lo && c <= hi }
        end
      end

      class Walker
        def initialize(grid, names)
          @grid = grid
          @names = names
        end

        def each_named(a, b)
          unless @names.empty?
            min_v = a < b ? a : b
            max_v = a < b ? b : a
            @grid.each_cell_near(min_v, max_v) { |c| yield c }
            return
          end
          @grid.each_cell_near(a, b) { |c| yield c }
        end

        def collect(a, b)
          out = []
          each_named(a, b) do |c|
            return out if c == 9
            out << @names[c % @names.size]
          end
          out
        end
      end

      g = Grid.new([2, 9, 4, 1, 7])
      w = Walker.new(g, ["red", "green", "blue"])
      puts w.collect(4, 1).inspect
      puts w.collect(1, 9).inspect
    RUBY

    _(result).must_answer <<~'OUT'
      ["blue", "green", "green"]
      ["blue"]
    OUT
  end

  it "inline yield deep nested self" do
    result = ze0(<<~'RUBY')
      # Three levels of inlined yielding methods: process (inlined via its block),
      # then @a.run and @b.run2 nested inside its spliced block. The deepest block
      # reads @tag through Top's self while A's and B's receivers have overwritten
      # the shared inline selfbuf. The caller-self fallback must survive by value,
      # not alias the clobbered buffer, or @tag resolves against the wrong receiver.
      class A
        def initialize(v); @v = v; end
        def run; yield @v; end
      end
      class B
        def initialize(v); @v = v; end
        def run2; yield @v; end
      end
      class Top
        def initialize
          @tag = "TOP"
          @a = A.new(10)
          @b = B.new(20)
        end
        def process
          yield 0
          @a.run do |x|
            @b.run2 do |y|
              puts "#{@tag}: #{x} #{y}"
            end
          end
        end
      end
      Top.new.process { |n| puts "start #{n}" }
    RUBY

    _(result).must_answer <<~'OUT'
      start 0
      TOP: 10 20
    OUT
  end

  it "inline yield method with return" do
    result = ze0(<<~'RUBY')
      # A yielding method containing `return` must still inline at block call sites
      # (a bailed inline emitted a plain call to a never-emitted symbol, an
      # undefined-symbol link error: doom's PlayerPhysics#each_nearby_linedef).
      # The method's own returns funnel to a per-inline exit; a `return` inside the
      # caller's block still exits the CALLER.
      class Walker
        def initialize(items)
          @items = items
          @fast = false
        end

        def each_item(a, b)
          unless @fast
            @items.each { |it| yield it }
            return
          end
          @items.each { |it| yield it if it >= a && it <= b }
        end

        def count_between(a, b)
          n = 0
          each_item(a, b) do |it|
            return -1 if it < 0
            n += 1
          end
          n
        end
      end

      w = Walker.new([3, 1, 4, 1, 5])
      puts w.count_between(1, 4)
      w2 = Walker.new([3, -2, 9])
      puts w2.count_between(0, 10)
    RUBY

    _(result).must_answer <<~'OUT'
      5
      -1
    OUT
  end

  it "inline yield nested self ivar" do
    result = ze0(<<~'RUBY')
      class Inner
        def initialize(v)
          @val = v
        end
        # a yielding method; inlined at the call site
        def run
          yield @val
        end
      end

      class Outer
        def initialize
          @tag = "outer"
          @inner = Inner.new(7)
        end

        # yielding method that, in its body, calls Inner#run with a block.
        # The block reads @tag through Outer's self -- while Inner#run is inlined
        # (its self is the Inner receiver). Nested inline must not clobber the
        # caller's self used by the spliced block body.
        def process
          yield 1
          @inner.run do |x|
            puts "#{@tag}: #{x}"
          end
        end
      end

      o = Outer.new
      o.process { |n| puts "start #{n}" }
    RUBY

    _(result).must_answer <<~'OUT'
      start 1
      outer: 7
    OUT
  end

  it "inline yield return side effect" do
    result = ze0(<<~'RUBY')
      def side
        puts "side effect happened"
        42
      end

      def each_thing
        puts "before"
        yield 1
        return side()
        puts "unreached"
      end

      each_thing { |x| puts "block #{x}" }
      puts "after"
    RUBY

    _(result).must_answer <<~'OUT'
      before
      block 1
      side effect happened
      after
    OUT
  end

  it "inlined yield block param type" do
    result = ze0(<<~'RUBY')
      # Issue #395 string-yield sub-variant. The previous fix only
      # covered int-yielding `each` over a user class; a string-yielding
      # variant still tripped a type mismatch (block param `k` got
      # declared `mrb_int` at the parent scope, but the yield expansion
      # assigned a `const char *` from the iterating method's body).
      #
      # Fix: scan_locals' obj-recv branch now scans the yielding method's
      # body in a temp scope (with @current_class_idx pointing at the
      # method's owner class so ivar reads resolve), then asks
      # body_yield_arg_types for the per-position yield arg types and
      # pushes those onto the block-param `types` array.

      class C
        def initialize
          @keys = []
          @keys << "alpha"
          @keys << "beta"
        end

        def each
          i = 0
          while i < @keys.length
            k = @keys[i]
            yield k
            i += 1
          end
          self
        end
      end

      c = C.new
      c.each { |k| puts k }
    RUBY

    _(result).must_answer <<~'OUT'
      alpha
      beta
    OUT
  end

  it "inlined yield self locals" do
    result = ze0(<<~'RUBY')
      # Issue #395 / #392 cluster: inlined yield-bearing method bodies
      # previously emitted (a) `self->iv_X` references with no `self` in
      # scope at the call site, (b) half-renamed locals (`lv_i_y1` for the
      # declaration but `lv_i` for some uses), and (c) `raise X unless Y`
      # hoisted out of the unless block.
      #
      # Fix: compile_yield_method_call_stmt sets @self_override to the
      # receiver expression so default ivar emission picks up the right
      # pointer. compile_expr_remap learns `[]` / `length` / `size` so
      # local-renamed receivers don't fall through to compile_expr.
      # fiber_var_ref consults @inline_rename_map_from / _to so any
      # CallNode that does fall through still gets the renamed local.
      # compile_stmt_with_block gets a UnlessNode arm.

      # A) Inlined `each` over an int_array ivar (issue #395 int variant).
      class C
        def initialize
          @nums = []
          @nums << 10
          @nums << 20
          @nums << 30
        end

        def each
          i = 0
          while i < @nums.length
            n = @nums[i]
            yield n
            i += 1
          end
          self
        end
      end

      c = C.new
      c.each { |n| puts n.to_s }   # 10 / 20 / 30

      # B) `raise X unless Y` inside an inlined yield-method body
      # (issue #392).
      def measure
        before = 1
        yield
        after = 2
        raise "fail" unless after > before
        true
      end

      measure { puts "block" }      # block
      puts "ok"                     # ok
    RUBY

    _(result).must_answer <<~'OUT'
      10
      20
      30
      block
      ok
    OUT
  end

  it "kwsplat yield inline bind" do
    result = ze0(<<~'RUBY')
      # A yielding method called with a forwarded **hash: its keyword params must
      # bind from the splatted hash (by runtime lookup) when the inlined body yields
      # to the caller's block, not fall through to a fabricated default.
      def add(a:, b:); yield(a + b); end
      def run_add(h); add(**h) { |s| s * 10 }; end
      p run_add({a: 1, b: 2})

      # a keyword param with a default, partially covered by the splat
      def sub(x:, y: 100); yield(x - y); end
      def run_sub(h); sub(**h) { |s| s.abs }; end
      p run_sub({x: 5})
      p run_sub({x: 5, y: 3})

      # mixed literal keyword and forwarded splat
      def prod(a:, b:); yield(a * b); end
      def run_prod(h); prod(a: 7, **h) { |s| s + 1 }; end
      p run_prod({b: 6})

      # string-valued keywords through the splat, interpolated in the yield
      def label(name:, n:); yield("#{name}=#{n}"); end
      def run_label(h); label(**h) { |s| s.upcase }; end
      p run_label({name: "x", n: 3})
    RUBY

    _(result).must_answer <<~'OUT'
      30
      95
      2
      43
      "X=3"
    OUT
  end

  it "massign in inlined yield" do
    result = ze0(<<~'RUBY')
      # A multiple assignment inside a method body that gets yield-inlined into its
      # caller: every local-target emission (fixed targets, the rest, poly gets)
      # must go through the inline rename table -- the declarations are renamed,
      # so an unrenamed assignment references an undeclared C variable.
      def pair
        a, b = yield
        [b, a]
      end
      p(pair { [1, 2] })
      def rest_only
        *r = *yield
        r
      end
      p(rest_only { [3, 4] })
      def spread
        x, y, *z = *yield
        [x, y, z]
      end
      p(spread { [1, 2, 3, 4] })
    RUBY

    _(result).must_answer <<~'OUT'
      [2, 1]
      [3, 4]
      [1, 2, [3, 4]]
    OUT
  end

  it "nested capture inlined times" do
    result = ze0(<<~'RUBY')
      # An escaping closure can capture the param (and block-locals) of an INLINED
      # `.times` block, even when that `.times` is itself nested inside another
      # escaping block (Batch H). The `.times` body shares the enclosing scope,
      # so each iteration's param is cell-wrapped fresh -- matching Ruby's
      # per-iteration block-param binding -- and the nested closure captures it.

      # param of a `.times` nested inside an `.each` block, captured by a lambda
      store = []
      [1, 2].each do |a|
        store << ->() { a }
        2.times do |b|
          store << ->() { a + b }
        end
      end
      store.each { |p| puts p.call }

      # a `.times` block-local (|i; n|) captured by a nested block
      labels = []
      [10].each do |base|
        3.times do |i; n|
          n = base + i
          labels << ->() { n }
        end
      end
      labels.each { |p| puts p.call }

      # the uncaptured fast path is untouched: break still works
      total = 0
      5.times { |i| total += i }
      puts total
      r = 5.times { |i| break i * 2 if i == 3 }
      p r
    RUBY

    _(result).must_answer <<~'OUT'
      1
      1
      2
      2
      2
      3
      10
      11
      12
      10
      6
    OUT
  end

  it "nested escaping block captures an inlined times param" do
    result = ze0(<<~'RUBY')
      # An escaping closure capturing the param of an INLINED `.times` block.
      # The `.times` body shares the enclosing scope, so the param is
      # cell-wrapped per iteration -- fresh each turn, matching Ruby -- and the
      # nested closure shares that cell, exactly like a real block param.
      # Previously a clean compile-error scope-cut.
      # a=1: {1}, {1+0}, {1+1}; a=2: {2}, {2+0}, {2+1}

      store = []
      [1, 2].each do |a|
        store << ->() { a }
        2.times do |b|
          store << ->() { a + b }
        end
      end
      store.each { |p| puts p.call }
    RUBY

    _(result).must_answer <<~'OUT'
      1
      1
      2
      2
      2
      3
    OUT
  end

  it "proc capture inline block param" do
    result = ze0(<<~'RUBY')
      # A proc created inside an INLINED iterator block, capturing the block's param
      # (#2648): the body is wrapped in an immediately-called lambda that owns a
      # renamed copy of the param, so each iteration captures a FRESH cell.
      fs = [1, 2, 3].map { |i| ->{ i * 10 } }
      p fs[0].call
      p fs[1].call
      p fs[2].call
      procs = []
      [7, 8].each { |v| procs << ->{ v } }
      p procs[0].call
      p procs[1].call
      # blocks that do not create capturing procs are left alone
      p [1, 2].map { |x| x + 1 }
      s = 0
      [1, 2, 3].each { |x| s += x }
      p s
    RUBY

    _(result).must_answer <<~'OUT'
      10
      20
      30
      7
      8
      [2, 3]
      6
    OUT
  end

  it "sibling block owns its local beside a fused loop" do
    result = ze0(<<~'RUBY')
      line = "mentions alpha and beta"
      names = ["alpha", "gamma"]

      # The fused loop is the LOCAL-receiver `map` (a typed nomination).
      p ["typed", ["alpha", "gamma"].map { |t| re = Regexp.new(t); ->(l) { !re.match(l).nil? } }.map { |m| m.call(line) }]
      p ["local", names.map { |t| re = Regexp.new(t); ->(l) { !re.match(l).nil? } }.map { |m| m.call(line) }]

      # The fused loop is a literal `times`, and it runs AFTER the sibling.
      p ["before", ["alpha", "gamma"].map { |t| rx = Regexp.new(t); -> { rx.source } }.map(&:call)]
      2.times { |i| rx = Regexp.new("zzz"); f = -> { rx } }

      # A fused body's own local never reaches the scope around it.
      2.times { |i| kept = i * 10 }
      p defined?(kept)

      # ...but a name the scope assigned FIRST is shared, as ruby shares it.
      shared = "outer"
      2.times { |i| shared = "in#{i}" }
      p shared
    RUBY

    _(result).must_answer <<~'OUT'
      ["typed", [true, false]]
      ["local", [true, false]]
      ["before", ["alpha", "gamma"]]
      nil
      "in1"
    OUT
  end

  it "yield inline arg caller context" do
    result = ze0(<<~'RUBY')
      # An argument to a yielding (inlined) method is call-site code: it must
      # resolve against the CALLER's self and class, not the receiver's. Here
      # `interval` is the caller Widget's attr_reader, interpolated into the
      # cache key passed to Cache#fetch. Regression: the receiver-context
      # switch happened before argument binding, so `interval` resolved (and
      # was invoked) against the Cache receiver instead of the Widget caller.
      class Cache
        def fetch(key)
          @store ||= {}
          return @store[key] if @store.key?(key)
          @store[key] = yield
        end
      end

      class Widget
        def initialize(name)
          @name = name
        end

        def interval
          @name
        end

        def compute
          # `interval` (caller's reader) is in the ARG; the block is caller code too.
          Cache.new.fetch("data_#{interval}") { "value_for_#{interval}" }
        end
      end

      puts Widget.new("hourly").compute
      puts Widget.new("daily").compute
    RUBY

    _(result).must_answer <<~'OUT'
      value_for_hourly
      value_for_daily
    OUT
  end

  it "yield inline ctor self" do
    result = ze0(<<~'RUBY')
      # A yielding `initialize` is inlined at the `new { }` call site. Its body
      # runs in the CONSTRUCTED class's context, so an implicit-self call there
      # (`setup`) must resolve against Builder, not the caller Client — while
      # constructor arguments stay call-site code (bound in the caller's
      # context, handled separately).
      class Builder
        def initialize(seed)
          @seed = seed
          setup                 # implicit-self call inside the yielding initialize
          yield self
        end

        def setup
          @ready = true
        end

        def ready?
          @ready
        end

        def seed
          @seed
        end
      end

      class Client
        def base
          100
        end

        def make
          # `base` (caller's method) is an ARG => caller context;
          # `setup` inside initialize => constructed-class context.
          Builder.new(base) { |b| b }
        end
      end

      w = Client.new.make
      p w.ready?
      p w.seed
    RUBY

    _(result).must_answer <<~'OUT'
      true
      100
    OUT
  end

  it "yield inline divergent accumulator" do
    result = ze0(<<~'RUBY')
      # A yield-inlined method that accumulates yield results into an array it
      # returns (map-style) must widen that array to poly when its callers pass
      # blocks of divergent value type -- otherwise an object-returning block's
      # elements land in an int-sized accumulator (#2454). The scalar round-trip
      # for a method that returns the yield value directly is unaffected.
      class Rel
        def map
          out = []
          [1, 2].each { |i| out << (yield i) }
          out
        end
      end
      class T
        attr_accessor :n
        def initialize(n); @n = n; end
      end
      def sum_ints; Rel.new.map { |i| i * 2 }; end
      def make_objs(counts); Rel.new.map { |i| o = T.new(counts[i]); o }; end
      def make_strs; Rel.new.map { |i| "v#{i}" }; end
      p sum_ints
      p make_objs({ 1 => 10, 2 => 20 }).map { |o| o.n }
      p make_strs
    RUBY

    _(result).must_answer <<~'OUT'
      [2, 4]
      [10, 20]
      ["v1", "v2"]
    OUT
  end

  it "yield inline divergent block map" do
    result = ze0(<<~'RUBY')
      # A yield-inline wrapper called from sites whose blocks return DIFFERENT types:
      # the collector the inner iterator builds must hold poly elements. One shared
      # inlined body cannot size it for both an Integer- and a String-returning block
      # -- whichever site is analyzed first would settle the slot and the other would
      # emit into it (#2457, same family as the `acc << yield(x)` case in #2454).
      class Row
        def initialize(i, c); @i = i; @c = c; end
        def id; @i; end
        def category; @c; end
      end
      class Relation
        def initialize(rows); @rows = rows; end
        def to_a; @rows; end
        def map; to_a.map { |x| yield x }; end
      end
      r = Relation.new([Row.new(1, "news"), Row.new(2, "ask")])
      puts r.map { |x| x.category }.join(" ")
      p r.map { |x| x.id }
      p r.map { |x| x.id }.length
      p r.map { |x| x.id.to_f }

      # a wrapper whose sites all agree keeps its concrete element type
      class IntsOnly; def map; [1, 2].map { |x| yield x }; end; end
      i = IntsOnly.new
      p i.map { |x| x + 1 }
      p i.map { |x| x * 2 }
    RUBY

    _(result).must_answer <<~'OUT'
      news ask
      [1, 2]
      2
      [1.0, 2.0]
      [2, 3]
      [2, 4]
    OUT
  end

  it "yield inline receiver self" do
    _(ze0(<<~'RUBY')).must_answer "[12, 3]\n"
      # A yielding method is inlined at its block call site. The inlined body
      # runs in the RECEIVER's class context, so an implicit-self call inside
      # it (`to_a` / `size` below, both defined on Relation) must resolve
      # against Relation — not against the CALLER's class (Paginator), which
      # has no such method. Regression: the inline bound `self` to the
      # receiver but left the emitting-class context as the caller's.
      class Relation
        def initialize(items)
          @items = items
        end

        def to_a
          @items
        end

        def size
          @items.length
        end

        # yields; also makes two implicit-self calls (to_a, size)
        def each_doubled
          to_a.each { |x| yield x * 2 }
          size
        end
      end

      class Paginator
        def run
          r = Relation.new([1, 2, 3])
          total = 0
          n = r.each_doubled { |v| total += v }
          [total, n]
        end
      end

      p Paginator.new.run
    RUBY
  end

  it "yield typed hash block local" do
    result = ze0(<<~'RUBY')
      # `yield <typed-hash>` from a top-level method should propagate the
      # hash's type to the caller's block-param local. Pre-fix
      # block_param_type_at returned `int` for no-recv user yield methods
      # (only the receiver-typed `arr.each` / `c.each` arms had yield-arg
      # lookup wired up), so the block-local was declared `mrb_int` and
      # the typed pointer was silently coerced to an int slot. Downstream
      # `row["k"]` then dispatched on int and folded to 0. Issue #628.

      def emit_rows
        i = 0
        while i < 2
          row = {"k" => "v" + i.to_s}
          yield row
          i += 1
        end
      end

      out = ""
      emit_rows do |row|
        out = out + row["k"] + ","
      end
      puts out

      # Same shape via a helper that returns the typed hash.
      def make_h(s)
        {"k" => s}
      end

      def emit_rows_via_helper
        i = 0
        while i < 2
          yield make_h("v" + i.to_s)
          i += 1
        end
      end

      out2 = ""
      emit_rows_via_helper do |row|
        out2 = out2 + row["k"] + ","
      end
      puts out2
    RUBY

    _(result).must_answer <<~'OUT'
      v0,v1,
      v0,v1,
    OUT
  end
end
