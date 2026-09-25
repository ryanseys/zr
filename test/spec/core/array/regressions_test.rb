# frozen_string_literal: true

require "spec_helper"

describe "Array: regressions" do
  it "unshift and prepend on an empty literal, reduce with a seed, and fetch_values with a fallback block" do
    result = zr(<<~'RUBY')
      # Array conformance
      p([].unshift(1))                              # empty-literal unshift
      p([].prepend(2, 3))
      a = []
      c = a.reduce(5, :+)                            # empty variable reduce(init, :sym)
      p c
      p([1, 2, 3].reduce(10, :+))
      p([nil, nil].all?(nil))                        # all? with a nil pattern
      p([nil, 1].all?(nil))
      p([1, nil].any?(nil))
      p([].rfind { |x| x > 0 })                      # rfind on an empty literal
      p([1, 2, 3].fetch_values(0, 5) { |i| i * 10 }) # fetch_values block fallback
      p(["a", "b"].fetch_values(1, 9) { |i| "x#{i}" })
      p([1, 2, 3].fetch_values(0, 1))                # blockless still exact
      begin
        [1, 2].fetch_values(9)
        p :no_error
      rescue IndexError
        p :index_error
      end
    RUBY

    _(result).must_answer <<~'OUT'
      [1]
      [2, 3]
      5
      16
      true
      false
      true
      nil
      [1, 50]
      ["b", "x9"]
      [1, 2]
      :index_error
    OUT
  end

  it "product, flatten, combination and permutation over the typed array kinds" do
    result = zr(<<~'RUBY')
      # Array#product (block form and no-arg), flatten/flatten! with a depth,
      # and value-captured block forms of the combination/slice family
      # (all return self per Ruby >= 3.1).
      r = []
      [1, 2].product([3, 4]) { |pair| r << pair }
      p r
      p([1, 2].product)
      a = [1, 2, [3, [4]]]
      p(a.flatten!(1))
      p a
      b = [1, 2]
      p(b.flatten!(1))
      v = [1, 2, 3].each_slice(2) { |s| p s }
      p v
      w = [1, 2, 3].combination(2) { |c| p c }
      p w
      x = [1, 2].repeated_permutation(2) { |q| p q }
      p x
      r = []
      [1, 2].product([3, 4]) { |pair| r << pair }
      p r
      p([1, 2].product)
      v = %w[a b].product([1]) { |q| p q }
      p v
      a = [1, 2, [3, [4]]]
      p(a.flatten!(1))
      p a
      b = [1, 2]
      p(b.flatten!(1))
      c = [1, [2, [3, [4]]]]
      p(c.flatten(2))
      p c
      v = [1, 2, 3].each_slice(2) { |s| p s }
      p v
      w = [1, 2, 3].combination(2) { |c| p c }
      p w
      x = [1, 2].repeated_permutation(2) { |q| p q }
      p x
      y = [1, 2].repeated_combination(2) { |q| p q }
      p y
      z = [1, 2, 3].each_cons(2) { |q| p q }
      p z
      u = [1, 2, 3].permutation(2) { |q| p q }
      p u
    RUBY

    _(result).must_answer <<~'OUT'
      [[1, 3], [1, 4], [2, 3], [2, 4]]
      [[1], [2]]
      [1, 2, 3, [4]]
      [1, 2, 3, [4]]
      nil
      [1, 2]
      [3]
      [1, 2, 3]
      [1, 2]
      [1, 3]
      [2, 3]
      [1, 2, 3]
      [1, 1]
      [1, 2]
      [2, 1]
      [2, 2]
      [1, 2]
      [[1, 3], [1, 4], [2, 3], [2, 4]]
      [[1], [2]]
      ["a", 1]
      ["b", 1]
      ["a", "b"]
      [1, 2, 3, [4]]
      [1, 2, 3, [4]]
      nil
      [1, 2, 3, [4]]
      [1, [2, [3, [4]]]]
      [1, 2]
      [3]
      [1, 2, 3]
      [1, 2]
      [1, 3]
      [2, 3]
      [1, 2, 3]
      [1, 1]
      [1, 2]
      [2, 1]
      [2, 2]
      [1, 2]
      [1, 1]
      [1, 2]
      [2, 2]
      [1, 2]
      [1, 2]
      [2, 3]
      [1, 2, 3]
      [1, 2]
      [1, 3]
      [2, 1]
      [2, 3]
      [3, 1]
      [3, 2]
      [1, 2, 3]
    OUT
  end

  it "array2" do
    result = zr(<<~'RUBY')
      # Test additional Array methods

      arr = (1..10).to_a

      # reject
      odds = arr.reject do |x|
        x % 2 == 0
      end
      puts odds.length  # 5

      # reduce/inject via each
      total = 0
      arr.each do |x|
        total += x
      end
      puts total  # 55

      # reverse
      nums = (1..10).to_a
      nums.reverse!
      puts nums[0]  # 10
      puts nums[9]  # 1

      # Array#first / Array#last
      puts nums.first  # 10
      puts nums.last   # 1

      # Array#min / Array#max
      mn = nums[0]
      mx = nums[0]
      nums.each do |x|
        if x < mn
          mn = x
        end
        if x > mx
          mx = x
        end
      end
      puts mn  # 1
      puts mx  # 10

      # Array#include?
      if nums.include?(5)
        puts "true"
      else
        puts "false"
      end   # true
      if nums.include?(11)
        puts "true"
      else
        puts "false"
      end  # false

      # Array#compact (remove nils) - simplified: just test count
      puts nums.length  # 10
    RUBY

    _(result).must_answer <<~'OUT'
      5
      55
      10
      1
      10
      1
      1
      10
      true
      false
      10
    OUT
  end

  it "array3" do
    result = zr(<<~'RUBY')
      # Test additional array methods

      arr = Array.new
      arr.push(5); arr.push(3); arr.push(8); arr.push(1)
      arr.push(4); arr.push(2); arr.push(7); arr.push(6)

      # count with block
      puts arr.count { |x| x > 4 }   # 4 (5,8,7,6)

      # count without block
      puts arr.count                   # 8

      # min_by / max_by
      puts arr.min_by { |x| x }       # 1
      puts arr.max_by { |x| x }       # 8

      # sort_by
      sorted = arr.sort_by { |x| -x }
      puts sorted[0]    # 8
      puts sorted[1]    # 7
      puts sorted[7]    # 1

      # String array count
      words = "hello world foo bar".split(" ")
      puts words.count { |w| w.length > 3 }  # 2 (hello, world)
      puts words.count                         # 4

      puts "done"
    RUBY

    _(result).must_answer <<~'OUT'
      4
      8
      1
      8
      8
      7
      1
      2
      4
      done
    OUT
  end

  it "difference removes one occurrence for each occurrence in the argument" do
    result = zr(<<~'RUBY')
      # Array#- / Array#difference must preserve LHS duplicates that
      # aren't in the RHS. CRuby semantics:
      #   [1, 1, 2, 3] - [3]  → [1, 1, 2]   (NOT [1, 2])
      #   [1, 1, 2, 3] - [1]  → [2, 3]      (every 1 removed)

      # Integer array
      puts ([1, 1, 2, 3] - [3]).inspect
      puts ([1, 1, 2, 3] - [1]).inspect
      puts ([1, 1, 1, 2, 2] - [1]).inspect
      puts ([1, 2, 1, 3, 1] - [3]).inspect

      # String array
      puts (["a", "a", "b", "c"] - ["c"]).inspect
      puts (["a", "b", "a", "c", "a"] - ["c"]).inspect

      # float_array
      puts ([1.0, 1.0, 2.0, 3.0] - [3.0]).inspect
      puts ([1.5, 1.5, 2.5] - [2.5]).inspect

      # method form
      puts [1, 1, 2, 3].difference([3]).inspect
      puts ["a", "a", "b"].difference(["b"]).inspect
    RUBY

    _(result).must_answer <<~'OUT'
      [1, 1, 2]
      [2, 3]
      [2, 2]
      [1, 2, 1, 1]
      ["a", "a", "b"]
      ["a", "b", "a", "a"]
      [1.0, 1.0, 2.0]
      [1.5, 1.5]
      [1, 1, 2]
      ["a", "a"]
    OUT
  end

  it "fill takes a value, a start, and a length" do
    result = zr(<<~'RUBY')
      # Array#fill: 1-arg, 2-arg, 3-arg forms.
      # The 2-arg and 3-arg forms fill only from start, for length elements.

      # 1-arg: fill all
      a = [1, 2, 3, 4, 5]
      a.fill(9)
      puts a[0]    # 9
      puts a[4]    # 9

      # 2-arg: fill from start to end
      b = [1, 2, 3, 4, 5]
      b.fill(9, 2)
      puts b[0]    # 1
      puts b[1]    # 2
      puts b[2]    # 9
      puts b[4]    # 9

      # 3-arg: fill from start, length elements
      c = [1, 2, 3, 4, 5]
      c.fill(0, 1, 3)
      puts c[0]    # 1
      puts c[1]    # 0
      puts c[3]    # 0
      puts c[4]    # 5

      # Negative start
      d = [1, 2, 3, 4, 5]
      d.fill(7, -2)
      puts d[0]    # 1
      puts d[2]    # 3
      puts d[3]    # 7
      puts d[4]    # 7

      # 3-arg with start beyond length: array grows.
      # Ruby fills the gap with nil. The test checks only the new length
      # and the filled values, not e[3] and e[4].
      e = [1, 2, 3]
      e.fill(9, 5, 2)
      puts e.length   # 7
      puts e[2]       # 3
      puts e[5]       # 9
      puts e[6]       # 9

      # 2-arg with start beyond length: no-op, array unchanged.
      f = [1, 2, 3]
      f.fill(9, 5)
      puts f.length   # 3
      puts f[2]       # 3

      # Very-negative start: clamped to 0 after wrap (start + len < 0).
      # CRuby: [1,2,3].fill(9, -5, 2) #=> [9, 9, 3]
      g = [1, 2, 3]
      g.fill(9, -5, 2)
      puts g[0]       # 9
      puts g[1]       # 9
      puts g[2]       # 3
    RUBY

    _(result).must_answer <<~'OUT'
      9
      9
      1
      2
      9
      9
      1
      0
      0
      5
      1
      3
      7
      7
      7
      3
      9
      9
      3
      3
      9
      9
      3
    OUT
  end

  it "an array literal answers length, subscript, sort, sum, min and max" do
    result = zr(<<~'RUBY')
      # Array literals of Integers and of Strings

      # Integer array literal
      arr = [5, 3, 8, 1, 4]
      puts arr.length    # 5
      puts arr.size      # 5  (alias for length)
      puts arr[0]        # 5
      puts arr.sort[0]   # 1
      puts arr.sum       # 21
      puts arr.min       # 1
      puts arr.max       # 8

      # size after push and pop
      arr.push(99)
      puts arr.size      # 6  (length+1 after push)
      arr.pop
      puts arr.size      # 5  (length-1 after pop)

      # Symbol array literal -- size works the same as for an Integer array
      syms = [:foo, :bar, :baz]
      puts syms.length   # 3
      puts syms.size     # 3

      # String array literal
      words = ["hello", "world", "foo"]
      puts words.length  # 3
      puts words.size    # 3
      puts words[0]      # hello
      puts words.join(", ") # hello, world, foo

      # Empty array
      empty = []
      empty.push(42)
      puts empty.length  # 1
      puts empty.size    # 1
      puts empty[0]      # 42

      # Hoisted-length optimisation: .size should behave the same as
      # .length when used as a loop bound. Both compile to a single
      # read of the array's len field, hoisted out of the loop body.
      sum = 0
      i = 0
      while i < arr.size
        sum += arr[i]
        i += 1
      end
      puts sum           # 21

      ssum = 0
      si = 0
      while si < syms.size
        ssum += 1
        si += 1
      end
      puts ssum          # 3

      wlen = 0
      wi = 0
      while wi < words.size
        wlen += words[wi].length
        wi += 1
      end
      puts wlen          # 13

      puts "done"
    RUBY

    _(result).must_answer <<~'OUT'
      5
      5
      5
      1
      21
      1
      8
      6
      5
      3
      3
      3
      3
      hello
      hello, world, foo
      1
      1
      42
      21
      3
      13
      done
    OUT
  end

  it "an array literal built from a widened local holds the value, not the box" do
    result = zr(<<~'RUBY')
      # A local can hold an Integer or a String, because two branches set it.
      # An `[x]` literal of that local holds the value itself.

      addr = 7
      flag = 0
      if flag > 0
        # This path does not run. It only lets `addr` also be a String.
        addr = "x"
      end

      # `addr` can be a String or an Integer, but at run time it is 7.
      # The `[addr]` literal holds that 7.
      arr = [addr]
      puts arr.length          # 1
      puts arr[0]              # 7
    RUBY

    _(result).must_answer "1\n7\n"
  end

  it "Array#* repeats the array, and times one is a copy the source cannot reach" do
    result = zr(<<~'RUBY')
      # Array#* (repeat) works the same for every element type:
      # Integer, Float, String, Symbol and mixed.

      # Integer array
      ints = [1, 2, 3] * 3
      puts ints.length      # 9
      puts ints[0]          # 1
      puts ints[3]          # 1
      puts ints[8]          # 3

      # Integer array * 0 → empty
      empty = [1, 2, 3] * 0
      puts empty.length     # 0

      # Integer array * 1 → copy (independent of source)
      arr = [1, 2]
      copy = arr * 1
      arr.push(99)
      puts copy.length      # 2

      # Float array
      floats = [1.5, 2.5] * 2
      puts floats.length    # 4
      puts floats[0]        # 1.5
      puts floats[3]        # 2.5

      # String array
      strs = ["a", "b"] * 3
      puts strs.length      # 6
      puts strs[0]          # a
      puts strs[5]          # b

      # Symbol array
      syms = [:x, :y] * 2
      puts syms.length      # 4
      puts syms[0]          # x
      puts syms[3]          # y

      # Mixed array
      mixed = [1, "two", 3.0] * 2
      puts mixed.length     # 6

      # Pre-fill an array
      zeros = [0] * 5
      puts zeros.length     # 5
      puts zeros[0]         # 0
      puts zeros[4]         # 0

      puts "done"
    RUBY

    _(result).must_answer <<~'OUT'
      9
      1
      1
      3
      0
      2
      4
      1.5
      2.5
      6
      a
      b
      4
      x
      y
      6
      5
      0
      0
      done
    OUT
  end

  it "Array.new with a block calls it once an index" do
    result = zr(<<~'RUBY')
      # Array.new(N) { |i| ... }: block form with index parameter.
      # The block gives each element.

      # Block uses index
      a = Array.new(5) { |i| i * 2 }
      puts a.length      # 5
      puts a[0]          # 0
      puts a[2]          # 4
      puts a[4]          # 8
      puts a.sum         # 20

      # Block returns constant
      b = Array.new(3) { 42 }
      puts b.length      # 3
      puts b[0]          # 42
      puts b[2]          # 42

      # Zero-length
      c = Array.new(0) { 99 }
      puts c.length      # 0
    RUBY

    _(result).must_answer <<~'OUT'
      5
      0
      4
      8
      20
      3
      42
      42
      0
    OUT
  end

  it "an array of arrays subscripts and iterates two levels deep" do
    result = zr(<<~'RUBY')
      # Array of arrays (2-level nesting)
      a = [[1, 2], [3, 4], [5, 6]]
      puts a.length

      # Iterate nested arrays
      a.each { |sub|
        puts sub[0] + sub[1]
      }

      # String array of arrays
      b = [["hello", "world"], ["foo", "bar"]]
      b.each { |pair|
        puts pair.join(" ")
      }

      # Push to array of arrays
      c = [[10, 20]]
      c.push([30, 40])
      c.push([50, 60])
      puts c.length
      c.each { |row|
        row.each { |v| print v.to_s + " " }
        puts ""
      }
    RUBY

    _(result).must_answer <<~'OUT'
      3
      3
      7
      11
      hello world
      foo bar
      3
      10 20 
      30 40 
      50 60 
    OUT
  end

  it "inspect prints a nested array of every element type" do
    result = zr(<<~'RUBY')
      # p and inspect on nested arrays of Integer, String, Float and Symbol.

      p [[1, 2], [3, 4]]
      p [[1, 2, 3], [4, 5, 6]]
      p [[10]]
      p [[1, 2], [3, 4]].transpose

      p [["a", "b"], ["c", "d"]]
      p [["hello", "world"]]

      p [[1.5, 2.5], [3.5, 4.5]]
      p [[0.1]]

      p [[:a, :b], [:c, :d]]
      p [[:foo]]
    RUBY

    _(result).must_answer <<~'OUT'
      [[1, 2], [3, 4]]
      [[1, 2, 3], [4, 5, 6]]
      [[10]]
      [[1, 3], [2, 4]]
      [["a", "b"], ["c", "d"]]
      [["hello", "world"]]
      [[1.5, 2.5], [3.5, 4.5]]
      [[0.1]]
      [[:a, :b], [:c, :d]]
      [[:foo]]
    OUT
  end

  it "push appends to an array of any element type and answers the receiver" do
    result = zr(<<~'RUBY')
      # Array#push on arrays of each element type.

      ints = [1, 2, 3]
      ints.push(4)
      ints.push(5)
      puts ints.length          # 5
      puts ints[3]              # 4
      puts ints[4]              # 5

      # The Float values have a fractional part, so no value prints as "N.0".
      floats = [1.5, 2.5]
      floats.push(3.5)
      floats.push(4.25)
      puts floats.length        # 4
      puts floats[2]            # 3.5
      puts floats[3]            # 4.25

      strs = ["a", "b"]
      strs.push("c")
      strs.push("d")
      puts strs.length          # 4
      puts strs[2]              # c
      puts strs[3]              # d

      syms = [:x, :y]
      syms.push(:z)
      puts syms.length          # 3
      puts syms[2]              # z

      # << on arrays of each element type, Symbol included.
      ints2 = [10]
      ints2 << 20
      ints2 << 30
      puts ints2.length         # 3
      puts ints2[2]             # 30

      floats2 = [1.5]
      floats2 << 2.5
      puts floats2.length       # 2
      puts floats2[1]           # 2.5

      strs2 = ["x"]
      strs2 << "y"
      puts strs2.length         # 2
      puts strs2[1]             # y

      syms2 = [:p]
      syms2 << :q
      puts syms2.length         # 2
      puts syms2[1]             # q
    RUBY

    _(result).must_answer <<~'OUT'
      5
      4
      5
      4
      3.5
      4.25
      4
      c
      d
      3
      z
      3
      30
      2
      2.5
      2
      y
      2
      q
    OUT
  end

  it "a subscript takes a range, or a start and a length" do
    result = zr(<<~'RUBY')
      # Integer array slicing: a[range] and a[start, len].
      # Both forms give a new array, not a single element.

      a = [10, 20, 30, 40, 50]

      # Range form
      b = a[1..3]
      puts b.length      # 3
      puts b[0]          # 20
      puts b[1]          # 30
      puts b[2]          # 40

      # (start, len) form
      c = a[1, 2]
      puts c.length      # 2
      puts c[0]          # 20
      puts c[1]          # 30

      # Negative start (counts from end)
      d = a[-2, 2]
      puts d.length      # 2
      puts d[0]          # 40
      puts d[1]          # 50

      # len exceeds remaining: clamped
      f = a[2, 100]
      puts f.length      # 3
      puts f[0]          # 30
      puts f[2]          # 50

      # Range to last index
      g = a[2..4]
      puts g.length      # 3
      puts g[0]          # 30
      puts g[2]          # 50

      # Bare a[i] still works as scalar get
      puts a[0]          # 10
      puts a[-1]         # 50

      # The result is an Integer array too
      puts a[1..3].sum   # 90
    RUBY

    _(result).must_answer <<~'OUT'
      3
      20
      30
      40
      2
      20
      30
      2
      40
      50
      3
      30
      50
      3
      30
      50
      10
      50
      90
    OUT
  end

  it "replace swaps the contents and keeps the receiver" do
    result = zr(<<~'RUBY')
      # Array#replace copies another array into the receiver, in place.
      # String#replace does the same for a String.

      a = [1, 2, 3, 4, 5]
      a.replace([10, 20, 30])
      puts a.length    # 3
      puts a[0]        # 10
      puts a[2]        # 30

      # Replace into smaller -> larger triggers grow
      b = [1]
      b.replace([100, 200, 300, 400, 500, 600, 700, 800, 900])
      puts b.length    # 9
      puts b[8]        # 900

      # String array
      s = ["a", "b", "c"]
      s.replace(["x", "y"])
      puts s.length    # 2
      puts s[0]        # x
      puts s[1]        # y

      # Float array
      f = [1.0, 2.0, 3.0]
      f.replace([7.5, 8.5])
      puts f.length    # 2
      puts f[0]        # 7.5
      puts f[1]        # 8.5

      # Mutable string (existing path; <<-promoted)
      ms = ""
      ms << "hello"
      ms.replace("world")
      puts ms          # world
    RUBY

    _(result).must_answer <<~'OUT'
      3
      10
      30
      9
      900
      2
      x
      y
      2
      7.5
      8.5
      world
    OUT
  end

  it "reverse! reverses in place, for every element type" do
    result = zr(<<~'RUBY')
      # Array#reverse! on arrays of each element type.

      ints = [1, 2, 3, 4, 5]
      ints.reverse!
      ints.each { |i| puts i }   # 5 4 3 2 1

      floats = [1.5, 2.5, 3.5, 4.25]
      floats.reverse!
      floats.each { |f| puts f }  # 4.25 3.5 2.5 1.5

      strs = ["alpha", "beta", "gamma"]
      strs.reverse!
      strs.each { |s| puts s }    # gamma beta alpha

      syms = [:a, :b, :c, :d]
      syms.reverse!
      syms.each { |y| puts y }    # d c b a

      # Even-length and single-element edge cases
      even = [10, 20]
      even.reverse!
      even.each { |i| puts i }   # 20 10

      one = [42]
      one.reverse!
      one.each { |i| puts i }    # 42

      empty = []
      empty.reverse!
      puts empty.length          # 0
    RUBY

    _(result).must_answer <<~'OUT'
      5
      4
      3
      2
      1
      4.25
      3.5
      2.5
      1.5
      gamma
      beta
      alpha
      d
      c
      b
      a
      20
      10
      42
      0
    OUT
  end

  it "the set operators keep the receiver's element type" do
    result = zr(<<~'RUBY')
      # Array#&, Array#-, Array#| all dispatch to typed-array intersect /
      # difference / union helpers. Each operator's per-shape coverage
      # (int / str / float / sym / variable receiver / chained) is
      # parallel — one file per operator was duplicating the matrix.
      # Element semantics live in test/array_{intersection,difference,union}.rb;
      # this file only exercises the operator dispatch path.

      # &
      puts ([1, 2, 3, 4] & [3, 4, 5]).inspect
      puts (["a", "b", "c"] & ["b", "c"]).inspect
      puts ([1.0, 2.0, 3.0] & [2.0, 3.0]).inspect
      puts ([:a, :b, :c] & [:b, :c]).inspect
      amp = [1, 2, 3, 4]
      puts (amp & [3, 4, 5]).inspect
      puts ([1, 2, 3, 4] & [2, 3, 4] & [3, 4]).inspect

      # -
      puts ([1, 2, 3, 4] - [2, 4]).inspect
      puts (["a", "b", "c"] - ["b"]).inspect
      puts ([1.0, 2.0, 3.0] - [2.0]).inspect
      puts ([:a, :b, :c] - [:b]).inspect
      mns = [1, 2, 3, 4]
      puts (mns - [2, 4]).inspect
      puts ([1, 2, 3, 4, 5] - [2] - [4]).inspect

      # |
      puts ([1, 2, 3] | [3, 4, 5]).inspect
      puts (["a", "b"] | ["b", "c"]).inspect
      puts ([1.0, 2.0] | [2.0, 3.0]).inspect
      puts ([:a, :b] | [:b, :c]).inspect
      pip = [1, 2, 3]
      puts (pip | [3, 4]).inspect
      puts ([1, 2] | [2, 3] | [3, 4]).inspect
    RUBY

    _(result).must_answer <<~'OUT'
      [3, 4]
      ["b", "c"]
      [2.0, 3.0]
      [:b, :c]
      [3, 4]
      [3, 4]
      [1, 3]
      ["a", "c"]
      [1.0, 3.0]
      [:a, :c]
      [1, 3]
      [1, 3, 5]
      [1, 2, 3, 4, 5]
      ["a", "b", "c"]
      [1.0, 2.0, 3.0]
      [:a, :b, :c]
      [1, 2, 3, 4]
      [1, 2, 3, 4]
    OUT
  end

  it "<< appends one element and answers the receiver" do
    result = zr(<<~'RUBY')
      # `arr << x` is also an expression, not only a statement. It appends
      # and gives the receiver.
      #
      # In `(arr << x) << y`, the inner `<<` gives the receiver, and the
      # outer `<<` appends to it again.

      ints = [1]
      (ints << 2) << 3
      puts ints.length    # 3
      puts ints[0]        # 1
      puts ints[1]        # 2
      puts ints[2]        # 3

      floats = [1.5]
      (floats << 2.5) << 3.5
      puts floats.length  # 3
      puts floats[2]      # 3.5

      strs = ["a"]
      (strs << "b") << "c"
      puts strs.length    # 3
      puts strs[2]        # c

      syms = [:x]
      (syms << :y) << :z
      puts syms.length    # 3
      puts syms[2]        # z
    RUBY

    _(result).must_answer <<~'OUT'
      3
      1
      2
      3
      3
      3.5
      3
      c
      3
      z
    OUT
  end

  it "shuffle keeps the length of a symbol or mixed array" do
    result = zr(<<~'RUBY')
      # Array#shuffle keeps all the elements of a Symbol array and of a
      # mixed array.

      # Symbol array
      sa = [:a, :b, :c, :d].shuffle
      puts sa.length

      # Mixed array
      pa = [1, "a", :s, 2.0].shuffle
      puts pa.length
    RUBY

    _(result).must_answer "4\n4\n"
  end

  it "a three-argument []= replaces that many elements with the ones given" do
    result = zr(<<~'RUBY')
      # `arr[i, n] = src` (Array#[]= with three args) replaces n
      # elements of `arr` starting at index i with the elements of
      # `src`. Here n is always equal to `src.length`.
      #
      # The second argument is a length, not the value to store.

      a = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
      a[2, 8] = [10, 20, 30, 40, 50, 60, 70, 80]
      p a

      # Float array
      f = [0.0, 0.0, 0.0, 0.0]
      f[1, 2] = [3.5, 4.5]
      p f

      # String array
      s = ["", "", "", ""]
      s[0, 3] = ["a", "b", "c"]
      p s
    RUBY

    _(result).must_answer <<~'OUT'
      [0, 0, 10, 20, 30, 40, 50, 60, 70, 80]
      [0.0, 3.5, 4.5, 0.0]
      ["a", "b", "c", ""]
    OUT
  end

  it "sort! orders in place, for every element type" do
    result = zr(<<~'RUBY')
      # Array#sort! on arrays of each element type.

      ints = [3, 1, 4, 1, 5, 9, 2, 6]
      ints.sort!
      ints.each { |i| puts i }   # 1 1 2 3 4 5 6 9

      floats = [3.5, 1.25, 4.75, 1.5, 0.25]
      floats.sort!
      floats.each { |f| puts f }  # 0.25 1.25 1.5 3.5 4.75

      strs = ["banana", "apple", "cherry", "date"]
      strs.sort!
      strs.each { |s| puts s }    # apple banana cherry date

      syms = [:c, :a, :d, :b]
      syms.sort!
      syms.each { |y| puts y }    # a b c d

      # Single-element and empty edge cases
      one = [99]
      one.sort!
      one.each { |i| puts i }     # 99

      empty = []
      empty.sort!
      puts empty.length           # 0
    RUBY

    _(result).must_answer <<~'OUT'
      1
      1
      2
      3
      4
      5
      6
      9
      0.25
      1.25
      1.5
      3.5
      4.75
      apple
      banana
      cherry
      date
      a
      b
      c
      d
      99
      0
    OUT
  end

  it "a splat inside an array literal spreads the whole range or array" do
    result = zr(<<~'RUBY')
      # `[*0..n]` and `[*arr]` are array literals with a splat element.
      # The splat spreads all the values, not only the first one.
      # optcarrot builds its dummy palette this way.

      a = [*0..5]
      puts a.length
      puts a[0]
      puts a[3]
      puts a[5]

      b = [*0...4]
      puts b.length
      puts b[0]
      puts b[3]

      src = [10, 20, 30]
      c = [*src]
      puts c.length
      puts c[0]
      puts c[2]
    RUBY

    _(result).must_answer <<~'OUT'
      6
      0
      3
      5
      4
      0
      3
      3
      10
      30
    OUT
  end

  it "take_while and drop_while cut where the block first says no" do
    result = zr(<<~'RUBY')
      # Array#take_while and Array#drop_while on an Integer array.
      # take_while collects elements from the front while the block stays
      # truthy; drop_while skips them and returns the rest.

      # take_while
      puts [1, 2, 3, 1].take_while { |x| x < 3 }.inspect
      puts [1, 2, 3].take_while { |x| x < 10 }.inspect
      puts [5, 6, 7].take_while { |x| x < 0 }.inspect
      puts [].take_while { |x| x > 0 }.inspect

      # drop_while
      puts [1, 2, 3, 1].drop_while { |x| x < 3 }.inspect
      puts [1, 2, 3].drop_while { |x| x < 10 }.inspect
      puts [5, 6, 7].drop_while { |x| x < 0 }.inspect
      puts [].drop_while { |x| x > 0 }.inspect

      # take_while + drop_while round-trip preserves total count
      arr = [1, 2, 3, 4, 5, 1, 2]
      puts(arr.take_while { |x| x < 4 }.length + arr.drop_while { |x| x < 4 }.length)

      # A block with many statements runs all of them, not only the last.
      counter = 0
      [1, 2, 3, 4].take_while { |x| counter = counter + 1; x < 3 }
      puts counter

      # A Symbol array gives Symbol elements to the block.
      puts [:a, :b, :c, :d].take_while { |s| s != :c }.inspect
      puts [:a, :b, :c, :d].drop_while { |s| s != :c }.inspect
    RUBY

    _(result).must_answer <<~'OUT'
      [1, 2]
      [1, 2, 3]
      []
      []
      [3, 1]
      []
      [5, 6, 7]
      []
      7
      3
      [:a, :b]
      [:c, :d]
    OUT
  end

  it "tally counts each symbol's occurrences" do
    result = zr(<<~'RUBY')
      # Array#tally on a Symbol array maps each distinct element to its count.

      # Basic tally over symbol array
      puts [:a, :b, :a, :c, :a, :b].tally[:a]
      puts [:a, :b, :a, :c, :a, :b].tally[:b]
      puts [:a, :b, :a, :c, :a, :b].tally[:c]

      # Single element
      puts [:foo].tally[:foo]

      # All same
      puts [:x, :x, :x, :x].tally[:x]

      # Length of result
      puts [:a, :b, :a, :c, :a, :b].tally.length
      puts [:foo].tally.length
      puts [:x, :x, :x, :x].tally.length

      # has_key? confirms membership
      puts [:a, :b, :c].tally.has_key?(:a)
      puts [:a, :b, :c].tally.has_key?(:z)
    RUBY

    _(result).must_answer <<~'OUT'
      3
      2
      1
      1
      4
      3
      1
      1
      true
      false
    OUT
  end

  it "transpose turns rows into columns" do
    result = zr(<<~'RUBY')
      # transpose on nested Integer arrays.
      # The test reads each element, and does not use inspect.

      m = [[1, 2], [3, 4]]
      t = m.transpose
      puts t.length
      puts t[0][0]
      puts t[0][1]
      puts t[1][0]
      puts t[1][1]

      # 2x3 -> 3x2
      m2 = [[1, 2, 3], [4, 5, 6]]
      t2 = m2.transpose
      puts t2.length
      puts t2[0][0]
      puts t2[0][1]
      puts t2[1][0]
      puts t2[1][1]
      puts t2[2][0]
      puts t2[2][1]

      # 1x3 -> 3x1
      m3 = [[7, 8, 9]]
      t3 = m3.transpose
      puts t3.length
      puts t3[0][0]
      puts t3[1][0]
      puts t3[2][0]
    RUBY

    _(result).must_answer <<~'OUT'
      2
      1
      3
      2
      4
      3
      1
      4
      2
      5
      3
      6
      3
      7
      8
      9
    OUT
  end

  it "empty poly array reassignment" do
    result = zr(<<~'RUBY')
      items = [0, ""]
      items = []
      items.push(1)
      items.push("x")

      puts items.length
      puts items[0]
      puts items[1]
    RUBY

    _(result).must_answer <<~'OUT'
      2
      1
      x
    OUT
  end

  it "minmax answers the smallest and the largest at once" do
    result = zr(<<~'RUBY')
      p [3,1,4,1,5,9,2,6].minmax
      p [3,1,2].minmax
      # minmax on a Float array gives a pair of Floats, and inspect shows it.
      p [1.5, 0.5, 2.5].minmax
    RUBY

    _(result).must_answer <<~'OUT'
      [1, 9]
      [1, 3]
      [0.5, 2.5]
    OUT
  end

  it "dig walks a nested array by the indices it is given" do
    result = zr(<<~'RUBY')
      a = [10, 20, 30]
      # In-bounds — first / middle / last.
      p a.dig(0)
      p a.dig(1)
      p a.dig(2)
      # Negative indices — counts from the end.
      p a.dig(-1)
      p a.dig(-3)
      # This test does not check an out-of-bounds dig. Ruby gives nil there.
    RUBY

    _(result).must_answer <<~'OUT'
      10
      20
      30
      30
      10
    OUT
  end

  it "difference removes every element the argument holds" do
    result = zr(<<~'RUBY')
      # Array#difference for typed arrays (int/sym/str/float).
      # Mirrors Array#intersection (c31b618) and Array#union — keep only
      # elements of self NOT present in other (deduplicated).

      # Integer array
      puts [1, 2, 3, 4].difference([2, 4]).inspect
      puts [1, 2, 3].difference([4, 5]).inspect
      puts [1, 2, 3].difference([1, 2, 3]).inspect
      puts [].difference([1, 2]).inspect
      puts [1, 2].difference([]).inspect
      puts [1, 1, 2, 3].difference([1]).inspect
      puts [].difference([]).inspect

      # String array
      puts ["a", "b", "c"].difference(["b"]).inspect
      puts ["x", "y"].difference(["a"]).inspect
      puts ["a", "b"].difference(["a", "b"]).inspect
      puts ["a", "a", "b"].difference(["a"]).inspect

      # float_array
      puts [1.0, 2.0, 3.0].difference([2.0]).inspect
      puts [1.5, 2.5].difference([3.5]).inspect
      puts [1.0, 1.0, 2.0].difference([1.0]).inspect

      # Symbol array
      puts [:a, :b, :c].difference([:b]).inspect
      puts [:x, :y].difference([:a]).inspect
      puts [:a, :a, :b].difference([:a]).inspect
    RUBY

    _(result).must_answer <<~'OUT'
      [1, 3]
      [1, 2, 3]
      []
      []
      [1, 2]
      [2, 3]
      []
      ["a", "c"]
      ["x", "y"]
      []
      ["b"]
      [1.0, 3.0]
      [1.5, 2.5]
      [2.0]
      [:a, :c]
      [:x, :y]
      [:b]
    OUT
  end

  it "intersection keeps only the elements both arrays hold" do
    result = zr(<<~'RUBY')
      # Integer array
      a = [1, 2, 3, 4]
      b = [3, 4, 5, 6]
      puts a.intersection(b).inspect

      # no common elements -> empty
      puts [1, 2].intersection([3, 4]).inspect

      # all in common
      puts [1, 2, 3].intersection([1, 2, 3]).inspect

      # duplicates in self are deduplicated
      puts [1, 1, 2, 3].intersection([1, 2]).inspect

      # empty self -> empty
      puts [].intersection([1, 2, 3]).inspect

      # empty other -> empty
      puts [1, 2, 3].intersection([]).inspect

      # both empty
      puts [].intersection([]).inspect

      # single element match
      puts [42].intersection([42]).inspect

      # single element no match
      puts [42].intersection([99]).inspect

      # String array
      x = "a b c d".split(" ")
      y = "c d e f".split(" ")
      puts x.intersection(y).inspect

      # str no common -> empty
      puts "a b".split(" ").intersection("c d".split(" ")).inspect

      # str all common
      puts "x y".split(" ").intersection("x y".split(" ")).inspect

      # str empty self
      puts "".split(" ").intersection("a b".split(" ")).inspect

      # str duplicates in self are deduplicated
      puts "a a b c".split(" ").intersection("a b".split(" ")).inspect

      # str empty other -> empty
      puts "a b".split(" ").intersection("".split(" ")).inspect

      # float_array
      puts [1.0, 2.0, 3.0].intersection([2.0, 3.0, 4.0]).inspect

      # float no common -> empty
      puts [1.1, 2.2].intersection([3.3, 4.4]).inspect

      # float all common
      puts [1.5, 2.5].intersection([1.5, 2.5]).inspect

      # float duplicates in self are deduplicated
      puts [1.0, 1.0, 2.0].intersection([1.0]).inspect

      # float single no match -> empty
      puts [9.9].intersection([1.0, 2.0]).inspect

      # Symbol array
      puts [:a, :b, :c, :d].intersection([:c, :d, :e]).inspect

      # sym no common -> empty
      puts [:a, :b].intersection([:c, :d]).inspect

      # sym all common
      puts [:x, :y].intersection([:x, :y]).inspect

      # sym duplicates in self are deduplicated
      puts [:a, :a, :b].intersection([:a]).inspect
    RUBY

    _(result).must_answer <<~'OUT'
      [3, 4]
      []
      [1, 2, 3]
      [1, 2]
      []
      []
      []
      [42]
      []
      ["c", "d"]
      []
      ["x", "y"]
      []
      ["a", "b"]
      []
      [2.0, 3.0]
      []
      [1.5, 2.5]
      [1.0]
      []
      [:c, :d]
      []
      [:x, :y]
      [:a]
    OUT
  end

  it "union keeps each element once, in first-seen order" do
    result = zr(<<~'RUBY')
      # Array#union for typed arrays (int/sym/str/float).
      # Mirrors Array#intersection (c31b618). Returns a new array with all
      # unique elements from `self` followed by unique elements from `other`.

      # Integer array
      puts [1, 2, 3].union([3, 4, 5]).inspect
      puts [1, 2].union([3, 4]).inspect
      puts [1, 2, 3].union([1, 2, 3]).inspect
      puts [].union([1, 2]).inspect
      puts [1, 2].union([]).inspect
      puts [1, 1, 2].union([2, 3]).inspect
      puts [].union([]).inspect

      # String array
      puts ["a", "b"].union(["b", "c"]).inspect
      puts ["x"].union(["y", "z"]).inspect
      puts ["a", "b", "c"].union(["a", "b", "c"]).inspect
      puts ["a", "a", "b"].union(["b", "c"]).inspect

      # float_array
      puts [1.0, 2.0].union([2.0, 3.0]).inspect
      puts [1.5, 2.5].union([3.5]).inspect
      puts [1.0, 1.0, 2.0].union([2.0, 3.0]).inspect

      # Symbol array
      puts [:a, :b].union([:b, :c]).inspect
      puts [:x].union([:y, :z]).inspect
      puts [:a, :a, :b].union([:b, :c]).inspect
    RUBY

    _(result).must_answer <<~'OUT'
      [1, 2, 3, 4, 5]
      [1, 2, 3, 4]
      [1, 2, 3]
      [1, 2]
      [1, 2]
      [1, 2, 3]
      []
      ["a", "b", "c"]
      ["x", "y", "z"]
      ["a", "b", "c"]
      ["a", "b", "c"]
      [1.0, 2.0, 3.0]
      [1.5, 2.5, 3.5]
      [1.0, 2.0, 3.0]
      [:a, :b, :c]
      [:x, :y, :z]
      [:a, :b, :c]
    OUT
  end

  it "at is the subscript, append is push, and chomp! writes in place" do
    result = zr(<<~'RUBY')
      # Method aliases and forms:
      #   Array#at(n)      -> Array#[n]
      #   Array#append(x)  -> Array#push(x), returning self (the array)
      #   String#chomp!    -> changes a mutable String in place; raises
      #                       FrozenError on a frozen string literal.
      #                       The test uses a mutable String.

      p([1, 2, 3].at(1) == 2)
      p(%w[a].append("b") == %w[a b])
      s = String.new("ab\n")
      s.chomp!
      p(s.to_s == "ab")
    RUBY

    _(result).must_answer <<~'OUT'
      true
      true
      true
    OUT
  end

  it "an array of integers never equals an array of symbols" do
    result = zr(<<~'RUBY')
      # `[0,0,0] == %i[a a a]` must answer FALSE -- CRuby compares element
      # classes too, so the Integer 0 is not equal to the Symbol :a.
      # This is true even when a Symbol's internal id is 0.

      p [0, 0, 0] != %i[a a a]                 # true
      p [0, 0, 0] == %i[a a a]                 # false
      p %i[a a a] != [0, 0, 0]                 # true

      # Arrays of the same element type still compare by their elements.
      p [1, 2, 3] == [1, 2, 3]                 # true
      p %i[a b c] == %i[a b c]                 # true
      p %i[a b c] != %i[a b]                   # true (length differs)

      # An array that starts with Integers and then gets a Symbol by `<<`.
      # It is equal to a literal [:foo] with the same Symbol.
      a = [1]
      a.shift
      a << :foo
      p a == [:foo]                            # true
    RUBY

    _(result).must_answer <<~'OUT'
      true
      false
      true
      true
      true
      true
      true
    OUT
  end

  it "index answers nil when nothing matches" do
    result = zr(<<~'RUBY')
      # `Array#index(x)` / `#find_index(x)` / `#rindex(x)` return
      # Integer or nil in CRuby. They give nil when no element matches,
      # not -1. `.nil?` and `== nil` see that nil.

      # Int arrays
      ints = [10, 20, 30, 40]
      puts ints.index(20).inspect       # 1
      puts ints.index(999).inspect      # nil
      puts ints.index(999).nil?         # true
      puts ints.index(20).nil?          # false
      puts ints.find_index(30).inspect  # 2

      # String arrays
      strs = ["alpha", "beta", "gamma"]
      puts strs.index("beta").inspect   # 1
      puts strs.index("zeta").inspect   # nil
      puts strs.rindex("alpha").inspect # 0
      puts strs.rindex("zeta").inspect  # nil
    RUBY

    _(result).must_answer <<~'OUT'
      1
      nil
      true
      false
      2
      1
      nil
      0
      nil
    OUT
  end

  it "an array used as a Hash key matches another with the same contents" do
    result = zr(<<~'RUBY')
      # A Hash with Array keys. Each `[a, b]` literal makes a new Array, but
      # two Arrays with the same elements have the same hash and are eql?.
      # So a new `[a, b]` finds the entry, and `||=` does not add a second.

      entries = {}
      entries[[1, 2]] = "a"
      entries[[3, 4]] = "b"
      entries[[1, 2]] ||= "z"   # already set, no overwrite
      puts entries[[1, 2]]      # "a"
      puts entries[[3, 4]]      # "b"
      puts entries.length       # 2

      # Mixed keys also work: an Integer and an Array in one Hash.
      mixed = {}
      mixed[42] = "int-key"
      mixed[[5, 6, 7]] = "arr-key"
      mixed[[5, 6, 7]] ||= "no-overwrite"
      puts mixed[42]            # int-key
      puts mixed[[5, 6, 7]]     # arr-key
      puts mixed.length         # 2
    RUBY

    _(result).must_answer <<~'OUT'
      a
      b
      2
      int-key
      arr-key
      2
    OUT
  end

  it "an array of nils reads nil at every index" do
    result = zr(<<~'RUBY')
      # `[nil, nil, ...].first` and `.last` give nil, not 0.
      # So `.nil?` is true.
      p [nil].first.nil?               # true
      p [nil].last.nil?                # true
      p [nil, nil, nil].first.nil?     # true
      p [nil, nil, nil].last.nil?      # true
    RUBY

    _(result).must_answer <<~'OUT'
      true
      true
      true
      true
    OUT
  end

  it "Array.new with a count and no block fills with nil" do
    result = zr(<<~'RUBY')
      # `Array.new(n)` (single arg, no fill value, no block) is CRuby
      # shorthand for `Array.new(n, nil)`: an array of n nils, NOT an
      # empty array.
      puts Array.new(3).length         # 3
      puts Array.new(3).inspect        # [nil, nil, nil]
      puts Array.new(3)[0].nil?        # true
      puts Array.new(0).length         # 0
      puts Array.new(5).length         # 5
    RUBY

    _(result).must_answer <<~'OUT'
      3
      [nil, nil, nil]
      true
      0
      5
    OUT
  end

  it "Array.new fills with nil, and the slots compare equal" do
    result = zr(<<~'RUBY')
      # `Array.new(n, nil)` -- the fill value is the nil singleton, so
      # MRI fills each slot with `nil` and `.inspect` prints
      # "[nil, nil, ...]", not "[0, 0, 0]". `[i].nil?` is true for
      # each slot.

      ary = Array.new(3, nil)
      puts ary.inspect
      puts ary[0].nil?
      puts ary[1].nil?
      puts ary[2].nil?
      puts ary.length
    RUBY

    _(result).must_answer <<~'OUT'
      [nil, nil, nil]
      true
      true
      true
      3
    OUT
  end

  it "sum takes a seed that decides the answer's type" do
    result = zr(<<~'RUBY')
      # Array#sum starts from its init argument, with or without a block:
      #   [1,2,3].sum(10)             # => 16
      #   [].sum(7)                   # => 7
      #   [1,2,3].sum(10) { |x| x*2 } # => 22

      # Integer array, no block
      puts [1, 2, 3].sum(10)            # 16
      puts [1, 2, 3].sum                # 6   (no init)
      puts [].sum(7)                    # 7   (empty + init survives)
      puts [].sum                       # 0   (empty default still 0)
      puts [1, 2].sum(-5)               # -2  (negative init)

      # Integer array, with block
      puts [1, 2, 3].sum(10) { |x| x * 2 }   # 22
      puts [1, 2, 3].sum { |x| x * 2 }       # 12  (block, no init)
      puts [].sum(7) { |x| x * 2 }           # 7   (empty + init w/ block)

      # Float array, no block
      puts [1.5, 2.5].sum(0.5)          # 4.5
      puts [1.5, 2.5].sum               # 4.0 (no init)
      puts [1.5, 2.5].sum(1)            # 5.0 (Integer init becomes a Float sum)
      puts [1.5, 2.5].sum(-0.5)         # 3.5 (negative float init)

      # The init comes from an element of a mixed array, so its type is not
      # known before run time.
      poly_arr = [10, "x"]
      init_p = poly_arr[0]
      puts [1, 2].sum(init_p)           # 13 (Integer init)

      fpoly_arr = [1.5, "x"]
      finit_p = fpoly_arr[0]
      puts [1.0, 2.0].sum(finit_p)      # 4.5 (Float init)

      # An Integer init for a Float array converts to a Float value.
      # It does not reuse the Integer's bits as a Float.
      ipoly_for_float = [1, "x"][0]
      puts [1.0, 2.0].sum(ipoly_for_float)   # 4.0 (Integer init, Float array)

      # Float array, with block and Float init: the 0.5 seed and the Float
      # block results are not truncated. The block parameters have their
      # own names (`fx` / `fy`), not the `|x|` of the Integer blocks above.
      puts [1.5, 2.5].sum(0.5) { |fx| fx }      # 4.5
      puts [1.0, 2.0].sum { |fy| fy * 1.5 }     # 4.5

      puts "done"
    RUBY

    _(result).must_answer <<~'OUT'
      16
      6
      7
      0
      -2
      22
      12
      7
      4.5
      4.0
      5.0
      3.5
      13
      4.5
      4.0
      4.5
      4.5
      done
    OUT
  end

  it "group_by then each over an array of hashes reaches the grouped rows" do
    result = zr(<<~'RUBY')
      # Array#group_by, then Hash#each, on an array of Hashes with Symbol
      # keys. group_by gives a Hash from each block result to an array of
      # rows. In the each block, `rows.map`, `rows.sum` and `rows.size`
      # all work on that array.
      #
      # Float interpolation shows 4.0 as "4.0", as Float#to_s does.

      scores = [
        { shop: "ginza", score: 5 },
        { shop: "ginza", score: 4 },
        { shop: "shibuya", score: 3 },
        { shop: "shibuya", score: 5 }
      ]

      scores.group_by { _1[:shop] }.each do |shop, rows|
        avg = rows.map { _1[:score] }.sum.to_f / rows.size
        puts "#{shop}: #{avg}"
      end
    RUBY

    _(result).must_answer "ginza: 4.5\nshibuya: 4.0\n"
  end

  it "a symbol write through a subscripted element reaches the Hash it holds" do
    result = zr(<<~'RUBY')
      # Chained `[]=` and `[]op=` with a Symbol key, on an array element
      # that is a Hash: `arr[i][:k] = v` and `arr[i][:k] += v`.
      # The write changes the Hash in the array. The same is true for
      # `f[:k] += v` in an each block, where `f` is each element.

      # T1: direct `[]=` on an array of Hashes
      arr1 = [{x: 1}]
      arr1[0][:x] = 99
      puts arr1[0][:x].to_s

      # T2: compound `[]+=` on an array of Hashes
      arr2 = [{x: 1}]
      arr2[0][:x] += 100
      puts arr2[0][:x].to_s

      # T3: `each` block mutating each hash via `f[:k] += v`
      arr3 = []
      arr3 << {x: 1}
      arr3 << {x: 3}
      arr3.each { |f| f[:x] += 100 }
      puts arr3[0][:x].to_s
      puts arr3[1][:x].to_s

      # T4: `each_with_index` block doing direct `f[:k] = v`
      arr4 = [{x: 1}, {x: 3}]
      arr4.each_with_index { |f, i| f[:x] = i * 10 }
      puts arr4[0][:x].to_s
      puts arr4[1][:x].to_s
    RUBY

    _(result).must_answer <<~'OUT'
      99
      101
      101
      103
      0
      10
    OUT
  end

  it "the two arrays partition answers survive a collection" do
    result = zr(<<~'RUBY')
      # Array#partition (block form) gives an array that holds two arrays.
      # The GC keeps the two inner arrays alive while the outer one is
      # alive. After many collections, `parts[0].length` is still 3.

      arr = [1, 2, 3, 4, 5, 6]
      parts = arr.partition { |x| x.odd? }

      # Force many GCs by allocating lots of GC-managed objects.
      i = 0
      while i < 200000
        tmp = [1, 2, 3]
        tmp.push(i)
        i += 1
      end

      puts parts[0].length   # 3
      puts parts[1].length   # 3
      puts "done"
    RUBY

    _(result).must_answer <<~'OUT'
      3
      3
      done
    OUT
  end

  it "Array#+ concatenates arrays of different element types" do
    result = zr(<<~'RUBY')
      # Array#+ on arrays of different element types gives a mixed array.
      # Each element keeps its own type.

      a1 = [1, 2, 3]
      a2 = ["x", "y", "z"]
      a3 = a1 + a2
      puts a3.length
      puts a3[0]
      puts a3[3]
      puts "ok"

      # Float + Int round-trip
      b1 = [1.5, 2.5]
      b2 = [10, 20]
      b3 = b1 + b2
      puts b3.length
      puts b3[0]
      puts b3[2]
      puts "done"
    RUBY

    _(result).must_answer <<~'OUT'
      6
      1
      x
      ok
      4
      1.5
      10
      done
    OUT
  end

  it "push takes an element of a type the array did not hold" do
    result = zr(<<~'RUBY')
      # Array#<< with elements of different types on an array that starts
      # empty. The array holds all of them: the type of the first push does
      # not decide the type of the array.

      arr = []
      arr << 1
      arr << "string"
      arr << :symbol
      puts arr.length
      puts arr[0]
      puts arr[1]
      puts arr[2]
      puts "ok"
    RUBY

    _(result).must_answer <<~'OUT'
      3
      1
      string
      symbol
      ok
    OUT
  end

  it "int array each with index" do
    result = zr(<<~'RUBY')
      # Array#each_with_index on an Integer array. The block params `i` and
      # `j` shadow outer String locals of the same names. The outer locals
      # keep their values. The block does not read the params.

      i = "hi"
      j = "ho"
      puts i
      puts j
      foo = [10, 20, 30]
      n = 0
      foo.each_with_index { |i, j| n = n + 1 }
      puts n   # 3
    RUBY

    _(result).must_answer <<~'OUT'
      hi
      ho
      3
    OUT
  end

  it "int array each with object" do
    result = zr(<<~'RUBY')
      # Array#each_with_object on an Integer array. The block params `i` and
      # `acc` shadow outer String locals of the same names. `acc` takes the
      # Integer seed, and the outer `acc` keeps its String. The block does
      # not read the params.

      i = "hi"
      acc = "ho"
      puts i
      puts acc
      foo = [10, 20, 30]
      n = 0
      foo.each_with_object(0) { |i, acc| n = n + 1 }
      puts n   # 3
    RUBY

    _(result).must_answer <<~'OUT'
      hi
      ho
      3
    OUT
  end

  it "int array reduce" do
    result = zr(<<~'RUBY')
      # Array#inject and Array#reduce are aliases. The test calls both, so
      # a difference between them shows. The block param `i` shadows an
      # outer String local of the same name and does not change it.

      i = "hi"
      puts i

      foo = [1, 2, 3, 4, 5]
      sum_inject = foo.inject(0) { |acc, i| acc + i }
      puts sum_inject   # 15

      sum_reduce = foo.reduce(0) { |acc, i| acc + i }
      puts sum_reduce   # 15
    RUBY

    _(result).must_answer <<~'OUT'
      hi
      15
      15
    OUT
  end

  it "int array reject" do
    result = zr(<<~'RUBY')
      # Array#reject on an Integer array. The block param `i` shadows an outer
      # String local of the same name. The block does not read the param,
      # and gives a constant result.

      i = "hi"
      puts i
      foo = [10, 20, 30]
      none = foo.reject { |i| true }
      puts none.length  # 0
      all = foo.reject { |i| false }
      puts all.length   # 3
      puts all[0]       # 10
      puts all[1]       # 20
      puts all[2]       # 30
    RUBY

    _(result).must_answer <<~'OUT'
      hi
      0
      3
      10
      20
      30
    OUT
  end

  it "int array select" do
    result = zr(<<~'RUBY')
      # Array#select on an Integer array. The block param `i` shadows an outer
      # String local of the same name. The block does not read the param,
      # and gives a constant result.

      i = "hi"
      puts i
      foo = [10, 20, 30]
      all = foo.select { |i| true }
      puts all.length   # 3
      puts all[0]       # 10
      puts all[1]       # 20
      puts all[2]       # 30
      none = foo.select { |i| false }
      puts none.length  # 0
    RUBY

    _(result).must_answer <<~'OUT'
      hi
      3
      10
      20
      30
      0
    OUT
  end

  it "int array zip" do
    result = zr(<<~'RUBY')
      # Array#zip with a block on Integer arrays. The block params `a` and
      # `b` shadow outer String locals of the same names. The block only
      # counts, and does not read the params.

      a = "ha"
      b = "hb"
      puts a
      puts b
      foo = [1, 2, 3]
      bar = [10, 20, 30]
      n = 0
      foo.zip(bar) { |a, b| n = n + 1 }
      puts n   # 3
    RUBY

    _(result).must_answer <<~'OUT'
      ha
      hb
      3
    OUT
  end

  it "bsearch finds the first element the block accepts, or nil when none is" do
    result = zr(<<~'RUBY')
      # Array#bsearch (find-minimum mode) on a sorted typed array: returns the
      # first element for which the block is truthy, or nil when none is.
      p [1, 3, 5, 7, 9].bsearch { |x| x >= 5 }
      p [1, 3, 5, 7, 9].bsearch { |x| x >= 100 }
      p [1, 3, 5, 7, 9].bsearch { |x| x >= 1 }
      p [2, 4, 6, 8].bsearch { |x| x >= 7 }
      p ["a", "b", "c", "d"].bsearch { |s| s >= "c" }
      p ["a", "b", "c", "d"].bsearch { |s| s >= "z" }
    RUBY

    _(result).must_answer <<~'OUT'
      5
      nil
      1
      8
      "c"
      nil
    OUT
  end

  it "each_index yields every index" do
    result = zr(<<~'RUBY')
      # Array#each_index { |i| } yields each index (0..length-1). Works on
      # any typed array; only the index is bound, no element.
      [10, 20, 30].each_index { |i| puts i }
      puts "---"
      %w[a b c].each_index { |i| puts "idx #{i}" }
      puts "---"
      [].each_index { |i| puts "never" }
      puts "done"
    RUBY

    _(result).must_answer <<~'OUT'
      0
      1
      2
      ---
      idx 0
      idx 1
      idx 2
      ---
      done
    OUT
  end

  it "find_index answers the first index the block accepts, or nil" do
    result = zr(<<~'RUBY')
      # Enumerable#find_index with block returns the index
      # of the first element where the block is truthy, nil otherwise.
      puts [1, 2, 3, 2].find_index { |x| x > 2 }
      puts [1, 2, 3].find_index { |x| x > 10 }.inspect
    RUBY

    _(result).must_answer "2\nnil\n"
  end

  it "group_by buckets the elements by the block's value" do
    result = zr(<<~'RUBY')
      # Array#group_by — standalone (no fused .each) returns a hash
      # keyed by the block result with arrays of matching elements.
      # The keys keep their insertion order.
      puts [1,2,3,4,5,6].group_by { |x| x % 3 }.inspect
      puts ["apple","ant","bee","cat","cow"].group_by { |s| s[0] }.inspect
    RUBY

    _(result).must_answer <<~'OUT'
      {1 => [1, 4], 2 => [2, 5], 0 => [3, 6]}
      {"a" => ["apple", "ant"], "b" => ["bee"], "c" => ["cat", "cow"]}
    OUT
  end

  it "join calls to_s on each element of a mixed array" do
    result = zr(<<~'RUBY')
      # Array#join on a mixed-element (poly) array: each element is to_s'd and
      # joined with the separator. Each literal holds elements of more than
      # one type.
      puts [1, "x", :y].join(",")
      puts [1, "x", :y].join
      puts [10, "y"].join("-")
      puts "done"
    RUBY

    _(result).must_answer <<~'OUT'
      1,x,y
      1xy
      10-y
      done
    OUT
  end

  it "member? is include?" do
    result = zr(<<~'RUBY')
      # Enumerable#member? is the documented alias of #include?. It works
      # on Integer arrays and on String arrays.
      puts [1,2,3].member?(2)
      puts [1,2,3].member?(99)
      puts ["a","b"].member?("a")
      puts ["a","b"].member?("z")
    RUBY

    _(result).must_answer <<~'OUT'
      true
      false
      true
      false
    OUT
  end

  it "product pairs every element with every element of the other array" do
    result = zr(<<~'RUBY')
      # Array#product with a single array argument of a different element type
      # gives [recv_elem, arg_elem] pairs of mixed types. Two Integer arrays
      # give pairs of Integers.
      p [1, 2].product(["a", "b"])
      p [1, 2, 3].product(["x"])
      p ["a", "b"].product([1, 2])
      p [1, 2].product([3, 4])
      p [1.5, 2.5].product([1, 2])
    RUBY

    _(result).must_answer <<~'OUT'
      [[1, "a"], [1, "b"], [2, "a"], [2, "b"]]
      [[1, "x"], [2, "x"], [3, "x"]]
      [["a", 1], ["a", 2], ["b", 1], ["b", 2]]
      [[1, 3], [1, 4], [2, 3], [2, 4]]
      [[1.5, 1], [1.5, 2], [2.5, 1], [2.5, 2]]
    OUT
  end

  it "repeated_combination lists the combinations that may reuse an element" do
    result = zr(<<~'RUBY')
      # Array#repeated_combination(k) on an int array: k-element combinations
      # allowing repeats, materialised as an array of arrays via .to_a.
      p [1, 2].repeated_combination(2).to_a
      p [1, 2, 3].repeated_combination(2).to_a
      p [1, 2].repeated_combination(3).to_a
      p [1, 2, 3].repeated_combination(1).to_a
    RUBY

    _(result).must_answer <<~'OUT'
      [[1, 1], [1, 2], [2, 2]]
      [[1, 1], [1, 2], [1, 3], [2, 2], [2, 3], [3, 3]]
      [[1, 1, 1], [1, 1, 2], [1, 2, 2], [2, 2, 2]]
      [[1], [2], [3]]
    OUT
  end

  it "int array fetch" do
    result = zr(<<~'RUBY')
      a = [10, 20, 30]
      p a.fetch(0)
      p a.fetch(2)
      p a.fetch(5, 99)
      p a.fetch(1, 99)
      s = [:x, :y, :z]
      p s.fetch(1)
    RUBY

    _(result).must_answer <<~'OUT'
      10
      30
      99
      20
      :y
    OUT
  end

  it "int array one arg" do
    result = zr(<<~'RUBY')
      # Enumerable#one?(x) — true iff exactly one element equals x.
      # This is the argument form, with no block.
      puts [1,2,3].one?(2)
      puts [1,2,3].one?(99)
      puts [1,2,2].one?(2)
      puts [].one?(1)
      puts [5].one?(5)
    RUBY

    _(result).must_answer <<~'OUT'
      true
      false
      false
      false
      true
    OUT
  end

  it "int array reduce init sym" do
    result = zr(<<~'RUBY')
      # Enumerable#reduce(init, :op) — explicit init plus a symbol
      # operator. The test also checks the 1-arg Symbol form.
      puts [1,2,3,4].reduce(:+)
      puts [1,2,3,4].reduce(:*)
      puts [1,2,3,4].reduce(10, :+)
      puts [1,2,3,4].reduce(100, :*)
      puts [].reduce(7, :+)
    RUBY

    _(result).must_answer <<~'OUT'
      10
      24
      20
      2400
      7
    OUT
  end

  it "poly array zip" do
    result = zr(<<~'RUBY')
      # Array#zip on mixed arrays gives an array of mixed pairs.
      # inspect shows each element as its own type.
      puts [1, "a"].zip([2, "b"]).inspect

      # Three heterogeneous arrays
      puts [1, "a", :s].zip([2, "b", :t]).inspect
    RUBY

    _(result).must_answer <<~'OUT'
      [[1, 2], ["a", "b"]]
      [[1, 2], ["a", "b"], [:s, :t]]
    OUT
  end

  it "scan with a block collects the matches, and without one the captures" do
    result = zr(<<~'RUBY')
      r = []
      "a(b)c(d)".scan(/[()]/) { |t| r << t }
      p r
      p "a(b)".scan(/[()]/)
      p "x1y2".scan(/(\d)/)
      p "a[b]c".scan(/[\[\]]/)
    RUBY

    _(result).must_answer <<~'OUT'
      ["(", ")", "(", ")"]
      ["(", ")"]
      [["1"], ["2"]]
      ["[", "]"]
    OUT
  end

  it "a parameter defaulted to an empty array answers every Array method" do
    result = zr(<<~'RUBY')
      # A method returning a default-valued array parameter: the empty `[]` default
      # types the param (and the method's return) as a poly array, so the result
      # responds to Array methods.
      def make(n, acc = [])
        acc << n
        acc
      end
      p make(3).length
      p make(3)
      p make(4, [1, 2])
      def build(x, acc = [])
        acc.push(x * 2)
        acc
      end
      p build(5).first
    RUBY

    _(result).must_answer <<~'OUT'
      1
      [3]
      [1, 2, 4]
      10
    OUT
  end

  it "an array a method appended to takes elements of another type afterwards" do
    result = zr(<<~'RUBY')
      def m(order)
        order << :sym
      end
      a = []
      m(a)
      a << "str"
      p a

      def n(dst)
        dst << 1
      end
      b = []
      b << "x"
      n(b)
      p b
    RUBY

    _(result).must_answer <<~'OUT'
      [:sym, "str"]
      ["x", 1]
    OUT
  end

  it "a string written through a subscript is the object the caller holds" do
    result = zr(<<~'RUBY')
      def f(word)
        word[0] = "z"
        word
      end
      def poison(start)
        path = [start]
        f(path.last)
      end
      p f("hot".dup)

      def g(word)
        out = []
        word.chars.each_with_index { |_, i| c = word.dup; c[i] = "z"; out << c }
        out
      end
      def poison2(start) = g([start].last)
      p g("hot")
    RUBY

    _(result).must_answer <<~'OUT'
      "zot"
      ["zot", "hzt", "hoz"]
    OUT
  end

  it "a method that returns two arrays built side by side keeps them apart" do
    result = zr(<<~'RUBY')
      def crash
        numbers, strings = [], []
        numbers << 1
        strings << "one"
        [numbers, strings]
      end
      p crash
    RUBY

    _(result).must_answer "[[1], [\"one\"]]\n"
  end

  it "a closure that appends to a captured string appends to the one the caller holds" do
    result = zr(<<~'RUBY')
      # Shared-mutable strings captured by closures (P6): the handle rides a
      # typed-pointer cell, so capture+mutation and capture+rebinding both share.
      s = +"cap"
      t = s
      cb = -> { s << "!" }
      cb.call
      p t
      p s.equal?(t)

      u = "one"
      v = u
      rb = -> { u = +"two"; u << "!" }
      rb.call
      p u
      p v

      procs = []
      w = +"held"
      x = w
      procs << -> { w << "." }
      2.times { procs[0].call }
      p x

      plain = "p"
      pp2 = -> { plain + "x" }
      p pp2.call
      p plain
    RUBY

    _(result).must_answer <<~'OUT'
      "cap!"
      true
      "two!"
      "one"
      "held.."
      "px"
      "p"
    OUT
  end

  it "start_with? and end_with? take several candidates on a string read out of a chain" do
    result = zr(<<~'RUBY')
      # A multi-argument String#start_with? / #end_with? on a poly string (a String
      # element read out of an each_line -> each_with_object chain) must dispatch on
      # the string tag, ORing the candidates, not raise NoMethodError.
      p "ab\ncd\n".each_line.each_with_object([]) { |raw, acc| acc << raw.start_with?("a", "c") }
      p "ab\ncd\n".each_line.each_with_object([]) { |raw, acc| acc << raw.end_with?("b\n", "z") }
      p "ab\ncd\n".each_line.each_with_object([]) { |raw, acc| acc << raw.start_with?("a") }
    RUBY

    _(result).must_answer <<~'OUT'
      [true, true]
      [true, false]
      [true, false]
    OUT
  end

  it "sum, reduce and inject fold a column that transpose produced" do
    result = zr(<<~'RUBY')
      cols = [[1, 2], [3, 4]].transpose
      p cols[0].sum
      r1 = (cols[0].reduce(0) { |a, x| a + x } rescue $!.class); p r1
      p cols[1].inject { |a, x| a + x }
      p [[1,2],[3,4]].transpose[1].reduce(10) { |a, x| a + x }
    RUBY

    _(result).must_answer <<~'OUT'
      4
      4
      6
      16
    OUT
  end

  it "zip on an empty array answers empty, whatever it is zipped with" do
    result = zr(<<~'RUBY')
      p([].zip(["a"]))
      p([].zip([1]))
      p([].zip([1.5]))
      p([].zip([:a]))
      p([].zip([[1]]))
      p([].zip(["a"], [2]))
      a = []
      p a.zip(["x"])
      p [1, 2].zip(["a", "b"])
    RUBY

    _(result).must_answer <<~'OUT'
      []
      []
      []
      []
      []
      []
      []
      [[1, "a"], [2, "b"]]
    OUT
  end

  it "push, append, concat, unshift and prepend with no argument leave the array alone" do
    result = zr(<<~'RUBY')
      a001 = [1, 2]
      p a001.push
      p a001
      p a001.append
      p a001.concat
      p a001.unshift
      p a001.prepend
    RUBY

    _(result).must_answer <<~'OUT'
      [1, 2]
      [1, 2]
      [1, 2]
      [1, 2]
      [1, 2]
      [1, 2]
    OUT
  end
end
