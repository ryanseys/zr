# frozen_string_literal: true

require "spec_helper"

describe "Array: searching and matching" do
  it "array assoc rassoc" do
    result = ze0(<<~'RUBY')
      # The cycle this program builds on purpose, and the census it leaves
      # behind. A cycle alive at exit is not a defect: it is a ring the
      # program never broke, so the census below is recorded as an
      # observation rather than gated on.
      # 
      # Self-referential arrays, built on purpose.
      # At exit: cycle leak: 3 objects (Array x3)
      # Array#assoc / #rassoc match the first / second element of each sub-array.
      # A like-typed pair such as [1, 2] is an IntArray (not a PolyArray), so the
      # match must compare and return it by dispatching on the pair's own kind.
      p [[1, 2], [3, 4]].assoc(3)
      p [[1, 2], [3, 4]].rassoc(2)
      p [[1, 2], [3, 4]].assoc(9)
      p [[1, 2], [3, 4]].rassoc(9)

      # String/mixed pairs (PolyArray) and a non-literal receiver.
      p [["a", 1], ["b", 2]].assoc("b")
      p [["a", 1], ["b", 2]].rassoc(1)

      def assoc_of(pairs, key)
        pairs.assoc(key)
      end
      p assoc_of([[10, 100], [20, 200]], 20)

      # Symbol-array pairs match and round-trip through their own kind.
      p [[:a, :b], [:c, :d]].assoc(:c)
      p [[:a, :b], [:c, :d]].rassoc(:b)

      # A nil key must not match an empty / too-short pair or a non-array element.
      p [[], [1], (1..2)].assoc(nil)
      p [[], [1], (1..2)].rassoc(nil)

      # An element that IS the receiver. Both methods lock each sub-array to read
      # its first / second slot, so walking the receiver under its own guard makes
      # that a self-lock -- which hangs forever rather than raising. Snapshotting
      # the receiver first is what keeps these terminating.
      selfref = [1]
      selfref << selfref
      p selfref.assoc(1)
      p selfref.rassoc(1)
      p selfref.assoc(nil)

      # The same shape one level down: the pair being probed contains the outer
      # array, so the probe's own element read re-enters it.
      outer = [[9, nil]]
      outer[0][1] = outer
      p outer.assoc(9)
      p outer.rassoc(outer)
    RUBY

    _(result).must_answer <<~'OUT'
      [3, 4]
      [1, 2]
      nil
      nil
      ["b", 2]
      ["a", 1]
      [20, 200]
      [:c, :d]
      [:a, :b]
      nil
      nil
      [1, [...]]
      nil
      nil
      [9, [[...]]]
      [9, [[...]]]
    OUT
  end

  it "array breadth matches the oracle" do
    result = ze0(<<~'RUBY')
      # The Array Tier A surface: set ops, mutators, sort family, flatten/
      # compact/uniq, join/to_h, fetch/dig/zip/rotate/values_at, and the
      # in-place filters' self-or-nil contract.

      p [1, 2] + [3]
      p [1, 2, 3] - [2]
      p [1, 2] * 2
      p [1, 2] * ","
      p([1, 2, 3] & [2, 3, 4])
      p([1, 2] | [2, 3])
      p([1, 2, 3] <=> [1, 2, 4])
      p [3, 1, 2].sort
      p [3, 1, 2].sort { |a, b| b <=> a }
      a = [1, 2, 3]
      p a.pop
      p a.shift
      a.unshift(9)
      a.push(8, 7)
      p a
      p [1, [2, [3]]].flatten
      p [1, [2, [3]]].flatten(1)
      p [1, nil, 2, nil].compact
      p [1, 2, 2, 3, 1].uniq
      p [1, 2, 3].reverse
      p [[1, :a], [2, :b]].to_h
      p [1, 2, 3].join
      p [1, 2, 3].join("-")
      p [1, 2, 3].index(2)
      p [1, 2, 3].index(9)
      p [1, 2, 1].rindex(1)
      p [[1, [2, 3]]].dig(0, 1, 0)
      p [1, 2].fetch(0)
      p [1, 2].fetch(9, :fallback)
      begin
        [1, 2].fetch(9)
      rescue IndexError => e
        puts "IndexError"
      end
      p [1, 2, 3, 4].take(2)
      p [1, 2, 3, 4].drop(2)
      p [1, 2, 3].zip([4, 5, 6], [7, 8, 9])
      p [1, 2, 3].rotate
      p [1, 2, 3].rotate(2)
      p [1, 2, 3, 4, 5].values_at(0, 2, 4)
      p [1, 2, 3].at(-1)
      p [0, 1, 2, 3, 4][1..3]
      p [1, 2, 3].delete(2)
      p [1, 2, 3].delete_at(0)
      p [1, 2, 3].insert(1, :x)
      p [1, 2].concat([3, 4])
      p [1, 2, 3].fill(0)
      p [1, 2, 3].clear
      b = [3, 1, 2]
      b.sort!
      p b
      c = [1, 2, 3]
      c.map! { |x| x * 10 }
      p c
      p [1, 2, 3, 4].select! { |x| x > 2 }
      p [1, 2, 3, 4].reject! { |x| x > 2 }
      p [1, 2].select! { |x| x > 0 }
    RUBY

    _(result).must_answer <<~'OUT'
      [1, 2, 3]
      [1, 3]
      [1, 2, 1, 2]
      "1,2"
      [2, 3]
      [1, 2, 3]
      -1
      [1, 2, 3]
      [3, 2, 1]
      3
      1
      [9, 2, 8, 7]
      [1, 2, 3]
      [1, 2, [3]]
      [1, 2]
      [1, 2, 3]
      [3, 2, 1]
      {1 => :a, 2 => :b}
      "123"
      "1-2-3"
      1
      nil
      2
      2
      1
      :fallback
      IndexError
      [1, 2]
      [3, 4]
      [[1, 4, 7], [2, 5, 8], [3, 6, 9]]
      [2, 3, 1]
      [3, 1, 2]
      [1, 3, 5]
      3
      [1, 2, 3]
      2
      1
      [1, :x, 2, 3]
      [1, 2, 3, 4]
      [0, 0, 0]
      []
      [1, 2, 3]
      [10, 20, 30]
      [3, 4]
      [1, 2]
      nil
    OUT
  end

  it "array grep" do
    result = ze0(<<~'RUBY')
      # Array#grep(pattern) / #grep_v(pattern) without a block: collect the
      # elements matching (or not matching) the pattern via `pattern ===`.
      # Supported: Range over an int array, primitive Class over a poly array,
      # Regexp over a str array. (The block form falls through to unresolved.)
      p [1, 2, 3, 4, 5].grep(1..3)
      p [1, 2, 3, 4, 5].grep_v(1..3)
      p [1, 2, 3, 4, 5].grep(2...4)
      p [1, 2].grep(10..20)
      p [1, "two", 3, "four"].grep(String)
      p [1, "two", 3, "four"].grep(Integer)
      p ["apple", "banana", "avocado"].grep(/^a/)
      p ["apple", "banana", "avocado"].grep_v(/^a/)
    RUBY

    _(result).must_answer <<~'OUT'
      [1, 2, 3]
      [4, 5]
      [2, 3]
      []
      ["two", "four"]
      [1, 3]
      ["apple", "avocado"]
      ["banana"]
    OUT
  end

  it "array grep empty literal" do
    result = ze0(<<~'RUBY')
      # Array#grep / #grep_v on an empty array literal match nothing and return an
      # empty array (the bare literal has no element type to dispatch from).
      p([].grep(Integer))
      p([].grep_v(Integer))
      p([1, "a", 2].grep(Integer))
      p([].grep(Integer) { |x| x * 2 })
    RUBY

    _(result).must_answer <<~'OUT'
      []
      []
      [1, 2]
      []
    OUT
  end

  it "array index and write" do
    result = ze0(<<~'RUBY')
      # arr[i] &&= v across array element kinds (IndexAndWriteNode, statement + expr).
      # &&= writes only when the slot is already truthy/present. Per-type helpers keep
      # each receiver's concrete array type (a shared helper would widen to poly).
      def si(x); x; end
      def sp(x); x; end
      def sg(x); x; end

      # int array: present slot overwritten, out-of-bounds slot left alone
      a = si([1, 2, 3])
      a[0] &&= 9          # present -> 9
      a[9] &&= 5          # absent  -> no write
      p a

      # poly array: truthy slot overwritten, nil slot left alone
      q = sp([1, "y", nil])
      q[0] &&= 7          # truthy -> 7
      q[2] &&= 8          # nil    -> no write
      p q

      # string array: present slot overwritten
      g = sg(["x", "y"])
      g[1] &&= "z"
      p g

      # expression position: yields the resulting slot value
      r = (a[0] &&= 4)    # present 9 -> 4, yields 4
      p [r, a]
    RUBY

    _(result).must_answer <<~'OUT'
      [9, 2, 3]
      [7, "y", nil]
      ["x", "z"]
      [4, [4, 2, 3]]
    OUT
  end

  it "array index block" do
    result = ze0(<<~'RUBY')
      # Array#index { |x| cond } finds the first index whose element satisfies the
      # block (an alias for #find_index in this form); returns nil on no match.
      # Receivers route through a per-kind identity method to exercise the typed path.
      def si(x); x; end
      def sw(x); x; end

      # block form (the gap)
      p si([1, 2, 3]).index { |x| x > 1 }
      p si([1, 2, 3]).index { |x| x > 9 }
      p sw(%w[a bb ccc]).index { |s| s.length == 2 }
      p sw(%w[a bb ccc]).index { |s| s.empty? }

      # find_index still behaves identically
      p si([4, 5, 6]).find_index { |x| x == 5 }

      # value form is unchanged (no block)
      p si([1, 2, 3]).index(2)
      p si([1, 2, 3]).index(9)
      p sw(%w[a b c]).index("b")
    RUBY

    _(result).must_answer <<~'OUT'
      1
      nil
      1
      nil
      1
      1
      nil
      1
    OUT
  end

  it "array index error" do
    result = ze0(<<~'RUBY')
      a = [1, 2, 3]
      begin
        a[-10] = :x
      rescue IndexError => e
        puts "caught out-of-range index assignment"
      end
      a[5] = :y
      puts a.length
      puts a[5]
    RUBY

    _(result).must_answer <<~'OUT'
      caught out-of-range index assignment
      6
      y
    OUT
  end

  it "array index gap" do
    result = ze0(<<~'RUBY')
      # An index write past the end grows the array, filling the gap with nil, the
      # way every typed array already did. The poly array silently dropped the write.
      a = []
      a[0] = 1
      p a
      b = []
      b[3] = "x"
      p b
      c = [1, 2, 3]
      c[1] = 9
      p c
      c[-1] = 8
      p c
      d = []
      d[0] = 1
      d[2] = 3
      p d
      e = [1]
      e[5] = :z
      p e
      p e.length

    RUBY

    _(result).must_answer <<~'OUT'
      [1]
      [nil, nil, nil, "x"]
      [1, 9, 3]
      [1, 9, 8]
      [1, nil, 3]
      [1, nil, nil, nil, nil, :z]
      6
    OUT
  end

  it "array index op write poly rhs" do
    result = ze0(<<~'RUBY')
      # Compound index assignment on a typed array with a poly right-hand side:
      # `float_array[i] += b[0]` where b is a heterogeneous (poly) array. The
      # emitter added the boxed sp_RbVal straight to the unboxed slot
      # (`double + sp_RbVal`), failing C compilation, while the equivalent plain
      # form `a[i] = a[i] + b[0]` already folded through the tag-dispatching
      # sp_poly_add. Also covers the str_array `+=` slot (native `char* + char*`
      # never compiled, poly RHS or not) and `+=` on a poly_array receiver.

      # float_array[i] += poly: literal index, variable index, inside a loop
      a = Array.new(2, 0.0)
      b = [1.5, "x"]
      a[0] += b[0]
      r = 1
      a[r] += b[0]
      p a                # [1.5, 1.5]
      i = 0
      while i < 2
        a[i] += b[0]
        i += 1
      end
      p a                # [3.0, 3.0]
      a[0] -= b[0]
      a[0] *= b[0]
      a[1] /= b[0]
      p a                # [2.25, 2.0]

      # int_array[i] with a poly RHS: arithmetic folds via the dynamic operator,
      # shifts unbox the RHS
      n = [10, 20]
      m = [3, "x"]
      n[0] += m[0]
      n[1] -= m[0]
      n[0] *= m[0]
      p n                # [39, 17]
      n[0] <<= m[0]
      p n                # [312, 17]

      # str_array[i] += string and += poly-carried string
      s = ["ab", "cd"]
      s[0] += "!"
      t = ["ef", 1]
      s[1] += t[0]
      p s                # ["ab!", "cdef"]

      # str_array[i] <<= (String#<< appends) and *= (String#* repeats)
      u = ["x", "y"]
      u[0] <<= "z"
      u[1] *= 3
      p u                # ["xz", "yyy"]

      # same ops when the analyzer demotes the receiver to poly_array
      # (mixing *= and <<= on one array does that): the fold goes through
      # sp_poly_mul / sp_poly_shl, which handle the String arms
      w = ["ab", "cd"]
      w[0] *= 2
      w[1] <<= "!"
      p w                # ["abab", "cd!"]

      # poly_array receiver: += float / int / poly slot
      pa = [1.5, "x", 2]
      pa[0] += 2.0
      pa[2] += 5
      pa[0] += pa[2]
      p pa[0]            # 10.5
      p pa[2]            # 7
    RUBY

    _(result).must_answer <<~'OUT'
      [1.5, 1.5]
      [3.0, 3.0]
      [2.25, 2.0]
      [39, 17]
      [312, 17]
      ["ab!", "cdef"]
      ["xz", "yyy"]
      ["abab", "cd!"]
      10.5
      7
    OUT
  end

  it "array index or write" do
    result = ze0(<<~'RUBY')
      # arr[i] ||= v across array element kinds (IndexOrWriteNode, statement + expr).
      # Each receiver is routed through a per-type helper so its concrete array type
      # survives (one shared helper would unify every kind to a boxed poly value).
      def si(x); x; end
      def sp(x); x; end
      def sf(x); x; end
      def sg(x); x; end

      # int array: a present slot is kept (0 is truthy in Ruby), nil slots written
      a = si([1, 2, 3])
      a[0] ||= 9          # kept
      a[1] ||= 8          # kept
      p a

      z = si([0, 2, 3])
      z[0] ||= 9          # 0 is truthy -> kept
      p z

      # nilable int (-> poly) array: the nil slot is filled
      n = sp([1, nil, 3])
      n[1] ||= 8
      p n

      # poly array: falsy (nil) slot filled, truthy slot kept
      q = sp([1, "y", nil])
      q[2] ||= 9
      q[0] ||= 7
      p q

      # float array: present slot kept
      f = sf([1.0, 2.0])
      f[0] ||= 9.0
      p f

      # string array: present slot kept
      g = sg(["x", "y"])
      g[0] ||= "z"
      p g

      # expression position: the form yields the resulting slot value
      r = (n[1] ||= 5)    # already 8 -> kept, yields 8
      p [r, n]
    RUBY

    _(result).must_answer <<~'OUT'
      [1, 2, 3]
      [0, 2, 3]
      [1, 8, 3]
      [1, "y", 9]
      [1.0, 2.0]
      ["x", "y"]
      [8, [1, 8, 3]]
    OUT
  end

  it "array index range variable" do
    result = ze0(<<~'RUBY')
      # Array#[] with a Range held in a variable/parameter (not a literal RangeNode)
      # routes to the slice path instead of the scalar integer-index accessor, which
      # previously passed an sp_Range to an mrb_int parameter and failed to compile.
      # Each method keeps its array parameter monomorphic so the typed-array path is
      # exercised.
      def si(a, rng); a[rng]; end

      p si([1, 2, 3, 4], 1..2)      # [2, 3]
      p si([1, 2, 3, 4], 1...3)     # [2, 3]
      p si([1, 2, 3, 4], 0..-1)     # [1, 2, 3, 4]
      p si([1, 2, 3, 4], 2..)       # [3, 4]  (endless)
      p si([1, 2, 3, 4], ..1)       # [1, 2]  (beginless)
      p si([1, 2, 3, 4], -2..)      # [3, 4]  (negative start)
      p si([1, 2, 3, 4], 4..5)      # []      (start == length)

      def ss(a, rng); a[rng]; end
      p ss(["a", "b", "c"], 0..1)   # ["a", "b"]

      def sf(a, rng); a[rng]; end
      p sf([1.5, 2.5, 3.5], 1..2)   # [2.5, 3.5]

      # The value survives further chaining (proves the subarray type is correct).
      p si([1, 2, 3, 4], 1..2).map { |x| x * 10 }   # [20, 30]

      # A start outside [-length, length] is nil, not a clamped slice. Checked via
      # .nil? -- p renders a nil array-typed value as [] (a separate display gap).
      def sn(a, rng); a[rng].nil?; end
      p sn([1, 2, 3, 4], -5..-1)    # true   (start < -length)
      p sn([1, 2, 3, 4], -6..2)     # true
      p sn([1, 2, 3, 4], 5..6)      # true   (start > length)
      p sn([1, 2, 3, 4], -4..-1)    # false  (start == -length, in range)
      p sn([1, 2, 3, 4], 1..2)      # false
    RUBY

    _(result).must_answer <<~'OUT'
      [2, 3]
      [2, 3]
      [1, 2, 3, 4]
      [3, 4]
      [1, 2]
      [3, 4]
      []
      ["a", "b"]
      [2.5, 3.5]
      [20, 30]
      true
      true
      true
      false
      false
    OUT
  end

  it "array index type errors" do
    result = ze0(<<~'RUBY')
      # GAP -- imported from the spinel corpus at c55d9bdb.
      # Array#[]= on a frozen array raises TypeError for the bad index before
      # FrozenError for the frozen receiver; ruby checks frozenness first.
      #
      r = ([1, 2].values_at("x") rescue $!.class); p r
      s = "x"; r = ([1, 2].values_at(s) rescue $!.class); p r
      r = ([1, 2].values_at([0]) rescue $!.class); p r
      r = ([1, 2].at("x") rescue $!.class); p r
      r = ([1, 2]["x"] rescue $!.class); p r
      r = ([1, 2].fetch("x") rescue $!.class); p r
      r = ([1, 2].first("x") rescue $!.class); p r
      r = ([1, 2].last(:s) rescue $!.class); p r
      r = ([1, 2].take(nil) rescue $!.class); p r
      r = ([1, 2].drop(true) rescue $!.class); p r
      r = ([1, 2].slice("x") rescue $!.class); p r
      r = ([1, 2].dig("x") rescue $!.class); p r
      r = ([1, 2].rotate(nil) rescue $!.class); p r
      r = ([1, 2].at(1..2) rescue $!.class); p r
      a = [1, 2]; r = (a.insert("x", 9) rescue $!.class); p r
      a = [1, 2]; r = ((a["x"] = 9) rescue $!.class); p r

      # the forms that stay legal
      p([1, 2].at(1))
      p([1, 2][0..1])
      p([1, 2].slice(0, 2))
      p([1, 2].values_at(0..1))
      p([1, 2].first(1.0))
      p([1, 2].at(1.0))
      p([1, 2].rotate(1))

      # a mutator checks frozen before it coerces the index
      f = [1, 2, 3].freeze
      r = ((f[:foo] = 1) rescue $!.class); p r
      r = (f.insert(:x, 9) rescue $!.class); p r
    RUBY

    _(result).must_answer <<~'OUT'
      TypeError
      TypeError
      TypeError
      TypeError
      TypeError
      TypeError
      TypeError
      TypeError
      TypeError
      TypeError
      TypeError
      TypeError
      TypeError
      TypeError
      TypeError
      TypeError
      2
      [1, 2]
      [1, 2]
      [1, 2]
      [1]
      2
      [2, 1]
      FrozenError
      FrozenError
    OUT
  end

  it "array inplace and universal object methods" do
    result = ze0(<<~'RUBY')
      p [1, nil, 2, nil].compact!
      p [1, 2].compact!
      a = [1, 2, 3, 4]; a.rotate!(2); p a
      case [1, 2]; in [x, y]; p [x, y]; end
      p :hello.start_with?("he")
      p :hello.end_with?("lo")
      p("abc" !~ /z/)
      p "hi".display
    RUBY

    _(result).must_answer <<~'OUT'
      [1, 2]
      nil
      [3, 4, 1, 2]
      [1, 2]
      true
      true
      true
      hinil
    OUT
  end

  it "array literal implicit hash" do
    result = ze0(<<~'RUBY')
      # A brace-less hash as the last element of an ARRAY literal. Ruby collapses it
      # into one ordinary Hash element, the same value the braced form builds --
      # `[1, k: 2]` is `[1, {k: 2}]`, two elements, not three.
      #
      # prism spells it `KeywordHashNode` rather than `HashNode`, and zeo lowered
      # that shape only in a CALL's argument list (where it means keyword arguments,
      # which bind differently). Anywhere else it fell through to the generic
      # rejection -- so activerecord's
      #
      #   [:change_column_default, [table, column, from: options[:to], to: options[:from]]]
      #
      # did not compile, and neither did `return k: 1`.

      p [1, 2, a: 3, b: 4]
      p [a: 1]
      p [1, 2, a: 3, b: 4].length

      # The values are ordinary expressions, including index reads -- the shape
      # activerecord's command recorder inverts a migration with.
      options = { to: "new", from: "old" }
      p [:change_column_default, ["posts", "title", from: options[:to], to: options[:from]]]

      # A `**splat` is the same node with only an AssocSplatNode inside it, which is
      # why graphql's `[*batch_args, **batch_kwargs]` failed with the same message.
      extra = { c: 3 }
      rest = [1, 2]
      p [*rest, **extra]
      p [1, **extra, d: 4]

      # Insertion order and last-wins merging survive, since this reuses the same
      # builder the braced literal and call kwargs use. The overlapping key comes
      # from a variable rather than a second literal, so this stays a test of the
      # lowering and not of ruby's duplicate-key warning.
      later = { x: 2, y: 3 }
      p [x: 1, **later]

      # Nested one level down, which is where activerecord's actually sits.
      p [[1, k: 2], [3, k: 4]]
    RUBY

    _(result).must_answer <<~'OUT'
      [1, 2, {a: 3, b: 4}]
      [{a: 1}]
      3
      [:change_column_default, ["posts", "title", {from: "new", to: "old"}]]
      [1, 2, {c: 3}]
      [1, {c: 3, d: 4}]
      [{x: 2, y: 3}]
      [[1, {k: 2}], [3, {k: 4}]]
    OUT
  end

  it "array member empty var" do
    result = ze0(<<~'RUBY')
      # Array#member? (an alias of include?) works on an empty array held in a
      # variable, not only on the empty literal.
      a = []
      p a.member?(1)
      b = [1, 2, 3]
      p b.member?(2)
      p b.member?(9)
      c = [1, "x"]
      p c.member?("x")
    RUBY

    _(result).must_answer <<~'OUT'
      false
      true
      false
      true
    OUT
  end

  it "array negative index too small" do
    result = ze0(<<~'RUBY')
      # Issue #839: an extreme negative index on []= raises IndexError
      # per MRI. Spinel previously silently no-op'd when the index after
      # `+= len` was still negative.
      a = [1, 2, 3]
      begin
        a[-999] = 99
      rescue IndexError => e
        puts "int: " + e.message
      end
      puts a.inspect

      b = ["a", "b", "c"]
      begin
        b[-50] = "x"
      rescue IndexError => e
        puts "str: " + e.message
      end
      puts b.inspect

      # Valid negative index still works.
      a[-1] = 33
      puts a.inspect
    RUBY

    _(result).must_answer <<~'OUT'
      int: index -999 too small for array; minimum: -3
      [1, 2, 3]
      str: index -50 too small for array; minimum: -3
      ["a", "b", "c"]
      [1, 2, 33]
    OUT
  end

  it "array negative size validation" do
    result = ze0(<<~'RUBY')
      # Array size/index operations validate their argument: a negative count to
      # take/drop raises ArgumentError, and an out-of-range negative insert index
      # raises IndexError. Spinel previously proceeded silently (drop even returned a
      # tail slice; a too-negative insert clamped to the front).
      def check
        yield
      rescue => e
        puts "#{e.class}: #{e.message}"
      end

      def dr(a, n); a.drop(n); end
      def tk(a, n); a.take(n); end
      def insi(a, n); a.insert(n, 9); end
      def inss(a, n); a.insert(n, "z"); end

      check { dr([1, 2], -1) }        # ArgumentError: attempt to drop negative size
      check { tk([1, 2], -1) }        # ArgumentError: attempt to take negative size
      check { insi([1, 2], -5) }      # IndexError: index -5 too small for array; minimum: -3
      check { inss(["a", "b"], -4) }  # IndexError: index -4 too small for array; minimum: -3

      # The valid forms still work.
      p dr([1, 2, 3], 1)              # [2, 3]
      p tk([1, 2, 3], 2)              # [1, 2]
      p dr([1, 2], 0)                 # [1, 2]
      p insi([1, 2], -3)             # [9, 1, 2]  (minimum valid negative index)
      p insi([1, 2], 1)              # [1, 9, 2]
      p inss(["a", "b"], -1)         # ["a", "b", "z"]
    RUBY

    _(result).must_answer <<~'OUT'
      ArgumentError: attempt to drop negative size
      ArgumentError: attempt to take negative size
      IndexError: index -5 too small for array; minimum: -3
      IndexError: index -4 too small for array; minimum: -3
      [2, 3]
      [1, 2]
      [1, 2]
      [9, 1, 2]
      [1, 9, 2]
      ["a", "b", "z"]
    OUT
  end

  it "array values at float index" do
    result = ze0(<<~'RUBY')
      p([1, 2].values_at(1.5))
      p([1, 2, 3].values_at(0.9))
      p([1, 2, 3].values_at(-1.5))
      p([1, 2, 3].values_at(1.5, 2.5))
      p([1, 2, 3].values_at(0, 1.5))
      b = 1.5
      p([1, 2, 3].values_at(b))
      p([1, 2, 3].values_at(1))
      p(["a", "b", "c"].values_at(2.7))
      p([1.5, 2.5].values_at(1.5))
    RUBY

    _(result).must_answer <<~'OUT'
      [2]
      [1]
      [3]
      [2, 3]
      [1, 2]
      [2]
      [2]
      ["c"]
      [2.5]
    OUT
  end

  it "dig multi step typeerror" do
    result = ze0(<<~'RUBY')
      # A multi-step dig stops at nil and raises TypeError on a step that cannot be
      # dug; chaining index reads answered the scalar the first step found (#3825).
      begin; p [1].dig(0, 0); rescue TypeError => e; p e.class; end
      p [[1, 2], [3]].dig(0, 1)
      p [[1, 2]].dig(5, 0)
      p [[1, 2]].dig(0, 9)
      p({ a: { b: 1 } }.dig(:a, :b))
      p [1].dig(0)
      h = { a: [1, 2] }
      p h.dig(:a, 1)
      begin; p({ a: 1 }.dig(:a, :b)); rescue TypeError => e; p e.class; end
    RUBY

    _(result).must_answer <<~'OUT'
      TypeError
      2
      nil
      nil
      1
      1
      2
      TypeError
    OUT
  end

  it "enumerable grep zip and minmax by" do
    result = ze0(<<~'RUBY')
      p (1..10).grep(3..5)
      p [1, "a", 2, "b"].grep(Integer)
      p [1, "a", 2, "b"].grep(Integer) { |x| x * 10 }
      p [1, "a", 2, "b"].grep_v(Integer)
      p [1, "a", 2, "b"].grep_v(Integer) { |x| x + "!" }
      p [1, 2, 3].zip([4, 5, 6])
      p [1, 2, 3].zip([4, 5], [6])
      p([1, 2, 3].zip([4, 5, 6]) { |x| })
      p [1, 2, 3, 4].minmax_by { |x| -x }
      p [].minmax_by { |x| x }
    RUBY

    _(result).must_answer <<~'OUT'
      [3, 4, 5]
      [1, 2]
      [10, 20]
      ["a", "b"]
      ["a!", "b!"]
      [[1, 4], [2, 5], [3, 6]]
      [[1, 4, 6], [2, 5, nil], [3, nil, nil]]
      nil
      [4, 1]
      [nil, nil]
    OUT
  end

  it "hash dig into array" do
    result = ze0(<<~'RUBY')
      # Hash#dig must descend into whatever the previous key returned -- an
      # Array element, a nested Hash, etc. -- dispatching each sub-key on the
      # runtime receiver. Previously a symbol-keyed hash forced every sub-key
      # to be looked up as a symbol, so `dig(:a, 1)` on an Array value gave nil.
      p({ a: [10, 20] }.dig(:a, 1))
      p({ a: { b: 1 } }.dig(:a, :b))
      p({ "a" => { "b" => 1 } }.dig("a", "b"))
      p({ a: { b: [1, 2, 3] } }.dig(:a, :b, 2))
      p({ a: [{ c: 9 }] }.dig(:a, 0, :c))
      p({ a: 1 }.dig(:a))
      p({ a: [1, 2] }.dig(:a, 5))   # out of range -> nil
      p({ a: [10, 20] }.dig(:b, 1)) # missing first key -> nil
      # a sub-key whose static type is poly (a non-constant index into a mixed
      # array) dispatches on both the runtime receiver and key kind.
      keys = [:b, 1, "c"]
      i = keys.length - 2
      p({ a: [10, 20] }.dig(:a, keys[i]))   # keys[1] == 1 -> [10, 20][1] -> 20
    RUBY

    _(result).must_answer <<~'OUT'
      20
      1
      1
      3
      9
      1
      nil
      nil
      20
    OUT
  end

  it "index operands take any integer in long range" do
    result = ze0(<<~'RUBY')
      # An index or a size reads as NUM2LONG reads it: any Integer that fits a
      # signed 64-bit word, a fixnum or not, and CRuby's RangeError past one. A
      # length past the end reads to the end, and an index past either end
      # names nothing; a Float truncates, and nil is refused.
      def t = yield rescue [$!.class, $!.message]

      a = [1, 2, 3]
      p t { a[1, 2**62] }, t { a[1, 2**63 - 1] }, t { a[1, 2**63] }, t { a[2**62] }, t { a[-(2**62), 1] }
      p t { a.first(2**62) }, t { a.last(2**62) }, t { a.rotate(2**62) }, t { a.sample(2**62).size }, t { a.take(2**62) }, t { a.drop(2**62) }
      p t { "abc"[1, 2**62] }, t { "abc".byteslice(1, 2**63 - 1) }, t { "abc"[1, 2**63] }, t { "abc"[2**62, 1] }, t { "abc".byteslice(1.9, 1) }
      p t { Array.new(2**62) }, t { Array.new(2**63) }, t { Array.new(2.7) }, t { Array.new(nil) }, t { a.first(2.5) }, t { a[1, 1.9] }, t { a.fetch(2**62) }
      p t { a.values_at(2**62) }, t { a.dig(2**62) }, t { a.dup.insert(2**62, 1) }, t { [].fill(0, 2**62, 0) }, t { [].fill(0, 2**62, -1) }
      p t { a.dup.tap { |b| b[2**62, 0] = 1 } }, t { a.dup.tap { |b| b[1, 2**62] = 9 } }, t { IO.new(2**40) }

      list = Class.new { def to_ary = [:x, :y] }
      p t { Array.new(list.new) }

    RUBY

    _(result).must_answer <<~'OUT'
      [2, 3]
      [2, 3]
      [RangeError, "bignum too big to convert into 'long'"]
      nil
      nil
      [1, 2, 3]
      [1, 2, 3]
      [2, 3, 1]
      3
      [1, 2, 3]
      []
      "bc"
      "bc"
      [RangeError, "bignum too big to convert into 'long'"]
      nil
      "b"
      [ArgumentError, "array size too big"]
      [RangeError, "bignum too big to convert into 'long'"]
      [nil, nil]
      [TypeError, "no implicit conversion from nil to integer"]
      [1, 2]
      [2]
      [IndexError, "index 4611686018427387904 outside of array bounds: -3...3"]
      [nil]
      nil
      [IndexError, "index 4611686018427387904 too big"]
      [ArgumentError, "argument too big"]
      []
      [IndexError, "index 4611686018427387904 too big"]
      [1, 9]
      [RangeError, "integer 1099511627776 too big to convert to 'int'"]
      [:x, :y]
    OUT
  end

  it "int array array" do
    result = ze0(<<~'RUBY')
      # Array of int-arrays (TY_INT_ARRAY_ARRAY): a monomorphic array whose elements
      # are themselves int arrays is stored unboxed (sp_PtrArray of sp_IntArray*),
      # so indexing yields a typed int array with no per-element boxing.
      module Field
        def self.mul(a, b) = (a * b) % 2013265921
        def self.add(a, b) = (a + b) % 2013265921
      end
      module Ext
        def self.scale(a, s)
          [Field.mul(a[0], s), Field.mul(a[1], s), Field.mul(a[2], s), Field.mul(a[3], s)]
        end
        def self.add(a, b)
          [Field.add(a[0], b[0]), Field.add(a[1], b[1]), Field.add(a[2], b[2]), Field.add(a[3], b[3])]
        end
      end

      alphas = []
      8.times { |i| alphas << [i + 1, i + 2, i + 3, i + 4] }

      acc = [0, 0, 0, 0]
      1000.times do |t|
        c = t % 8
        acc = Ext.add(acc, Ext.scale(alphas[c], t))
      end
      p acc

      # container ops: index, first, last, length, []=
      p alphas.length
      p alphas[0]
      p alphas.first
      p alphas.last
      alphas[2] = [99, 98, 97, 96]
      p alphas[2]

      # element pulled into a local, then indexed
      row = alphas[3]
      p row[1]

      # push more, iterate by index
      alphas << [10, 20, 30, 40]
      sum = 0
      alphas.length.times { |k| sum += alphas[k][0] }
      p sum

      # array-of-int-array LITERAL narrows the same way a pushed one does (the
      # OA_CLS_IA sentinel is negative but IS evidence, not an invalid marker)
      rows = [[1, 2], [3, 4], [5, 6]]
      p rows.length
      p rows[0]
      p rows[2]
      tot = 0
      rows.length.times { |k| tot += rows[k][0] + rows[k][1] }
      p tot
    RUBY

    _(result).must_answer <<~'OUT'
      [2253000, 2752500, 3252000, 3751500]
      8
      [1, 2, 3, 4]
      [1, 2, 3, 4]
      [8, 9, 10, 11]
      [99, 98, 97, 96]
      5
      142
      3
      [1, 2]
      [5, 6]
      21
    OUT
  end

  it "int array foreign values" do
    result = ze0(<<~'RUBY')
      # A homogeneous int array widens when a foreign value arrives through
      # unshift/insert/concat (like push already did), a gap left by an
      # out-of-range index write reads as nil, and delete of an absent value
      # returns nil.
      a = [1, 2, 3]
      a.unshift(:x)
      p a
      c = [1, 2]
      c.insert(1, :x)
      p c
      d = [1, 2]
      d.concat([:x])
      p d
      e = [1, 2]
      e.unshift(1.5)
      p e
      b = [1, 2, 3]
      b[5] = 9
      p b
      p b[3]
      f = [1, 2]
      p f.delete(9)
      p f.delete(2)
      p f
      g = [1, 2]
      g.push(:x)
      p g
    RUBY

    _(result).must_answer <<~'OUT'
      [:x, 1, 2, 3]
      [1, :x, 2]
      [1, 2, :x]
      [1.5, 1, 2]
      [1, 2, 3, nil, nil, 9]
      nil
      nil
      2
      [1]
      [1, 2, :x]
    OUT
  end

  it "rand float bound is integer and digits radix messages" do
    result = ze0(<<~'RUBY')
      # rand(Float) truncates the bound and draws an Integer (CRuby 4.0.6);
      # Integer#digits distinguishes a negative radix from a 0/1 radix.

      p rand(3.5).class
      p (0...3).include?(rand(3.5))
      r1 = (begin; 123.digits(0); rescue ArgumentError => e; e.message; end); p r1
      r2 = (begin; 123.digits(-5); rescue ArgumentError => e; e.message; end); p r2
    RUBY

    _(result).must_answer <<~'OUT'
      Integer
      true
      "invalid radix 0"
      "negative radix"
    OUT
  end

  it "three level array outer index" do
    result = ze0(<<~'RUBY')
      # `[a, b, c, d].map { (0...M).map { (0..N).map { ... } } }` builds a
      # 3-level Array<Array<IntArray>>. The outer .map's receiver is an
      # array literal; spinel's compile_map_expr stored that receiver in a
      # C-stack temp without registering it with the GC. When the block
      # body's nested allocations crossed the GC threshold (~272 inner
      # rows triggered the first sp_gc_collect), the unrooted receiver was
      # freed mid-loop and the next iteration's `sp_IntArray_length(rc)`
      # read the len of whatever IntArray reused that heap slot — usually
      # the most recent inner (0..N).map result, length N+1.
      #
      # Symptom on master: `TBL.length` printed 8 instead of 4, and every
      # `TBL[X]` returned the same recycled inner row regardless of X.
      # The fix roots the receiver temp when its static type is a
      # GC-allocated pointer.
      #
      # A second related fix in compile_bracket_assign covers
      # `recv[start, len] = src` where recv is statically poly_array and
      # src is poly (e.g. `@bg_pixels[xfine, 8] = @bg_pattern_lut[idx]`
      # when bg_pattern_lut comes from a poly_array<poly_array<int_array>>
      # constant). Without the dispatch the slice assignment silently
      # became `recv[start] = len` and dropped the rhs entirely.

      # Inner range is sized large enough (>= ~272) that an inner GC
      # triggers during the outer .map's iteration. Using runtime-bound
      # indices (i, j, k) to read TBL[a][b][c] avoids spinel emitting the
      # `int >> literal_index & 1` bit-index warning branch (spinel
      # can't statically tell that TBL[a] is always an array, so it
      # generates both branches; the int-branch shift count >= 64
      # triggers -Werror in the test runner with literal indices).
      TBL = [10, 20, 30, 40].map do |a|
        (0...500).map do |i|
          (0..7).map do |j|
            a + i + j
          end
        end
      end

      puts TBL.length          # 4
      puts TBL[0].length       # 500

      a0 = 0
      a1 = 1
      a2 = 2
      a3 = 3
      i0 = 0
      i499 = 499
      j0 = 0
      j7 = 7

      puts TBL[a0].length        # 500
      puts TBL[a0][i0].length    # 8
      puts TBL[a0][i0][j0]       # 10
      puts TBL[a1][i0][j0]       # 20
      puts TBL[a3][i0][j7]       # 47
      puts TBL[a2][i499][j0]     # 529
      puts TBL[a3][i499][j7]     # 546

      # Slice assign with poly_array recv + poly src — the
      # `@buf[start, len] = @table[a][i]` shape that @bg_pixels falls
      # into in optcarrot once TILE_LUT is no longer split.  @table is
      # poly_array<poly_array<int_array>>, so @table[a][i] is `poly`
      # (sp_RbVal).  @buf is sized via `[nil] * N` so it's poly_array
      # (sp_PolyArray *).  Without the dispatch fix the bracket-assign
      # falls through to single-elem write `@buf[start] = len`,
      # silently dropping the rhs.
      class Slicer
        def initialize
          @table = [10, 20, 30].map { |a| (0...4).map { |i| (0..3).map { |j| a + i + j } } }
          @buf = [nil] * 7
          @buf[0] = -1; @buf[1] = -1; @buf[2] = -1; @buf[3] = -1
          @buf[4] = -1; @buf[5] = -1; @buf[6] = -1
        end
        def fill(a, i); @buf[1, 4] = @table[a][i]; end
        def get(k); @buf[k]; end
      end

      s = Slicer.new
      s.fill(2, 1)
      puts s.get(0)            # -1
      puts s.get(1)            # 31
      puts s.get(2)            # 32
      puts s.get(3)            # 33
      puts s.get(4)            # 34
      puts s.get(5)            # -1
      s.fill(0, 0)
      puts s.get(1)            # 10
      puts s.get(4)            # 13
    RUBY

    _(result).must_answer <<~'OUT'
      4
      500
      500
      8
      10
      20
      47
      529
      546
      -1
      31
      32
      33
      34
      -1
      10
      13
    OUT
  end
end
