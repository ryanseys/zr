# frozen_string_literal: true

require "spec_helper"

describe "Array: blocks and yields" do
  it "combination with a block yields each combination without building them all" do
    result = ze0(<<~'RUBY')
      # Array#combination(k) with a block iterates each combination
      # without materialising a giant intermediate array.

      count = 0
      [1, 2, 3, 4].combination(2) { |c| count = count + 1 }
      puts count

      # Body actually sees each sub-array.
      out = []
      [1, 2, 3].combination(2) { |c| out.push(c[0] + c[1]) }
      puts out.inspect
    RUBY

    _(result).must_answer <<~'OUT'
      6
      [3, 4, 5]
    OUT
  end

  it "fill's block form takes the index span positionally and the value from the block" do
    result = ze0(<<~'RUBY')
      # Array#fill's block form takes NO value argument: the positional args are the
      # index span (start[, length] or a range) and the value at each index comes from
      # the block, invoked with the index. Spinel previously treated the first arg as
      # the fill value and ignored the block entirely.
      def f2(a); a.fill(1, 2) { |i| i }; end
      p f2([1, 2, 3, 4])            # [1, 1, 2, 4]

      def f1(a); a.fill(2) { |i| i * 10 }; end
      p f1([1, 2, 3, 4])            # [1, 2, 20, 30]

      def f0(a); a.fill { |i| i }; end
      p f0([9, 9, 9])               # [0, 1, 2]

      def fr(a); a.fill(1..2) { |i| i + 100 }; end
      p fr([0, 0, 0, 0])            # [0, 101, 102, 0]

      def frx(a); a.fill(1...3) { |i| i }; end
      p frx([9, 9, 9, 9])           # [9, 1, 2, 9]

      # Negative start normalizes against the length.
      def fneg(a); a.fill(-2) { |i| i }; end
      p fneg([5, 5, 5, 5])          # [5, 5, 2, 3]

      # String and float arrays.
      def fs(a); a.fill(0, 2) { |i| "x#{i}" }; end
      p fs(["a", "b", "c"])         # ["x0", "x1", "c"]

      def ff(a); a.fill(1, 2) { |i| i.to_f }; end
      p ff([0.0, 0.0, 0.0, 0.0])    # [0.0, 1.0, 2.0, 0.0]

      # Out-of-range length clamps; zero length is a no-op.
      def fclamp(a); a.fill(2, 10) { |i| i }; end
      p fclamp([0, 0, 0, 0])        # [0, 0, 2, 3]

      # The return value is the (mutated) receiver.
      p f2([1, 2, 3, 4]).class      # Array
    RUBY

    _(result).must_answer <<~'OUT'
      [1, 1, 2, 4]
      [1, 2, 20, 30]
      [0, 1, 2]
      [0, 101, 102, 0]
      [9, 1, 2, 9]
      [5, 5, 2, 3]
      ["x0", "x1", "c"]
      [0.0, 1.0, 2.0, 0.0]
      [0, 0, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11]
      Array
    OUT
  end

  it "flat_map with a scalar block value is exactly map, and an array value splices" do
    result = ze0(<<~'RUBY')
      # flat_map whose block value is statically scalar is exactly map (CRuby
      # appends non-array values as-is); array/poly block values keep the
      # splicing emitters.
      p [1, 2, 3].flat_map { |x| x }
      p [1, 2, 3].flat_map { |x| [x, x] }
      p [1, 2, 3].flat_map { |x| x * 10 }
      p %w[ab cd].flat_map { |s| s.upcase }
      p [1, 2, 3].collect_concat { |x| x + 1 }
      p [[1, 2], [3]].flat_map { |a| a }
      h = {a: 1}
      p h.flat_map { |k, v| v }
    RUBY

    _(result).must_answer <<~'OUT'
      [1, 2, 3]
      [1, 1, 2, 2, 3, 3]
      [10, 20, 30]
      ["AB", "CD"]
      [2, 3, 4]
      [1, 2, 3]
      [1]
    OUT
  end

  it "minmax honours a two-parameter comparator block instead of < and >" do
    result = ze0(<<~'RUBY')
      # Array#minmax with a 2-param comparator block honours the block's
      # ordering instead of the default < / >.
      p [3, 1, 2].minmax { |a, b| b <=> a }   # reversed: [3, 1]
      p [3, 1, 2].minmax { |a, b| a <=> b }   # normal:   [1, 3]
      p [5, 2, 8, 1, 9].minmax { |a, b| a <=> b }
      p [5, 2, 8, 1, 9].minmax { |a, b| b <=> a }

      # String elements, comparing by length.
      p ["bb", "a", "ccc"].minmax { |a, b| a.length <=> b.length }
      p ["bb", "a", "ccc"].minmax { |a, b| b.length <=> a.length }

      # Single-element and the no-block form still work.
      p [42].minmax { |a, b| a <=> b }
      p [3, 1, 2].minmax
    RUBY

    _(result).must_answer <<~'OUT'
      [3, 1]
      [1, 3]
      [1, 9]
      [9, 1]
      ["a", "ccc"]
      ["ccc", "a"]
      [42, 42]
      [1, 3]
    OUT
  end

  it "Array.new(n) { Array.new(m, 0) } is a table of integer arrays, not a boxed one" do
    result = ze0(<<~'RUBY')
      # `t = Array.new(n) { Array.new(m, 0) }` is a table of int arrays, but the
      # narrowing pass that gives an array of int-arrays its typed representation
      # only classified pushes and literals -- a generator block killed the slot, so
      # the table stayed a boxed poly array and every read of it went through
      # sp_poly_arr_get. Reading the block's value as element evidence narrows it,
      # and the generator emits the pointer array the slot now holds.
      t = Array.new(3) { Array.new(4, 0) }
      p t.length
      p t[0].length
      t[1][2] = 5
      p t[1][2]
      row = t[1]
      p row[2]
      p row.length
      t[0][0] = t[0][0] + 7
      p t[0][0]
      s = 0
      r = 0
      while r < 3
        q = t[r]
        c = 0
        while c < 4
          s = s * 31 + q[c]
          c += 1
        end
        r += 1
      end
      p s
      u = Array.new(2) { |i| Array.new(2) { |j| i * 2 + j } }
      p u[1][1]
      p u.map { |x| x.length }
      # a generator whose element is NOT an int array keeps the boxed representation
      v = Array.new(2) { |i| i.to_s }
      p v
      w = Array.new(2) { [1, "s"] }
      p w[0][1]
    RUBY

    _(result).must_answer <<~'OUT'
      3
      4
      5
      5
      4
      7
      177859338417979572
      3
      [2, 2]
      ["0", "1"]
      "s"
    OUT
  end

  it "Array.new takes a size, a default and a block, and a bare call is empty" do
    result = ze0(<<~'RUBY')
      # The block form has to reach the runtime allocator, so `Array.new`
      # joins the block-keeping set in lowering -- routing it through
      # `HirNode::New` (which has no block slot) silently answered nils.

      p Array.new(3) { |i| i * 2 }
      p Array.new(2, "x")
      p Array.new(3)
      p Array.new
    RUBY

    _(result).must_answer <<~'OUT'
      [0, 2, 4]
      ["x", "x"]
      [nil, nil, nil]
      []
    OUT
  end

  it "the blockless predicates read a value-typed array, where no element is nil or false" do
    result = ze0(<<~'RUBY')
      # any?/all?/none?/one? with NO block on value-typed arrays. Elements are never
      # nil/false, so all? is always true, any? is non-empty, none? is empty, one? is
      # a single element. Covers symbol, int, and string arrays.
      p(%i[a b c].all?)
      p(%i[a b c].any?)
      p(%i[a b c].none?)
      p(%i[a b c].one?)
      p(%i[a].one?)
      p([1, 2, 3].all?)
      p([].all?)
      p([].any?)
      p([].none?)
      p(["x", "y"].all?)
      p(["x"].one?)
    RUBY

    _(result).must_answer <<~'OUT'
      true
      true
      false
      false
      true
      true
      true
      false
      true
      true
      true
    OUT
  end

  it "a predicate's block may take no parameter at all" do
    result = ze0(<<~'RUBY')
      # any?/all?/none?/one? with a block that takes NO parameter. The synthetic
      # iteration slot must not be bound (an empty block can't reference the yielded
      # value), otherwise codegen emits an undeclared `lv__x` write. Covers empty and
      # non-empty arrays plus the range path.
      p([].any? { true })
      p([1, 2].any? { true })
      p([].all? { false })
      p([1, 2].all? { true })
      p([1, 2].none? { false })
      p([1, 2, 3].one? { true })
      p([1].one? { true })
      p((1..3).any? { true })
      p((1..3).all? { false })
      p((1..3).none? { false })
    RUBY

    _(result).must_answer <<~'OUT'
      false
      true
      true
      true
      true
      false
      true
      true
      false
      true
    OUT
  end

  it "sum with a Float initial value answers a Float, even over an integer array" do
    result = ze0(<<~'RUBY')
      # Array#sum with a Float initial value returns a Float, even for an integer
      # array: CRuby accumulates in floating point. Spinel had truncated the float
      # initial value through the integer sum (returning an Integer). Distinct
      # monomorphic helpers keep the int- and float-array receivers from unifying.
      def ai(x); x; end
      def af(x); x; end

      p ai([1, 2, 3]).sum(0.0)      # => 6.0
      p ai([1, 2, 3]).sum(10.5)     # => 16.5
      p ai([10, 20]).sum(1.5)       # => 31.5
      p ai([]).sum(2.0)             # => 2.0

      # an integer (or no) initial value still yields an Integer
      p ai([1, 2, 3]).sum(0)        # => 6
      p ai([1, 2, 3]).sum           # => 6

      # a float array is unchanged
      p af([1.5, 2.5]).sum(1)       # => 5.0
      p af([1.5, 2.5]).sum          # => 4.0

      # the block form also promotes to Float with a float initial value
      p ai([1, 2, 3]).sum(0.0) { |x| x }      # => 6.0
      p ai([1, 2, 3]).sum(10.5) { |x| x }     # => 16.5
      p ai([1, 2, 3]).sum(0.0) { |x| x * 2 }  # => 12.0
    RUBY

    _(result).must_answer <<~'OUT'
      6.0
      16.5
      31.5
      2.0
      6
      6
      5.0
      4.0
      6.0
      16.5
      12.0
    OUT
  end

  it "sum over floats compensates, so 0.1 + 0.2 + 0.3 is 0.6" do
    result = ze0(<<~'RUBY')
      # Array#sum on floats must use Kahan-Babuska-Neumaier compensated
      # summation, matching CRuby: a naive left-fold of these values drifts
      # (0.1+0.2+0.3 -> 0.6000000000000001), the compensated sum yields 0.6.
      puts [0.1, 0.2, 0.3].sum
      puts [0.1, 0.2, 0.3].sum(1.0)
      puts [1.0, 2.0, 3.0].sum
      puts([0.1] * 10 == [0.1, 0.1, 0.1, 0.1, 0.1, 0.1, 0.1, 0.1, 0.1, 0.1])
      puts [0.1, 0.1, 0.1, 0.1, 0.1, 0.1, 0.1, 0.1, 0.1, 0.1].sum
      puts [1, 2, 3].sum            # integer sum stays exact

      # block form promotes to float and compensates too
      arr = [0.1, 0.2, 0.3]
      puts arr.sum { |x| x * 2 }
      puts arr.sum(1.0) { |x| x }
      puts [1, 2, 3].sum { |x| x * 2 }
    RUBY

    _(result).must_answer <<~'OUT'
      0.6
      1.6
      6.0
      true
      1.0
      6
      1.2
      1.6
      12
    OUT
  end

  it "to_h builds a hash from pairs, and sort! sorts in place by its comparator block" do
    result = ze0(<<~'RUBY')
      # #1224 I1: Array#to_h builds a hash from [key, value] pairs. Verified
      # via lookups + length (Spinel's hash #inspect format is a separate,
      # pre-existing concern and would only make this test fragile).
      h1 = [[:a, 1], [:b, 2], [:c, 3]].to_h
      p h1[:a]
      p h1[:c]
      p h1.length
      h2 = [["x", 10], ["y", 20]].to_h
      p h2["x"]
      p h2["y"]
      h3 = [[1, "one"], [2, "two"]].to_h
      p h3[1]
      p h3[2]

      # #1224 I2: Array#sort! with a comparator block sorts in place (the
      # block's <=> return drives the order); the block was previously ignored
      # and a default ascending sort happened.
      a = [3, 1, 4, 1, 5]
      a.sort! { |x, y| y <=> x }
      p a
      b = [3, 1, 4, 1, 5]
      b.sort! { |x, y| x <=> y }
      p b
      s = ["bb", "a", "ccc"]
      s.sort! { |x, y| x.length <=> y.length }
      p s
    RUBY

    _(result).must_answer <<~'OUT'
      1
      3
      3
      10
      20
      "one"
      "two"
      [5, 4, 3, 1, 1]
      [1, 1, 3, 4, 5]
      ["a", "bb", "ccc"]
    OUT
  end

  it "block auto splats a lone array across its positional params" do
    result = ze0(<<~'RUBY')
      # CRuby's `has_lead && !ambiguous_param0` rule.

      def one(v)
        yield v
      end
      p(one([1, 2]) { |a, b| [a, b] })
      p(one([1, 2]) { |a| a })
      p(one([1, 2]) { |*a| a })
      p(one([1, 2]) { |a, *b| [a, b] })
      p(one([1, 2]) { |a, **k| [a, k] })
      p [[1, 2], [3, 4]].map { |a, b| a + b }
      p({ x: 1 }.map { |k, v| [k, v] })
    RUBY

    _(result).must_answer <<~'OUT'
      [1, 2]
      [1, 2]
      [[1, 2]]
      [1, [2]]
      [[1, 2], {}]
      [3, 7]
      [[:x, 1]]
    OUT
  end

  it "block that changes its array sees crubys walk" do
    result = ze0(<<~'RUBY')
      # A block that grows, shrinks, replaces or freezes the Array it runs
      # over sees each element where CRuby's walk has it: select!, reject!,
      # delete_if and keep_if keep the Array's length until the walk ends,
      # then cut it to what was kept; uniq! keys with its block; sort! works
      # on a copy.
      a = [3, 1, 2]; a.sort! { |x, y| a << 9 if a.size < 4; x <=> y }; p a
      a = [3, 1, 2]; a.sort! { |x, y| a.pop if a.size > 1; x <=> y }; p a
      a = [3, 1, 2]; a.sort_by! { |x| a << 9 if a.size < 4; x }; p a
      a = [3, 1, 2]; a.sort_by! { |x| a.clear; x }; p a
      a = [1, 2, 3]; a.map! { |x| a << 9 if a.size < 5; x * 2 }; p a
      a = [1, 2, 3, 4]; a.map! { |x| a.pop; x * 2 }; p a
      a = [1, 2, 3, 4]; a.select! { |x| a.pop if x == 1; x.odd? }; p a
      a = [1, 2, 3, 4]; a.reject! { |x| a << 5 if a.size < 6; x.even? }; p a
      a = [1, 2, 3, 4]; a.keep_if { |x| a.shift if x == 2; true }; p a
      a = [1, 1, 2, 3]; a.uniq! { |x| a << 7 if a.size < 6; x }; p a
      a = [0, 0, 0]; a.fill { |i| a << 1 if a.size < 5; i }; p a
      a = [5, 4, 3, 2, 1]; a.sort! { |x, y| a.replace([9, 9]) if a.size == 5; x <=> y }; p a
      a = [3, 1, 2]; b = a.sort { |x, y| a << 9 if a.size < 5; x <=> y }; p a, b
      a = [1, 2, 3, 4, 5]; begin; a.reject! { |x| raise "no" if x == 3; x.even? }; rescue => e; p e.message; end; p a
      a = [1, 2, 3, 4, 5]; a.delete_if { |x| break if x == 4; x.odd? }; p a
      a = [1, -1, 2, -2, 3]; p a.uniq!(&:abs), a, [5].uniq!, [1, 2].uniq!
      a = [1, 2, 3]; p a.select! { true }, a.reject! { false }, a.keep_if { true }, a.filter! { _1 > 1 }, a
    RUBY

    _(result).must_answer <<~'OUT'
      [1, 2, 3]
      [1, 2, 3]
      [1, 2, 3, 9]
      [3]
      [2, 4, 6, 18, 18]
      [2, 4]
      [1, 3]
      [1, 3, 5, 5]
      [2, 3, 4]
      [1, 2, 3, 7]
      [0, 1, 2, 1, 1]
      [1, 2, 3, 4, 5]
      [3, 1, 2, 9, 9]
      [1, 2, 3]
      "no"
      [1, 3, 4, 5]
      [2, 4, 5]
      [1, 2, 3]
      [1, 2, 3]
      nil
      nil
      nil
      nil
      [2, 3]
      [2, 3]
      [2, 3]
    OUT
  end

  it "bsearch rejects a non numeric block result" do
    result = ze0(<<~'RUBY')
      # `Array#bsearch`'s block must answer numeric, true, false or nil; any
      # other type is a TypeError naming the class. zeo treats a String result as
      # a truthy find-minimum hit and answers an element. (Found by the
      # 2026-08-24 probe sweep.)
      begin
        p [1, 2].bsearch { |x| "s" }
      rescue TypeError => e
        puts e.message
      end
    RUBY

    _(result).must_answer <<~'OUT'
      wrong argument type String (must be numeric, true, false or nil)
    OUT
  end

  it "bsearch without block" do
    result = ze0(<<~'RUBY')
      p [1, 2, 3].bsearch.class
      p [1, 2, 3].bsearch_index.class
      p (1..5).bsearch.class
    RUBY

    _(result).must_answer <<~'OUT'
      Enumerator
      Enumerator
      Enumerator
    OUT
  end

  it "combination chain in destructured block" do
    result = ze0(<<~'RUBY')
      # A combination / each_cons chain whose receiver is an Array bound by
      # destructuring a Hash iteration's block parameter compiles and folds like
      # the same chain on a plain local Array.
      h = { "a" => [1, 2, 3] }
      p h.flat_map { |k, rows| rows.combination(2).select { |a, b| a < b }.map { |a, b| a + b } }
      p h.flat_map { |k, rows| rows.combination(2).to_a.size }
      p h.map { |k, rows| rows.each_cons(2).map { |a, b| a + b } }
    RUBY

    _(result).must_answer <<~'OUT'
      [3, 4, 5]
      [3]
      [[3, 5]]
    OUT
  end

  it "dig raises typeerror through non diggable intermediate" do
    result = ze0(<<~'RUBY')
      # Array/Hash#dig recurse through each intermediate's OWN #dig (CRuby's
      # rb_obj_dig), so digging past a non-diggable (an Integer) raises
      # TypeError rather than silently indexing its bits via Integer#[].

      def cls; begin; yield; rescue => e; e.class; end; end
      p(cls { [1, [2]].dig(1, 0, 3) })
      p [1, [2]].dig(1, 0)
      p [1, [2, [3]]].dig(1, 1, 0)
      p [[nil]].dig(0, 0, 5)
      p [{ a: 7 }].dig(0, :a)
      p({ a: { b: 1 } }.dig(:a, :b))
      p(cls { { a: 5 }.dig(:a, :b) })
    RUBY

    _(result).must_answer <<~'OUT'
      TypeError
      2
      3
      nil
      7
      1
      TypeError
    OUT
  end

  it "empty array tap block" do
    result = ze0(<<~'RUBY')
      [].tap do |rings|
        rings = [].take 1000
      end

      [].tap do |rings|
        rings = rings.take 1000
      end

      [].tap { |r| p r }
      [].then { |r| p r }
      p([].tap { |r| r })
      p([].tap { |r| r.push(1) })
      p([1].tap { |r| p r })
      p([].then { |r| r.size })
      p({}.tap { |h| p h })
    RUBY

    _(result).must_answer <<~'OUT'
      []
      []
      []
      [1]
      [1]
      [1]
      0
      {}
      {}
    OUT
  end

  it "find block poly array" do
    result = ze0(<<~'RUBY')
      # find / detect { |x| cond } over a poly array (mixed element types, or an array
      # of user objects) returns the first matching element, or nil when none match.
      # The typed-array forms already worked; array_kind is NULL for a poly array, so
      # this exercises the boxed-element path. Distinct helpers keep each receiver's
      # element type clean and defeat constant folding of the receiver.
      def sa(x) = x
      def sb(x) = x
      def sc(x) = x
      def su(x) = x

      p sa([:a, :b, :c]).find { |n| n == :b }              # :b
      p sb([:a, :b, :c]).detect { |n| n == :z }            # nil
      p sc([1, "two", :three, 4]).find { |e| e == :three } # :three

      S = Struct.new(:node)
      r = su([S.new(:a), S.new(:b)]).find { |n| n.node == :b }
      p r.node                                             # :b
      p su([S.new(:a)]).find { |n| n.node == :zzz }        # nil

      # the same find as a parameter default: evaluated at the call site, where the
      # block local has no top-level declaration (it is declared in the loop body).
      NET = [S.new(:begin), S.new(:x)]
      def pick(cur: NET.find { |n| n.node == :begin })
        cur.node
      end
      p pick                                               # :begin
      p pick(cur: S.new(:z))                               # :z
    RUBY

    _(result).must_answer <<~'OUT'
      :b
      nil
      :three
      :b
      nil
      :begin
      :z
    OUT
  end

  it "proc call array autosplat" do
    result = ze0(<<~'RUBY')
      # Proc#call with a single Array on a multi-parameter non-lambda proc auto-splats
      # the array across the parameters; passing the exact args is unchanged.
      fmt = proc { |a, b, c| "#{a}-#{b}-#{c}" }
      p fmt.call([1, 2, 3])
      p fmt.call(1, 2, 3)
      add = proc { |x, y| x + y }
      p add.call([4, 5])
      p add.call(4, 5)
      cat = proc { |a, b| a + b }
      p cat.call(["x", "y"])
      # A heterogeneous array (element type not a single static kind) auto-splats with
      # each param bound as poly, so a non-integer element is not miscompiled.
      pair = proc { |a, b| [a, b] }
      p pair.call([1, "two"])
    RUBY

    _(result).must_answer <<~'OUT'
      "1-2-3"
      "1-2-3"
      9
      9
      "xy"
      [1, "two"]
    OUT
  end

  it "proc lambda array of param" do
    result = ze0(<<~'RUBY')
      # proc/lambda returning an array built from a block param must carry the
      # param's real type through .call, not leak it as a raw pointer-int (#1372).
      f = proc { |t| [t] }
      p f.call("x")
      g = ->(t) { [t] }
      p g.call("y")

      class Wrap
        def initialize(t); @t = t; end
        def pair; [@t, @t]; end
      end
      h = proc { |text| Wrap.new(text).pair }
      p h.call("z")

      # arithmetic lambda still defaults its param to int
      add = ->(n) { n + 1 }
      puts add.call(5)
    RUBY

    _(result).must_answer <<~'OUT'
      ["x"]
      ["y"]
      ["z", "z"]
      6
    OUT
  end

  it "zip block tuples" do
    result = ze0(<<~'RUBY')
      # Array#zip with a block: a SOLO param receives the boxed [e1, e2] tuple,
      # two params auto-splat it, and the block form returns nil (value position
      # included).
      z = []
      r = [1, 2, 3].zip([4, 5, 6]) { |t| z << t }
      p r
      p z
      w = []
      %w[a b].zip([1, 2]) { |pair| w << pair }
      p w
      q = []
      [1, 2].zip([7, 8]) { |x, y| q << x + y }
      p q
    RUBY

    _(result).must_answer <<~'OUT'
      nil
      [[1, 4], [2, 5], [3, 6]]
      [["a", 1], ["b", 2]]
      [8, 10]
    OUT
  end
end
