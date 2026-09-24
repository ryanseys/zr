# frozen_string_literal: true

require "spec_helper"

describe "Blocks: formatting and inspection" do
  it "argument assignment is visible to the calls own block" do
    result = zr(<<~'RUBY')
      # An assignment written INSIDE an argument list parses -- and executes --
      # before the call's own block body, so the name is the enclosing scope's
      # local and the block shares it. The deep shape is activerecord's
      # `attribute_types.fetch(name = result.columns[i]) { lookup(name) }`: the
      # argument assignment lives in an enclosing BLOCK's scope and a nested
      # escaping block reads it.
      def lookup(map)
        [nil, "b", nil].map do |column|
          map.fetch(key = column.to_s) do
            fallback(key)
          end
        end
      end

      def fallback(key)
        "fell back for #{key.inspect}"
      end

      p lookup("b" => "hit")

      # One level shallower: the argument assignment feeds the same call's block
      # directly at method scope.
      def direct(map)
        map.fetch(k = "absent") { "#{k} missing" }
      end

      p direct({})
    RUBY

    _(result).must_answer <<~'OUT'
      ["fell back for \"\"", "hit", "fell back for \"\""]
      "absent missing"
    OUT
  end

  it "block autosplat" do
    result = zr(<<~'RUBY')
      # 2-param block auto-splat of array elements over `each` (W4 / B19).
      # When a block with >=2 params iterates an array whose elements are arrays,
      # Ruby splats each element into the params. A non-array element binds the
      # first param (the rest nil). Receivers are routed through a method param so
      # the array isn't constant-folded away.

      # poly array of string/int pairs (full pairs fill both params)
      def join_pairs(arr)
        out = []
        arr.each { |k, v| out << "#{k}#{v}" }
        out
      end
      p(join_pairs([["a", 1], ["b", 2]]))

      # int pairs -> arithmetic on both params
      def sum_pairs(arr)
        out = []
        arr.each { |a, b| out << a + b }
        out
      end
      p(sum_pairs([[1, 2], [3, 4]]))

      # the whole pair is bound (k, v), not (pair, nil)
      def echo_pairs(arr)
        out = []
        arr.each { |k, v| out << [k, v] }
        out
      end
      p(echo_pairs([["x", 9]]))

      # three params over a 2-element pair: third param is nil
      def triple(arr)
        out = []
        arr.each { |a, b, c| out << [a, b, c] }
        out
      end
      p(triple([["p", 1]]))

      # a fully-poly receiver (mixed element kinds force the poly-value each path):
      # array elements splat, scalar elements bind the first param with rest nil
      def describe(arr)
        out = []
        arr.each { |a, b| out << "#{a.inspect},#{b.inspect}" }
        out
      end
      p(describe([["k", 1], "scalar", [2, 3]]))

      # Hash#each with |k, v| still binds both (sanity: not regressed)
      def pairs_of(h)
        out = []
        h.each { |k, v| out << "#{k}=#{v}" }
        out
      end
      p(pairs_of({ "a" => 1, "b" => 2 }))
    RUBY

    _(result).must_answer <<~'OUT'
      ["a1", "b2"]
      [3, 7]
      [["x", 9]]
      [["p", 1, nil]]
      ["\"k\",1", "\"scalar\",nil", "2,3"]
      ["a=1", "b=2"]
    OUT
  end

  it "block forward mixed call forms" do
    result = zr(<<~'RUBY')
      def fwd(&b)
        [1, 2].map(&b)
      end
      tri = ->(x) { x * 3 }
      p fwd(&tri)
      p(fwd { |x| x * 3 })

      def fwd2(&b)
        [1, 2].map(&b)
      end
      p(fwd2 { |x| x * 3 })
      tri2 = ->(x) { x * 3 }
      p fwd2(&tri2)

      def fwd3(&b)
        [1, 2].map(&b)
      end
      str = ->(x) { "s#{x}" }
      p fwd3(&str)
      p(fwd3 { |x| x * 3 })
      p(fwd3 { |x| x.to_s })

      def sel(&b)
        [1, 2].select(&b)
      end
      odd = ->(x) { x.odd? }
      p sel(&odd)
      p(sel { |x| x > 1 })

      def ea(&b)
        [1, 2].each(&b)
      end
      pr = ->(x) { p x }
      ea(&pr)
      ea { |x| p x * 10 }

      def sm(&b)
        [1, 2, 3].sum(&b)
      end
      dbl = ->(x) { x * 2 }
      p sm(&dbl)
      p(sm { |x| x + 1 })

      def mn(&b)
        [1, 2, 3].min_by(&b)
      end
      neg = ->(x) { -x }
      p mn(&neg)
      p(mn { |x| x })
      p(mn { |x| x.to_s })

      def mx(&b)
        [1, 2, 3].max_by(&b)
      end
      p mx(&neg)
      p(mx { |x| x })

      def gb(&b)
        [1, 2, 3].group_by(&b)
      end
      p gb(&dbl)
      p(gb { |x| x + 1 })

      def ct(&b)
        [1, 2, 3].count(&b)
      end
      big = ->(x) { x > 1 }
      p ct(&big)
      p(ct { |x| x < 3 })

      def sb(&b)
        [3, 1, 2].sort_by(&b)
      end
      p sb(&neg)
      p(sb { |x| x })

      def rg(&b)
        (1..3).map(&b)
      end
      p rg(&dbl)
      p(rg { |x| x + 1 })

      def fs(&b)
        [1, 2, 3].sum(&b)
      end
      half = ->(x) { x * 0.5 }
      p fs(&half)
      p(fs { |x| x + 1 })
    RUBY

    _(result).must_answer <<~'OUT'
      [3, 6]
      [3, 6]
      [3, 6]
      [3, 6]
      ["s1", "s2"]
      [3, 6]
      ["1", "2"]
      [1]
      [2]
      1
      2
      10
      20
      12
      9
      3
      1
      1
      1
      3
      {2 => [1], 4 => [2], 6 => [3]}
      {2 => [1], 3 => [2], 4 => [3]}
      2
      2
      [3, 2, 1]
      [1, 2, 3]
      [2, 4, 6]
      [2, 3, 4]
      3.0
      9
    OUT
  end

  it "block local cell own frame" do
    result = zr(<<~'RUBY')
      # A local the BLOCK declares, named by a block or lambda nested in it, is
      # reached through a cell. The cell was treated as a capture from the enclosing
      # frame: its declaration went to the caller, the block-local reset then
      # assigned a `_cell_x` the block's own function did not declare, and the C
      # build stopped (#4087). Capturing it was also wrong on its own terms -- every
      # invocation would share the outer frame's cell, which is what #3230 fixed for
      # the inlined shape.
      #
      # The block's frame owns it now, allocated in the prologue. That has to be the
      # prologue rather than the reset, because the reset runs only where emit_stmts
      # sees the body as a BlockNode and a proc reached through the poly enumerator
      # never gets there -- the body dereferenced a NULL cell.

      Name = Struct.new(:params)

      box = { "n" => Name.new([1, 2]) }

      box["n"].each do |row|
        spelled = []
        row.each { |x| spelled.push("#{x}") }
        puts spelled.join(", ")
      end

      # per-invocation freshness: each outer iteration gets its own binding
      h = { "a" => [1, 2, 3] }
      h["a"].each do |v|
        seen = []
        seen.push(v)
        puts seen.join("-")
      end

      # and each closure keeps the binding it was made with
      procs = []
      h["a"].each do |v|
        kept = []
        kept.push(v)
        procs.push(proc { kept.join("-") })
      end
      procs.each { |pr| puts pr.call }

      # a name only READ from the enclosing scope is still the enclosing one
      outer = []
      h["a"].each do |v|
        inner = []
        inner.push(v)
        outer.push(inner.length)
      end
      p outer

      # the cell types that are not pointers, through the same shape
      h["a"].each do |v|
        n = 0
        [1, 2].each { |x| n += x }
        puts n.to_s
      end

      h["a"].each do |v|
        f = 0.0
        [1, 2].each { |x| f += x }
        puts f.to_s
      end

      h["a"].each do |v|
        s = ""
        [1, 2].each { |x| s += x.to_s }
        puts s
      end
    RUBY

    _(result).must_answer <<~'OUT'
      1, 2
      1
      2
      3
      1
      2
      3
      [1, 1, 1]
      3
      3
      3
      3.0
      3.0
      3.0
      12
      12
      12
    OUT
  end

  it "block nil fill" do
    result = zr(<<~'RUBY')
      # An unfilled int-typed block/proc param holds the SP_INT_NIL sentinel.
      # Collected into an array and inspected it must render as nil, not the
      # raw INT64_MIN sentinel.

      # Trailing param left unfilled -> nil inside the returned array.
      p proc { |a, b| [a, b] }.call(1)

      # A bare unfilled param still renders nil on its own (don't regress).
      p proc { |a, b| a }.call(1)

      # Multiple unfilled params.
      p proc { |a, b, c| [a, b, c] }.call(7)

      # Block passed through a method param so the call is not constant-folded.
      def run(&blk) = blk.call(1)
      p run { |a, b| [a, b] }
    RUBY

    _(result).must_answer <<~'OUT'
      [1, nil]
      1
      [7, nil, nil]
      [1, nil]
    OUT
  end

  it "block param sibling collision" do
    result = zr(<<~'RUBY')
      # Sibling blocks reusing a parameter name must not collapse onto one
      # typed slot. Block params intern into the enclosing (flat) scope, so two
      # blocks both named |x| of different element types unified to poly and
      # corrupted codegen. The alpha-rename pass now splits genuine collisions.

      # --- chained maps of divergent element types (the original report) ---
      # [1,2,3] -> float -> int. The two |x| are int and float respectively.
      p [1, 2, 3].map { |x| x + 0.5 }.map { |x| x.floor }
      # [1, 2, 3]

      # --- the same chain folded with reduce (the exact filed one-liner) ---
      # The second map's |x| must re-narrow poly->float so the chain yields a
      # typed int array that reduce can fold, instead of locking poly.
      puts([1, 2, 3].map { |x| x + 0.5 }.map { |x| x.floor }.reduce(0) { |a, x| a + x })
      # 6

      # --- a genuinely heterogeneous receiver must stay poly (no bad re-narrow) ---
      p [1, "a", 2.0].map { |x| x.inspect }.reduce("") { |a, x| a + x }
      # "1\"a\"2.0"

      # --- three sibling each_index blocks share |i| (all int indices) ---
      def t_each_index
        [10, 20, 30].each_index { |i| puts i }
        puts "---"
        %w[a b c].each_index { |i| puts "idx #{i}" }
        puts "---"
        [].each_index { |i| puts "never" }
      end
      t_each_index

      # --- sibling selects of divergent element types share |v| ---
      def t_select
        ints = [1, 2, 3, 4].select { |v| v > 2 }
        strs = %w[aa b ccc].select { |v| v.length > 1 }
        puts ints.inspect
        puts strs.inspect
      end
      t_select

      # --- nested same-name: inner |x| shadows the outer block's |x| ---
      [1].each { |x| [20, 30].each { |x| puts x } }
      # 20
      # 30

      # --- nested capture: inner block (no param) captures the outer |x| ---
      [7].each { |x| [1, 2].each { puts x } }
      # 7
      # 7

      # --- inject folds reusing |acc, e| over arrays of different element types ---
      def t_inject
        si = [1, 2, 3].inject(0) { |acc, e| acc + e }
        ss = %w[a b c].inject("") { |acc, e| acc + e }
        puts si
        puts ss
      end
      t_inject
    RUBY

    _(result).must_answer <<~'OUT'
      [1, 2, 3]
      6
      "1\"a\"2.0"
      0
      1
      2
      ---
      idx 0
      idx 1
      idx 2
      ---
      [3, 4]
      ["aa", "ccc"]
      20
      30
      7
      7
      6
      abc
    OUT
  end

  it "block splat param" do
    result = zr(<<~'RUBY')
      # A trailing rest block parameter (`|*a|`) collects the values yielded past the
      # required parameters into an array (previously it was left nil/unbound).
      def m3
        yield 1, 2, 3
      end
      m3 { |*a| p a }
      m3 { |x, *rest| p x; p rest }

      def one
        yield 5
      end
      one { |*a| p a }

      def none
        yield
      end
      none { |*a| p a }

      def pair
        yield "x", "y"
      end
      pair { |first, *others| p first; p others }

      def mixed
        yield 1, "two", :three
      end
      mixed { |*all| p all }

      # The yielded value is used (expression position): the rest array is bound and
      # the block's value flows back out.
      def collect
        yield 1, 2, 3
      end
      total = collect { |*a| a.sum }
      p total
      labeled = collect { |x, *rest| "#{x}:#{rest.inspect}" }
      p labeled

      # The bound rest is a real, usable Array (sum / inspect / map+join all work).
      def emit3
        yield "p", "q", "r"
      end
      joined = emit3 { |*xs| xs.map { |x| x + "!" }.join("-") }
      p joined
    RUBY

    _(result).must_answer <<~'OUT'
      [1, 2, 3]
      1
      [2, 3]
      [5]
      []
      "x"
      ["y"]
      [1, "two", :three]
      6
      "1:[2, 3]"
      "p!-q!-r!"
    OUT
  end

  it "block with more params than yielded values nil fills leniently" do
    result = zr(<<~'RUBY')
      # `puts` on `nil` prints an empty line -- real Ruby's own behavior, and
      # avoids `Object#inspect` (a separate, unrelated, unimplemented method).

      class Collector
        def each_one(a)
          yield a
        end
      end
      Collector.new.each_one(1) { |a, b| puts a; puts b }
    RUBY

    _(result).must_answer "1\n\n"
  end

  it "by key block shapes" do
    result = zr(<<~'RUBY')
      # `min_by` / `max_by` / `minmax_by` / `sort_by` over the block shapes their
      # arms once refused: a block with NO parameter, a key that IS nil, a key
      # whose type differs per element, and a key CRuby cannot order.
      #
      # The last one to close was the nil key, and it was not the by-key drivers
      # at all: `rb_cmp` had no `Object#<=>` fallback, so a pair of `nil`s was
      # INCOMPARABLE. Every element ties on nil, so `sort_by {}` raised
      # "comparison failed" -- and so did `[nil, nil].sort`, `[true, true].sort`
      # and any other pair of equal values with no ordering arm of its own.

      p [3, 1, 2].min_by { 5 }
      p [3, 1, 2].max_by { 5 }
      p [3, 1, 2].minmax_by { 5 }
      p [3, 1, 2].sort_by { 5 }

      # 2. A key whose value IS nil. It types VOID/NIL, which is not a C type to hold
      #    a key in -- but nil is a key: every element ties, so CRuby answers the
      #    first one and leaves the order alone.
      p [3, 1, 2].min_by {}
      p [3, 1, 2].max_by {}
      p [3, 1, 2].minmax_by {}
      p [3, 1, 2].sort_by {}
      p [3, 1, 2].min_by { |x| nil }
      p [3, 1, 2].sort_by { |x| nil }
      a = [3, 1, 2]
      a.sort_by! {}
      p a

      # minmax_by with a BOXED key (String, Array, nil) fell through to the
      # single-winner pass, which answers a bare min rather than [min, max]
      p [3, 1, 2].minmax_by { |x| x.to_s }
      p [3, 1, 2].minmax_by { |x| [x] }
      p ["bb", "a", "ccc"].minmax_by { |s| s.length }

      # nil orders against nil and only against nil: CRuby's NilClass defines #<=>
      # and not #<=, so these answer while a mixed pair still raises
      b = [nil, nil]
      p b.min
      p b.max
      p b.sort
      begin
        p [nil, 1].min
      rescue ArgumentError => e
        p e.class
      end

      # the ordinary forms keep working
      p [3, 1, 2].min_by { |x| -x }
      p [3, 1, 2].sort_by { |x| -x }
      p [3, 1, 2].minmax_by { |x| x }
      p ["bb", "a", "ccc"].sort_by { |s| s.length }
    RUBY

    _(result).must_answer <<~'OUT'
      3
      3
      [3, 3]
      [3, 1, 2]
      3
      3
      [3, 3]
      [3, 1, 2]
      3
      [3, 1, 2]
      [3, 1, 2]
      [1, 3]
      [1, 3]
      ["a", "ccc"]
      nil
      nil
      [nil, nil]
      ArgumentError
      3
      [3, 2, 1]
      [1, 3]
      ["a", "bb", "ccc"]
    OUT
  end

  it "class reflection block param" do
    result = zr(<<~'RUBY')
      # `ancestors` (and its Module neighbours) had an arm only for a receiver typed
      # TY_CLASS -- a constant. Iterating an Array of classes gives the block a BOXED
      # class, which reached no arm at all: the call reported the method as undefined,
      # and with nothing to type it, anything chained on reported itself undefined
      # "for unknown" (#4018).
      class A; end
      class B; end
      module M; end
      class C
        include M
      end

      [A, B].each do |klass|
        p klass.ancestors.map { |m| m.name.to_s }
      end

      [A, C].each do |klass|
        p klass.ancestors
        p klass.superclass
        p klass.included_modules
        p klass.ancestors.length
        p klass.ancestors.take_while { |m| true }.size
      end

      # the constant receiver keeps answering the same thing
      p A.ancestors
      p A.superclass
      p C.included_modules
      p A.ancestors.map { |m| m.name }

      # and a class reached through a local or a hash value is the same boxed value
      k = [A].first
      p k.ancestors
      h = { a: A }
      p h[:a].superclass
    RUBY

    _(result).must_answer <<~'OUT'
      ["A", "Object", "Kernel", "BasicObject"]
      ["B", "Object", "Kernel", "BasicObject"]
      [A, Object, Kernel, BasicObject]
      Object
      [Kernel]
      4
      4
      [C, M, Object, Kernel, BasicObject]
      Object
      [M, Kernel]
      5
      5
      [A, Object, Kernel, BasicObject]
      Object
      [M, Kernel]
      ["A", "Object", "Kernel", "BasicObject"]
      [A, Object, Kernel, BasicObject]
      Object
    OUT
  end

  it "closure captures pointer locals" do
    result = zr(<<~'RUBY')
      # A closure that escapes (stored in an ivar -> real proc) may now capture
      # pointer-typed locals -- string, array, heap object -- not just ints. Each is
      # laundered through the int cell and the cell's GC scan marks the referent, so
      # it survives after the defining method returns and across a collection.
      class Box
        def initialize(v)
          @v = v
        end
        def v
          @v
        end
      end
      class BoxPlus < Box   # subclass keeps Box heap (not a by-value type)
      end

      class Holder
        def store(&blk)
          @blk = blk
        end
        def fire
          @blk.call
        end
      end

      def capture_string
        s = "hello-" + 7.to_s
        h = Holder.new
        h.store { s + "!" }
        h
      end

      def capture_array
        a = [10, 20, 30]
        h = Holder.new
        h.store { a.length }
        h
      end

      def capture_object
        b = BoxPlus.new(42)
        h = Holder.new
        h.store { b.v }
        h
      end

      hs = capture_string
      ha = capture_array
      ho = capture_object

      # churn the heap so a GC runs after the defining methods returned; the captured
      # referents must survive only via each proc's cap-cell scan.
      acc = 0
      i = 0
      while i < 50000
        junk = "g-" + i.to_s
        acc = acc + junk.length
        i = i + 1
      end

      puts hs.fire     # hello-7!
      puts ha.fire     # 3
      puts ho.fire     # 42
      puts acc > 0     # true
    RUBY

    _(result).must_answer <<~'OUT'
      hello-7!
      3
      42
      true
    OUT
  end

  it "forwarding params forward positionals keywords and block" do
    result = zr(<<~'RUBY')
      # `...` is real now (G3): it desugars to internal `*__fwd_rest,
      # **__fwd_kw, &__fwd_blk` params referenced by the call-site `...`.

      def target(a, b, mode: "m")
        r = yield if block_given?
        "#{a}/#{b}/#{mode}/#{r.inspect}"
      end
      def fwd(...)
        target(...)
      end
      puts fwd(1, 2, mode: "z") { "blk" }
    RUBY

    _(result).must_answer "1/2/z/\"blk\"\n"
  end

  it "a block passed to a constructor is called once per element it builds" do
    result = zr(<<~'RUBY')
      class Pool
        def initialize(size)
          @free = []
          i = 0
          while i < size
            @free.push(yield)
            i += 1
          end
        end
        def first
          @free[0]
        end
        def count
          @free.length
        end
      end

      counter = 0
      p = Pool.new(2) do
        counter += 1
        "handle-#{counter}"
      end
      puts p.first
      puts p.count

      class Acc
        def initialize(n)
          @vals = []
          i = 0
          while i < n
            @vals.push(yield(i))
            i += 1
          end
        end
        def all
          @vals
        end
      end

      a = Acc.new(3) { |x| x * 10 }
      puts a.all.inspect
    RUBY

    _(result).must_answer <<~'OUT'
      handle-1
      2
      [0, 10, 20]
    OUT
  end

  it "yield fills the block's missing parameters with nil" do
    result = zr(<<~'RUBY')
      def show2
        yield
      end
      show2 { |a, b| puts "a=#{a.inspect} b=#{b.inspect}" }

      def show3
        yield 1
      end
      show3 { |a, b, c| puts "a=#{a.inspect} b=#{b.inspect} c=#{c.inspect}" }

      def multi
        yield 1, 2
        yield 3
      end
      multi { |p, q| puts "p=#{p.inspect} q=#{q.inspect}" }

      def one
        yield 10
      end
      one { |x, y| puts x.nil?; puts y.nil? }
    RUBY

    _(result).must_answer <<~'OUT'
      a=nil b=nil
      a=1 b=nil c=nil
      p=1 q=2
      p=3 q=nil
      false
      true
    OUT
  end

  it "iter block autosplat" do
    result = zr(<<~'RUBY')
      # A flat multi-param block over an array of arrays auto-splats each element
      # across the params (CRuby block semantics) in every element-loop emitter,
      # not just each/map. Regression: filter_map/count/any?/all?/one?/find/
      # take_while/drop_while/partition bound the first param to the whole element.
      DIRS = [[10, 1], [20, 2], [30, 3]]

      puts DIRS.filter_map { |a, b| a + b if a > 15 }.inspect
      puts DIRS.count { |a, b| a > 15 }
      puts DIRS.any? { |a, b| b > 2 }
      puts DIRS.all? { |a, b| b > 0 }
      puts DIRS.none? { |a, b| b > 9 }
      puts DIRS.one? { |a, b| a == 20 }
      puts DIRS.find { |a, b| a > 15 }.inspect
      puts DIRS.take_while { |a, b| a < 25 }.inspect
      puts DIRS.drop_while { |a, b| a < 25 }.inspect
      puts DIRS.partition { |a, b| a > 15 }.inspect
      puts DIRS.select { |a, b| a > 15 }.inspect
      puts DIRS.reject { |a, b| a > 15 }.inspect
      puts DIRS.min_by { |a, b| -a }.inspect
      puts DIRS.sort_by { |a, b| -a }.inspect
      puts DIRS.flat_map { |a, b| [a, b] }.inspect

      # group_by buckets keyed by a runtime-computed bool: exercises both the
      # autosplat and boxed-bool key equality (Hash#inspect spacing differs across
      # CRuby versions, so print the buckets instead)
      g = DIRS.group_by { |a, b| b.odd? }
      puts g[true].inspect
      puts g[false].inspect

      # a bare `next` mid-block filters the element out (the #1876 GoL shape:
      # neighbours = DIRECTIONS.filter_map with bounds checks + hash read)
      cells = {}
      5.times { |x| cells[x.to_s] = x * 10 }
      picked = [[-1, 0], [1, 0], [9, 9]].filter_map do |dx, dy|
        nx = 2 + dx
        if nx < 0 || nx >= 5
          next # out of bounds
        end
        cells[nx.to_s]
      end
      puts picked.inspect

      # boxed bool as a hash key must be equal to itself across separate boxings
      h = {}
      h[1.odd?] = 1
      h[3.odd?] = h[1.odd?] + 10
      h[2.odd?] = 100
      puts h.size
      puts h[true]
      puts h[false]
    RUBY

    _(result).must_answer <<~'OUT'
      [22, 33]
      2
      true
      true
      true
      true
      [20, 2]
      [[10, 1], [20, 2]]
      [[30, 3]]
      [[[20, 2], [30, 3]], [[10, 1]]]
      [[20, 2], [30, 3]]
      [[10, 1]]
      [30, 3]
      [[30, 3], [20, 2], [10, 1]]
      [10, 1, 20, 2, 30, 3]
      [[10, 1], [30, 3]]
      [[20, 2]]
      [10, 30]
      2
      11
      100
    OUT
  end

  it "lifted block nested capture" do
    result = zr(<<~'RUBY')
      # A block passed as a real &blk to a class/module method is lifted to a proc.
      # When that lifted block captures an enclosing local -- directly, or through a
      # further nested block -- and is invoked across a fiber/thread boundary, the
      # capture must reach the enclosing frame. Two bugs broke this:
      #
      #   1. a_block_is_lifted only recognized instance-method (and bare) calls, so a
      #      block passed to a *class/module* method (`M.f { }`) never had its captures
      #      celled -- writes to the captured local were silently dropped (printed 0).
      #   2. the celled-int compound-assign path did not coerce a poly RHS, so folding
      #      a poly value (e.g. a poly array element) into a captured int accumulator
      #      failed C compilation (`mrb_int + sp_RbVal`).
      #
      # All deterministic here: each Thread is joined / Fiber resumed before the
      # captured value is read, so there is no concurrent mutation.

      # module method: lifted block captures `sum` directly, invoked from a thread
      module M
        def self.run(&blk)
          t = Thread.new { blk.call(5) }
          t.join
        end
      end
      sum = 0
      M.run { |i| sum += i }
      puts sum                       # 5

      # module method: capture through a NESTED block, int elements
      total = 0
      M.run { |i| [10, 20].each { |x| total += x } }
      puts total                     # 30

      # module method: nested block folding a POLY element (the coercion fix)
      poly = 0
      M.run { |i| [i].each { |x| poly += x } }
      puts poly                      # 5

      # instance method: capture through a nested block combining the arg + element
      class C
        def run(&blk)
          t = Thread.new { blk.call(5) }
          t.join
        end
      end
      inst = 0
      C.new.run { |i| [10, 20].each { |x| inst += x + i } }
      puts inst                      # 40

      # Fiber (not Thread): same lifted-block capture path
      module F
        def self.run(&blk)
          fib = Fiber.new { blk.call(4) }
          fib.resume
        end
      end
      acc = 0
      F.run { |i| 2.times { acc += i } }
      puts acc                       # 8

      # a simple worker-pool: several threads, each joined, accumulate distinct slots
      module P
        def self.each_index(n, &blk)
          threads = []
          n.times { |i| threads << Thread.new(i) { |j| blk.call(j) } }
          threads.each(&:join)
        end
      end
      seen = []
      P.each_index(3) { |i| seen << i }
      puts seen.sort.inspect         # [0, 1, 2]
    RUBY

    _(result).must_answer <<~'OUT'
      5
      30
      5
      40
      8
      [0, 1, 2]
    OUT
  end

  it "multi arg lambda" do
    result = zr(<<~'RUBY')
      # Issue #400. `->(a, b) { a + b }` and longer-arity lambdas
      # previously emitted broken code: scan_lambda_free_vars saw only
      # reqs[0] as a formal param, so the 2nd+ params were treated as
      # free variables to capture from the surrounding scope. The
      # call site dropped extra args, too.
      #
      # Fix: scan_lambda_free_vars + compile_lambda_expr collect every
      # required param, the lambda fn signature gets one sp_Val* slot
      # per param, and compile_lambda_call_expr dispatches to
      # sp_lam_call2 / _3 / _4 (new runtime helpers that re-cast the
      # stored 1-arg fn ptr to the matching arity at the call site).
      # compile_lambda_body_expr learns `*` / `-` / `/` / `%` / `<>=`
      # arms so multi-arg arithmetic bodies lower correctly.

      add = ->(a, b) { a + b }
      puts add.call(3, 4).to_s        # 7

      mul3 = ->(a, b, c) { a * b * c }
      puts mul3.call(2, 3, 5).to_s    # 30

      quad = ->(a, b, c, d) { a + b + c + d }
      puts quad.call(1, 2, 3, 4).to_s # 10

      # 1-arg still works through the unchanged sp_lam_call path.
      double = ->(x) { x * 2 }
      puts double.call(21).to_s       # 42

      # Comparison
      gt = ->(a, b) { a > b }
      puts gt.call(5, 3).to_s         # true
      puts gt.call(2, 9).to_s         # false
    RUBY

    _(result).must_answer <<~'OUT'
      7
      30
      10
      42
      true
      false
    OUT
  end

  it "nested block capture in a dsl" do
    result = zr(<<~'RUBY')
      # zr refuses to compile this program:
      #
      #     a nested escaping block capturing its enclosing BLOCK's own local `n`
      #     isn't supported yet (zr limitation)
      #
      # The shape is the standard class-macro: a block receives a value and closes
      # over it in a `define_method` body. Every Rails-style declaration is written
      # this way -- `has_many`, `validates`, `delegate` all build methods that
      # remember an argument -- so the limitation reaches a large amount of ordinary
      # ruby, and it reaches it as a compile error rather than a wrong answer.
      #
      # The diagnostic names the fix it wants (hoist the local to a method or the top
      # level, which makes it a shared `Captured` cell); what is missing is doing that
      # for the programmer, since a block-local captured by an escaping inner block
      # needs exactly the same promotion an enclosing METHOD's local already gets.

      klass = Class.new
      klass.class_exec(5) do |n|
        define_method(:n) { n }
      end
      p klass.new.n

      # The same shape via a method parameter already compiles -- this is the half
      # that works, and the pair is what makes the limitation visible.
      def build(v)
        Class.new { define_method(:v) { v } }
      end
      p build(7).new.v

      # ...and via each, which is how a macro takes a list.
      maker = Class.new
      [:x, :y].each do |name|
        maker.send(:define_method, name) { name.to_s }
      end
      p [maker.new.x, maker.new.y]
    RUBY

    _(result).must_answer <<~'OUT'
      5
      7
      ["x", "y"]
    OUT
  end

  it "nested yield with block param" do
    result = zr(<<~'RUBY')
      # Issue #664: `outer { |x| yield x*2 }` appearing inside an already-
      # inlined caller (`inner` itself yields) previously emitted `lv_x` and
      # `_block` references in a scope where neither existed — `inner` got
      # inlined into main and the codegen left the nested `outer { ... }`
      # call site dangling. Fix routes nested user-yield calls through
      # compile_nested_yield_call_inline so the inner block's body's yield
      # substitutes back to the outer-most caller's block.

      def outer
        yield 1
      end

      def inner
        outer do |x|
          yield x * 2
        end
      end

      inner { |v| puts v.to_s }

      # Multi-arg yield path. inner forwards a 2-tuple, outer's block param
      # captures and re-yields one of them. Exercises both args + offsets.
      def add_one
        yield 10
      end

      def double_then_emit
        add_one do |n|
          yield n + 5
        end
      end

      double_then_emit { |r| puts r.to_s }
    RUBY

    _(result).must_answer "2\n15\n"
  end

  it "new with block no block param" do
    result = zr(<<~'RUBY')
      # `Klass.new { ... }` where `initialize` declares no block parameter. Ruby runs
      # the block through `Proc.new`/`block_given?` and otherwise ignores it; zr's
      # static `.new` path passes it as a second argument to an `initialize` whose
      # generated signature has no block slot, so the generated program does not
      # compile.
      class Bag
        def initialize(**kw)
          @kw = kw
        end

        def show = @kw.inspect
      end

      p Bag.new(a: 1) { :ignored }.show
    RUBY

    _(result).must_answer "\"{a: 1}\"\n"
  end

  it "nullable int sentinel boxing" do
    result = zr(<<~'RUBY')
      # An int slot that can hold the nil sentinel has to box as nil, not as the
      # raw INTPTR_MIN, or a value that prints as nil compares unequal to nil. The
      # slot reaches that state four ways: an outright nil write, a destructuring
      # target the right side cannot supply, a parameter bound from such a value,
      # and a proc parameter the caller did not supply.
      class Box
        def initialize(v)
          @v = v
        end

        def eq(other)
          @v == other
        end
      end

      def takes(n)
        [n == nil, n.inspect]
      end

      x, y = nil
      x = true || false or y = 1
      p [y, y == nil, Box.new(y).eq(nil)]

      a, b, *c, d, e = 1
      p [a, b, c, d, e]
      p [a, b, c, d, e] == [1, nil, [], nil, nil]

      p takes("abc".index("z"))
      p takes(0)

      p proc { |m, *n, o| [m, n, o] }.call == [nil, [], nil]
      p proc { |m, *n, o| [m, n, o] }.call(7) == [7, [], nil]

      i = "hello".index("z")
      p [i, i == nil, Box.new(i).eq(nil)]
    RUBY

    _(result).must_answer <<~'OUT'
      [nil, true, true]
      [1, nil, [], nil, nil]
      true
      [true, "nil"]
      [false, "0"]
      true
      true
      [nil, true, true]
    OUT
  end

  it "proc anon dot call" do
    result = zr(<<~'RUBY')
      # `proc { ... }.call` — the receiver is the inline `proc { ... }` call,
      # not a local variable holding the proc. compile_dot_call_expr only
      # matched LocalVariableReadNode receivers and emitted sp_proc_call
      # against `lv_<name>`; the inline form fell through to
      # warn_unresolved_call and the proc body was never invoked.
      #
      # Fix: after the LocalVariableReadNode special-case, fall through to
      # a generic branch keyed on `infer_type(recv) == "proc"` that compiles
      # the receiver expression and feeds it to sp_proc_call. The check is
      # node-shape-agnostic — any receiver whose inferred type is `proc`
      # routes through the same emitter.
      #
      # Coverage scope (all routed through `infer_type(recv) == "proc"`):
      # - Anonymous proc literal `.call`           — CallNode receiver
      # - Anonymous proc with args                 — CallNode receiver
      # - Method returning a proc, immediately called (factory pattern)
      # - Ternary returning a proc                 — IfNode receiver
      #
      # Out of scope (separate code paths / pre-existing limitations):
      # - lambda { ... }.call / ->() { ... }.()
      #     Lambdas have a separate handler (`compile_lambda_call_expr` at
      #     ~line 11941 in master). Not exercised by this PR.
      # - @ivar = proc { ... }; @ivar.call
      #     Spinel's ivar codegen rejects assigning sp_Proc* to the ivar
      #     slot today. Pre-existing inference/codegen gap on proc ivars,
      #     independent of this PR.
      # - $global = proc { ... }; $global.call
      #     Spinel's $global proc inference is unverified. Separate concern.
      # - [proc1, proc2].each(&:call)
      #     Symbol#to_proc (`&:sym`) is unsupported in master (see
      #     `spinel_codegen.rb:1067` TODO). Added in rs-no-recv-io-expr-bridge.

      def show(s)
        puts s
      end

      # Anonymous proc literal — the original bug.
      proc { show("anon") }.call
      proc { show("second") }.call
      proc { |n| show((n * 2).to_s) }.call(7)

      # CallNode receiver returning a proc (factory pattern).
      def factory
        proc { show("factory") }
      end
      factory.call

      # Ternary returning a proc — both branches must unify to `proc`.
      cond = true
      (cond ? proc { show("ternary-true") } : proc { show("ternary-false") }).call
    RUBY

    _(result).must_answer <<~'OUT'
      anon
      second
      14
      factory
      ternary-true
    OUT
  end

  it "proc introspection" do
    result = zr(<<~'RUBY')
      # Issue #861: Proc#arity, #lambda?, and #parameters dispatch.

      p = Proc.new { |a, b| }
      puts p.arity
      puts p.lambda?
      puts p.parameters.inspect

      l = lambda { |a, b| }
      puts l.arity
      puts l.lambda?
      puts l.parameters.inspect
    RUBY

    _(result).must_answer <<~'OUT'
      2
      false
      [[:opt, :a], [:opt, :b]]
      2
      true
      [[:req, :a], [:req, :b]]
    OUT
  end

  it "safe nav with block" do
    result = zr(<<~'RUBY')
      # A block on a safe-navigation call (`recv&.m { ... }`): nil short-circuits
      # before the block is entered, else the block rides the ordinary dispatch.
      a = [1, 2, 3]
      puts a&.map { |x| x * 2 }.inspect
      b = nil
      puts (b&.each { |x| puts x }).inspect
      h = {}
      [[:a, 1], [:b, 2]].each { |k, v| h[k] = v }
      puts h&.select { |_, v| v > 1 }.inspect
    RUBY

    _(result).must_answer <<~'OUT'
      [2, 4, 6]
      nil
      {b: 2}
    OUT
  end

  it "setter yields assigned value" do
    result = zr(<<~'RUBY')
      # The value of a setter call, `obj.x = v`: the argument as written, in value
      # position, at a method's tail, and through a receiver whose class is only
      # known at run time, for hand-written writers and attr_writer alike.
      # CRuby generated the expectations.
      class Node
        attr_reader :label, :weight
        attr_accessor :tag
        def initialize; @label = ""; @weight = 0; @tag = nil; end
        def label=(v); @label = v.to_s; :ignored; end
        def weight=(v); @weight = v; 99; end
        def set_weight(v); self.weight = v; end        # tail position, hand-written
        def set_tag(v); self.tag = v; end              # tail position, attr_accessor
      end

      n = Node.new
      p(n.label = 42)          # the Integer as written, not the String stored
      p n.label
      p(n.weight = 7)
      x = (n.weight = 8); p x
      y = n.weight = 20; p y
      p n.set_weight(10)
      p n.set_tag(11)
      p(n.weight = nil)
      p(n.weight = "s")
      p(n.tag = [1, 2])
      n.weight = 13; p n.weight   # statement position stores as before

      # a receiver whose class is only known at run time
      r = [Node.new, "x"][0]
      p(r.weight = 5)
      p(r.tag = 6)
      def poly_tail(o); o.weight = 7; end
      p poly_tail(r)
      def poly_tail_attr(o); o.tag = 8; end
      p poly_tail_attr(r)
      p(r.weight = nil)
      p(r.label = 3.5)
      p r.label
      w = (r.weight = "poly-str"); p w
      begin
        q = [Node.new, "x"][1]
        q.weight = 1
      rescue NoMethodError => e
        puts "NoMethodError: #{e.message[0, 25]}"
      end
    RUBY

    _(result).must_answer <<~'OUT'
      42
      "42"
      7
      8
      20
      10
      11
      nil
      "s"
      [1, 2]
      13
      5
      6
      7
      8
      nil
      3.5
      "3.5"
      "poly-str"
      NoMethodError: undefined method 'weight=
    OUT
  end

  it "user operator on block param" do
    result = zr(<<~'RUBY')
      # A user object reaching an operator through a block parameter is a BOXED
      # receiver, and only `+`, `-` and `*` found their way to the class's own
      # method: every other operator coerced the object to an integer, the
      # comparisons failed outright, and `<<` was read as an array push that typed
      # the loop variable an int array (#3501, #3502). The same expressions on the
      # same object held in a plain local were always correct, which is what makes
      # these worth pinning in both positions.
      class Money
        include Comparable
        attr_reader :cents

        def initialize(cents)
          @cents = cents
        end

        def /(n)
          Money.new(@cents / n)
        end

        def %(n)
          Money.new(@cents % n)
        end

        def **(n)
          Money.new(@cents**n)
        end

        def &(n)
          Money.new(@cents & n)
        end

        def |(n)
          Money.new(@cents | n)
        end

        def ^(n)
          Money.new(@cents ^ n)
        end

        def <<(n)
          Money.new(@cents << n)
        end

        def >>(n)
          Money.new(@cents >> n)
        end

        def +(n)
          Money.new(@cents + n)
        end

        def <=>(other)
          @cents <=> other.cents
        end

        def to_s
          "$#{@cents}"
        end
      end

      [Money.new(250)].each do |m|
        puts (m / 5).to_s
        puts (m % 7).to_s
        puts (m + 1).to_s
        puts (m & 12).to_s
        puts (m | 1).to_s
        puts (m ^ 3).to_s
        puts (m << 2).to_s
        puts (m >> 1).to_s
        puts (m < Money.new(300))
        puts (m > Money.new(300))
        puts (m <=> Money.new(250))
        puts (m == Money.new(250))
      end

      [Money.new(3)].each { |m| puts (m**2).to_s }

      # the same object in a plain local still behaves
      m = Money.new(250)
      puts (m / 5).to_s
      puts (m << 2).to_s
      puts (m < Money.new(300))
      puts (m <=> Money.new(250))

      # a genuine push accumulator keeps its promotion even though a class owns `<<`
      out = []
      [1, 2, 3].each { |x| out << x * 2 }
      p out
    RUBY

    _(result).must_answer <<~'OUT'
      $50
      $5
      $251
      $8
      $251
      $249
      $1000
      $125
      true
      false
      0
      true
      $9
      $50
      $1000
      true
      0
      [2, 4, 6]
    OUT
  end

  it "yield into local divergent" do
    result = zr(<<~'RUBY')
      # A yield-inlined method assigning its yield to a LOCAL, called with blocks of
      # divergent value types: the local must be a boxed carrier so each site boxes
      # its own value (it settled the local from the first site otherwise).
      module NS
        class Base
          def self.ping = "ping"
        end
      end
      module NS
        class Base
          def self.transaction
            result = yield
            result
          end
        end
      end
      a = NS::Base.transaction { "str" }
      b = NS::Base.transaction { 42 }
      puts a
      puts b

      # a body that further consumes the yielded local
      class W
        def self.wrap
          r = yield
          "[#{r.inspect}]"
        end
      end
      p W.wrap { "s" }
      p W.wrap { 7 }
      p W.wrap { [1, 2] }
    RUBY

    _(result).must_answer <<~'OUT'
      str
      42
      "[\"s\"]"
      "[7]"
      "[[1, 2]]"
    OUT
  end

  it "yield value per site" do
    result = zr(<<~'RUBY')
      class A
        def initialize(v); @v = v; end
        def show; "A=#{@v}"; end
      end
      class B
        def initialize(v); @v = v; end
        def show; "B=#{@v}"; end
      end
      def fire
        puts yield.show
      end
      fire { A.new(1) }
      fire { B.new(2) }

      def twice
        x = yield
        y = yield
        [x, y]
      end
      p(twice { 3 })
      p(twice { "s" }.length)

      def use
        v = yield
        v.to_s
      end
      p use { 7 }
      p use { :sym }
      p use { A.new(9) }.class.to_s
    RUBY

    _(result).must_answer <<~'OUT'
      A=1
      B=2
      [3, 3]
      2
      "7"
      "sym"
      "String"
    OUT
  end
end
