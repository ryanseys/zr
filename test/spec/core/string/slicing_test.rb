# frozen_string_literal: true

require "spec_helper"

describe "String: slicing" do
  it "array product block sample and each slice return" do
    result = ze0(<<~'RUBY')
      # product's block form yields each tuple and returns self; sample(-n) has
      # its own message; each_slice/each_cons block forms return the receiver.

      r = []
      ret = [1, 2].product([3, 4]) { |t| r << t }
      p r
      p ret
      p([1, 2, 3].each_slice(2) { |s| })
      p([1, 2, 3].each_cons(2) { |s| })
      begin
        [1, 2].sample(-1)
      rescue ArgumentError => e
        p e.message
      end
    RUBY

    _(result).must_answer <<~'OUT'
      [[1, 3], [1, 4], [2, 3], [2, 4]]
      [1, 2]
      [1, 2, 3]
      [1, 2, 3]
      "negative sample number"
    OUT
  end

  it "array slice bang" do
    result = ze0(<<~'RUBY')
      # Array#slice!(from, n) on every typed array. Returns a fresh
      # array of n elements starting at `from`, and mutates the receiver
      # to remove them. IntArray uses its `start` field for an O(1) head
      # peel; the others shift the tail down to fill the hole.

      # --- IntArray: head peel (from == 0) ---
      arr = [10, 20, 30, 40, 50]
      head = arr.slice!(0, 2)
      puts head.length        # 2
      puts head[0]            # 10
      puts head[1]            # 20
      puts arr.length         # 3
      puts arr[0]             # 30

      # --- IntArray: middle slice (from > 0, tail shift) ---
      arr2 = [1, 2, 3, 4, 5, 6, 7]
      mid = arr2.slice!(2, 3)
      puts mid[0]             # 3
      puts mid[2]             # 5
      puts arr2.length        # 4
      puts arr2[2]            # 6 (tail shifted down)
      puts arr2[3]            # 7

      # --- IntArray: n > available, clamped ---
      arr3 = [100, 200, 300]
      big = arr3.slice!(1, 999)
      puts big.length         # 2
      puts arr3.length        # 1

      # --- FloatArray ---
      fa = [1.5, 2.5, 3.5, 4.5, 5.5]
      fh = fa.slice!(0, 2)
      puts fh.length          # 2
      puts fh[0]              # 1.5
      puts fa.length          # 3
      puts fa[0]              # 3.5

      # --- StrArray ---
      sa = ["a", "b", "c", "d", "e"]
      sh = sa.slice!(1, 2)
      puts sh.length          # 2
      puts sh[0]              # b
      puts sh[1]              # c
      puts sa.length          # 3
      puts sa[0]              # a
      puts sa[1]              # d (tail shifted down)
      puts sa[2]              # e

      # --- SymArray (shares the IntArray helper internally) ---
      syms = [:foo, :bar, :baz, :qux]
      sym_h = syms.slice!(0, 2)
      puts sym_h.length       # 2
      puts sym_h[0]           # foo
      puts syms.length        # 2
      puts syms[0]            # baz
      puts syms[1]            # qux

      # --- PtrArray (array of obj_X instances) ---
      class Box
        attr_reader :v
        def initialize(v); @v = v; end
      end

      pa = [Box.new(10), Box.new(20), Box.new(30), Box.new(40)]
      ph = pa.slice!(1, 2)
      puts ph.length          # 2
      puts ph[0].v            # 20
      puts ph[1].v            # 30
      puts pa.length          # 2
      puts pa[0].v            # 10
      puts pa[1].v            # 40 (tail shifted down)

      # --- PolyArray (heterogeneous literal) ---
      poly = [1, "two", :three, 4.5, "five"]
      poly_h = poly.slice!(1, 3)
      puts poly_h.length      # 3
      puts poly_h[0]          # two
      puts poly_h[2]          # 4.5
      puts poly.length        # 2
      puts poly[0]            # 1
      puts poly[1]            # five
    RUBY

    _(result).must_answer <<~'OUT'
      2
      10
      20
      3
      30
      3
      5
      4
      6
      7
      2
      1
      2
      1.5
      3
      3.5
      2
      b
      c
      3
      a
      d
      e
      2
      foo
      2
      baz
      qux
      2
      20
      30
      2
      10
      40
      3
      two
      4.5
      2
      1
      five
    OUT
  end

  it "array slice bang bounds" do
    result = ze0(<<~'RUBY')
      # GAP -- imported from the spinel corpus at c55d9bdb.
      # Array#slice! past the end answers [] where ruby answers nil.
      #
      a = [1, 2, 3]
      p a.slice!(1, -1)
      p a
      b = [1, 2, 3]
      p b.slice!(..1)
      p b
      c = [1, 2, 3]
      p c.slice!(9, 2)
      d = [1, 2, 3]
      p d.slice!(0..1)
      p d
      e = [1, 2, 3]
      p e.slice!(1..)
      p e
      f = ["x", "y", "z"]
      p f.slice!(..0)
      p f
      g = [1, 2, 3]
      p g.slice!(0, -2)
      p g
    RUBY

    _(result).must_answer <<~'OUT'
      nil
      [1, 2, 3]
      [1, 2]
      [3]
      nil
      [1, 2]
      [3]
      [2, 3]
      [1]
      ["x"]
      ["y", "z"]
      nil
      [1, 2, 3]
    OUT
  end

  it "array slice bang out of range" do
    result = ze0(<<~'RUBY')
      # slice!(start, len) with a start past the end is nil, not an empty slice --
      # only start == length answers []. The start was clamped to the length, so
      # every out-of-range call answered [].
      a=[1,2,3]; p a.slice!(9,2); p a
      b=[1,2,3]; p b.slice!(3,2); p b
      c=[1,2,3]; p c.slice!(1,2); p c
      d=[1,2,3]; p d.slice!(-1,1); p d
      e=[1,2,3]; p e.slice!(1,0); p e
      f=["a","b"]; p f.slice!(9,1); p f
      g=[1,:x]; p g.slice!(9,1); p g
    RUBY

    _(result).must_answer <<~'OUT'
      nil
      [1, 2, 3]
      []
      [1, 2, 3]
      [2, 3]
      [1]
      [3]
      [1, 2]
      []
      [1, 2, 3]
      nil
      ["a", "b"]
      nil
      [1, :x]
    OUT
  end

  it "array slice before after" do
    result = ze0(<<~'RUBY')
      # Array#slice_before / #slice_after on int_array with a literal
      # int delimiter.
      puts [1, 2, 3, 4, 5].slice_before(3).to_a.inspect
      puts [1, 2, 3, 4, 5].slice_after(3).to_a.inspect
      # Empty matches: delimiter never appears.
      puts [1, 2, 3].slice_before(99).to_a.inspect
    RUBY

    _(result).must_answer <<~'OUT'
      [[1, 2], [3, 4, 5]]
      [[1, 2, 3], [4, 5]]
      [[1, 2, 3]]
    OUT
  end

  it "array slice sample methods" do
    result = ze0(<<~'RUBY')
      # Array slicing/sampling coverage: rotate(n), slice(start, len) / [start, len],
      # sample(n), and the n-arg min(n)/max(n) forms across the typed-array kinds and
      # poly arrays. Receivers are routed through per-type method params so each stays
      # a concrete typed array (a shared param would widen to poly), exercising the
      # runtime builtin path rather than constant folding.
      def ints(a); a; end
      def strs(a); a; end
      def flts(a); a; end
      def polys(a); a; end

      # rotate: non-mutating, wraps around, negative counts rotate right
      p ints([1, 2, 3, 4, 5]).rotate(2)
      p ints([1, 2, 3, 4, 5]).rotate
      p ints([1, 2, 3, 4, 5]).rotate(-1)
      p strs(%w[a b c d]).rotate(1)
      p polys([1, :b, "c", 4]).rotate(2)

      # the receiver is left unmodified by the non-mutating rotate
      orig = ints([1, 2, 3])
      orig.rotate(1)
      p orig

      # slice(start, len) and the equivalent [start, len]
      p ints([1, 2, 3, 4, 5]).slice(1, 3)
      p ints([1, 2, 3, 4, 5])[1, 3]
      p strs(%w[a b c d e]).slice(2, 2)
      p polys([1, :b, "c", 4]).slice(1, 2)

      # min(n) / max(n): n smallest ascending, n largest descending
      p ints([3, 1, 4, 1, 5, 9, 2]).min(3)
      p ints([3, 1, 4, 1, 5, 9, 2]).max(2)
      p flts([1.5, 0.5, 2.5]).min(2)
      p strs(%w[banana apple cherry]).max(2)

      # sample(n): nondeterministic order, so assert on length and (when n >= size)
      # the sorted full set, which is deterministic
      p ints([1, 2, 3, 4, 5]).sample(2).length
      p ints([5, 3, 1, 4, 2]).sample(10).sort
      p strs(%w[a b c]).sample(5).sort
    RUBY

    _(result).must_answer <<~'OUT'
      [3, 4, 5, 1, 2]
      [2, 3, 4, 5, 1]
      [5, 1, 2, 3, 4]
      ["b", "c", "d", "a"]
      ["c", 4, 1, :b]
      [1, 2, 3]
      [2, 3, 4]
      [2, 3, 4]
      ["c", "d"]
      [:b, "c"]
      [1, 1, 2]
      [9, 5]
      [0.5, 1.5]
      ["cherry", "banana"]
      2
      [1, 2, 3, 4, 5]
      ["a", "b", "c"]
    OUT
  end

  it "array slice start oob nil" do
    result = ze0(<<~'RUBY')
      # Array#[start, len] / #slice(start, len) with start outside [-len, len]
      # returns nil like CRuby (start == len is the empty slice; a negative
      # length is nil) -- on typed int/str arrays and poly arrays, through both
      # the nil-capable and the plain slice arms.
      a = [1, 2, 3]
      p a[3, 1]
      p a[4, 1]
      p a[-4, 1]
      p a[3, 0]
      p a[2, -1]
      p a.slice(3, 1)
      p a.slice(5, 2)
      s = ["x", "y"]
      p s[2, 1]
      p s[3, 1]
      p s[2, 0]
      m = [1, "a", :b]
      p m[3, 1]
      p m[4, 2]
      p m[3, 0]
    RUBY

    _(result).must_answer <<~'OUT'
      []
      nil
      nil
      []
      nil
      []
      nil
      []
      nil
      []
      []
      nil
      []
    OUT
  end

  it "array slice when chunk" do
    result = ze0(<<~'RUBY')
      # Array#slice_when and Array#chunk on int_array. Materialises
      # directly (no Enumerator); .to_a is a no-op on the result.

      puts [1, 2, 3, 4, 5].slice_when { |a, b| b > 3 }.to_a.inspect
      puts [1, 2, 2, 3, 3, 3, 4].chunk { |x| x }.to_a.inspect
      # Empty array: empty result.
      puts [].slice_when { |a, b| true }.to_a.inspect
    RUBY

    _(result).must_answer <<~'OUT'
      [[1, 2, 3], [4], [5]]
      [[1, [1]], [2, [2, 2]], [3, [3, 3, 3]], [4, [4]]]
      []
    OUT
  end

  it "case when string range" do
    result = ze0(<<~'RUBY')
      # case/when with a String scrutinee and string-range conditions: Range#===
      # is cover? (lexicographic <=>), including exclusive, beginless, endless,
      # and non-literal endpoints, in both statement and value position.
      def label(c)
        case c
        when "a".."m" then "low"
        else "hi"
        end
      end
      p label("c")
      p label("a")
      p label("m")
      p label("n")
      p label("cat")
      p label("")

      def label_excl(c)
        case c
        when "a"..."m" then "low"
        else "hi"
        end
      end
      p label_excl("l")
      p label_excl("m")
      p label_excl("lz")

      def label_var(c, lo, hi)
        case c
        when lo..hi then "in"
        else "out"
        end
      end
      p label_var("dog", "d", "f")
      p label_var("cat", "d", "f")

      def label_open(c)
        case c
        when ..."d" then "early"
        when "n".. then "late"
        else "mid"
        end
      end
      p label_open("b")
      p label_open("q")
      p label_open("g")

      def bucket(c)
        r = case c
            when "a".."m" then 1
            when "x" then 2
            else 3
            end
        r
      end
      p bucket("b")
      p bucket("x")
      p bucket("q")
    RUBY

    _(result).must_answer <<~'OUT'
      "low"
      "low"
      "low"
      "hi"
      "low"
      "hi"
      "low"
      "hi"
      "low"
      "in"
      "out"
      "early"
      "late"
      "mid"
      1
      2
      3
    OUT
  end

  it "clamp string and range" do
    result = ze0(<<~'RUBY')
      # Comparable#clamp — string receiver and Range arg form.
      # 2-arg int form was already supported by #899.
      puts "b".clamp("a", "c")
      puts "z".clamp("a", "c")
      puts "a".clamp("b", "y")

      # Range arg on Integer
      puts 5.clamp(1..10)
      puts 0.clamp(1..10)
      puts 11.clamp(1..10)

      # Range arg on String
      puts "m".clamp("a".."z")
      puts "Z".clamp("a".."z")
    RUBY

    _(result).must_answer <<~'OUT'
      b
      c
      b
      5
      1
      10
      m
      a
    OUT
  end

  it "each slice and frozen hash filter error messages" do
    result = ze0(<<~'RUBY')
      # each_slice(0) says "invalid slice size", each_cons(0) just "invalid
      # size"; an in-place Hash filter on a frozen receiver raises FrozenError.

      begin; [1, 2, 3].each_slice(0).to_a; rescue ArgumentError => e; puts e.message; end
      begin; [1, 2, 3].each_cons(0).to_a; rescue ArgumentError => e; puts e.message; end
      begin; {a: 1}.freeze.reject! { |k, v| true }; rescue => e; puts e.class; end
    RUBY

    _(result).must_answer <<~'OUT'
      invalid slice size
      invalid size
      FrozenError
    OUT
  end

  it "each slice cons enumerator" do
    result = ze0(<<~'RUBY')
      # Blockless Array#each_slice(n) / Array#each_cons(n) return a materialized
      # Enumerator: a first-class value supporting to_a / next / peek / size / take /
      # first(n). The block and .map/.collect chain forms must keep working too.

      # --- blockless: a first-class Enumerator value ---
      e = [1, 2, 3, 4, 5].each_slice(2)
      p e.class
      p e.to_a
      p e.size
      p e.next
      p e.next
      p e.peek
      p e.next
      p [1, 2, 3, 4, 5].each_slice(2).first(2)
      p [1, 2, 3, 4, 5].each_slice(2).take(2)

      c = [1, 2, 3, 4].each_cons(2)
      p c.class
      p c.to_a
      p c.size

      # non-divisible and short receivers
      p [1, 2, 3, 4, 5].each_slice(3).to_a
      p [1, 2, 3].each_slice(5).to_a
      p [1].each_cons(2).to_a
      p %w[a b c d e].each_slice(2).to_a

      # --- assigned, then materialized ---
      slices = [10, 20, 30, 40, 50].each_slice(2)
      arr = slices.to_a
      p arr.length
      p arr

      # --- .map / .collect chains (fold-unrolled; must not regress) ---
      p [1, 2, 3, 4, 5].each_slice(2).map { |s| s.sum }
      p [1, 2, 3, 4, 5].each_slice(2).collect { |s| s.first }
      p [1, 2, 3, 4].each_cons(2).map { |a, b| a + b }
      p [1, 2, 3, 4].each_cons(2).map { |pair| pair }
      p [1, 2, 3, 4].each_cons(2).map { |(a, b)| a * b }
      p [1.5, 2.5, 3.5].each_slice(2).map { |s| s.sum }
      p %w[a b c].each_slice(2).map { |s| s.join }
      p [1, 2, 3, 4].each_cons(2).with_index.map { |w, i| [w, i] }

      # --- direct block form (yields each slice / window, returns receiver) ---
      acc = []
      [1, 2, 3, 4, 5].each_slice(2) { |s| acc << s }
      p acc
      acc2 = []
      [1, 2, 3, 4].each_cons(2) { |w| acc2 << w }
      p acc2

      # --- argument errors ---
      begin
        [1, 2, 3].each_slice(0).to_a
      rescue ArgumentError => err
        p err.message
      end
      begin
        [1, 2, 3].each_cons(0).to_a
      rescue ArgumentError => err
        p err.message
      end
    RUBY

    _(result).must_answer <<~'OUT'
      Enumerator
      [[1, 2], [3, 4], [5]]
      3
      [1, 2]
      [3, 4]
      [5]
      [5]
      [[1, 2], [3, 4]]
      [[1, 2], [3, 4]]
      Enumerator
      [[1, 2], [2, 3], [3, 4]]
      3
      [[1, 2, 3], [4, 5]]
      [[1, 2, 3]]
      []
      [["a", "b"], ["c", "d"], ["e"]]
      3
      [[10, 20], [30, 40], [50]]
      [3, 7, 5]
      [1, 3, 5]
      [3, 5, 7]
      [[1, 2], [2, 3], [3, 4]]
      [2, 6, 12]
      [4.0, 3.5]
      ["ab", "c"]
      [[[1, 2], 0], [[2, 3], 1], [[3, 4], 2]]
      [[1, 2], [3, 4], [5]]
      [[1, 2], [2, 3], [3, 4]]
      "invalid slice size"
      "invalid size"
    OUT
  end

  it "each slice cons to a" do
    result = ze0(<<~'RUBY')
      # Array#each_slice(n) / #each_cons(n) without a block return an Enumerator;
      # materializing it with #to_a yields the array of slices / windows. Also the
      # single-param `.map { |s| ... }` chain binds the whole slice (not an element).
      p [1, 2, 3, 4, 5].each_slice(2).to_a       # [[1, 2], [3, 4], [5]]
      p [1, 2, 3, 4].each_cons(2).to_a           # [[1, 2], [2, 3], [3, 4]]
      p ["a", "b", "c", "d", "e"].each_slice(2).to_a

      nums = [1, 2, 3, 4, 5, 6]
      p nums.each_slice(3).to_a

      # the single-param map chain binds the slice as a whole
      p [1, 2, 3, 4, 5].each_slice(2).map { |s| s.sum }   # [3, 7, 5]
      p [1, 2, 3, 4].each_cons(2).map { |w| w.sum }       # [3, 5, 7]
      # many params destructure the slice into elements
      p [1, 2, 3, 4].each_slice(2).map { |a, b| a * b }   # [2, 12]
    RUBY

    _(result).must_answer <<~'OUT'
      [[1, 2], [3, 4], [5]]
      [[1, 2], [2, 3], [3, 4]]
      [["a", "b"], ["c", "d"], ["e"]]
      [[1, 2, 3], [4, 5, 6]]
      [3, 7, 5]
      [3, 5, 7]
      [2, 12]
    OUT
  end

  it "each slice map" do
    result = ze0(<<~'RUBY')
      # Issue #829: array.each_slice(n).map { |x, y| ... } chains.
      a = [1, 3, 6, 10]
      p a.each_slice(2).map { |x, y| y - x }

      # A second chain to verify reuse.
      b = [2, 4, 8, 16]
      p b.each_slice(2).map { |x, y| y * x }

      # A single destructured param |(lo, hi)| splits the slice into its elements.
      c = [1, 3, 6, 10]
      p c.each_slice(2).map { |(lo, hi)| hi - lo }
    RUBY

    _(result).must_answer <<~'OUT'
      [2, 4]
      [8, 128]
      [2, 4]
    OUT
  end

  it "enum chain splat sliceb wave6" do
    result = ze0(<<~'RUBY')
      # String#slice! statement forms, literal-splat expansion, each_codepoint
      # enumerator, hash comparator min/max, Hash#flat_map single-param pair,
      # chunk/slice enumerator chains (each/select/reject/flat_map),
      # &:sym.to_proc as a block argument, and lazy take(n).force.
      s = "hello"
      s.slice!(0)
      puts s
      s = "hello"
      s.slice!(1..2)
      puts s
      s = "hello"
      s.slice!(99)
      puts s
      p [1, 2, 3].min(*[2])
      p [1, 2, 3].first(*[2])
      add = ->(a, b) { a + b }
      p add.(*[3, 4])
      p "abc".each_codepoint.to_a
      h = { a: 1, b: 3, c: 2 }
      p h.min { |x, y| x[1] <=> y[1] }
      p h.max { |x, y| x[1] <=> y[1] }
      p h.minmax { |x, y| x[1] <=> y[1] }
      p({ a: [1, 2], b: [3, 4] }.flat_map { |pair| pair[1] })
      p({ a: 1, b: 2 }.flat_map { |k, v| [k, v] })
      [1, 1, 2, 3].chunk { |x| x }.each { |k, v| p [k, v] }
      p [1, 2, 3, 4].each_slice(2).select { |sl| sl.sum > 3 }
      p [1, 2, 3, 4].each_slice(2).reject { |sl| sl.sum > 3 }
      p [1, 2, 3, 4].each_cons(2).flat_map { |sl| sl }
      p ["a", "b"].map(&:upcase.to_proc)
      p [1, 2, 3, 4, 5, 6].lazy.map { |x| x * 2 }.take(3).force
      p (1..Float::INFINITY).lazy.map { |x| x * x }.take(3).force
    RUBY

    _(result).must_answer <<~'OUT'
      ello
      hlo
      hello
      [1, 2]
      [1, 2]
      7
      [97, 98, 99]
      [:a, 1]
      [:b, 3]
      [[:a, 1], [:b, 3]]
      [1, 2, 3, 4]
      [:a, 1, :b, 2]
      [1, [1, 1]]
      [2, [2]]
      [3, [3]]
      [[3, 4]]
      [[1, 2]]
      [1, 2, 2, 3, 3, 4]
      ["A", "B"]
      [2, 4, 6]
      [1, 4, 9]
    OUT
  end

  it "hash shorthand str" do
    result = ze0(<<~'RUBY')
      # Hash shorthand with string-valued local variable.
      # Regression: scan_locals's first pass infers the hash literal value type
      # before the local's type lands in @scope_names, so `{first:}` mis-types
      # as int. Pre-fix: declared sp_SymIntHash / sp_SymPolyHash but built with
      # string values -> incompatible-pointer C error or unknown-type error.

      # Single string-valued shorthand
      name = "ada"
      who1 = {name:}
      puts who1[:name]
      puts who1.length

      # Mixed string-valued shorthand and explicit string pair
      first = "ada"
      who2 = {first:, last: "lovelace"}
      puts who2[:first]
      puts who2[:last]
      puts who2.length

      # Compare against the explicit equivalent (both should produce the same output)
      who3 = {first: first, last: "lovelace"}
      puts who3[:first]
      puts who3[:last]
      puts who3.length

      # Three string-valued shorthand keys
      a = "alpha"
      b = "beta"
      c = "gamma"
      who4 = {a:, b:, c:}
      puts who4[:a]
      puts who4[:b]
      puts who4[:c]
      puts who4.length

      # Mixed shorthand and explicit pairs round-tripping a single value type
      x = "one"
      y = "two"
      who5 = {x:, y:, z: "three"}
      puts who5[:x]
      puts who5[:y]
      puts who5[:z]
      puts who5.length

      # Has-key membership over the inferred hash type
      puts who1.has_key?(:name)
      puts who2.has_key?(:first)
      puts who2.has_key?(:missing)
    RUBY

    _(result).must_answer <<~'OUT'
      ada
      1
      ada
      lovelace
      2
      ada
      lovelace
      2
      alpha
      beta
      gamma
      3
      one
      two
      three
      3
      true
      true
      false
    OUT
  end

  it "hash slice" do
    result = ze0(<<~'RUBY')
      # Hash#slice picks the given keys into a fresh hash (missing keys skipped).
      p({ a: 1, b: 2, c: 3 }.slice(:a, :b))
      p({ a: 1 }.slice(:zz))
      h = { "x" => 1, "y" => 2 }
      p h.slice("y")
      p({ a: 1, b: 2 }.except(:a))
    RUBY

    _(result).must_answer <<~'OUT'
      {a: 1, b: 2}
      {}
      {"y" => 2}
      {b: 2}
    OUT
  end

  it "integer bit slice negative start and width" do
    result = ze0(<<~'RUBY')
      # Integer#[start, len]: a negative start shifts left (5[-1,3] == 2), a
      # negative len keeps the whole shifted value with no mask (5[2,-1] == 1,
      # 255[0,-5] == 255), a zero len selects nothing, and a positive len masks.

      p 0b1011010[1, 3]
      p 255[0, 4]
      p 5[2, -1]
      p 5[-1, 3]
      p 255[0, -5]
      p 7[0, 0]
      p(-1[60, 8])
    RUBY

    _(result).must_answer <<~'OUT'
      5
      15
      1
      2
      255
      0
      255
    OUT
  end

  it "last paren backreference and adjacent interpolation" do
    result = ze0(<<~'RUBY')
      # `$+` is the highest-numbered group that PARTICIPATED, skipping
      # declared-but-unmatched ones (rb_reg_match_last, re.c:2093), and is nil
      # when only group 0 matched -- it never reports the whole match.
      #
      # Backslash-continued adjacent literals parse as an InterpolatedStringNode
      # whose own parts are InterpolatedStringNodes, so parts must flatten
      # recursively rather than being treated as leaves.

      "abc123" =~ /([a-z]+)(\d+)/
      puts $1
      puts $2
      puts $+
      "abc" =~ /([a-z]+)(\d+)?/
      puts $+
      "xyz" =~ /xyz/
      p $+
      "b" =~ /(a)|(b)|(c)/
      p $+
      def svg(px, inner)
        "<a width='#{px}' " \
        "height='#{px}'>#{inner}</a>"
      end
      def tail(n)
        "n=#{n}" \
        " done"
      end
      puts svg(16, "x")
      puts tail(7)
    RUBY

    _(result).must_answer <<~'OUT'
      abc
      123
      123
      abc
      nil
      "b"
      <a width='16' height='16'>x</a>
      n=7 done
    OUT
  end

  it "lazy drop while each slice" do
    result = ze0(<<~'RUBY')
      p (1..10).lazy.drop_while { |x| x < 3 }.to_a
      p (1..10).lazy.each_slice(2).to_a
      p (1..10).lazy.each_slice(3).to_a
      p (1..10).lazy.map { |x| x * 2 }.drop_while { |x| x < 9 }.to_a
      p (1..10).lazy.select { |x| x.even? }.each_slice(2).to_a
      p (1..10).lazy.each_slice(4).first(2)
    RUBY

    _(result).must_answer <<~'OUT'
      [3, 4, 5, 6, 7, 8, 9, 10]
      [[1, 2], [3, 4], [5, 6], [7, 8], [9, 10]]
      [[1, 2, 3], [4, 5, 6], [7, 8, 9], [10]]
      [10, 12, 14, 16, 18, 20]
      [[2, 4], [6, 8], [10]]
      [[1, 2, 3, 4], [5, 6, 7, 8]]
    OUT
  end

  it "negative range slice" do
    result = ze0(<<~'RUBY')
      # #496. `a[1..-2]` returned [] in spinel where CRuby returns
      # [a[1], a[2], a[3]]. Codegen emitted `sp_IntArray_slice(arr, 1,
      # -2 - 1 + 1)` (length = -2), and the runtime's `len <= 0` early
      # return produced an empty array. Fix: new `_slice_range` /
      # `_sub_range_r` runtime helpers take (start, end, exclusive)
      # and normalize negative end against the collection length
      # before computing slice length.
      #
      # Test covers the four receiver shapes that route through the
      # fixed emit sites: int_array, float_array, str_array, and
      # string. Exclusive (`...`) and inclusive (`..`) forms both
      # exercise negative endpoints.

      a = [0, 1, 2, 3, 4]
      p a[1..-2]   # inclusive: [1, 2, 3]
      p a[1...-1]  # exclusive: [1, 2, 3]
      p a[-3..-1]  # both negative: [2, 3, 4]
      p a[0..-1]   # whole array: [0, 1, 2, 3, 4]
      p a[2..-3]   # single element (-3 -> 2, so a[2..2]): [2]
      p a[-4..-2]  # negative start, negative end: [1, 2, 3]

      f = [0.5, 1.5, 2.5, 3.5]
      p f[1..-2]   # [1.5, 2.5]

      s_arr = ["a", "b", "c", "d", "e"]
      p s_arr[1..-2]   # ["b", "c", "d"]

      s = "hello"
      p s[1..-2]   # "ell"
      p s[1...-1]  # "ell"
      p s[-3..-1]  # "llo"
      p s[-4..-2]  # negative start + end: "ell"
    RUBY

    _(result).must_answer <<~'OUT'
      [1, 2, 3]
      [1, 2, 3]
      [2, 3, 4]
      [0, 1, 2, 3, 4]
      [2]
      [1, 2, 3]
      [1.5, 2.5]
      ["b", "c", "d"]
      "ell"
      "ell"
      "llo"
      "ell"
    OUT
  end

  it "poly slice assign" do
    result = ze0(<<~'RUBY')
      # `compile_slice_assign` had no `rt == "poly"` arm; the
      # fall-through used arg[1] (the slice length) as the assignment
      # value and silently dropped the rhs entirely.
      #
      # Trigger: `arr[i, n] = src` where arr's slot type is plain poly
      # (widened via heterogeneous writes).

      class C
        def init_arr
          @arr = [10, 20, 30, 40, 50]
        end
        def init_str
          @arr = "scalar"     # widens slot to poly
        end
        def replace
          @arr[1, 2] = [99, 88]
        end
        def at(i); @arr[i]; end
      end

      c = C.new
      c.init_arr
      c.replace
      puts c.at(0)
      puts c.at(1)
      puts c.at(2)
    RUBY

    _(result).must_answer <<~'OUT'
      10
      99
      88
    OUT
  end

  it "Section 1: ptr array map" do
    result = ze0(<<~'RUBY')
      # Pointer-array (`<obj>_ptr_array`) coverage — typed-obj `[]` map,
      # value-class instances in array literals (and via `push`/`<<`),
      # and slot widening from `[nil] * N` writes. Was four tests; the
      # only class-name collisions were Foo (same definition reused
      # across the two value-class sections — kept once) and Bag (two
      # unrelated shapes — section 1's Bag renamed to MapBag).


      # `compile_map_expr` had no `ptr_array` recv branch — `.map { ... }`
      # on a typed `obj_X[]` ivar/local fell through to the trailing
      # `"0"` placeholder.
      class Box
        attr_reader :v
        def initialize(v); @v = v; end
      end

      class MapBag
        def initialize
          @items = [Box.new(1), Box.new(2), Box.new(3)]
        end
        def doubled
          @items.map { |b| b.v * 2 }
        end
        def names
          @items.map { |b| "v=#{b.v}" }
        end
      end

      mbag = MapBag.new
      mints = mbag.doubled
      puts mints.length    # 3
      puts mints[0]        # 2
      puts mints[2]        # 6
      mnames = mbag.names
      puts mnames.length   # 3
      puts mnames[0]       # v=1
      puts mnames[2]       # v=3
    RUBY

    _(result).must_answer <<~'OUT'
      3
      2
      6
      3
      v=1
      v=3
    OUT
  end

  it "Section 2 + 3: value-class instances in ptr array (literal + push)" do
    result = ze0(<<~'RUBY')
      # Pointer-array (`<obj>_ptr_array`) coverage — typed-obj `[]` map,
      # value-class instances in array literals (and via `push`/`<<`),
      # and slot widening from `[nil] * N` writes. Was four tests; the
      # only class-name collisions were Foo (same definition reused
      # across the two value-class sections — kept once) and Bag (two
      # unrelated shapes — section 1's Bag renamed to MapBag).


      # A class with no attr_writers / no mutating methods would normally
      # be value-type'd, but its instances landing in an array literal or
      # being push'd into one must demote it to a heap-allocated obj so
      # `sp_PtrArray_push`'s `void *` arg type-checks. PR #87 covered the
      # literal case; #91 (follow-up) extended it to push / <<.
      class Foo
        def initialize(x); @x = x; end
        attr_reader :x
      end

      # Literal form.
      flit = [Foo.new(1), Foo.new(2), Foo.new(3)]
      puts flit.length
      flit.each { |f| puts f.x }

      # `push` form.
      fpush = []
      fpush.push(Foo.new(1))
      fpush.push(Foo.new(2))
      puts fpush.length
      fpush.each { |f| puts f.x }

      # `<<` form (same code path through the parser).
      fsh = []
      fsh << Foo.new(10)
      fsh << Foo.new(20)
      fsh << Foo.new(30)
      puts fsh.length
      fsh.each { |f| puts f.x }
    RUBY

    _(result).must_answer <<~'OUT'
      3
      1
      2
      3
      2
      1
      2
      3
      10
      20
      30
    OUT
  end

  it "Section 4: ptr array slot widening from [nil] * N" do
    result = ze0(<<~'RUBY')
      # Pointer-array (`<obj>_ptr_array`) coverage — typed-obj `[]` map,
      # value-class instances in array literals (and via `push`/`<<`),
      # and slot widening from `[nil] * N` writes. Was four tests; the
      # only class-name collisions were Foo (same definition reused
      # across the two value-class sections — kept once) and Bag (two
      # unrelated shapes — section 1's Bag renamed to MapBag).


      # `@arr = [nil] * N` followed by `@arr[i] = obj` widens the slot
      # to `<obj>_ptr_array`. Without the widening, the slot stays at
      # the default IntArray and the object pointer write is truncated.
      class Item
        def initialize(label)
          @label = label
          @history = [0]   # array ivar keeps Item off the value-type fast path
        end
        def visit
          @history << @history.last + 1
          @label
        end
        def visits
          @history.length - 1
        end
      end

      class Bag
        def initialize
          @slots = [nil] * 4
          @slots[0] = Item.new("a")
          @slots[1] = Item.new("b")
          @slots[3] = Item.new("d")
        end
        attr_reader :slots
        def visit_at(i)
          @slots[i].visit
        end
      end

      b = Bag.new
      puts b.visit_at(0)
      puts b.visit_at(1)
      puts b.visit_at(3)
      puts b.slots[0].visits   # 1
      puts b.slots[1].visits   # 1
      puts b.slots[3].visits   # 1
    RUBY

    _(result).must_answer <<~'OUT'
      a
      b
      d
      1
      1
      1
    OUT
  end

  it "range arguments across string and array slicing" do
    result = ze0(<<~'RUBY')
      p "hello".byteslice(1..3)
      p "hello".byteslice(2..)
      p "hello".byteslice(10..12)
      a = [1, 2, 3, 4]
      p a.slice!(1..2)
      p a
      b = [0, 0, 0, 0, 0]
      b.fill(1..2) { |i| i + 100 }
      p b
    RUBY

    _(result).must_answer <<~'OUT'
      "ell"
      "llo"
      nil
      [2, 3]
      [1, 4]
      [0, 101, 102, 0, 0]
    OUT
  end

  it "range each slice answers receiver" do
    result = ze0(<<~'RUBY')
      v = (1..5).each_cons(2) { |s| s }
      p v

      v = (1..5).each_slice(2) { |s| s }; p v        # Ruby: 1..5    Spinel: [1, 2, 3, 4, 5]
      v = (1..5).each_cons(2) { |s| s }; p v.class   # Ruby: Range   Spinel: Array

      p((1..5).each_cons(2) { |s| s })                  # => 1..5
      p((1..5).each_slice(2) { |s| s })                 # => 1..5
      v = [1, 2, 3].each_cons(2) { |s| s }; p v         # => [1, 2, 3]
      v = [1, 2, 3].each_slice(2) { |s| s }; p v        # => [1, 2, 3]
      v = (1..5).each { |s| s }; p v                    # => 1..5
      v = (1..5).each_entry { |s| s }; p v              # => 1..5

      v = (1..5).reverse_each { |s| s }; p v
      h = { a: 1, b: 2 }
      v = h.each_slice(1) { |s| s }; p v
      p((1..6).each_cons(3) { |s| s })
      acc = []; (1..5).each_slice(2) { |s| acc << s }; p acc
    RUBY

    _(result).must_answer <<~'OUT'
      1..5
      1..5
      Range
      1..5
      1..5
      [1, 2, 3]
      [1, 2, 3]
      1..5
      1..5
      1..5
      {a: 1, b: 2}
      1..6
      [[1, 2], [3, 4], [5]]
    OUT
  end

  it "range each slice cons" do
    result = ze0(<<~'RUBY')
      # Range#each_slice / #each_cons: the block form, the blockless
      # Enumerator form (.to_a), and the .map chain all materialize the
      # integer range once and reuse the array emitters (range_enum_redispatch).
      p (1..6).each_slice(2).to_a
      (1..6).each_slice(2) { |s| p s }
      p (1..6).each_slice(2).map { |s| s.sum }
      p (1..6).each_cons(3).to_a
      (1..5).each_cons(2) { |a, b| puts "#{a}-#{b}" }
      p (1..6).each_cons(2).map { |a, b| a * b }
      r = (2..9)
      p r.each_slice(4).to_a
    RUBY

    _(result).must_answer <<~'OUT'
      [[1, 2], [3, 4], [5, 6]]
      [1, 2]
      [3, 4]
      [5, 6]
      [3, 7, 11]
      [[1, 2, 3], [2, 3, 4], [3, 4, 5], [4, 5, 6]]
      1-2
      2-3
      3-4
      4-5
      [2, 6, 12, 20, 30]
      [[2, 3, 4, 5], [6, 7, 8, 9]]
    OUT
  end

  it "range each slice returns receiver" do
    result = ze0(<<~'RUBY')
      p((1..5).each_cons(2) { |s| s })
      p((1..5).each_slice(2) { |s| s })
      p([1, 2, 3].each_cons(2) { |s| s })
      p([1, 2, 3].each_slice(2) { |s| s })
      p({ a: 1, b: 2 }.each_cons(2) { |s| s })
      p({ a: 1, b: 2 }.each_slice(2) { |s| s })
      p((1..5).to_a.each_slice(2) { |s| s })
    RUBY

    _(result).must_answer <<~'OUT'
      1..5
      1..5
      [1, 2, 3]
      [1, 2, 3]
      {a: 1, b: 2}
      {a: 1, b: 2}
      [1, 2, 3, 4, 5]
    OUT
  end

  it "range step walks by succ" do
    result = ze0(<<~'RUBY')
      # `Range#step` over a NON-numeric range walks by `succ`, in both the block
      # and the blockless form.
      #
      # `docs/COMPATIBILITY.md` recorded this as the one outright panic in the
      # document -- "answers the right Enumerator, but WALKING it panics". It
      # does not: every row below matches ruby 4.0.6, so the note is deleted and
      # these rows replace it.

      p ("a".."e").step(2).to_a
      out = []
      ("a".."e").step(2) { |v| out << v }
      p out
      p ("a".."e").step(1).to_a
      p ("aa".."ad").step(2).to_a
      p ("a".."e").step(2).class
      p (:a..:e).step(2).to_a

      # A user class with `succ` and `<=>` walks the same way. Ruby reaches for
      # `+` first and only falls back to `succ`, so a class without `+` raises
      # -- which is the row that pins WHICH protocol is being used.
      class Countable
        include Comparable
        attr_reader :n

        def initialize(n) = @n = n
        def succ = Countable.new(@n + 1)
        def <=>(o) = @n <=> o.n
        def inspect = "C#{@n}"
      end
      begin
        (Countable.new(1)..Countable.new(5)).step(2).to_a
      rescue NoMethodError => e
        puts e.message
      end

      # Every numeric range keeps its ArithmeticSequence.
      p (1..9).step(2).class
      p (1..9).step(2).to_a
    RUBY

    _(result).must_answer <<~'OUT'
      ["a", "c", "e"]
      ["a", "c", "e"]
      ["a", "b", "c", "d", "e"]
      ["aa", "ac"]
      Enumerator
      [:a, :c, :e]
      undefined method '+' for an instance of Countable
      Enumerator::ArithmeticSequence
      [1, 3, 5, 7, 9]
    OUT
  end

  it "range string cover" do
    result = ze0(<<~'RUBY')
      # Range#include? / cover? / === on string ranges. Spinel inlines
      # strcmp bounds for literal string-range receivers rather than
      # trying to fit the receiver into the int-only sp_Range struct.

      puts ("a".."z").include?("m")
      puts ("a".."z").cover?("m")
      puts ("a".."z").include?("Z")
      puts ("a".."z").cover?("a")
      puts ("a".."z").cover?("z")
      puts ("a"..."z").cover?("z")  # exclusive end
    RUBY

    _(result).must_answer <<~'OUT'
      true
      true
      false
      true
      true
      false
    OUT
  end

  it "rational mod cmp slice default wave10" do
    result = ze0(<<~'RUBY')
      # Rational %/modulo/remainder/divmod, Complex <=> (real-valued compare,
      # nil otherwise), slice! on literal receivers, and Hash#default after
      # a default= on an un-narrowed empty hash.
      p("hello".slice!(/l+/))
      p("hello".slice!("ell"))
      s = "hello"
      p(s.slice!(/l+/))
      p s
      a = {}; a.default = 9; c = (a.default); p c
      p a[:missing]
      b = {}
      b.default = "d"
      p b["nope"]
      p(({}.default = 5))
      v = Rational(7,2) % Rational(1,3); p v
      p(Rational(7,2) % 2)
      p(Rational(7,2).modulo(Rational(1,3)))
      p(Rational(-7,2) % Rational(1,3))
      p(Rational(7,2).remainder(Rational(1,3)))
      p(Rational(-7,2).remainder(Rational(1,3)))
      p(Rational(7,2).divmod(Rational(1,3)))
      p(Complex(2, 0) <=> Complex(2, 0))
      p(Complex(3, 0) <=> Complex(2, 0))
      p(Complex(1, 0) <=> Complex(2, 0))
      p(Complex(2, 0) <=> 3)
      p(Complex(2, 3) <=> Complex(1, 1))
    RUBY

    _(result).must_answer <<~'OUT'
      "ll"
      "ell"
      "ll"
      "heo"
      9
      9
      "d"
      5
      (1/6)
      (3/2)
      (1/6)
      (1/6)
      (1/6)
      (-1/6)
      [10, (1/6)]
      0
      1
      -1
      -1
      nil
    OUT
  end

  it "slice before after block" do
    result = ze0(<<~'RUBY')
      p [1, 2, 4, 9, 10, 11, 12, 0].slice_before { |x| x.even? }.to_a
      p [1, 2, 4, 9, 10, 11, 12, 0].slice_after { |x| x.even? }.to_a
      p %w[a bb c dd].slice_before { |s| s.length == 1 }.to_a
      p [3, 1, 4, 1, 5].slice_after { |x| x == 1 }.to_a
      e = [1, 2, 3, 4].slice_before { |x| x > 2 }
      p e.to_a
    RUBY

    _(result).must_answer <<~'OUT'
      [[1], [2], [4, 9], [10, 11], [12], [0]]
      [[1, 2], [4], [9, 10], [11, 12], [0]]
      [["a", "bb"], ["c", "dd"]]
      [[3, 1], [4, 1], [5]]
      [[1, 2], [3], [4]]
    OUT
  end

  it "slice length overflow" do
    result = ze0(<<~'RUBY', argv: ["9223372036854775807"])

      # Ruby hands a slice length straight through from user code, so `a[1, huge]`
      # reaches the clamp with len == INT64_MAX. Written as `start + len > N` the sum
      # overflows, wraps negative, the guard reads false, and the clamp is skipped --
      # after which the copy loop, bounded only by len, walks off the heap. This
      # segfaulted on ordinary -O2 for an index CRuby answers fine.
      n = ARGV[0].to_i     # runtime value, so nothing folds it away

      p(["x", "y", "z"][1, n])
      p([1, 2, 3][1, n])
      p([1.5, 2.5, 3.5][1, n])
      p([1, "x", :y, 2.0][1, n])
      p("abcdef".byteslice(1, n))
      p("abcdef"[1, n])
      p("日本語です"[1, n])

      # the boundary cases the clamp still has to get right
      p([1, 2, 3][3, n])
      p([1, 2, 3][0, n])
      p("abc".byteslice(3, n))
      p([1, 2, 3][1, 0])
      p([1, 2, 3][-2, n])
    RUBY

    _(result).must_answer <<~'OUT'
      ["y", "z"]
      [2, 3]
      [2.5, 3.5]
      ["x", :y, 2.0]
      "bcdef"
      "bcdef"
      "本語です"
      []
      [1, 2, 3]
      ""
      []
      [2, 3]
    OUT
  end

  it "slice when first class" do
    result = ze0(<<~'RUBY')
      # int_array.slice_when { |a,b| cond }.to_a returns a first-class array of slices
      # (a new slice starts before b whenever the block is truthy).
      p [1, 2, 4, 5, 7].slice_when { |a, b| b - a > 1 }.to_a
      p [1, 2, 3].slice_when { |a, b| false }.to_a
      p [1, 2, 3].slice_when { |a, b| true }.to_a
      p [42].slice_when { |a, b| a < b }.to_a
      p [1, 3, 5, 2, 4].slice_when { |a, b| a > b }.to_a
      # the result is a real array: chain further
      p [1, 2, 4, 5].slice_when { |a, b| b - a > 1 }.to_a.map { |s| s.sum }
      p [1, 2, 4, 5, 7].slice_when { |a, b| b - a > 1 }.to_a.length
      # chunk_while (the inverse) still works
      p [1, 2, 4, 9, 10, 11, 12, 0].chunk_while { |a, b| b - a == 1 }.to_a
    RUBY

    _(result).must_answer <<~'OUT'
      [[1, 2], [4, 5], [7]]
      [[1, 2, 3]]
      [[1], [2], [3]]
      [[42]]
      [[1, 3, 5], [2, 4]]
      [3, 9]
      3
      [[1, 2], [4], [9, 10, 11, 12], [0]]
    OUT
  end

  it "splat slice keys" do
    result = ze0(<<~'RUBY')
      # `Hash#slice(*keys)` is variadic, but `slice` sat in the fixed-arity splat
      # expansion table with arity 1, so a splat whose length is not a literal was
      # rewritten to `keys[0]` -- every key after the first silently dropped. A
      # constant splat was not expanded at all and reached the emitter as one whole
      # array, which the key coercion answered nothing for. Three spellings of one
      # splat gave three answers (#4164).
      ATTRS = [:a, :b]
      IDX = [1, 2]
      h = { a: 1, b: 2, c: 3 }
      x = ATTRS
      y = IDX

      def poly(n) = n > 0 ? { a: 1, b: 2, c: 3 } : 7
      def polys(n) = n > 0 ? "abcdef" : 7
      def polya(n) = n > 0 ? [10, 20, 30, 40] : 7

      p h.slice(*[:a, :b]).keys
      p h.slice(*ATTRS).keys
      p h.slice(*x).keys
      p h.slice(:a, *[:b]).keys
      p h.slice(*[]).keys
      p h.except(*ATTRS).keys
      p h.values_at(*ATTRS)

      # the same splat on a BOXED receiver: Hash#slice answers a sub-Hash, while
      # String#slice / Array#slice is #[] and takes one argument or two -- only the
      # run time says which, so the key list decides
      p poly(1).slice(*ATTRS).keys
      p poly(1).values_at(*ATTRS)
      p polys(1).slice(*IDX)
      p polya(1).slice(*IDX)
      p polys(1).slice(*[1])
    RUBY

    _(result).must_answer <<~'OUT'
      [:a, :b]
      [:a, :b]
      [:a, :b]
      [:a, :b]
      []
      [:c]
      [1, 2]
      [:a, :b]
      [1, 2]
      "bc"
      [20, 30]
      "b"
    OUT
  end

  it "string charset range notation" do
    result = ze0(<<~'RUBY')
      # Issue #858: `a-z` range notation inside the charset string
      # argument of String#delete / #tr / #tr_s / #count expands to
      # the codepoint range. Previously the range syntax was treated
      # as three literal characters (a, -, z).
      puts "hello world".delete("a-z").inspect
      puts "abc123".tr("a-z", "X").inspect
      puts "Hello World".count("a-z")
      puts "AaBbCc".count("a-zA-Z")
      puts "abc-def".delete("a-c").inspect
    RUBY

    _(result).must_answer <<~'OUT'
      " "
      "XXX123"
      8
      6
      "-def"
    OUT
  end

  it "string crypt" do
    result = ze0(<<~'RUBY')
      # String#crypt — real libc crypt(3) (traditional DES), matching MRI:
      # 13-char output whose first 2 chars are the salt.

      r = "hello".crypt("ab")
      puts r
      puts r.length
      puts r[0, 2]

      # Determinism: same inputs → identical output.
      puts "hello".crypt("ab") == "hello".crypt("ab")

      # Different password → different hash, same salt prefix.
      a = "hello".crypt("ab")
      b = "world".crypt("ab")
      puts b
      puts a[0, 2] == b[0, 2]   # same salt
      puts a == b                # different hash

      # A salt shorter than 2 characters is an ArgumentError.
      begin
        "x".crypt("z")
      rescue ArgumentError => e
        puts "salt too short"
      end
    RUBY

    _(result).must_answer <<~'OUT'
      abl0JrMf6tlhw
      13
      ab
      true
      abMGUTItM1t0k
      true
      false
      salt too short
    OUT
  end

  it "string range accessors" do
    result = ze0(<<~'RUBY')
      # begin/end/first/last/min/max on a String-endpoint Range read the endpoints
      # as strings (the int-backed sp_Range stores their pointers), and first(n)/
      # last(n) materialize n elements via string succ.
      p(("a".."e").begin)
      p(("a".."e").end)
      p(("a".."e").first)
      p(("a".."e").last)
      p(("a".."e").min)
      p(("a".."e").max)
      p(("a".."e").first(2))
      p(("a".."e").last(2))
      r = ("b".."d")
      p(r.begin)
      p(r.max)
    RUBY

    _(result).must_answer <<~'OUT'
      "a"
      "e"
      "a"
      "e"
      "a"
      "e"
      ["a", "b"]
      ["d", "e"]
      "b"
      "d"
    OUT
  end

  it "string range each inspect" do
    result = ze0(<<~'RUBY')
      # String-endpoint ranges have no int sp_Range representation. Iterating one
      # with a block (materialized as a succ-sequence) and inspecting a literal now
      # work instead of miscompiling. (Accumulating the yielded strings into an array
      # declared outside the block still needs wider element inference -- separate.)

      # each with a block
      letters = ""
      ("a".."e").each { |ch| letters += ch }
      puts letters

      # exclusive range each
      ("a"..."d").each { |ch| print ch }
      puts

      # multi-char succ
      seq = ""
      ("aa".."ac").each { |s| seq += s + " " }
      puts seq

      # counting
      n = 0
      ("a".."z").each { |_| n += 1 }
      puts n

      # inspect of a string-range literal (p uses #inspect: endpoints are quoted)
      p ("a".."c")
      p ("a"..."e")
      p ("aa".."ac")

      # numeric ranges are unaffected
      total = 0
      (1..5).each { |i| total += i }
      puts total
      p (1..5)
      p (1...5)
    RUBY

    _(result).must_answer "abcde\nabc\naa ab ac \n26\n\"a\"..\"c\"\n\"a\"...\"e\"\n\"aa\"..\"ac\"\n15\n1..5\n1...5\n"
  end

  it "string range include iterates" do
    result = ze0(<<~'RUBY')
      # `Range#include?` WALKS the range; `Range#cover?` compares endpoints with
      # `<=>`. For a String range the two disagree, and zeo answers `cover?` for both.
      #
      # `("a".."e").include?("bb")` is false -- `bb` is not one of a, b, c, d, e --
      # while `cover?("bb")` is true, because `"a" <= "bb" <= "e"`. zeo aliases
      # `include?`/`member?` onto `===`'s cover check
      # (`builtins::range.rs`'s shared row), whose comment claims the approximation is
      # faithful "for the numeric/comparable cases this runtime supports". A String
      # range is exactly the case it is not faithful for, and ruby's own docs use this
      # pair as the illustration of the difference.
      #
      # Ruby takes the cover shortcut only for a range whose endpoints are Numeric
      # (`range.c`'s `range_include_internal` falls through to `rb_ary_includes`-style
      # iteration otherwise), so the numeric answers below must stay as they are.

      p ("a".."e").include?("bb")
      p ("a".."e").cover?("bb")
      p ("a".."e").member?("bb")
      p ("a".."e") === "bb"

      p ("a".."e").include?("c")
      p ("a".."z").include?("cc")

      # Numeric ranges take the shortcut in ruby too -- these must not change.
      p (1..10).include?(5.5)
      p (1..10).cover?(5.5)
    RUBY

    _(result).must_answer <<~'OUT'
      false
      true
      false
      true
      true
      false
      true
      true
    OUT
  end

  it "string range step" do
    result = ze0(<<~'RUBY')
      r001 = []; ("a".."e").step(2) { |s001| r001 << s001 }; p r001
      sr = ("a".."e")
      p sr.step(2).to_a
      p sr.step(2).class
      p (sr % 2).to_a
      p ("a".."e").to_a
      r2 = []; (("a".."e") % 2).each { |s| r2 << s }; p r2
    RUBY

    _(result).must_answer <<~'OUT'
      ["a", "c", "e"]
      ["a", "c", "e"]
      Enumerator
      ["a", "c", "e"]
      ["a", "b", "c", "d", "e"]
      ["a", "c", "e"]
    OUT
  end

  it "string range to a" do
    result = ze0(<<~'RUBY')
      # String range to_a — single-char ASCII case (the common subset
      # shape). Multi-char ranges need full String#succ with cross-position
      # carry and are out of scope for now (the runtime helper returns
      # an empty array on multi-char input).
      puts ("a".."c").to_a.inspect
      puts ("A".."E").to_a.inspect
      puts ("0".."5").to_a.inspect

      # Exclusive range
      puts ("a"..."c").to_a.inspect
    RUBY

    _(result).must_answer <<~'OUT'
      ["a", "b", "c"]
      ["A", "B", "C", "D", "E"]
      ["0", "1", "2", "3", "4", "5"]
      ["a", "b"]
    OUT
  end

  it "string search slice" do
    result = ze0(<<~'RUBY')
      # String search/slice coverage: index-by-substring (returns the substring or
      # nil), start_with? with a regex (anchored at index 0), the byte-sum checksum,
      # and unpack1 (the first element of unpack). Receivers go through a method
      # param so the runtime path is exercised rather than constant folding.
      def s(x); x; end

      # s["sub"]: the matched substring, or nil
      p s("hello")["ll"]
      p s("hello")["zz"]
      p s("hello")["hello"]

      # start_with? accepts a regex, true only when it matches at the start
      p s("hello").start_with?(/he/)
      p s("hello").start_with?(/ell/)
      p s("hello").start_with?(/zz/)
      p s("hello").start_with?("he")

      # sum: 16-bit byte checksum
      p s("hello").sum
      p s("abc").sum

      # unpack1: first element of unpack
      p s("AB").unpack1("C")
      p s("ABCD").unpack1("N")
    RUBY

    _(result).must_answer <<~'OUT'
      "ll"
      nil
      "hello"
      true
      false
      false
      true
      532
      294
      65
      1094861636
    OUT
  end

  it "string slice bang value" do
    result = ze0(<<~'RUBY')
      # String#slice! in value position returns the removed part (or nil).
      s = "hello world"
      removed = s.slice!(0, 6)
      p removed
      p s
      t = "hello"
      r2 = t.slice!("ll")
      p r2
      p t
      u = "abc"
      p u.slice!("zz").inspect
      p u
      v = "hello"
      p v.slice!(2, 99)
      p v
    RUBY

    _(result).must_answer <<~'OUT'
      "hello "
      "world"
      "ll"
      "heo"
      "nil"
      "abc"
      "llo"
      "he"
    OUT
  end

  it "string slice casecmp succ" do
    result = ze0(<<~'RUBY')
      # CRuby contracts for three String surfaces: the [start, len] / [range]
      # nil boundaries, casecmp/casecmp? answering nil for a non-String argument,
      # and the alphanumeric-aware succ carry.

      def sub2(s, i, n); s[i, n]; end

      # in-range, boundary (start == length -> ""), past the end -> nil
      p sub2("hello", 1, 3)
      p sub2("hello", 5, 2)
      p sub2("hello", 6, 2)

      # negative starts: in range counts back; before -length -> nil
      p sub2("hello", -4, 2)
      p sub2("hello", -5, 1)
      p sub2("hello", -6, 1)

      # negative length -> nil; zero length -> ""
      p sub2("hello", 1, -1)
      p sub2("hello", 1, 0)

      def subr(s, r); s[r]; end
      p subr("hello", 3..9)
      p subr("hello", 9..12)
      p subr("hello", -99..2)
      p subr("hello", 5..7)

      # slice is the same method
      def sl2(s, i, n); s.slice(i, n); end
      p sl2("hello", 10, 2)
      p sl2("hello", 2, 2)

      def cc(a, b); a.casecmp(b); end
      def ccp(a, b); a.casecmp?(b); end
      p cc("abc", "ABD")
      p cc("ABC", "abc")
      p ccp("abc", "ABC")
      p ccp("abc", "abd")
      p cc("abc", :abc)
      p ccp("abc", :abc)
      p ccp("abc", 42)

      def sc(x); x.succ; end
      # digit carry across a same-class gap; alpha likewise
      p sc("1.9")
      p sc("1.99")
      p sc("z.z")
      # adjacent alnum takes the carry regardless of class
      p sc("a9")
      p sc("1z")
      p sc("z9")
      p sc("Zz9")
      # a different class across a gap inserts instead of carrying
      p sc("a-9")
      p sc("1.z")
      p sc(".9")
      # no alphanumerics: the last byte increments
      p sc("***")
      p sc("<<koala>>")
    RUBY

    _(result).must_answer <<~'OUT'
      "ell"
      ""
      nil
      "el"
      "h"
      nil
      nil
      ""
      "lo"
      nil
      nil
      ""
      nil
      "ll"
      -1
      0
      true
      false
      nil
      nil
      nil
      "2.0"
      "2.00"
      "aa.a"
      "b0"
      "2a"
      "aa0"
      "AAa0"
      "a-10"
      "1.aa"
      ".10"
      "**+"
      "<<koalb>>"
    OUT
  end

  it "string slice range" do
    result = ze0(<<~'RUBY')
      # String#slice(Range) — decompose the Range and reuse the same
      # runtime helper as String#[](Range). Inclusive, exclusive,
      # endless, beginless and negative endpoints all supported.
      p "hello".slice(1..3)
      p "hello".slice(1...3)
      p "hello".slice(1..)
      p "hello".slice(..2)
      p "hello".slice(1..-2)
      p "hello".slice(2..10)
      p "hello".slice(0..-1)

      # slice still works with (start, length) and single-index forms.
      p "hello".slice(1, 2)
      p "hello".slice(1)

      # Through a local receiver too.
      s = "spinel"
      p s.slice(2..4)
    RUBY

    _(result).must_answer <<~'OUT'
      "ell"
      "el"
      "ello"
      "hel"
      "ell"
      "llo"
      "hello"
      "el"
      "e"
      "ine"
    OUT
  end

  it "string upto and range" do
    result = ze0(<<~'RUBY')
      z = []
      r = "a".upto("c") { |s| z << s }
      p z
      p r
      p "9".upto("11").to_a
      p "a".upto("e").to_a
      p ("9".."11").to_a
      p ("a".."e").to_a
      p ("y".."ab").to_a
      p ("a"..."d").to_a
      w = []
      "aa".upto("ac") { |s| w << s }
      p w
      p 1.upto(3).to_a
      q = []
      1.upto(3) { |i| q << i }
      p q
      p "a".upto("e", true).to_a
      p "a".upto("e", false).to_a
      x = []
      "a".upto("d", true) { |s| x << s }
      p x
    RUBY

    _(result).must_answer <<~'OUT'
      ["a", "b", "c"]
      "a"
      ["9", "10", "11"]
      ["a", "b", "c", "d", "e"]
      ["9", "10", "11"]
      ["a", "b", "c", "d", "e"]
      []
      ["a", "b", "c"]
      ["aa", "ab", "ac"]
      [1, 2, 3]
      [1, 2, 3]
      ["a", "b", "c", "d"]
      ["a", "b", "c", "d", "e"]
      ["a", "b", "c"]
    OUT
  end

  it "symbol range enum" do
    result = ze0(<<~'RUBY')
      # (:a..:e): a symbol-endpoint range enumerates by name succession --
      # the range lowers to a poly array of boxed symbols (to_a/map/each/
      # include?, exclusive ends, multi-char names).
      p (:a..:e).to_a
      p((:a..:c).map(&:to_s))
      p (:a...:d).to_a
      acc = []
      (:x..:z).each { |s| acc << s }
      p acc
      p (:a..:e).include?(:c)
      p (:aa..:ac).to_a
    RUBY

    _(result).must_answer <<~'OUT'
      [:a, :b, :c, :d, :e]
      ["a", "b", "c"]
      [:a, :b, :c]
      [:x, :y, :z]
      true
      [:aa, :ab, :ac]
    OUT
  end

  it "when string range" do
    result = ze0(<<~'RUBY')
      # `when ("a".."e")`: the parentheses hid the range from the literal check, so
      # the arm declined and the whole when folded to false. A String range held in a
      # variable had no arm at all.
      case "c" when ("a".."e") then p :in else p :out end
      case "z" when ("a".."e") then p :in else p :out end
      case "c" when "a".."e" then p :in2 else p :out2 end
      p(("a".."e") === "c")
      r = ("a".."e")
      case "c" when r then p :in3 else p :out3 end
      case "z" when r then p :in3 else p :out3 end
      case 3 when (1..5) then p :n_in else p :n_out end
      case 9 when (1..5) then p :n_in else p :n_out end
      case "e" when ("a"..."e") then p :x_in else p :x_out end
    RUBY

    _(result).must_answer <<~'OUT'
      :in
      :out
      :in2
      true
      :in3
      :out3
      :n_in
      :n_out
      :x_out
    OUT
  end
end
