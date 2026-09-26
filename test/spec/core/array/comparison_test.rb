# frozen_string_literal: true

require "spec_helper"

describe "Array: comparison and equality" do
  it "bsearch with an Integer block follows the comparator protocol, and a float miss answers nil" do
    result = zr(<<~'RUBY')
      # Array#bsearch / #bsearch_index find-ANY mode: an Integer-valued block follows
      # the comparator protocol (0 found, negative searches left, positive right),
      # distinct from the boolean find-minimum mode. Also: a float-array bsearch miss
      # is nil.
      a = [0, 4, 7, 10, 12]
      p a.bsearch { |x| x <=> 7 }
      p(a.bsearch { |x| x <=> 3 })
      p a.bsearch_index { |x| x <=> 12 }
      p(a.bsearch_index { |x| x <=> 11 })
      p [1, 2, 3].bsearch { |x| 1 - x }
      # find-minimum still works
      p a.bsearch { |x| x >= 10 }
      p a.bsearch_index { |x| x >= 5 }
      b = [1.0, 2.5, 4.0]
      p b.bsearch { |x| x >= 2.0 }
      p(b.bsearch { |x| x >= 9.0 })
    RUBY

    _(result).must_answer <<~'OUT'
      7
      nil
      nil
      nil
      1
      10
      2
      2.5
      nil
    OUT
  end

  it "compact's poly result compares equal to a typed literal, in both operand orders" do
    result = zr(<<~'RUBY')
      # `[1, nil, 2].compact` starts from an array with mixed element types.
      # It compares equal to a literal like `[1, 2]` element by element, in
      # both operand orders.

      p [1, nil, 2].compact                          #=> [1, 2]
      p([1, nil, 2].compact == [1, 2])               #=> true
      p([1, nil, 2].compact == [1, 3])               #=> false
      p([1, 2] == [1, nil, 2].compact)               #=> true  (reverse order)
      p(["a", nil, "b"].compact == ["a", "b"])       #=> true
      p([1.0, nil, 2.0].compact == [1.0, 2.0])       #=> true
      p([1, nil].compact == [1])                     #=> true
      p([1, nil, 2].compact != [1, 2])               #=> false
      p([1, nil, 2].compact != [9])                  #=> true
      puts "done"
    RUBY

    _(result).must_answer <<~'OUT'
      [1, 2]
      true
      false
      true
      true
      true
      true
      false
      true
      done
    OUT
  end

  it "== compares by value, whatever storage kind each side holds" do
    result = zr(<<~'RUBY')
      # Array == compares by value across storage kinds: a splat-rest rebuilds its
      # arguments as a poly array, while the literal it is compared against may box
      # as an int array. Ruby has one Array; storage kinds must not leak into ==.
      pr = proc do |*a, b|
        [a, b]
      end
      p pr.call(1, 2, 3) == [[1, 2], 3]
      p pr.call("x", "y") == [["x"], "y"]
      p pr.call(1) == [[], 1]
      p pr.call(1, 2) == [[1], 999]
    RUBY

    _(result).must_answer <<~'OUT'
      true
      true
      true
      false
    OUT
  end

  it "eql? and uniq compare class-strictly, so 1 and 1.0 stay apart" do
    result = zr(<<~'RUBY')
      # Array#eql? and Array#uniq compare per element with eql? (class-strict:
      # 1 is == to 1.0 but not eql?), matching CRuby.
      def e(a, b); a.eql?(b); end
      def u(a); a.uniq; end     # mixed (poly) arrays only
      def ui(a); a.uniq; end    # int arrays only

      p e([1, 2], [1, 2.0])       # false
      p e([1, 2], [1, 2])         # true
      p e([1, 2], [1, 2, 3])      # false
      p e(["a", 1.5], ["a", 1.5]) # true
      p [1, 2] == [1, 2.0]        # true (== still coerces)
      p u([1.0, 1])               # [1.0, 1]
      p ui([1, 1, 2])             # [1, 2]
      p u([1, 1.0, "x", "x"])     # [1, 1.0, "x"]
      a2 = [2.0, 2]
      a2.uniq!
      p a2                        # [2.0, 2]
    RUBY

    _(result).must_answer <<~'OUT'
      false
      true
      false
      true
      true
      [1.0, 1]
      [1, 2]
      [1, 1.0, "x"]
      [2.0, 2]
    OUT
  end

  it "object_id answers a stable integer per array, and two arrays never share one" do
    result = zr(<<~'RUBY')
      # Array#object_id on typed arrays: a stable per-object integer. (Exact
      # values are pointer-dependent, so check identity/distinctness/type.)
      a = [1, 2, 3]
      b = ["x", "y"]
      c = [1.5, 2.5]
      d = [1, "two"]
      p(a.object_id == a.object_id)
      p(a.object_id == b.object_id)
      p(a.object_id.is_a?(Integer))
      p(b.object_id.is_a?(Integer))
      p(c.object_id.is_a?(Integer))
      p(d.object_id.is_a?(Integer))
    RUBY

    _(result).must_answer <<~'OUT'
      true
      false
      true
      true
      true
      true
    OUT
  end

  it "<=> compares element-wise with a length tiebreak, and terminates on a self-referential array" do
    result = zr(<<~'RUBY')
      # The cycle this program builds on purpose, and the census it leaves
      # behind. A cycle alive at exit is not a defect: it is a ring the
      # program never broke, so the census below is recorded as an
      # observation rather than gated on.
      #
      # A self-referential array, built on purpose to prove the comparison terminates.
      # At exit: cycle leak: 1 objects (Array x1)
      # Array#<=>: lexicographic element-wise comparison with a length tiebreak,
      # across every array kind. Receivers go through per-type method params so each
      # stays a concrete typed (or boxed-poly) array rather than constant folding.
      # A typed comparison whose elements are mutually incomparable yields nil.
      def ints(a); a; end
      def strs(a); a; end
      def flts(a); a; end
      def polys(a); a; end

      # element difference decides before length
      p(ints([1, 2, 3]) <=> ints([1, 2, 4]))
      p(ints([1, 2, 4]) <=> ints([1, 2, 3]))
      p(ints([1, 2, 3]) <=> ints([1, 2, 3]))

      # equal prefix: the shorter array is smaller
      p(ints([1, 2, 3]) <=> ints([1, 2]))
      p(ints([1, 2]) <=> ints([1, 2, 3]))

      # string and float arrays compare the same way
      p(strs(%w[a b]) <=> strs(%w[a c]))
      p(strs(%w[a b c]) <=> strs(%w[a b]))
      p(flts([1.0, 2.0]) <=> flts([1.0, 2.0, 3.0]))
      p(flts([2.5]) <=> flts([1.5]))

      # poly arrays (mixed element kinds), passed through a method param
      p(polys([1, "a"]) <=> polys([1, "b"]))
      p(polys([1, 2]) <=> polys([1, 2, 3]))

      # mutually incomparable element kinds: nil
      p(ints([1, 2]) <=> strs(["a"]))

      # an array compared to itself is 0; a self-referential array still terminates
      a = ints([1, 2, 3])
      p(a <=> a)
      r = polys([1, 2])
      r.push(r)
      p(r <=> r)
    RUBY

    _(result).must_answer <<~'OUT'
      -1
      1
      0
      1
      -1
      -1
      1
      -1
      1
      -1
      -1
      nil
      0
      0
    OUT
  end

  it "uniq confirms a hash-equal candidate with eql? before it drops one" do
    result = zr(<<~'RUBY')
      # `Array#uniq` confirms hash-equal candidates with `eql?`.
      #
      # Two objects with colliding hashes are one key only when `eql?` says so.
      # `a_user_hash_that_collides.rb` checks the rest, including Hash lookup.
      c = Struct.new(:v) do
        def hash = 0
        def eql?(o) = v == o.v
      end
      p [c.new(1), c.new(1), c.new(2)].uniq.length
      p [c.new(1), c.new(2)].uniq { |x| x }.length
    RUBY

    _(result).must_answer "2\n2\n"
  end

  it "bsearch find any mode follows the comparator protocol" do
    result = zr(<<~'RUBY')
      # A Numeric block result selects find-any mode: 0 is a hit, negative
      # searches the lower half, positive the upper; a non-hit answers nil. The
      # boolean find-minimum mode still works alongside it.

      a = [0, 4, 7, 10, 12]
      p a.bsearch { |x| 7 <=> x }
      p a.bsearch { |x| 10 <=> x }
      p a.bsearch_index { |x| 12 <=> x }
      p(a.bsearch { |x| 3 <=> x })
      p a.bsearch { |x| x >= 10 }
      p [1, 2, 3].bsearch { |x| 1 - x }
      p((1..100).bsearch { |x| x >= 8 })
    RUBY

    _(result).must_answer <<~'OUT'
      7
      10
      4
      nil
      10
      1
      8
    OUT
  end

  it "container reads its elements by identity first" do
    result = zr(<<~'RUBY')
      # CRuby's rb_equal: an element inside a container is equal to itself
      # before `==` is asked, which is what makes `[nan].include?(nan)` true
      # while `nan == nan` is false.
      n = Float::NAN
      p [n == n, [n] == [n], { a: n } == { a: n }]
      p [[n].rindex(n), [n].count(n), [n].delete(n)]
      p [[[n, 1]].assoc(n), [[1, n]].rassoc(n)]
      p [{ a: n }.value?(n), { a: n }.key(n), { a: n }.rassoc(n), { a: n } <= { a: n }]
      p [[n].each_entry.include?(n), [n].each_entry.count(n), [n].each_entry.find_index(n)]

      # A user `==` that answers false for its own receiver loses the same way.
      class Never
        def ==(_other) = false
        def inspect = "Never"
      end
      q = Never.new
      p [q == q, [q] == [q], [q].include?(q), [q].index(q), [q].rindex(q), [q].count(q)]
      p({ a: q } == { a: q })
    RUBY

    _(result).must_answer <<~'OUT'
      [false, true, true]
      [0, 1, NaN]
      [[NaN, 1], [1, NaN]]
      [true, :a, [:a, NaN], true]
      [true, 1, 0]
      [false, true, true, 0, 0, 1]
      true
    OUT
  end

  it "hash dig and hash key" do
    result = zr(<<~'RUBY')
      # The cycle this program builds on purpose, and the census it leaves
      # behind. A cycle alive at exit is not a defect: it is a ring the
      # program never broke, so the census below is recorded as an
      # observation rather than gated on.
      #
      # `a << a` -- a self-referential container, built on purpose to prove the walk terminates.
      # At exit: cycle leak: 2 objects (Array x1, Hash x1)
      h = { a: 1 }
      r = (h.dig(:a, :b) rescue $!.class); p r
      r = (h.dig(:a, :b) rescue $!.message); p r
      r = ({ a: "str" }.dig(:a, :b) rescue $!.class); p r

      # the walk still ends quietly at a missing key
      p h.dig(:zz)
      p h.dig(:zz, :deeper)

      # and still walks what it can
      p({ a: { b: { c: 7 } } }.dig(:a, :b, :c))
      p({ a: [10, 20] }.dig(:a, 1))
      p({ a: { b: [1, { c: 2 }] } }.dig(:a, :b, 1, :c))

      # Hash#hash is content-based and order-independent
      p({ a: 1 }.hash == { a: 1 }.hash)
      p({ a: 1, b: 2 }.hash == { b: 2, a: 1 }.hash)
      p({ a: 1 }.hash == { a: 2 }.hash)
      p({ "x" => [1, 2] }.hash == { "x" => [1, 2] }.hash)
      p({}.hash == {}.hash)
      p({ a: 1 }.eql?({ a: 1 }))

      # self-referential containers terminate (CRuby answers a fixed value for the
      # recursive reference; the walk is depth-capped here)
      h2 = {}
      h2[:me] = h2
      p(h2.hash == h2[:me].hash)
      a = []
      a << a
      p(a.hash == a[0].hash)
    RUBY

    _(result).must_answer <<~'OUT'
      TypeError
      "Integer does not have #dig method"
      TypeError
      nil
      nil
      7
      20
      2
      true
      true
      false
      true
      true
      true
      true
      true
    OUT
  end

  it "hash keyed by an array hashes structurally not by identity" do
    result = zr(<<~'RUBY')
      h = {}
      h[[1, 2]] = "pair"
      puts h[[1, 2]]
    RUBY

    _(result).must_answer "pair\n"
  end

  it "nested array eq" do
    result = zr(<<~'RUBY')
      # Array#== on an array of arrays/objects compares deeply, element by
      # element, so `[[1]] == [[1]]` is true.

      p([[1]] == [[1]])                         #=> true
      p([[1, 2], [3]] == [[1, 2], [3]])         #=> true
      p([[1]] == [[2]])                         #=> false
      p([[1], [2]] == [[1]])                    #=> false (length)
      p([["a"], ["b"]] == [["a"], ["b"]])       #=> true
      p([["a"]] == [["b"]])                     #=> false
      p([[1.0]] == [[1.0]])                     #=> true
      p([[1]] != [[2]])                         #=> true
      p([[1]] != [[1]])                         #=> false

      x = [[1, 2, 3]]
      y = [[1, 2, 3]]
      p(x == y)                                 #=> true
      x[0] << 4
      p(x == y)                                 #=> false

      puts "done"
    RUBY

    _(result).must_answer <<~'OUT'
      true
      true
      false
      false
      true
      false
      true
      true
      false
      true
      false
      done
    OUT
  end

  it "recursive array spaceship overflows" do
    result = zr(<<~'RUBY')
      # The cycle this program builds on purpose, and the census it leaves
      # behind. A cycle alive at exit is not a defect: it is a ring the
      # program never broke, so the census below is recorded as an
      # observation rather than gated on.
      #
      # Four rings: `a`, `b`, `c` and `d` each hold themselves, which is the graph the paired guard has to walk.
      # At exit: cycle leak: 4 objects (Array x4)
      # `<=>` between self-referential arrays uses CRuby's PAIRED recursion
      # guard, the same one `==` already had. Without it the walk recursed until
      # the stack ran out and the process aborted.
      #
      # A revisited pair does NOT answer 0. CRuby's `recursive_cmp` hands back
      # `Qundef` and `rb_ary_cmp` falls through to the LENGTH comparison, so the
      # two agree for equal-length arrays and differ otherwise -- which is what
      # the third row below is for.

      a = [1]
      a << a
      b = [1]
      b << b
      p a == b
      p(a <=> b)

      # Different lengths: the length comparison is what answers, not 0.
      c = [1]
      c << c
      d = [1]
      d << d << 3
      p(c <=> d)
      p(d <=> c)

      # The pair is ORDERED, so `a <=> b` and `b <=> a` are different
      # comparisons and both terminate.
      p(b <=> a)

      # A shared element is not a cycle, and still compares element-wise.
      shared = [1, 2]
      p([shared, 3] <=> [shared, 4])
      p([shared] <=> [shared])

      # Ordinary comparisons are untouched.
      p([1, 2] <=> [1, 3])
      p([1, 2] <=> [1, 2, 3])
      p([[1], [2]] <=> [[1], [2]])
      p(([1] <=> ["a"]).inspect)
    RUBY

    _(result).must_answer <<~'OUT'
      true
      0
      -1
      1
      0
      -1
      0
      -1
      -1
      0
      "nil"
    OUT
  end

  it "min and max compare the best so far with each element, as ary_min_generic does" do
    result = zr(<<~'RUBY')
      def t
        p yield
      rescue ArgumentError => e
        puts e.message
      end
      a = [1, nil]
      b = [1, "a"]
      c = [2.0, nil]
      t { a.min }
      t { a.max }
      t { b.min }
      t { c.min }
      t { a.minmax }
      t { b.min { |x, y| x <=> y } }
    RUBY

    _(result).must_answer <<~'OUT'
      comparison of Integer with nil failed
      comparison of Integer with nil failed
      comparison of Integer with String failed
      comparison of Float with nil failed
      comparison of Integer with nil failed
      comparison of String with 1 failed
    OUT
  end

  it "a literal that is not static compares each element with the best, as opt_newarray_send does" do
    result = zr(<<~'RUBY')
      def t
        p yield
      rescue ArgumentError => e
        puts e.message
      end
      x = "a"
      a = [1, nil]
      t { [1, "a"].min }
      t { [1, x, 2].min }
      t { [1, nil].min }
      t { [1, "a"].max }
      t { a.min }
      t { [1, "a"].min { |p, q| p <=> q } }
      t { [3, 1, 2].min }
      t { [3, 1, x.size + 5].max }
      class Array
        def min = :redefined
      end
      t { [1, x].min }
    RUBY

    _(result).must_answer <<~'OUT'
      comparison of String with 1 failed
      comparison of String with 1 failed
      comparison of Integer with nil failed
      comparison of String with 1 failed
      comparison of Integer with nil failed
      comparison of String with 1 failed
      1
      6
      :redefined
    OUT
  end
end
