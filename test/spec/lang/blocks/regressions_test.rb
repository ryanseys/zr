# frozen_string_literal: true

require "spec_helper"

describe "Blocks: regressions" do
  it "bundle misc c 17" do
    result = ze0(<<~'RUBY')
      # Bundled tests:
      #   - io_call_in_proc_body
      #   - local_hash_cross_type_widen
      #   - map_block_string_new

      # === io_call_in_proc_body ===
      def t_io_call_in_proc_body
        # `puts` / `print` / `printf` reached in expression context — the
        # last statement of a `proc { ... }` body. The expression-context
        # dispatcher previously had no path for these no-recv IO methods,
        # so the call fell through to warn_unresolved_call and the IO
        # side-effect was silently dropped. Fix: bridge through
        # compile_io_call_stmt and pass "0" up as the C expression value.
        #
        # To exercise all three IO methods concisely, the test iterates an
        # array of procs and `.call`s each. This relies on two adjacent
        # fixes also in this PR:
        #
        # 1. Heterogeneous array literals of procs (`[proc, proc, proc]`)
        #    are inferred as `poly_array` (boxed via sp_box_proc) rather
        #    than falling through to `int_array`. Without this, the array
        #    construction emitted `sp_IntArray_push` with a `sp_Proc *`
        #    argument and the C compiler rejected the int-from-pointer
        #    conversion.
        #
        # 2. Poly `.call` dispatch in `compile_poly_method_call` — when a
        #    block param iterates a poly array carrying procs, the recv's
        #    static type is `poly`. Unbox via `(sp_Proc *)recv.v.p` and
        #    invoke `sp_proc_call`. Without this, `p.call` inside the
        #    block fell through to warn_unresolved_call on a poly recv.
        #
        # Symbol#to_proc (`&:call`) — the more idiomatic Ruby form for this
        # iteration — is still TODO in spinel (`find_block_arg` returns -1
        # for the SymbolNode shape). The explicit-block form `{ |p| p.call }`
        # is the closest equivalent that works today; the &:sym lowering is
        # a separate concern.

        [
          proc { puts "a" },
          proc { print "b\n" },
          proc { printf("c=%d\n", 3) }
        ].each { |p| p.call }
      end
      t_io_call_in_proc_body

      # === local_hash_cross_type_widen ===
      def t_local_hash_cross_type_widen
        # Cross-type `[]=` write on a non-empty hash literal should widen the
        # LV's hash type so the store accepts the new value via boxing.
        # Before this fix, `m = {"a" => "1"}; m["k"] = 42` lowered to
        # `sp_StrStrHash_set(m, "k", 42LL)` -- gcc rejected the mrb_int passed
        # where a `const char *` was expected.
        #
        # Fix: scan_locals's CallNode `[]=` arm widens the LV from a narrow
        # variant (str_str_hash / sym_int_hash / etc.) to its corresponding
        # `*_poly_hash` when the new write's key or value type doesn't fit
        # the current variant. The LV-write emit then builds the literal
        # init as the widened poly variant directly (boxing each value).
        # Issue #589.

        # str_str_hash → str_poly_hash via int value
        m = {"a" => "1"}
        m["k"] = 42
        puts m.length          # 2
        puts m["a"]            # "1"
        puts m["k"]            # 42

        # str_int_hash → str_poly_hash via string value
        n = {"x" => 10, "y" => 20}
        n["z"] = "thirty"
        puts n.length          # 3
        puts n["x"]            # 10
        puts n["z"]            # "thirty"

        # sym_int_hash → sym_poly_hash via string value
        o = {a: 1, b: 2}
        o[:c] = "three"
        puts o.length          # 3
        puts o[:a]             # 1
        puts o[:c]             # "three"

        # sym_str_hash unchanged when same value-type written
        p = {x: "one", y: "two"}
        p[:z] = "three"
        puts p.length          # 3
        puts p[:y]             # two

        # str_str_hash unchanged when same value-type written -- the widening
        # arm only fires on a real key/value mismatch, so consistent writes
        # stay on the narrow variant.
        q = {"a" => "1"}
        q["b"] = "2"
        puts q.length          # 2
        puts q["b"]            # "2"
      end
      t_local_hash_cross_type_widen

      # === map_block_string_new ===
      def t_map_block_string_new
        # #522. Sibling to #519. The literal-array path `[String.new]` was
        # fixed in #519 to infer as `mutable_str_ptr_array` (a sp_PtrArray
        # of sp_String*). The `.map { String.new }` path didn't share the
        # inference — block-return type `mutable_str` was missing from the
        # map-result type cascade, so the accumulator stayed at the
        # default int_array shape and the push failed C compilation with
        # `sp_IntArray_push(arr, sp_String_new(""))`.
        #
        # Fix: add a `mutable_str` arm in both the analyzer
        # (infer_call_type's map branch -> mutable_str_ptr_array) and the
        # codegen (int_array recv branch -> sp_PtrArray accumulator with
        # `(void *)val` push).

        xs = [1, 2, 3]

        # Block returns String.new directly.
        result = xs.map { |x| String.new }
        puts result.length

        # Block returns a local widened to mutable_str.
        result2 = xs.map { |x| s = String.new; s << "v"; s }
        puts result2.length
      end
      t_map_block_string_new

    RUBY

    _(result).must_answer <<~'OUT'
      a
      b
      c=3
      2
      1
      42
      3
      10
      thirty
      3
      1
      three
      3
      two
      2
      2
      3
      3
    OUT
  end

  it "issue 2874" do
    result = ze0(<<~'RUBY')
      fns = [->(x) { x + 1 }, ->(x) { x * 2 }]
      composed = fns.reduce(->(x) { x }) { |acc, f| ->(x) { f.call(acc.call(x)) } }
      p composed.call(5)

      more = [->(x) { x + 1 }, ->(x) { x * 2 }, ->(x) { x - 3 }]
      c2 = more.reduce(->(x) { x }) { |acc, f| ->(x) { f.call(acc.call(x)) } }
      p c2.call(10)
      p c2.call(0)
    RUBY

    _(result).must_answer <<~'OUT'
      12
      19
      -1
    OUT
  end

  it "issue 2880" do
    result = ze0(<<~'RUBY')
      fns = [->(x) { x + 1 }, ->(x) { x * 2 }]
      combined = fns.reduce(:>>)
      p combined.call(3)
      back = fns.reduce(:<<)
      p back.call(3)
      p [1, 2, 3].reduce(:+)
      p [1, 2, 3].reduce(:*)
    RUBY

    _(result).must_answer <<~'OUT'
      8
      7
      6
      6
    OUT
  end

  it "issue 2883" do
    result = ze0(<<~'RUBY')
      callbacks = []
      callbacks << ->(e) { p e }
      callbacks << ->(e) { p e * 10 }
      callbacks.each { |cb| cb.call(5) }

      # string arg through a poly-param proc read from a container
      fns = []
      fns << ->(s) { p s.upcase }
      fns.each { |f| f.call("hi") }
    RUBY

    _(result).must_answer <<~'OUT'
      5
      50
      "HI"
    OUT
  end

  it "issue 2942" do
    result = ze0(<<~'RUBY')
      # Calling a Proc obtained via Array#last: `.last` must be a self-contained
      # expression (not a g_pre decl) so it works as the receiver of a following
      # `.call`.
      pipe = [->(x) { x * 2 }, ->(x) { x + 1 }]
      p pipe.last.call(6)
      p pipe.first.call(6)
      fns = [->(a, b) { a + b }, ->(a, b) { a * b }]
      p fns.last.call(3, 4)
    RUBY

    _(result).must_answer <<~'OUT'
      7
      12
      12
    OUT
  end

  it "issue 2958" do
    _(ze0(<<~'RUBY')).must_answer "{1 => 1, 2 => 4, 3 => 9}\n"
      class Tags
        include Enumerable
        def initialize(*xs); @xs = xs; end
        def each; @xs.each { |x| yield x }; end
      end

      freq = Tags.new(1, 2, 3).reduce({}) { |h, x| h[x] = x * x; h }
      p freq
    RUBY
  end

  it "issue 2959" do
    result = ze0(<<~'RUBY')
      class Nums
        include Enumerable
        def initialize(*xs); @xs = xs; end
        def each; @xs.each { |x| yield x }; end
      end
      p Nums.new(1.0, 2.0, 3.0).sum(0)
      p Nums.new(1.0, 2.0, 3.0).sum(0.0)
      p Nums.new(1.0, 2.0, 3.0).sum
    RUBY

    _(result).must_answer <<~'OUT'
      6.0
      6.0
      6.0
    OUT
  end

  it "issue 2960" do
    result = ze0(<<~'RUBY')
      class Nums
        include Enumerable
        def initialize(*xs); @xs = xs; end
        def each; @xs.each { |x| yield x }; end
      end

      n = Nums.new(1, 2, 3)
      p n.all?(1..3)
      p n.any?(2..2)
      p n.none?(2..2)
      p n.one?(2..2)
      p Nums.new("a", "b").all?(/a|b/)
      p Nums.new("a", "b").any?(/a/)
    RUBY

    _(result).must_answer <<~'OUT'
      true
      true
      false
      true
      true
      true
    OUT
  end

  it "issue 2981" do
    result = ze0(<<~'RUBY')
      class Nums
        include Enumerable
        def initialize(*xs); @xs = xs; end
        def each; @xs.each { |x| yield x }; end
      end
      p(Nums.new(1, 2, 3, 4).each_slice(2) { |sl| }.class)
      p(Nums.new(1, 2, 3, 4).each_cons(2) { |c| }.class)
      p(Nums.new(1, 2, 3).each_with_index { |x, i| }.class)
      p([1, 2, 3, 4].each_slice(2) { |sl| }.class)
      n = Nums.new(1, 2, 3, 4)
      sl = []
      r = n.each_slice(2) { |s| sl << s }
      p sl
      p r.equal?(n)
    RUBY

    _(result).must_answer <<~'OUT'
      Nums
      Nums
      Nums
      Array
      [[1, 2], [3, 4]]
      true
    OUT
  end

  it "issue 2982" do
    result = ze0(<<~'RUBY')
      class Nums
        include Enumerable
        def initialize(*xs); @xs = xs; end
        def each; @xs.each { |x| yield x }; end
      end
      p Nums.new(1, 2, 3).reduce(0) { |a, x| a + x * 0.5 }
      p [1, 2, 3].reduce(0) { |a, x| a + x * 0.5 }
      p Nums.new(1, 2, 3).reduce(0.0) { |a, x| a + x * 0.5 }
      p Nums.new(1, 2, 3).reduce(0) { |a, x| a + x }
      p Nums.new(1, 2, 3).sum
      p [1, 2, 3].reduce(0) { |a, x| a + x }
    RUBY

    _(result).must_answer <<~'OUT'
      3.0
      3.0
      3.0
      6
      6
      6
    OUT
  end

  it "issue 3026" do
    result = ze0(<<~'RUBY')
      p(proc { next 5 }.call)
      p(proc { |x| next x * 2 }.call(4))
      p([1,2,3].map { |x| next x + 1 })
      pr = proc { |x| next 0 if x < 0; x }
      p pr.call(-3)
      p pr.call(3)
    RUBY

    _(result).must_answer <<~'OUT'
      5
      8
      [2, 3, 4]
      0
      3
    OUT
  end

  it "issue 3048" do
    result = ze0(<<~'RUBY')
      pr = proc { |x| (x || 0) + 1 }
      d = pr.dup
      p d.equal?(pr)
      p d.call(41)
      c = pr.clone
      p c.equal?(pr)
      p c.call(1)
      n = 0
      inc = proc { n += 1 }
      inc.dup.call
      inc.call
      p n
      lam = lambda { |a| a * 2 }
      p lam.dup.lambda?
      p lam.dup.call(21)
    RUBY

    _(result).must_answer <<~'OUT'
      false
      42
      false
      2
      2
      true
      42
    OUT
  end

  it "issue 3051" do
    result = ze0(<<~'RUBY')
      f = proc { |x| x + 1 }
      g = proc { |x| x * 2 }
      l = lambda { |x| x + 10 }
      h = f >> g
      p h.lambda?
      p h.arity
      p h.call(3)
      p (l >> f).lambda?
      p (f << l).lambda?
      p (l << f).lambda?
      pr = proc { |a, b| a }
      p pr.curry.lambda?
      p l.curry.lambda?
    RUBY

    _(result).must_answer <<~'OUT'
      false
      -1
      8
      true
      true
      false
      false
      true
    OUT
  end

  it "issue 3053" do
    result = ze0(<<~'RUBY')
      p :upcase.to_proc.arity
      p :+.to_proc.arity
      s = :upcase
      p s.to_proc.arity
      p :upcase.to_proc.call("ab")
      p :+.to_proc.call(4, 5)
      p ["x", "y"].map(&:upcase)
      p :upcase.to_proc.lambda?
    RUBY

    _(result).must_answer <<~'OUT'
      -2
      -2
      -2
      "AB"
      9
      ["X", "Y"]
      true
    OUT
  end

  it "issue 3054" do
    result = ze0(<<~'RUBY')
      blk = proc { |x| x * 2 }
      p [1, 2].map(&(blk))
      p [1, 2, 3].select(&(proc { |x| x.odd? }))
      lam = ->(x) { x + 1 }
      p [1, 2].map(&(lam))
      p [3, 1, 2].sort_by(&(proc { |x| -x }))
    RUBY

    _(result).must_answer <<~'OUT'
      [2, 4]
      [1, 3]
      [2, 3]
      [3, 2, 1]
    OUT
  end

  it "issue 3117" do
    result = ze0(<<~'RUBY')
      p([1, 2, 3].map(&(->(x) { x + 1 } >> ->(x) { x * 2 })))
      p([1, 2, 3].map(&(->(x) { x + 1 } << ->(x) { x * 2 })))
      f = ->(x) { x + 1 }
      g = ->(x) { x * 2 }
      p([1, 2, 3].map(&(f >> g)))
      h = f >> g
      p([1, 2, 3].map(&h))
      p([1, 2, 3].map(&f))
    RUBY

    _(result).must_answer <<~'OUT'
      [4, 6, 8]
      [3, 5, 7]
      [4, 6, 8]
      [4, 6, 8]
      [2, 3, 4]
    OUT
  end

  it "issue 3140" do
    result = ze0(<<~'RUBY')
      class Crash
        def hi = "hi"
      end
      def fn = Crash.new.tap { yield(_1) }
      r = nil
      fn { |x| r = x.hi }
      p r
      # non-escaping tap: typed access
      c = Crash.new.tap { |o| p o.hi }
      p c.hi
      # int tap
      n = 5.tap { |x| p x * 2 }
      p n
    RUBY

    _(result).must_answer <<~'OUT'
      "hi"
      "hi"
      "hi"
      10
      5
    OUT
  end

  it "issue 3162" do
    result = ze0(<<~'RUBY')
      ranges = [(1..3)]
      p ranges[0].to_a
      p [->(x) { x }].map(&:arity)                     # Ruby [1]        Spinel: NoMethodError 'arity' (Proc)
      [["a", "b"]].each { |k, v| puts "#{k.ljust(3)}." } # Ruby "a  ."     Spinel: NoMethodError 'ljust' (String)
      p (0...3).map { |n| n }.each_cons(2).map { |a, b| (a ^ b).to_s(2) }
                                                       # Ruby ["1","11"] Spinel: NoMethodError 'to_s' (Integer)
      [[1, 2], [3, 4]].last.map! { |x| x * 10 }        # Ruby [30,40]   Spinel: NoMethodError 'map!' (Array)
      t = Time.new(2026, 7, 21, 9, 30); p [t][0].hour  # Ruby 9         Spinel: NoMethodError 'hour'/'year'/... (Time; ALL accessors)
      def r(state); state.merge(x: 1); end
      acc = [{}]; acc << r(acc.last)                    # Ruby {x:1}     Spinel: NoMethodError 'merge' (Hash; param poisoned by acc.last)
    RUBY

    _(result).must_answer <<~'OUT'
      [1, 2, 3]
      [1]
      a  .
      ["1", "11"]
      9
    OUT
  end

  it "issue 3163" do
    result = ze0(<<~'RUBY')
      l = ->(a) { a }
      p l.dup == l
      p l.clone == l
      p l.dup.eql?(l)
      p l.dup.equal?(l)   # equal? is identity -> false
      # distinct blocks are not ==
      f = ->(a) { a }
      g = ->(a) { a }
      p f == g
      # same literal evaluated separately -> not ==
      procs = 2.times.map { ->(x) { x } }
      p procs[0] == procs[1]
    RUBY

    _(result).must_answer <<~'OUT'
      true
      true
      true
      false
      false
      false
    OUT
  end

  it "issue 3166" do
    _(ze0(<<~'RUBY')).must_answer "[[:a, :b], [:a, :c], [:b, :c]]\n"
      def hanoi(n, from, to, via, &block)
        return if n.zero?
        hanoi(n - 1, from, via, to, &block)
        yield [from, to]
        hanoi(n - 1, via, to, from, &block)
      end

      moves = []
      hanoi(2, :a, :c, :b) { |m| moves << m }
      p moves
    RUBY
  end

  it "issue 3167" do
    result = ze0(<<~'RUBY')
      pl = [->(x) { x * x }, ->(x) { x + 1 }].reduce(:>>)
      p pl.call(3)
      p [1, 2, 3].map(&pl)

      pl2 = [->(x) { x + 1 }, ->(x) { x * 2 }].reduce(:<<)
      p pl2.call(3)
      p [1, 2, 3].map(&pl2)
    RUBY

    _(result).must_answer <<~'OUT'
      10
      [2, 5, 10]
      7
      [3, 5, 7]
    OUT
  end

  it "issue 3175" do
    result = ze0(<<~'RUBY')
      def seq(parsers)
        ->(s) {
          rest = s
          parsers.each { |pp| out = pp.call(rest); rest = out[1] }
          rest
        }
      end

      lit = ->(str) { [str[0], str[1..]] }
      r = seq([lit]).call("abc")
      p r          # Ruby: "bc"       Spinel: 2151525692 (garbage Integer)
      p r.class    # Ruby: String     Spinel: Integer
    RUBY

    _(result).must_answer <<~'OUT'
      "bc"
      String
    OUT
  end

  it "issue 3178" do
    result = ze0(<<~'RUBY')
      # The cycle this program builds on purpose, and the census it leaves
      # behind. A cycle alive at exit is not a defect: it is a ring the
      # program never broke, so the census below is recorded as an
      # observation rather than gated on.
      #
      # A D holds `@h`, whose default proc closed over the D.
      # At exit: cycle leak: 5 objects (Proc x2, Array x1, D x1, Hash x1)
      h = { a: ->(x) { "got #{x}" } }
      p h[:a].call(*["z"])

      class D
        def initialize; @h = Hash.new { |x, k| x[k] = [] }; end
        def on(e, &b); @h[e] << b; end
        def emit(e, *a); @h[e].map { |p| p.call(*a) }; end
      end
      d = D.new
      d.on(:x) { |u| "hi #{u}" }
      p d.emit(:x, "al")

      procs = [->(a, b) { a + b }, ->(a, b) { a * b }]
      p procs.map { |pr| pr.call(*[3, 4]) }
    RUBY

    _(result).must_answer <<~'OUT'
      "got z"
      ["hi al"]
      [7, 12]
    OUT
  end

  it "issue 3209" do
    _(ze0(<<~'RUBY')).must_answer "true\n"
      class Foo
        def initialize = @hash = {}
        def empty? = @hash.empty?
      end
      class Crash
        def self.fn(&) = new(&).fn
        def initialize = yield (@foo = Foo.new)
        def fn = @foo.empty?
      end
      p Crash.fn {}
    RUBY
  end

  it "issue 3241" do
    result = ze0(<<~'RUBY')
      # A lambda with an early (non-local) return whose type diverges from the
      # fall-through tail must publish the wider boxed return value.
      f = ->(items) {
        items.each do |pr|
          out = pr.call
          return out if out
        end
        nil
      }
      p f.call([-> { "A" }])
      p f.call([-> { false }])

      g = ->(a) { a.each { |x| return x if x > 2 }; nil }
      p g.call([1, 2, 3])
      p g.call([1, 1])
    RUBY

    _(result).must_answer <<~'OUT'
      "A"
      nil
      3
      nil
    OUT
  end

  it "issue 3281" do
    result = ze0(<<~'RUBY')
      # Numbered block params across a yield-inline boundary: the callee's tap
      # block and the caller's block both use _1 with different types; each must
      # keep its own variable (the splice must not capture the caller's _1 with
      # the callee inline's renames).
      class Config
        def str(*opts, default: nil, required: false, choices: [])
          "str:#{opts.first}:#{required}"
        end
      end

      class Main
        attr_reader :config

        def initialize
          @config = Config.new
        end

        def label = "main-label"

        def parse(argv)
          "parsed:#{argv.length}"
        end
      end

      module Slap
        def self.parse(argv = [])
          Main.new.tap { yield _1.config if block_given? }.parse(argv)
        end
      end

      p Slap.parse { p _1.str "--name", required: true }

      module Slap2
        def self.run
          Main.new.tap { yield _1.config if block_given?; p _1.label }
        end
      end
      Slap2.run { p _1.str("num") }
    RUBY

    _(result).must_answer <<~'OUT'
      "str:--name:true"
      "parsed:0"
      "str:num:false"
      "main-label"
    OUT
  end

  it "issue 3309 lambda param reassign" do
    result = ze0(<<~'RUBY')
      f = ->(s) { s = s[1..]; s }
      p f.call("abc")
      f2 = ->(a, b) { a = a + 1; b = b * 2; [a, b] }
      p f2.call(1, 2)
      pr = proc { |s| s = s.to_s; s }
      p pr.call(5)
    RUBY

    _(result).must_answer <<~'OUT'
      "bc"
      [2, 4]
      "5"
    OUT
  end

  it "issue 3337 yield local tail multistmt" do
    result = ze0(<<~'RUBY')
      class A; def id; 1; end; end
      class B; def id; 2; end; end
      def txn; r = yield; r; end
      def ba; txn { t = A.new; t }; end
      def bb; txn { t = B.new; t }; end
      x = ba; y = bb; puts x.id; puts y.id

      class C; def id; 3; end; end
      def one; txn { u = C.new; u }; end
      puts one.id
    RUBY

    _(result).must_answer <<~'OUT'
      1
      2
      3
    OUT
  end
end
