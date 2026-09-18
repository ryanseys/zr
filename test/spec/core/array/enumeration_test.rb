# frozen_string_literal: true

require "spec_helper"

describe "Array: enumeration" do
  it "rotate, sum, product, inject and fill raise on a bad argument instead of refusing to compile" do
    result = ze0(<<~'RUBY')
      r = ([1, 2].rotate("a") rescue $!.class)
      p r

      r = ([1, 2].sum("x") rescue $!.class); p r        # Ruby: TypeError      Spinel: C compile abort
      r = ([1, 2].product(3) rescue $!.class); p r      # Ruby: TypeError      Spinel: C compile abort
      r = ([1, 2].inject(:nope) rescue $!.class); p r   # Ruby: NoMethodError  Spinel: C compile abort

      r = ([1, 2].fill(0, "x") rescue $!.class); p r    # => TypeError
      p([1, 2].rotate(1))                                # => [2, 1]
      p([1, 2].sum(3))                                   # => 6
      p([1, 2].product([3]))                             # => [[1, 3], [2, 3]]
      p([1, 2].inject(:+))                               # => 3
    RUBY

    _(result).must_answer <<~'OUT'
      TypeError
      TypeError
      TypeError
      NoMethodError
      TypeError
      [2, 1]
      6
      [[1, 3], [2, 3]]
      3
    OUT
  end

  it "dup and sort keep an unnamed receiver rooted across the allocation the copy makes" do
    result = ze0(<<~'RUBY')
      # Array#dup and Array#sort copy the receiver into a freshly allocated array.
      # That allocation can trigger a collection, so the receiver must stay rooted
      # across it -- otherwise a receiver that is only reachable as the call's
      # transient (e.g. the result of a method, not a named local) is freed mid-copy
      # and the copy reads freed memory. Exercised across every array kind under GC
      # pressure; verified clean under -fsanitize=address with SPINEL_GC_STRESS=1.
      def make_ints;  (1..200).to_a.reverse;            end
      def make_flts;  (1..200).map { |i| i.to_f }.reverse; end
      def make_strs;  (1..200).map { |i| "s#{1000 - i}" };  end
      def make_polys; (1..200).map { |i| i.even? ? i : "x#{i}" }; end

      GC.start
      p make_ints.sort.first
      p make_ints.dup.length
      GC.start
      p make_flts.sort.first
      p make_strs.sort.first
      GC.start
      p make_polys.dup.length
    RUBY

    _(result).must_answer <<~'OUT'
      1
      200
      1.0
      "s800"
      200
    OUT
  end

  it "map! transforms in place, answers the receiver, and holds a typed array to its element type" do
    result = ze0(<<~'RUBY')
      # Array#map! / #collect! transform each element in place and return the
      # (mutated) receiver. Typed arrays are homogeneous, so the block must
      # keep the element type; poly arrays accept any result.
      a = [1, 2, 3]
      r = a.map! { |x| x * 10 }
      p a
      p r

      b = ["a", "b", "c"]
      b.collect! { |s| s.upcase }
      p b

      c = [1.5, 2.5]
      c.map! { |x| x + 1.0 }
      p c

      g = [1, "two", 3]
      g.map! { |x| x }
      p g

      s = [:a, :b, :c]
      s.map! { |x| x }
      p s

      # Empty array.
      e = []
      e.map! { |x| x * 2 }
      p e
    RUBY

    _(result).must_answer <<~'OUT'
      [10, 20, 30]
      [10, 20, 30]
      ["A", "B", "C"]
      [2.5, 3.5]
      [1, "two", 3]
      [:a, :b, :c]
      []
    OUT
  end

  it "minmax_by answers the pair in one pass, and bsearch_index the leftmost index or nil" do
    result = ze0(<<~'RUBY')
      # Array reduction/search coverage: minmax_by (one-pass [min, max] by a block
      # key) and bsearch_index (find-minimum binary search returning an index or nil).
      # Receivers go through per-type method params so each stays a concrete typed
      # array, and each block uses a distinct param name (sibling blocks that reuse a
      # name share one typed C local, which would widen to poly).
      def ints(a); a; end
      def flts(a); a; end
      def strs(a); a; end
      def polys(a); a; end

      # minmax_by: ties keep the first occurrence, matching Ruby
      p ints([3, 1, 4, 1, 5]).minmax_by { |a1| -a1 }
      p ints([3, 1, 4, 1, 5, 9, 2, 6]).minmax_by { |a2| a2 }
      p strs(%w[banana apple cherry kiwi]).minmax_by { |s1| s1.length }
      p flts([1.5, 0.25, 3.0]).minmax_by { |f1| f1 }
      p polys([1, :b, "cc", 4]).minmax_by { |p1| p1.to_s.length }

      # an empty receiver yields [nil, nil] -- a generic array, not the typed kind
      p ints([]).minmax_by { |e1| e1 }
      p strs([]).minmax_by { |e2| e2.length }
      p flts([]).minmax_by { |e3| e3 }
      p polys([]).minmax_by { |e4| e4 }

      # bsearch_index: index of the first element satisfying the predicate, or nil
      p ints([1, 2, 3, 4, 5, 6]).bsearch_index { |b1| b1 >= 4 }
      p ints([1, 2, 3, 4, 5, 6]).bsearch_index { |b2| b2 >= 10 }
      p ints([1, 3, 5, 7, 9]).bsearch_index { |b3| b3 >= 5 }
      p ints([1, 3, 5, 7, 9]).bsearch_index { |b4| b4 >= 0 }

      # a poly (true/nil) predicate exercises the poly truthiness path
      p ints([1, 2, 3, 4, 5, 6]).bsearch_index { |b5| (b5 >= 4) ? true : nil }
    RUBY

    _(result).must_answer <<~'OUT'
      [5, 1]
      [1, 9]
      ["kiwi", "banana"]
      [0.25, 3.0]
      [1, "cc"]
      [nil, nil]
      [nil, nil]
      [nil, nil]
      [nil, nil]
      3
      nil
      2
      0
      3
    OUT
  end

  it "sort_by! orders in place and answers the receiver" do
    result = ze0(<<~'RUBY')
      a = [3, 1, 2]
      r = a.sort_by! { |x| -x }
      p a
      p r
      s = %w[ccc a bb]
      s.sort_by! { |w| w.length }
      p s
      f = [2.5, 0.5, 1.5]
      f.sort_by! { |g| g }
      p f
      mixed = [3, "b", 1, "a"]
      mixed.sort_by! { |m| m.to_s }
      p mixed
      e = []
      p e.sort_by! { |q| q }
      orig = [5, 1, 9]
      ali = orig
      ali.sort_by! { |z| z }
      p orig
    RUBY

    _(result).must_answer <<~'OUT'
      [3, 2, 1]
      [3, 2, 1]
      ["a", "bb", "ccc"]
      [0.5, 1.5, 2.5]
      [1, 3, "a", "b"]
      []
      [1, 5, 9]
    OUT
  end

  it "sort_by calls the key block once per element, in order, stably, and leaves the receiver alone" do
    result = ze0(<<~'RUBY')
      # sort_by lowers to a Schwartzian transform: the key block runs exactly ONCE per
      # element, in element order (not once per comparison like a naive sort), the sort
      # is stable, and the receiver is left unmodified.

      # Once per element, in input order (route through a method to exercise the runtime
      # path, not a constant fold).
      def keyed_log(arr, log)
        arr.sort_by { |x| log << x; -x }
      end
      log = []
      res = keyed_log([5, 3, 1, 4, 2], log)
      p res          # sorted descending
      p log          # the block saw each element once, in input order
      p log.length   # 5, not 20

      # Stability: equal keys keep their input order.
      def by_first(pairs)
        pairs.sort_by { |pair| pair[0] }
      end
      p by_first([[1, "a"], [2, "b"], [1, "c"], [2, "d"], [1, "e"]])

      # Float key.
      def by_negf(arr)
        arr.sort_by { |x| x * -1.5 }
      end
      p by_negf([3, 1, 2])

      # String key.
      def by_self(arr)
        arr.sort_by { |s| s }
      end
      p by_self(["banana", "apple", "cherry"])

      # Poly-array receiver, integer key derived from each element.
      def by_digits(arr)
        arr.sort_by { |x| x.to_s.length }
      end
      p by_digits([100, 5, 42])

      # Non-mutating: the receiver is unchanged after sort_by.
      a = [3, 1, 2]
      a.sort_by { |x| x }
      p a

      # Empty and single-element receivers.
      def ident(arr)
        arr.sort_by { |x| x }
      end
      p ident([])
      p ident([7])
    RUBY

    _(result).must_answer <<~'OUT'
      [5, 4, 3, 2, 1]
      [5, 3, 1, 4, 2]
      5
      [[1, "a"], [1, "c"], [1, "e"], [2, "b"], [2, "d"]]
      [3, 2, 1]
      ["apple", "banana", "cherry"]
      [5, 42, 100]
      [3, 1, 2]
      []
      [7]
    OUT
  end

  it "zip with no argument wraps each element in a one-element array" do
    result = ze0(<<~'RUBY')
      # Array#zip with nothing to zip against: each element alone in a one-element
      # array. Every zip arm was written for at least one argument, so this was
      # refused as an unsupported call.
      p([1, 2].zip)
      p([].zip)
      p(["a", "b"].zip)
      p([[1], [2]].zip)
      p([1.5].zip)

      # with arguments, unchanged
      p([1, 2].zip([3, 4]))
      p([1, 2].zip([3, 4], [5, 6]))
    RUBY

    _(result).must_answer <<~'OUT'
      [[1], [2]]
      []
      [["a"], ["b"]]
      [[[1]], [[2]]]
      [[1.5]]
      [[1, 3], [2, 4]]
      [[1, 3, 5], [2, 4, 6]]
    OUT
  end

  it "combination returns enumerator" do
    result = ze0(<<~'RUBY')
      p([1, 2, 3].combination(2).class)
      p([1, 2, 3].permutation(2).class)
      p([1, 2, 3].repeated_combination(2).class)
      a001 = [1, 2, 3]
      p a001.combination(2).class
      v001 = a001.permutation(2); p v001.class
      p([1,2,3].combination(2).to_a)
      p([1,2,3].permutation(2).to_a.size)
      r = []; [1,2,3].combination(2) { |x| r << x }; p r
    RUBY

    _(result).must_answer <<~'OUT'
      Enumerator
      Enumerator
      Enumerator
      Enumerator
      Enumerator
      [[1, 2], [1, 3], [2, 3]]
      6
      [[1, 2], [1, 3], [2, 3]]
    OUT
  end

  it "enumerator chain product and lazy size" do
    result = ze0(<<~'RUBY')
      # Enumerator::Chain over held (not flattened) sources, Enumerator.product's
      # rightmost-fastest ordering, and Lazy#size folding ops without iterating.

      p(([1, 2].each + [3, 4].each).class)
      p(([1, 2].each + [3, 4].each).to_a)
      p([1, 2].chain([3], [4, 5]).to_a)
      p([1, 2].chain([3]).size)

      class Letters
        include Enumerable
        def initialize(*xs); @xs = xs; end
        def each(&blk); @xs.each(&blk); end
      end
      p([9].chain(Letters.new(7, 8)).to_a)
      p([1, 2].chain([3]).select { |x| x > 1 })

      p(Enumerator.product([1, 2], [3, 4]).class)
      p(Enumerator.product([1, 2], [3], [4, 5]).to_a)
      p(Enumerator.product([1, 2], [3, 4]).size)

      p([1, 2, 3].lazy.map { |x| x * 2 }.size)
      p([1, 2, 3].lazy.select { |x| x > 1 }.size)
      p([1, 2, 3, 4, 5].lazy.drop(1).take(2).size)
      p((1..Float::INFINITY).lazy.size)
      p((1..Float::INFINITY).lazy.take(3).size)
    RUBY

    _(result).must_answer <<~'OUT'
      Enumerator::Chain
      [1, 2, 3, 4]
      [1, 2, 3, 4, 5]
      3
      [9, 7, 8]
      [2, 3]
      Enumerator::Product
      [[1, 3, 4], [1, 3, 5], [2, 3, 4], [2, 3, 5]]
      4
      3
      nil
      2
      Infinity
      3
    OUT
  end

  it "enumerator chain product lazy size" do
    result = ze0(<<~'RUBY')
      # Enumerator::Chain (Enumerator#+ / Enumerable#chain), Enumerator.product,
      # and Enumerator::Lazy#size -- all of which answer without iterating.

      # `+` and `chain` both build an Enumerator::Chain over the held sources.
      a = [1, 2].each
      b = [3, 4].each
      p((a + b).class)
      p((a + b).to_a)
      p((a + b).size)
      p([1, 2].chain([3], [4, 5]).to_a)
      p((1..2).chain([3]).to_a)

      # The sources are held, not flattened, so each is driven by its own #each.
      class Letters
        include Enumerable
        def initialize(*xs) = @xs = xs
        def each(&blk) = @xs.each(&blk)
      end
      p([9].chain(Letters.new(7, 8)).to_a)
      p(Letters.new(1, 2).chain([3]).map { |x| x * 2 })

      # Terminals inherited from Enumerable work over a chain.
      p([1, 2].chain([3]).select { |x| x > 1 })
      p([1, 2].chain([3]).sum)
      p([1, 2].chain([3]).include?(3))

      # Enumerator.product: rightmost source varies fastest.
      p(Enumerator.product([1, 2], [3, 4]).class)
      p(Enumerator.product([1, 2], [3, 4]).to_a)
      p(Enumerator.product([1, 2], [3], [4, 5]).to_a)
      p(Enumerator.product([1, 2], [3, 4]).size)

      # Lazy#size folds the ops that have a knowable effect; a filter makes it nil.
      p((1..10).lazy.size)
      p([1, 2, 3].lazy.map { |x| x * 2 }.size)
      p([1, 2, 3].lazy.select { |x| x > 1 }.size)
      p([1, 2, 3].lazy.take(5).size)
      p([1, 2, 3, 4, 5].lazy.drop(1).take(2).size)
      p((1..Float::INFINITY).lazy.size)
      p((1..Float::INFINITY).lazy.take(3).size)
      p((1..Float::INFINITY).lazy.map { |x| x * 2 }.first(3))
    RUBY

    _(result).must_answer <<~'OUT'
      Enumerator::Chain
      [1, 2, 3, 4]
      4
      [1, 2, 3, 4, 5]
      [1, 2, 3]
      [9, 7, 8]
      [2, 4, 6]
      [2, 3]
      6
      true
      Enumerator::Product
      [[1, 3], [1, 4], [2, 3], [2, 4]]
      [[1, 3, 4], [1, 3, 5], [2, 3, 4], [2, 3, 5]]
      4
      10
      3
      nil
      3
      2
      Infinity
      3
      [2, 4, 6]
    OUT
  end

  it "enumerator product block" do
    result = ze0(<<~'RUBY')
      # GAP -- imported from the spinel corpus at c55d9bdb.
      # Enumerator.product with a block returns the Enumerator::Product instead
      # of running the block over each tuple.
      #
      Enumerator.product([1, 2], [3]) { |a, b| p [a, b] }
      r = Enumerator.product([1, 2], [3]) { |a, b| }
      p r
      p Enumerator.product([1, 2], [3]).to_a
    RUBY

    _(result).must_answer <<~'OUT'
      [1, 3]
      [2, 3]
      nil
      [[1, 3], [2, 3]]
    OUT
  end

  it "map obj array poly field" do
    result = ze0(<<~'RUBY')
      # map over an array of objects where the block returns a polymorphic
      # field (sp_RbVal) must collect into a PolyArray, not a PtrArray that
      # casts the sp_RbVal element through (void *).
      class Box
        def initialize
          @v = 0
        end

        def taint
          @v = "x"
        end

        def v
          @v
        end
      end

      boxes = []
      boxes.push(Box.new)
      b2 = Box.new
      b2.taint
      boxes.push(b2)

      vs = boxes.map { |b| b.v }
      puts vs.length
      p vs
      p vs[0]
      p vs[1]
    RUBY

    _(result).must_answer <<~'OUT'
      2
      [0, "x"]
      0
      "x"
    OUT
  end

  it "reduce array accumulator" do
    result = ze0(<<~'RUBY')
      # `acc + elem` on an array accumulator answers a BOXED array -- the concat runs
      # through the poly adder -- which cannot be assigned to the array pointer the
      # accumulator slot holds, so the C would not compile at all.
      g = [[1, 2], [3, 4]]
      p g.reduce([]) { |acc, r| acc + r }
      p g.inject([]) { |acc, r| acc + r }

      p({ a: [1, 2], b: [3] }.reduce([]) { |acc, (_k, v)| acc + v })

      p [[1], [2, 3]].reduce([]) { |acc, r| acc + r }
      p [["a"], ["b"]].reduce([]) { |acc, r| acc + r }
      p [[1, 2]].reduce([9]) { |acc, r| acc + r }

      # the scalar accumulators are unchanged
      p [1, 2, 3].reduce(0) { |a, x| a + x }
      p [1, 2, 3].reduce("") { |a, x| a + x.to_s }
      p [1, 2, 3].reduce(:+)
    RUBY

    _(result).must_answer <<~'OUT'
      [1, 2, 3, 4]
      [1, 2, 3, 4]
      [1, 2, 3]
      [1, 2, 3]
      ["a", "b"]
      [9, 1, 2]
      6
      "123"
      6
    OUT
  end

  it "sort by array key" do
    result = ze0(<<~'RUBY')
      # sort_by with an array-returning block (the multi-key sort idiom) orders
      # element-wise through the boxed-key comparator.
      p [[1, 2], [1, 1], [0, 5]].sort_by { |a, b| [a, b] }
      p ["bb", "a", "ccc"].sort_by { |s| [s.length, s] }
      p [["b", 2], ["a", 2], ["a", 1]].sort_by { |x, y| [x, y] }
      p [3, 1, 2].sort_by { |x| -x }
      rows = [{ n: "z", v: 1 }, { n: "a", v: 1 }]
      p rows.sort_by { |r| [r[:v], r[:n]] }.map { |r| r[:n] }
    RUBY

    _(result).must_answer <<~'OUT'
      [[0, 5], [1, 1], [1, 2]]
      ["a", "bb", "ccc"]
      [["a", 1], ["a", 2], ["b", 2]]
      [3, 2, 1]
      ["a", "z"]
    OUT
  end

  it "zip argument each" do
    result = ze0(<<~'RUBY')
      # `zip`'s arguments must respond to :each. The emitters read every argument as
      # a container regardless of its type, so a nil quietly became a column of nils
      # and an Integer or a String stopped the C build -- found verifying the gaps
      # left after PR #4029, whose sweep of the typed slots did not reach this one.
      #
      # A Hash and an Enumerator DO respond to :each, and were the same ill-typed C
      # for the opposite reason: the slot was spelled sp_PolyArray* and handed an
      # sp_SymPolyHash*.
      def try
        yield
      rescue => e
        p [e.class, e.message]
      end
      # valid forms keep working
      p [1,2].zip([3,4])
      p [1,2].zip([3,4], [5,6])
      p [1,2].zip([3])
      p [1,2].zip(1..2)
      p ["a","b"].zip([1,2])
      p [1.5].zip([2.5])
      p [1,2].zip({a: 1, b: 2})
      p [1,2].zip([3,4].each)
      p [[1],[2]].zip([[3],[4]])
      def poly(f) = f ? [1,2] : "s"
      p poly(true).zip([3,4])
      xs = [[3,4], nil][0]
      p [1,2].zip(xs)

      # every scalar is CRuby's TypeError naming the class
      try { [1,2].zip(nil) }
      try { [1,2].zip([3,4], nil) }
      try { [1,2].zip(5) }
      try { [1,2].zip("ab") }
      try { [1,2].zip(:s) }
      try { [1,2].zip(true) }
      try { [1,2].zip(1.5) }
      try { ["a"].zip(nil) }
      try { [1.5].zip(nil) }
      try { poly(true).zip(nil) }
    RUBY

    _(result).must_answer <<~'OUT'
      [[1, 3], [2, 4]]
      [[1, 3, 5], [2, 4, 6]]
      [[1, 3], [2, nil]]
      [[1, 1], [2, 2]]
      [["a", 1], ["b", 2]]
      [[1.5, 2.5]]
      [[1, [:a, 1]], [2, [:b, 2]]]
      [[1, 3], [2, 4]]
      [[[1], [3]], [[2], [4]]]
      [[1, 3], [2, 4]]
      [[1, 3], [2, 4]]
      [TypeError, "wrong argument type NilClass (must respond to :each)"]
      [TypeError, "wrong argument type NilClass (must respond to :each)"]
      [TypeError, "wrong argument type Integer (must respond to :each)"]
      [TypeError, "wrong argument type String (must respond to :each)"]
      [TypeError, "wrong argument type Symbol (must respond to :each)"]
      [TypeError, "wrong argument type TrueClass (must respond to :each)"]
      [TypeError, "wrong argument type Float (must respond to :each)"]
      [TypeError, "wrong argument type NilClass (must respond to :each)"]
      [TypeError, "wrong argument type NilClass (must respond to :each)"]
      [TypeError, "wrong argument type NilClass (must respond to :each)"]
    OUT
  end

  it "zip poly operands" do
    result = ze0(<<~'RUBY')
      # `ai.zip(tj) { }` where both rows are elements of a poly table: neither side
      # is a statically typed array. The block form handed the sp_RbVal straight to
      # the typed array accessor (invalid C), and with a poly RECEIVER the call fell
      # through to the runtime dispatch, which has no zip arm and raised.

      def mat(n)
        rows = []
        n.times do |i|
          row = []
          n.times { |j| row << (i + j).to_f }
          rows << row
        end
        rows
      end

      def mul(a, t)
        c = []
        a.each_with_index do |ai, i|
          ci = []
          t.each_with_index do |tj, j|
            s = 0.0
            ai.zip(tj) do |av, tv|
              s += av * tv
            end
            ci[j] = s
          end
          c << ci
        end
        c
      end

      m = mat(3)
      r = mul(m, m)
      p r[0][0]
      p r[2][2]
    RUBY

    _(result).must_answer "5.0\n29.0\n"
  end
end
