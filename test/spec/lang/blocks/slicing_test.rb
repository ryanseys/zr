# frozen_string_literal: true

require "spec_helper"

describe "Blocks: slicing" do
  it "begin and end blocks run before and after the main program" do
    result = zr(<<~'RUBY')
      # BEGIN runs first in SOURCE order; END runs at exit in REVERSE order,
      # which is `at_exit` exactly -- so END lowers to one.

      puts "main 1"
      END { puts "end A" }
      BEGIN { puts "begin A" }
      puts "main 2"
      END { puts "end B" }
      BEGIN { puts "begin B" }
      puts "main 3"
    RUBY

    _(result).must_answer <<~'OUT'
      begin A
      begin B
      main 1
      main 2
      main 3
      end B
      end A
    OUT
  end

  it "begin block defines a class" do
    result = zr(<<~'RUBY')
      # `BEGIN { ... }` runs before the main program, in the top-level scope and
      # the top-level cref -- so a `class`, a `module` or a `def` written there is
      # an ordinary top-level definition that simply happens earlier. sekrets and
      # telesign both put their whole API inside one.
      #
      # The hoisting is what makes the last line work: `Early` is used above the
      # BEGIN that defines it, and several BEGIN blocks run in source order among
      # themselves.
      class Recorder
        def self.method_added(name)
          puts "added #{name}"
        end
      end

      puts "main: #{Early.new.hi} / #{Late::WHO} / #{early_helper}"
      puts "main: reopened #{Recorder.new.respond_to?(:from_begin)}"

      BEGIN {
        puts "first begin"

        class Early
          def hi = "early hi"
        end

        module Late
          WHO = "late"
        end

        def early_helper = "helper"

        class Recorder
          def from_begin = :yes
        end
      }

      BEGIN {
        puts "second begin"
        Early.class_eval { def extra = "extra" }
      }

      puts "main: #{Early.new.extra}"
      p [Early.instance_methods(false).sort, Late.constants, Late.class]

      # The hook ordering both ways round. `Recorder`'s hook is installed in the
      # MAIN body, so it never sees `from_begin` -- that ran first. `Watched`'s is
      # installed inside a BEGIN, so it sees every main definition however early in
      # the file it is written.
      class Watched
        def main_one = 1
      end

      BEGIN {
        class Watched
          def self.method_added(name)
            puts "watched added #{name}"
          end
        end
      }

      class Watched
        def main_two = 2
      end
    RUBY

    _(result).must_answer <<~'OUT'
      first begin
      second begin
      main: early hi / late / helper
      main: reopened true
      main: extra
      [[:extra, :hi], [:WHO], Module]
      watched added main_one
      watched added main_two
    OUT
  end

  it "block call multi arg first" do
    result = zr(<<~'RUBY')
      # `first` on an Enumerable whose #each invokes the block through
      # `block.call(a, b)` with MULTIPLE arguments failed to compile:
      #
      #   error: cannot convert to a pointer type
      #
      # `first` takes the block's value as one object, so the multi-argument call has
      # to pack its arguments into an array -- the same packing `to_a` needs. The
      # `yield a, b` spelling of the same method compiles and answers [1, 2].
      #
      # Found porting tobi/try, whose fuzzy matcher forwards the caller's block from
      # #each and yields (entry, positions, score).
      class ViaCall
        include Enumerable
        def each(&block)
          block.call(1, 2)
          block.call(3, 4)
        end
      end

      class ViaYield
        include Enumerable
        def each
          yield 1, 2
          yield 3, 4
        end
      end

      p ViaCall.new.first
      p ViaYield.new.first
    RUBY

    _(result).must_answer "[1, 2]\n[1, 2]\n"
  end

  it "block local cell in nested block" do
    result = zr(<<~'RUBY')
      # A local declared in a block that sits inside another block, and captured by a
      # third: the cell VARIABLE is declared in the frame that owns the scope, but
      # this block body is emitted INSIDE the enclosing block's proc function, where
      # the cell is reachable only through the capture struct. The per-iteration
      # refresh named the bare `_cell_terms` there, which that function does not
      # declare, and the C build stopped (#4127).
      Section = Struct.new(:statements)

      sections = [Section.new(["Order", "Chaos"])]

      sections.each do |section|
        ["a.rb", "b.rb"].each do |path|
          terms = {}
          section.statements.each { |term| terms[term] = path }
          p terms
        end
      end

      # The refresh is not bookkeeping: it is what gives each iteration its own
      # binding. Procs made in the inner block must each see their own `seen`, not
      # the last iteration's -- which is the bug the refresh was added for, and the
      # reason the fix updates the capture slot rather than skipping the reset.
      made = []
      [1, 2].each do |outer|
        [10, 20].each do |inner|
          seen = []
          seen << (outer * inner)
          made << proc { seen }
        end
      end
      p made.map { |pr| pr.call }

      # The same shape one level deeper, and with a non-container cell.
      counts = []
      [[1, 2], [3]].each do |group|
        group.each do |n|
          total = 0
          [n, n].each { |x| total += x }
          counts << proc { total }
        end
      end
      p counts.map { |pr| pr.call }
    RUBY

    _(result).must_answer <<~'OUT'
      {"Order" => "a.rb", "Chaos" => "a.rb"}
      {"Order" => "b.rb", "Chaos" => "b.rb"}
      [[10], [20], [20], [40]]
      [2, 4, 6]
    OUT
  end

  it "block local fresh per iteration" do
    result = zr(<<~'RUBY')
      # Block-local variables are FRESH on every block invocation: a name first
      # assigned inside a block (not captured from the enclosing scope) must not
      # carry its value into the next iteration. The `keep ||=` pattern below
      # relied on that freshness; without the per-iteration reset every element
      # after the first truthy one reused the stale value.

      def widen(x); x; end

      # --- each_with_index over a poly array, `||=` fallback (the doom shape) ---
      items = widen([1, 60, 2, 70, 3])
      out = []
      items.each_with_index do |v, i|
        keep = v if v > 50
        keep ||= "none"
        out << keep
      end
      p out
      # ["none", 60, "none", 70, "none"]

      # --- each over an int array, plain conditional first-assignment ---
      hits = []
      [5, 25, 8, 30].each do |n|
        big = "big" if n > 20
        hits << (big ? big : "small")
      end
      p hits
      # ["small", "big", "small", "big"]

      # --- times loop, block-local shadowless accumulator probe ---
      3.times do |t|
        first_time = "yes" if t == 0
        puts first_time.nil? ? "fresh" : first_time
      end
      # yes
      # fresh
      # fresh

      # --- map: block-local must not leak into the next element's value ---
      vals = [10, 1, 20, 2].map do |n|
        label = "high" if n >= 10
        label || "low"
      end
      p vals
      # ["high", "low", "high", "low"]

      # --- outer local of the same kind is NOT reset (captured, not block-local) ---
      count = 0
      [1, 2, 3].each do |n|
        count += 1
      end
      puts count
      # 3
    RUBY

    _(result).must_answer <<~'OUT'
      ["none", 60, "none", 70, "none"]
      ["small", "big", "small", "big"]
      yes
      fresh
      fresh
      ["high", "low", "high", "low"]
      3
    OUT
  end

  it "block param trailing comma" do
    result = zr(<<~'RUBY')
      # GAP -- imported from the spinel corpus at c55d9bdb.
      # A block parameter list with a trailing comma (`|a,|`) does not discard
      # the extra element, so the body sees the wrong binding.
      #
      # `|x,|` -- a trailing comma in a block's parameter list -- means "destructure
      # the element and take the leading names, drop the rest". Prism spells the
      # comma as an ImplicitRestNode, which nothing read, so `|x,|` behaved as `|x|`
      # and bound the whole element.
      pairs = [[10, 20], [30, 40]]
      p pairs.map { |x,| x }
      p pairs.flat_map { |x,| [x] }
      p pairs.each { |x,| p x }
      p pairs.select { |x,| x > 10 }
      p pairs.each_with_object([]) { |x, acc| acc << x }

      nested = [[[[1, 2]], "yes"]]
      p nested.flat_map { |ring,| ring }
      p nested.map { |ring,| ring }
      p nested.flat_map { |ring,| ring.map { |pt| pt[0] } }

      # two names and a comma: the third value is the one dropped
      triples = [[1, 2, 3], [4, 5, 6]]
      p triples.map { |a, b,| [a, b] }

      # a plain scalar element is bound whole, not destructured away
      p [1, 2].map { |x,| x }

      # reflection: the synthesized tail is not part of the signature
      pr = proc { |x,| x }
      p pr.arity
      p pr.call([1, 2])

      # a lambda is strict about its list, and there the comma changes nothing:
      # exactly one argument, and it is not destructured
      l = lambda { |a,| a }
      p l.arity
      p l.call(1)
      p(begin; l.call(1, 2); rescue ArgumentError; "ArgumentError"; end)

      # the ordinary forms are unchanged
      p pairs.map { |x| x }
      p pairs.map { |x, y| x + y }
    RUBY

    _(result).must_answer <<~'OUT'
      [10, 30]
      [10, 30]
      10
      30
      [[10, 20], [30, 40]]
      [[30, 40]]
      [[10, 20], [30, 40]]
      [[1, 2]]
      [[[1, 2]]]
      [1]
      [[1, 2], [4, 5]]
      [1, 2]
      1
      1
      1
      1
      "ArgumentError"
      [[10, 20], [30, 40]]
      [30, 70]
    OUT
  end

  it "block proc args" do
    result = zr(<<~'RUBY')
      # Block and Proc argument semantics.

      # Hash#each yields each pair as ONE array, so a block sees it whole or splits it.
      h = { a: 1, b: 2 }
      h.each { |pair| p pair }             # [:a, 1] / [:b, 2]
      h.each { |k, v| puts "#{k}=#{v}" }   # a=1 / b=2

      # A forwarded 1-arg callable receives the pair array (no arity error).
      def show(pair) = p pair
      h.each(&method(:show))               # [:a, 1] / [:b, 2]

      # A proc's keyword params bind from the call's kwargs; a required keyword
      # omitted raises, an optional one defaults.
      add = proc { |a:, b:| a + b }
      p add.call(a: 1, b: 2)               # 3
      opt = proc { |x:, y: 100| [x, y] }
      p opt.call(x: 5)                     # [5, 100]
      begin
        add.call(a: 1)
      rescue ArgumentError => e
        puts e.message                     # missing keyword: :b
      end

      # A lambda with keyword-only params counts the kwargs hash as keywords, not
      # a positional argument.
      lam = ->(x:, y: 9) { [x, y] }
      p lam.call(x: 5)                     # [5, 9]

      # Non-lambda blocks are lenient: extra args drop, missing ones nil-fill, and
      # a single array auto-splats across multiple params.
      pr = proc { |a, b| [a, b] }
      p pr.call(1, 2, 3)                   # [1, 2]
      p pr.call(1)                         # [1, nil]
      p [[1, 2], [3, 4]].map { |a, b| a + b }   # [3, 7]
    RUBY

    _(result).must_answer <<~'OUT'
      [:a, 1]
      [:b, 2]
      a=1
      b=2
      [:a, 1]
      [:b, 2]
      3
      [5, 100]
      missing keyword: :b
      [5, 9]
      [1, 2]
      [1, nil]
      [3, 7]
    OUT
  end

  it "closure captures class value" do
    result = zr(<<~'RUBY')
      # A class held in a local rides a cell when a closure captures it, the way a
      # float does: a cls_id and a rodata name, with no GC pointer of its own. It had
      # no cell shape, so the capture was refused outright -- reachable as soon as the
      # receiver is boxed and the block is a real closure rather than an inlined loop.
      # The capture struct also names its fields after the Ruby locals, so a local
      # named for a C keyword (`struct`, `int`, `default`) has to be prefixed.
      rings = ""
      rings = [[1, 2], [3, 4]]

      struct = Struct.new :x, :y
      int = 5
      default = "d"

      # the reported shape: the block never runs here, but it still has to compile
      empty = ""
      empty = []
      empty.each do |ring|
        ring.sum do |lon, lat|
          struct.new lon, lat
        end
      end

      p rings.map { |r| struct.new(r[0], r[1]).x + int }
      p rings.map { |_r| default }
      p rings.map { |r| struct.new(r[0], r[1]).to_a }

      mk = struct
      p mk.new(9, 8).y

      k = String
      p rings.map { |_r| k }.first
      puts "OK"
    RUBY

    _(result).must_answer <<~'OUT'
      [6, 8]
      ["d", "d"]
      [[1, 2], [3, 4]]
      8
      String
      OK
    OUT
  end

  it "escaping block captures self" do
    result = zr(<<~'RUBY')
      # The cycle this program builds on purpose, and the census it leaves
      # behind. A cycle alive at exit is not a defect: it is a ring the
      # program never broke, so the census below is recorded as an
      # observation rather than gated on.
      #
      # A Foo stores a block that captured `self`.
      # At exit: cycle leak: 3 objects (Array x1, Foo x1, Proc x1)
      # A block that escapes inlining -- stored in an ivar, so it becomes a real
      # _proc_<n> function -- and references self (here calls the instance method
      # `record` and, through it, the `@log` ivar) must capture self through the proc
      # cap struct. Otherwise the proc body emits `self` with no parameter or capture
      # for it -> "use of undeclared identifier 'self'". Verified via the side effect
      # (record appends to @log), not the block's return value.
      class Foo
        def initialize
          @log = [""]
          @log.pop
        end
        def record(x)
          @log.push(x)
        end
        def store(&blk)
          @blk = blk
        end
        def setup
          store { record("hi") }   # block calls instance method `record` -> needs self
        end
        def fire
          @blk.call
        end
        def first
          @log[0]
        end
      end

      f = Foo.new
      f.setup
      f.fire
      puts f.first
    RUBY

    _(result).must_answer "hi\n"
  end

  it "multi arg yield" do
    result = zr(<<~'RUBY')
      # Multi-argument `yield` in a method body (issue #98).
      #
      # Pre-fix, every `yield` lowered against a single-arg `_block`
      # function pointer (`void (*_block)(mrb_int, void*)`), so any
      # `yield x, y[, ...]` emitted `_block(x, y, _benv)` against the
      # wrong signature and `cc` rejected it. The yield-inlined path
      # (`compile_stmt_with_block`'s YieldNode branch) had a parallel
      # bug: smaller-arity yields in a multi-arity method only assigned
      # the args that were passed, so unset block-local C vars leaked
      # whatever value the previous yield had set.
      #
      # Fix scans each yield-using method's body for the max yield arity
      # and threads that count through `yield_params_suffix*` (so the
      # function-pointer signature gets N `mrb_int` slots) and through
      # `compile_yield_stmt` (function-pointer-path emit). The inlined
      # path is fixed by zeroing remaining `lv_<bp>` slots after each
      # yield's args are assigned.

      # 1. Basic 2-arg yield.
      def add_pair
        yield 1, 2
      end

      add_pair { |a, b| puts a + b }

      # 2. 3-arg yield with block returning to a local.
      def sum_triple
        yield 10, 20, 30
      end

      sum_triple { |a, b, c| puts a + b + c }

      # 3. Mixed-arity yields in the same method. The smaller yields
      #    must not leak values from the larger ones. Pre-fix, the second
      #    yield's `b` would carry 999 from the first yield; post-fix it's
      #    0. Test uses `b.to_i` so the CRuby-side `nil` and Spinel-side
      #    mrb_int 0 both produce the same numeric value.
      def mixed_yield
        yield 100, 999
        yield 200
      end

      total = 0
      mixed_yield { |a, b| total = total + a + b.to_i }
      puts total

      # 4. Multi-arg yield from a class instance method.
      class Dispatcher
        def emit
          yield 100, 200
          yield 300, 400
        end
      end

      Dispatcher.new.emit { |x, y| puts x + y }

      # 5. Three different yield arities in one method. Max-arity detection
      #    must find 3 so the function-pointer signature has 3 slots; the
      #    smaller yields must zero-pad their unused slots. Test uses
      #    `b.to_i` / `c.to_i` so CRuby's `nil` for missing block params
      #    and Spinel's `mrb_int 0` produce the same numeric sum.
      def varied
        yield 1, 2, 3
        yield 10, 20
        yield 100
      end

      acc = 0
      varied { |a, b, c| acc = acc + a + b.to_i + c.to_i }
      puts acc
    RUBY

    _(result).must_answer <<~'OUT'
      3
      60
      1299
      300
      700
      136
    OUT
  end

  it "nested block captures outer param" do
    result = zr(<<~'RUBY')
      # A nested block reading the ENCLOSING block's parameter, where the inner call
      # is one a user class owns and the block is therefore materialized as a proc.
      #
      # An inlined iterator block's parameter binds in the loop, so there is no cell
      # for a proc to close over. A proc LITERAL there is already handled: the body
      # is wrapped in an immediately-called lambda that owns the variable, and the
      # enclosing-proc-param capture machinery takes it from there. A block lifted
      # because a user class owns the name was not recognised as such a proc, so the
      # wrapper never fired and codegen met a capture with no storage.
      #
      # Two things behind it: only the BLOCK of such a call is lifted -- its receiver
      # and arguments are evaluated in the enclosing frame, so a name read there is
      # not a capture -- and a proc built INSIDE another proc has to forward the cell
      # from that proc's capture struct, since no `_cell_<name>` is in scope there.

      class Rel
        def each
          yield "row"
        end
      end

      class R
        def conditions(hash)
          out = ""
          hash.each do |key, val|
            val.each { |col| out = "#{key}.#{col}" }
          end
          out
        end

        # both the enclosing block's param and a method local, accumulated
        def pairs(hash)
          acc = []
          hash.each do |key, val|
            val.each { |col| acc << "#{key}=#{col}" }
          end
          acc
        end

        # the outer param read from the inner call's RECEIVER, which is evaluated in
        # the enclosing frame and is not a capture
        def firsts(rows)
          out = []
          rows.each do |row|
            row.first.each { |ch| out << ch }
          end
          out
        end

        # three levels
        def deep(hash)
          out = []
          hash.each do |key, vals|
            vals.each do |val|
              [1, 2].each { |n| out << "#{key}#{val}#{n}" }
            end
          end
          out
        end
      end

      r = R.new
      p r.conditions({"t" => ["c"]})
      p r.pairs({"a" => ["x", "y"], "b" => ["z"]})
      p r.firsts([[["p", "q"]], [["s"]]])
      p r.deep({"k" => ["v"]})

      # the user arm is still reached
      p Rel.new.each { |x| x }

      # and a plain proc literal capturing an inlined block param still works
      res = []
      {"h" => 1}.each do |k, v|
        f = ->(n) { "#{k}:#{n}" }
        res << f.call(v)
      end
      p res
    RUBY

    _(result).must_answer <<~'OUT'
      "t.c"
      ["a=x", "a=y", "b=z"]
      ["p", "q", "s"]
      ["kv1", "kv2"]
      "row"
      ["h:1"]
    OUT
  end

  it "nested block frame counts its levels" do
    result = zr(<<~'RUBY')
      # Ruby names a block after the scope it was WRITTEN in and COUNTS the nesting:
      # `block in <base>`, then `block (2 levels) in <base>`, `block (3 levels) in
      # <base>`. The base never changes as the nesting grows -- it stays the method
      # or body the outermost block sits in.
      #
      # Composing a block's label out of its ENCLOSING FRAME's label makes a
      # nested block read `block in block in <main>`: a spelling ruby never
      # produces, and one that grows without bound. A real `def` restarts the count, because
      # the method it creates IS the frame however it was written.

      def label = caller_locations(1, 1).first.label

      # --- at the top level -------------------------------------------------------
      p(->() { label }.call)
      p(->() { ->() { label }.call }.call)
      p(->() { ->() { ->() { label }.call }.call }.call)

      # --- under a method ---------------------------------------------------------
      class Deep
        def run
          [1].map { [2].map { label } }
        end
      end
      p Deep.new.run

      # --- under a class body -----------------------------------------------------
      class Body
        RESULT = [1].map { [2].map { label } }
      end
      p Body::RESULT

      # --- under a singleton-class body -------------------------------------------
      class Sing
        class << self
          RESULT = [1].map { [2].map { label } }
        end
      end
      p Sing.singleton_class::RESULT

      # --- a `def` restarts the count ---------------------------------------------
      [1].each do
        [2].each do
          def restarted = [3].map { label }
        end
      end
      p restarted

      # --- a `define_method` body IS a block, so its own blocks count from it ------
      class Installed
        define_method(:one) { label }
        define_method(:two) { [1].map { label } }
      end
      p Installed.new.one
      p Installed.new.two
    RUBY

    _(result).must_answer <<~'OUT'
      "block in <main>"
      "block (2 levels) in <main>"
      "block (3 levels) in <main>"
      [["block (2 levels) in Deep#run"]]
      [["block (2 levels) in <class:Body>"]]
      [["block (2 levels) in singleton class"]]
      ["block in Object#restarted"]
      "block in <class:Installed>"
      ["block (2 levels) in <class:Installed>"]
    OUT
  end

  it "numbered param per block" do
    result = zr(<<~'RUBY')
      # `_1` .. `_9` (and `it`, which the parser lowers to `_1`) are names spinel
      # synthesizes rather than names the author wrote, and blocks share their
      # enclosing scope's local table -- so two such blocks in one method interned
      # the SAME slot and their types merged. Values stayed right, because each block
      # writes the slot before reading it; what it cost was the type.
      #
      # A scope with one numbered-param block over integers gets `sp_int lv__1`. Add
      # a second over strings and, before this, BOTH became a boxed sp_RbVal. It also
      # left two passes typing that one slot from different call shapes on every
      # round, which was the last program in the suite whose inference fixpoint ran
      # to its 128-round cap (#4116).
      def alone
        out = []
        [10, 20].each { out << _1 + 1 }
        out
      end

      def together
        seen = []
        [1, 2].each { seen << _1 }
        ["a", "b"].each { seen << _1 }
        seen
      end

      p alone
      p together

      # Three blocks, three element types, all in one scope.
      def three
        a = []
        [1, 2].each { a << _1 * 2 }
        ["x"].each { a << _1 * 2 }
        [1.5].each { a << _1 * 2 }
        a
      end
      p three

      # `it` is the same slot by another spelling.
      def with_it
        r = []
        [1, 2].each { r << it }
        ["p", "q"].each { r << it }
        r
      end
      p with_it

      # _2 as well as _1, and a block that uses only _2.
      def pairs
        out = []
        { a: 1, b: 2 }.each { out << [_1, _2] }
        [[3, 4], [5, 6]].each { out << _2 }
        out
      end
      p pairs

      # The first-class forms keep working: a proc/lambda's numbered parameters bind
      # from the argument channel, and Proc#parameters and #arity report the names
      # Ruby reports whatever the slot is called internally.
      f = -> { _1 * 10 }
      p f.call(5)
      p f.arity
      g = proc { _1 + _2 }
      p g.call(1, 2)
      p proc { _1 }.parameters
      p lambda { _1 }.call("a")
      p(-> { _1 }.call("a"))

      # A block nested inside a method that also has one: different scopes, so no
      # collision and no rename.
      def outer
        x = [1, 2].map { _1 + 1 }
        x
      end
      def other
        y = ["a"].map { _1 }
        y
      end
      p [outer, other]
    RUBY

    _(result).must_answer <<~'OUT'
      [11, 21]
      [1, 2, "a", "b"]
      [2, 4, "xx", 3.0]
      [1, 2, "p", "q"]
      [[:a, 1], [:b, 2], 4, 6]
      50
      1
      3
      [[:opt, :_1]]
      "a"
      "a"
      [[2, 3], ["a"]]
    OUT
  end

  it "proc numbered params" do
    result = zr(<<~'RUBY')
      # Numbered parameters (_1.._9) in first-class procs/lambdas: they surface as
      # plain local reads with no parameters node, bind boxed off the argument
      # side-channel, and count toward lambda arity.
      f = -> { _1 * 10 }
      p f.call(5)
      g = proc { _1 + _2 }
      p g.call(1, 2)
      p [1, 2, 3].map { _1 * 2 }
      h = -> { _2 }
      p h.call(7, 8)
      begin
        h.call(1)
      rescue ArgumentError
        puts "arity"
      end
    RUBY

    _(result).must_answer <<~'OUT'
      50
      3
      [2, 4, 6]
      8
      arity
    OUT
  end

  it "proc param container input" do
    result = zr(<<~'RUBY')
      # Call-site argument inference for proc/lambda params: a container argument
      # (array/hash/string) overrides a param's bare-int default instead of widening
      # to a poly scalar. This is what lets a 1-param proc/lambda VALUE forwarded into
      # Hash#each receive the [k, v] pair (the pair array), and it also fixes a proc
      # called directly with a container arg. Method objects take any hash yield via
      # their array ABI. Distinct per-type helpers keep receiver types monomorphic.
      def hsh(x) = x
      def ints(x) = x

      h = hsh({ a: 1, b: 2 })

      # 1-param proc / lambda values receive the [k, v] pair
      pair_l = ->(pair) { p pair }
      h.each(&pair_l)                  # [:a, 1] / [:b, 2]
      pair_p = proc { |pair| p pair.last }
      h.each(&pair_p)                  # 1 / 2

      # a Method object forwards each / each_key / each_value through its array ABI
      def show(pair) = p(pair)
      def showk(k) = p(k)
      def showv(v) = p(v)
      h.each(&method(:show))           # [:a, 1] / [:b, 2]
      h.each_key(&method(:showk))      # :a / :b
      h.each_value(&method(:showv))    # 1 / 2

      # the underlying inference win: a proc called directly with a container arg gets
      # the container type for its param, not a poly scalar
      arr = ints([10, 20, 30])
      total = ->(a) { a.sum }
      p total.call(arr)                # 60
      head2 = ->(a) { a.first(2) }
      p head2.call(arr)                # [10, 20]
    RUBY

    _(result).must_answer <<~'OUT'
      [:a, 1]
      [:b, 2]
      1
      2
      [:a, 1]
      [:b, 2]
      :a
      :b
      1
      2
      60
      [10, 20]
    OUT
  end

  it "repeated underscore parameter binds the first slot" do
    result = zr(<<~'RUBY')
      # Ruby lets a parameter name repeat when it begins with `_` -- `def f(a, a)` is
      # a SyntaxError, `def f(_, _)` is not -- and only the FIRST occurrence owns the
      # readable local. Every shape below is oracled against ruby 4.0.6.
      #
      # The method signature and the block prologue got this wrong in opposite
      # ways: a method put one generated name on two parameters, which the
      # generated program refused (this is where aws-sdk-core stopped), while a
      # block's sequential bindings merely shadowed, so it compiled and quietly
      # answered the LAST argument.

      def two(_, _)
        _
      end
      p two(1, 2)

      def lead_and_post(*_, _)
        _
      end
      p lead_and_post(1, 2, 3)

      def every_slot(_, *_, **_, &_)
        _
      end
      p every_slot(1, 2)

      def reassigned(_, _)
        _ = 99
        _
      end
      p reassigned(1, 2)

      # A `_` parameter is still an ordinary local, so the later slots being
      # unreachable by name costs the body nothing it could have used.
      def counts(_, _)
        [1, 2, 3].map { |_| _ * 2 }
      end
      p counts(1, 2)

      p proc { |_, _| _ }.call(7, 8)
      p lambda { |_, _| _ }.call(7, 8)

      # The spliced iterator path binds its params as sequential `let`s too.
      p [[1, 2], [3, 4]].map { |_, _| _ }
      p({ a: 1, b: 2 }.map { |_, _| _ })
      { a: 1 }.each { |_, _| p _ }

      # A destructuring group assigns BY NAME, so its writes land on the slot the
      # name owns and the last one wins -- unlike a repeated parameter slot.
      p proc { |_, (_, _)| _ }.call(1, [2, 3])
    RUBY

    _(result).must_answer <<~'OUT'
      1
      [1, 2]
      1
      99
      [2, 4, 6]
      7
      7
      [1, 3]
      [:a, :b]
      :a
      3
    OUT
  end

  it "splat param with block" do
    result = zr(<<~'RUBY')
      # A splat parameter collects the call's arguments even when the call site
      # also passes a block: the block routes the call through the inlining path,
      # which used to bind parameters positionally and drop the rest packing --
      # leaving the first argument in the rest slot as a pointer of the wrong type.
      class Thing; end

      class Utils
        def self.silence_stream(*streams)
          p streams.length
          p streams.first.class
          yield
        end
        def self.with_pre(first, *rest)
          p first
          p rest
          yield
        end
        def self.with_post(*mid, last)
          p mid
          p last
          yield
        end
        def self.with_kw(*args, mode: "x")
          p args
          p mode
          yield
        end
        def inst(*a)
          p a
          yield
        end
      end

      p Utils.silence_stream(Thing.new) { 1 }
      p Utils.silence_stream(1, 2, 3) { 2 }
      p Utils.silence_stream { 3 }
      p Utils.with_pre(1, 2, 3) { 4 }
      p Utils.with_post(1, 2, 3) { 5 }
      p Utils.with_kw(1, 2, mode: "y") { 6 }
      p Utils.new.inst("a", "b") { 7 }
      arr = [4, 5]
      p Utils.silence_stream(*arr) { 8 }
      class Box
        def initialize(*items)
          @items = items
          yield items.length if block_given?
        end
        def items = @items
      end
      b = Box.new(1, 2) { |n| p ["ctor", n] }
      p b.items
    RUBY

    _(result).must_answer <<~'OUT'
      1
      Thing
      1
      3
      Integer
      2
      0
      NilClass
      3
      1
      [2, 3]
      4
      [1, 2]
      3
      5
      [1, 2]
      "y"
      6
      ["a", "b"]
      7
      2
      Integer
      8
      ["ctor", 2]
      [1, 2]
    OUT
  end

  it "to enum size block" do
    result = zr(<<~'RUBY')
      # `to_enum`/`enum_for` take a block that supplies the enumerator's `size`
      # lazily. zr drops it, so a custom Enumerable's `size` answers nil.
      #
      #     def each(&b) = block_given? ? (@items.each(&b); self) : to_enum(:each) { @items.size }
      #
      # That line is the documented way to write `each`, and the block exists so the
      # count is computed only if someone asks -- which is what makes `size` usable on
      # an enumerator over something expensive to walk. Anything that reads it to
      # preallocate, to drive a progress bar, or to decide a strategy gets nil and has
      # to fall back to walking.
      #
      # zr's Enumerator already carries a size (`each_slice` reports one below), so
      # the field exists; `to_enum` just does not accept the block that fills it.

      class Bag
        include Enumerable
        def initialize(*items) = @items = items
        def each(&b) = block_given? ? (@items.each(&b); self) : to_enum(:each) { @items.size }
      end

      e = Bag.new(1, 2, 3).each
      p e.size
      p e.to_a

      class Counter
        def go = enum_for(:go) { 7 }
      end
      p Counter.new.go.size

      class Pairs
        def pairs(n)
          return to_enum(:pairs, n) { n } unless block_given?
          n.times { |i| yield i, i * 2 }
        end
      end
      pe = Pairs.new.pairs(3)
      p pe.size
      p pe.to_a

      # A builtin enumerator already reports its size.
      p [1, 2].each_slice(1).size
      p (1..10).each_entry.size
    RUBY

    _(result).must_answer <<~'OUT'
      3
      [1, 2, 3]
      7
      3
      [[0, 0], [1, 2], [2, 4]]
      2
      10
    OUT
  end

  it "yield mixed block types" do
    result = zr(<<~'RUBY')
      # One yield method called with blocks of different value types: each call
      # site carries its own block's type (a class method used to funnel every
      # site through the first site's C type and segfault).
      class B
        def self.tx
          yield
        end
        def itx
          yield
        end
      end

      puts(B.tx { "in" })
      n = B.tx { 41 + 1 }
      p n
      B.tx { puts "side" }

      puts(B.new.itx { "istr" })
      m = B.new.itx { 7 }
      p m

      module NS
        class C
          def self.run
            yield
          end
        end
      end
      puts(NS::C.run { "scoped" })
      k = NS::C.run { 5 }
      p k
    RUBY

    _(result).must_answer <<~'OUT'
      in
      42
      side
      istr
      7
      scoped
      5
    OUT
  end
end
