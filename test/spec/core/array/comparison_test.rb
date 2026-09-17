# frozen_string_literal: true

require "spec_helper"

describe "Array: comparison and equality" do
  it "array bsearch find any" do
    result = ze0(<<~'RUBY')
      # Array#bsearch / #bsearch_index find-ANY mode: an Integer-valued block follows
      # the comparator protocol (0 found, negative searches left, positive right),
      # distinct from the boolean find-minimum mode. Also: a float-array bsearch miss
      # is nil (the result temp used to init as NULL, an invalid mrb_float).
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

  it "array compact eq" do
    result = ze0(<<~'RUBY')
      # `[1, nil, 2].compact` yields a poly_array, but a literal like `[1, 2]`
      # stays an int_array, so `compact == [1, 2]` compared distinct pointer
      # types and failed the -Werror build. Add a poly_array-vs-typed-array
      # equality that boxes the typed side per element and compares via
      # sp_poly_eq (both operand orders).

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

  it "array eq cross kind" do
    result = ze0(<<~'RUBY')
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

  it "array eql strict" do
    result = ze0(<<~'RUBY')
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

  it "array object id" do
    result = ze0(<<~'RUBY')
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

  it "array uniq hash collision skips eql" do
    result = ze0(<<~'RUBY')
      # `Array#uniq` confirms hash-equal candidates with `eql?`.
      #
      # The whole key table used to collapse on the user `hash` alone, so any
      # two objects with colliding hashes were one key however their `eql?`
      # read. `uniq` was the visible symptom; `a_user_hash_that_collides.rb`
      # carries the rest, including the Hash that read back another key's value.
      c = Struct.new(:v) do
        def hash = 0
        def eql?(o) = v == o.v
      end
      p [c.new(1), c.new(1), c.new(2)].uniq.length
      p [c.new(1), c.new(2)].uniq { |x| x }.length
    RUBY

    _(result).must_answer <<~'OUT'
      2
      2
    OUT
  end

  it "bsearch find any mode follows the comparator protocol" do
    result = ze0(<<~'RUBY')
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
    result = ze0(<<~'RUBY')
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

  it "hash keyed by an array hashes structurally not by identity" do
    _(ze0(<<~'RUBY')).must_answer "pair\n"
      h = {}
      h[[1, 2]] = "pair"
      puts h[[1, 2]]
    RUBY
  end

  it "nested array eq" do
    result = ze0(<<~'RUBY')
      # Array#== on an array of arrays/objects (a ptr_array) had no deep
      # comparison -- the dispatch covered int/str/float/poly arrays but not
      # ptr_array, so `[[1]] == [[1]]` fell through to FALSE. Compare
      # element-wise inline using each element's statically-known type.

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
end
