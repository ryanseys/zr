# frozen_string_literal: true

require "spec_helper"

describe "Array: regressions" do
  it "unshift and prepend on an empty literal, reduce with a seed, and fetch_values with a fallback block" do
    result = ze0(<<~'RUBY')
      # Array conformance (KieranP #2364-#2368)
      p([].unshift(1))                              # #2364 empty-literal unshift
      p([].prepend(2, 3))
      a = []
      c = a.reduce(5, :+)                            # #2365 empty variable reduce(init, :sym)
      p c
      p([1, 2, 3].reduce(10, :+))
      p([nil, nil].all?(nil))                        # #2366 all? with a nil pattern
      p([nil, 1].all?(nil))
      p([1, nil].any?(nil))
      p([].rfind { |x| x > 0 })                      # #2367 rfind on an empty literal
      p([1, 2, 3].fetch_values(0, 5) { |i| i * 10 }) # #2368 fetch_values block fallback
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
    result = ze0(<<~'RUBY')
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
    result = ze0(<<~'RUBY')
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
    result = ze0(<<~'RUBY')
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

      # StrArray count
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
    result = ze0(<<~'RUBY')
      # Array#- / Array#difference must preserve LHS duplicates that
      # aren't in the RHS. CRuby semantics:
      #   [1, 1, 2, 3] - [3]  → [1, 1, 2]   (NOT [1, 2])
      #   [1, 1, 2, 3] - [1]  → [2, 3]      (every 1 removed)

      # int_array
      puts ([1, 1, 2, 3] - [3]).inspect
      puts ([1, 1, 2, 3] - [1]).inspect
      puts ([1, 1, 1, 2, 2] - [1]).inspect
      puts ([1, 2, 1, 3, 1] - [3]).inspect

      # str_array
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
    result = ze0(<<~'RUBY')
      # Array#fill: 1-arg, 2-arg, 3-arg forms.
      # Previously the 2-/3-arg forms silently ignored start/length and
      # filled the entire array.

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
      # CRuby fills the gap with nil; Spinel's IntArray can't hold nil so it
      # uses 0. The grown length and the explicit fill values are the same;
      # we only assert on those (skip e[3]/e[4] which differ in formatting).
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
    result = ze0(<<~'RUBY')
      # Test array literals as IntArray/StrArray

      # Integer array literal
      arr = [5, 3, 8, 1, 4]
      puts arr.length    # 5
      puts arr.size      # 5  (alias for length)
      puts arr[0]        # 5
      puts arr.sort[0]   # 1
      puts arr.sum       # 21
      puts arr.min       # 1
      puts arr.max       # 8

      # IntArray.size after mutation
      arr.push(99)
      puts arr.size      # 6  (length+1 after push)
      arr.pop
      puts arr.size      # 5  (length-1 after pop)

      # Symbol array literal -- size shares the same dispatch as IntArray
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
    result = ze0(<<~'RUBY')
      # `compile_array_literal`'s int-array fallback pushed elements
      # verbatim, including poly-typed ones. When a local was widened to
      # poly via cross-branch assignments and then wrapped in an `[x]`
      # literal, the generated C had `sp_IntArray_push(arr, <sp_RbVal
      # struct>)`, which gcc rejected with "incompatible type for
      # argument 2 of sp_IntArray_push". The fix unboxes the int payload
      # via `.v.i`. Caller code is responsible for keeping the poly slot
      # integer-tagged at the moment the literal is built.

      addr = 7
      flag = 0
      if flag > 0
        # Dead path at runtime — only here to widen `addr` to poly so
        # the array literal lands on the unboxing path.
        addr = "x"
      end

      # `addr` is poly at compile time (sp_RbVal) but always int=7 at
      # runtime. The `[addr]` literal infers as int_array (a single poly
      # element falls through to the IntArray branch).
      arr = [addr]
      puts arr.length          # 1
      puts arr[0]              # 7
    RUBY

    _(result).must_answer <<~'OUT'
      1
      7
    OUT
  end

  it "Array#* repeats the array, and times one is a copy the source cannot reach" do
    result = ze0(<<~'RUBY')
      # Array#* (repeat). Works uniformly across every typed array kind
      # is_array_type() recognises (int / float / str / sym / poly).

      # IntArray
      ints = [1, 2, 3] * 3
      puts ints.length      # 9
      puts ints[0]          # 1
      puts ints[3]          # 1
      puts ints[8]          # 3

      # IntArray * 0 → empty
      empty = [1, 2, 3] * 0
      puts empty.length     # 0

      # IntArray * 1 → copy (independent of source)
      arr = [1, 2]
      copy = arr * 1
      arr.push(99)
      puts copy.length      # 2

      # FloatArray
      floats = [1.5, 2.5] * 2
      puts floats.length    # 4
      puts floats[0]        # 1.5
      puts floats[3]        # 2.5

      # StrArray
      strs = ["a", "b"] * 3
      puts strs.length      # 6
      puts strs[0]          # a
      puts strs[5]          # b

      # SymArray
      syms = [:x, :y] * 2
      puts syms.length      # 4
      puts syms[0]          # x
      puts syms[3]          # y

      # PolyArray (mixed types)
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
    result = ze0(<<~'RUBY')
      # Array.new(N) { |i| ... }: block form with index parameter.
      # Previously returned an empty IntArray (the block was ignored).

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
    result = ze0(<<~'RUBY')
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
    result = ze0(<<~'RUBY')
      # Issue #169: p / inspect on nested arrays whose element type is one
      # of the four built-in T_array shapes (int/str/float/sym).

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
    result = ze0(<<~'RUBY')
      # Array#push across typed-array variants.
      # Previously push only dispatched for IntArray and StrArray; FloatArray
      # and SymArray (and PtrArray) silently fell through to a no-op expression.

      ints = [1, 2, 3]
      ints.push(4)
      ints.push(5)
      puts ints.length          # 5
      puts ints[3]              # 4
      puts ints[4]              # 5

      # Float values use non-integer fractional parts so Spinel's float-puts
      # (which strips a trailing ".0") matches CRuby's output.
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

      # << on every typed-array variant. Previously << did not dispatch
      # for sym_array, so `syms << :z` silently fell through.
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
    result = ze0(<<~'RUBY')
      # IntArray slicing: a[range] and a[start, len].
      # Previously a[1..2] failed with `incompatible type for argument 2 of
      # 'sp_IntArray_get'` (Range passed where mrb_int was expected), and
      # a[1, 2] silently dropped the second arg and returned a single int.

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

      # Result is usable as an IntArray
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
    result = ze0(<<~'RUBY')
      # Array#replace: mutating in-place copy from another array.
      # Previously a silent no-op for arrays; only String/MutableString worked.

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
    result = ze0(<<~'RUBY')
      # Array#reverse! across typed-array variants.
      # Previously only IntArray dispatched; SymArray, StrArray, FloatArray
      # silently fell through.

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
    result = ze0(<<~'RUBY')
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
    result = ze0(<<~'RUBY')
      # `arr << x` used in expression context (not a top-level statement)
      # fell through to a literal C `<<` (bit shift). The stmt-level path
      # already lowered `arr << x` to push for typed arrays; the operator/
      # expression form did not. gcc rejected the result with "invalid
      # operands to binary <<" on a pointer LHS.
      #
      # Chaining `(arr << x) << y` is the natural expression-context use
      # case: the inner `<<` returns the recv, which the outer `<<`
      # mutates again. Both the codegen path and `infer_call_type` need
      # to know the result is the recv's array type so the outer operand
      # type-checks.

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
    result = ze0(<<~'RUBY')
      # Array#shuffle / Array#shuffle! used to skip sym_array and poly_array.
      # For sym_array the dispatcher silently fell through (bin output empty);
      # for poly_array the runtime had no shuffle helper at all.

      # sym_array
      sa = [:a, :b, :c, :d].shuffle
      puts sa.length

      # poly_array
      pa = [1, "a", :s, 2.0].shuffle
      puts pa.length
    RUBY

    _(result).must_answer <<~'OUT'
      4
      4
    OUT
  end

  it "a three-argument []= replaces that many elements with the ones given" do
    result = ze0(<<~'RUBY')
      # `arr[i, n] = src` (Array#[]= with three args) replaces n
      # elements of `arr` starting at index i with the elements of
      # `src`. Same-length only — n must equal `src.length`; resize
      # semantics not supported.
      #
      # Without this, the codegen path for `[]=` only looked at args
      # 0 and 1, so `a[2, 8] = [10, 20, ...]` lowered to `a[2] = 8`,
      # silently treating the length argument as the value.

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
    result = ze0(<<~'RUBY')
      # Array#sort! across typed-array variants.
      # Previously only IntArray and SymArray dispatched; StrArray and
      # FloatArray silently fell through.

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
    result = ze0(<<~'RUBY')
      # `[*0..n]` and `[*arr]` are array literals with a SplatNode element.
      # Without SplatNode handling in compile_array_literal, the splat was
      # lowered to a single default value (e.g., just the range's lower
      # bound), so `[*0..4096]` produced a 1-element array. This broke
      # optcarrot's dummy palette and made every `palette[i]` for i > 0
      # read out-of-bounds garbage.

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
    result = ze0(<<~'RUBY')
      # Array#take_while and Array#drop_while for int_array (the common case).
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

      # Multi-stmt block — preceding statements must execute (regression for the
      # "only last expr is compiled" bug).
      counter = 0
      [1, 2, 3, 4].take_while { |x| counter = counter + 1; x < 3 }
      puts counter

      # sym_array path (regression for the bp-hardcoded-int bug).
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
    result = ze0(<<~'RUBY')
      # Array#tally for sym_array. str_array#tally already shipped — this
      # extends it to symbol arrays via a sp_SymArray_tally runtime helper
      # that produces a sym_int_hash mapping each unique element to its
      # occurrence count.

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
    result = ze0(<<~'RUBY')
      # Issue #156: transpose for nested int arrays.
      # Inspect of nested arrays still prints "#<Object>" (separate issue),
      # so each test reads element-wise to keep the comparison meaningful.

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
    result = ze0(<<~'RUBY')
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
    result = ze0(<<~'RUBY')
      p [3,1,4,1,5,9,2,6].minmax
      p [3,1,2].minmax
      # Float-array minmax returns tuple:float,float — exercises the
      # matching inspect arm.
      p [1.5, 0.5, 2.5].minmax
    RUBY

    _(result).must_answer <<~'OUT'
      [1, 9]
      [1, 3]
      [0.5, 2.5]
    OUT
  end

  it "dig walks a nested array by the indices it is given" do
    result = ze0(<<~'RUBY')
      a = [10, 20, 30]
      # In-bounds — first / middle / last.
      p a.dig(0)
      p a.dig(1)
      p a.dig(2)
      # Negative indices — counts from the end.
      p a.dig(-1)
      p a.dig(-3)
      # Out-of-bounds dig isn't covered here. Ruby returns nil; Spinel's
      # Array#[] inherits its existing in-bounds-only contract on int_array
      # (the single-arg dig delegates to []), so out-of-bounds reads behave
      # like out-of-bounds [] reads. Adding nil-returning bounds checks is
      # a separate scope (would widen the result type to poly).
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
    result = ze0(<<~'RUBY')
      # Array#difference for typed arrays (int/sym/str/float).
      # Mirrors Array#intersection (c31b618) and Array#union — keep only
      # elements of self NOT present in other (deduplicated).

      # int_array
      puts [1, 2, 3, 4].difference([2, 4]).inspect
      puts [1, 2, 3].difference([4, 5]).inspect
      puts [1, 2, 3].difference([1, 2, 3]).inspect
      puts [].difference([1, 2]).inspect
      puts [1, 2].difference([]).inspect
      puts [1, 1, 2, 3].difference([1]).inspect
      puts [].difference([]).inspect

      # str_array
      puts ["a", "b", "c"].difference(["b"]).inspect
      puts ["x", "y"].difference(["a"]).inspect
      puts ["a", "b"].difference(["a", "b"]).inspect
      puts ["a", "a", "b"].difference(["a"]).inspect

      # float_array
      puts [1.0, 2.0, 3.0].difference([2.0]).inspect
      puts [1.5, 2.5].difference([3.5]).inspect
      puts [1.0, 1.0, 2.0].difference([1.0]).inspect

      # sym_array
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
    result = ze0(<<~'RUBY')
      # int_array
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

      # str_array
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

      # sym_array
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
    result = ze0(<<~'RUBY')
      # Array#union for typed arrays (int/sym/str/float).
      # Mirrors Array#intersection (c31b618). Returns a new array with all
      # unique elements from `self` followed by unique elements from `other`.

      # int_array
      puts [1, 2, 3].union([3, 4, 5]).inspect
      puts [1, 2].union([3, 4]).inspect
      puts [1, 2, 3].union([1, 2, 3]).inspect
      puts [].union([1, 2]).inspect
      puts [1, 2].union([]).inspect
      puts [1, 1, 2].union([2, 3]).inspect
      puts [].union([]).inspect

      # str_array
      puts ["a", "b"].union(["b", "c"]).inspect
      puts ["x"].union(["y", "z"]).inspect
      puts ["a", "b", "c"].union(["a", "b", "c"]).inspect
      puts ["a", "a", "b"].union(["b", "c"]).inspect

      # float_array
      puts [1.0, 2.0].union([2.0, 3.0]).inspect
      puts [1.5, 2.5].union([3.5]).inspect
      puts [1.0, 1.0, 2.0].union([2.0, 3.0]).inspect

      # sym_array
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
    result = ze0(<<~'RUBY')
      # Method aliases / shapes from #619 puzzles 8 / 9 / 10:
      #   Array#at(n)      -> Array#[n]
      #   Array#append(x)  -> Array#push(x), returning self (the array)
      #   String#chomp!    -> mutates in place on mutable_str; raises
      #                       FrozenError on a frozen string literal
      #                       (#859 / #886). Test exercises the
      #                       mutable_str path.

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
    result = ze0(<<~'RUBY')
      # `[0,0,0] == %i[a a a]` must answer FALSE -- CRuby compares element
      # classes too, so int 0 != sym :a even when their encoded ids match.
      # Spinel's sym_array storage shares the sp_IntArray layout with
      # int_array (sym ids stored as raw mrb_int), and sp_IntArray_eq
      # compares raw bytes. With SPS_a == 0, both arrays' bytes are
      # [0,0,0] and the eq returned `true`, breaking `!=` to false.
      #
      # Fix: when the equality is between literal `[...]` and literal
      # `%i[...]` and the static types differ (int_array vs sym_array),
      # short-circuit to FALSE. The `<<`-widened "int_array carrying
      # syms at runtime" shape from issue #555 keeps both sides typed
      # `int_array` (the analyzer leaves the static type alone), so the
      # guard's "different static types" condition doesn't fire and
      # IntArray_eq continues to apply. Issue #600 puzzle 1.

      p [0, 0, 0] != %i[a a a]                 # true
      p [0, 0, 0] == %i[a a a]                 # false
      p %i[a a a] != [0, 0, 0]                 # true

      # Sibling shapes -- arrays of the same element-kind still compare
      # correctly via IntArray_eq.
      p [1, 2, 3] == [1, 2, 3]                 # true
      p %i[a b c] == %i[a b c]                 # true
      p %i[a b c] != %i[a b]                   # true (length differs)

      # Issue #555 test #6 shape: int_array with sym pushes at runtime.
      # Both sides resolve to lt == at == "int_array" statically, so the
      # new guard doesn't engage and IntArray_eq compares element ids
      # (which match for the :foo pushed and the :foo literal in [:foo]).
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
    result = ze0(<<~'RUBY')
      # `Array#index(x)` / `#find_index(x)` / `#rindex(x)` return
      # Integer | nil in CRuby (nil when not found). spinel previously
      # returned the raw -1 sentinel from `sp_*Array_index`, which
      # diverged from CRuby's nil for the not-found case.
      #
      # spinel positions itself as a Ruby SUBSET, so documented Ruby
      # APIs must match CRuby behavior. The fix: codegen now routes
      # Array#index family through `sp_*Array_index_poly` wrappers
      # that box nil for not-found / box int for found. The type
      # inference returns "poly" for the call result so `.nil?` /
      # `== nil` checks dispatch through the standard poly-tag path.
      #
      # The raw `_index` helpers (returning -1) stay for any internal
      # caller that needs the sentinel.

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
    result = ze0(<<~'RUBY')
      # Array-keyed Hash. `entries[[a, b]] ||= ...` was broken because
      # spinel's PolyPolyHash defaulted to pointer-identity comparison
      # for SP_TAG_OBJ keys — every fresh `[a, b]` literal allocated a
      # new IntArray, so identical-content keys never matched and the
      # `||=` never deduped. The cache grew unboundedly and reads with
      # a fresh `[a, b]` returned nil.
      #
      # Fix: extend the codegen-emitted sp_obj_hash_hook /
      # sp_obj_eql_hook to handle SP_BUILTIN_INT_ARRAY with element-wise
      # content hash + comparison. Two IntArray instances with the same
      # elements now hash and eql? identically — array-keyed Hash
      # behaves like CRuby's `Hash` with the [a,b]-style key idiom.

      entries = {}
      entries[[1, 2]] = "a"
      entries[[3, 4]] = "b"
      entries[[1, 2]] ||= "z"   # already set, no overwrite
      puts entries[[1, 2]]      # "a"
      puts entries[[3, 4]]      # "b"
      puts entries.length       # 2

      # Heterogeneous keys still work — int / IntArray / string mixed.
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
    result = ze0(<<~'RUBY')
      # `[nil, nil, ...].first` / `.last` returns nil. Pre-fix the
      # array-literal lowering pushed each NilNode as `sp_IntArray_push(_t, 0)`
      # (the int_array default) and `.first` returned int 0, so `.nil?`
      # folded to false. The peephole keeps the int_array layout for the
      # rest of the inference -- lifting all-nil literals to poly_array
      # breaks optcarrot's `[nil] * N` initialization -- but recognises
      # the `[nil, ...].first / .last` shape at the analyzer's CallNode
      # return-type site. Issue #619 puzzle 5.
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
    result = ze0(<<~'RUBY')
      # `Array.new(n)` (single arg, no fill value, no block) is CRuby
      # shorthand for `Array.new(n, nil)`: an array of n nils, NOT an
      # empty array. Pre-fix the single-arg lowering returned
      # `sp_IntArray_new()` (length 0) and downstream `.length` /
      # `.inspect` / `[i].nil?` saw the wrong shape. Issue #619 puzzle 4.
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
    result = ze0(<<~'RUBY')
      # `Array.new(n, nil)` -- the fill value is the nil singleton, so
      # MRI fills each slot with `nil` and `.inspect` prints
      # "[nil, nil, ...]". Spinel previously lowered the call to an
      # int_array filled with the C default (0), and inspect printed
      # "[0, 0, 0]". Lowering must produce a sp_PolyArray so the slot
      # can carry the nil tag and `.inspect` / `[i].nil?` / etc. see
      # the actual nil.

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
    result = ze0(<<~'RUBY')
      # Array#sum's init argument was silently dropped on the IntArray /
      # FloatArray dispatch paths -- spinel emitted sp_IntArray_sum(rc)
      # (no init parameter) and the block-form accumulator in
      # compile_array_sum_block was hardcoded to `mrb_int t = 0;`.
      # Pre-fix:
      #   [1,2,3].sum(10)             # => 6   (CRuby: 16)
      #   [].sum(7)                   # => 0   (CRuby: 7)
      #   [1,2,3].sum(10) { |x| x*2 } # => 12  (CRuby: 22)
      #
      # Fix: sp_IntArray_sum / sp_FloatArray_sum take an init parameter
      # and seed the accumulator with it; codegen forwards
      # compile_arg0(nid) at every sum dispatch. compile_array_sum_block
      # initialises tmp_sum from compile_arg0(nid).

      # IntArray, no block
      puts [1, 2, 3].sum(10)            # 16
      puts [1, 2, 3].sum                # 6   (no-init regression check)
      puts [].sum(7)                    # 7   (empty + init survives)
      puts [].sum                       # 0   (empty default still 0)
      puts [1, 2].sum(-5)               # -2  (negative init)

      # IntArray, with block
      puts [1, 2, 3].sum(10) { |x| x * 2 }   # 22
      puts [1, 2, 3].sum { |x| x * 2 }       # 12  (block, no init)
      puts [].sum(7) { |x| x * 2 }           # 7   (empty + init w/ block)

      # FloatArray, no block
      puts [1.5, 2.5].sum(0.5)          # 4.5
      puts [1.5, 2.5].sum               # 4.0 (no-init regression check)
      puts [1.5, 2.5].sum(1)            # 5.0 (int init implicitly widens)
      puts [1.5, 2.5].sum(-0.5)         # 3.5 (negative float init)

      # Poly init: a heterogeneous-array element resolves to a poly local.
      # compile_arg0_as_int / compile_arg0_as_float unbox via `.v.i` / `.v.f`;
      # without them gcc rejects passing sp_RbVal to mrb_int / mrb_float.
      poly_arr = [10, "x"]
      init_p = poly_arr[0]
      puts [1, 2].sum(init_p)           # 13 (poly init unboxed as mrb_int)

      fpoly_arr = [1.5, "x"]
      finit_p = fpoly_arr[0]
      puts [1.0, 2.0].sum(finit_p)      # 4.5 (poly init unboxed as mrb_float)

      # Tag-mixed: poly is INT-tagged but the FloatArray expects mrb_float.
      # sp_poly_to_f dispatches on the tag so the int value is coerced to
      # float rather than reinterpreted bit-for-bit from `.v.f`.
      ipoly_for_float = [1, "x"][0]
      puts [1.0, 2.0].sum(ipoly_for_float)   # 4.0 (poly INT->float via sp_poly_to_f)

      # FloatArray + block + float init: compile_array_sum_block now picks
      # an mrb_float accumulator and compile_arg0_as_float when recv_type is
      # float_array, so the 0.5 seed and the float block result are no
      # longer truncated. Use distinct block-param names (`fx` / `fy`) so
      # they don't get widened by the earlier int blocks' `|x|` -- spinel
      # hoists block params to a shared function-scope local, an orthogonal
      # limitation outside this PR's scope.
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
    result = ze0(<<~'RUBY')
      # Array#group_by + Hash#each chain on a poly_array of sym_poly_hashes.
      # spinel fuses `<arr>.group_by(blk).each |k, rows|` into a single emit
      # that builds a sp_PolyPolyHash keyed by the block's return value, with
      # each slot holding a sp_PolyArray of elements (boxed as poly). The
      # iteration loop then unboxes the slot back to a typed sp_PolyArray so
      # `rows.map { ... }` / `rows.sum` / `rows.size` reach the existing
      # poly_array dispatch arms.
      #
      # Two downstream gaps the fusion exposes get fixed in the same change:
      # `Array#size` was missing for poly_array (only `.length`), and
      # `Array#sum` on a poly_array now uses a runtime helper that sums the
      # int-tagged elements (the shape the .map produces for `_1[:int_key]`).
      # Float interpolation also routes through sp_float_to_s so 4.0 renders
      # as "4.0" (matching Ruby's Float#to_s) rather than "4" (printf %g).

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

    _(result).must_answer <<~'OUT'
      ginza: 4.5
      shibuya: 4.0
    OUT
  end

  it "a symbol write through a subscripted element reaches the Hash it holds" do
    result = ze0(<<~'RUBY')
      # Chained `[]=` / `[]op=` on a poly_array element that is a
      # boxed SymIntHash: `arr[i][:k] = v` and `arr[i][:k] += v`.
      #
      # Mirror of Issue #456 (chained_aset_on_poly_hash_recv.rb) for
      # the symbol-idx side. The string-idx arm was already present in
      # the poly-recv `[]=` dispatch, but the symbol-idx arm was
      # missing — the assignment fell through to the Array arms
      # (PolyArray / PtrArray / IntArray) whose cls_id never matched
      # SP_BUILTIN_SYM_INT_HASH, so the write silently no-op'd.
      #
      # Same gap existed for `compile_index_op_assign` (`[]op=`): when
      # recv was inferred as poly (e.g. `arr[i]` returning sp_RbVal),
      # no Hash-storage arm was emitted, so `arr[i][:k] += v` and the
      # each-block analog `f[:k] += v` (with `f` widened to poly)
      # silently dropped the modification.
      #
      # Fix: add a symbol-idx arm next to the string-idx arm in the
      # `[]=` dispatch (SymIntHash + SymPolyHash), and a poly-recv +
      # symbol-idx arm to `compile_index_op_assign` (SymIntHash;
      # SymPolyHash compound-assign needs poly-op semantics, deferred).

      # T1: direct `[]=` on poly_array of sym_int_hash
      arr1 = [{x: 1}]
      arr1[0][:x] = 99
      puts arr1[0][:x].to_s

      # T2: compound `[]+=` on poly_array of sym_int_hash
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
    result = ze0(<<~'RUBY')
      # Regression: Array#partition (block form) returns a tuple holding two
      # inner arrays. The tuple's sp_gc_alloc was emitted with scan=NULL, so
      # the inner arrays were swept while the tuple was still alive, and a
      # subsequent allocation reused the freed memory — `parts[0].length`
      # came back as the length of whatever object now sat there.

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
    result = ze0(<<~'RUBY')
      # Issue #662: Array#+ concatenating arrays of different element
      # types. Previously the codegen assumed both operands had the same
      # array prefix and used the lhs's *_get / *_length / *_push for
      # both -- failed C compilation with a pointer-type mismatch.
      #
      # Fix: infer_call_type returns "poly_array" when lhs is a typed
      # array and rhs is an array of a different element type. compile_+
      # detects the same shape and builds an sp_PolyArray, boxing each
      # source element via sp_box_* (sp_box_obj with cls_id for ptr).

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
    result = ze0(<<~'RUBY')
      # Issue #663: Array#<< with heterogeneous element types on an
      # initially-empty array. Previously the type inference latched
      # onto the first push's element type (transitioning int_array ->
      # str_array / float_array / sym_array) but didn't widen to
      # poly_array when a subsequent push had a different type. The
      # codegen then emitted e.g. sp_StrArray_push with an int literal
      # and failed C compilation.
      #
      # Fix: scan_locals's push/<< inference now widens to poly_array
      # when the slot is already a non-target concrete array type and
      # the next push is of a different family.

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
    result = ze0(<<~'RUBY')
      # Array#each_with_index on an int_array. The element block param must
      # shadow an outer same-named local of a different C type, and the
      # index block param must be block-local mrb_int (not leak the outer
      # `j`). Body skips reading the params to keep this scope-shadow case
      # separate from the format-specifier path.

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
    result = ze0(<<~'RUBY')
      # Array#each_with_object on an int_array. The element block param
      # must shadow an outer same-named local of a different C type, and
      # the accumulator block param must take the C type of the seed
      # (here mrb_int) — not leak the outer `acc` (string). Body avoids
      # reading the params to keep this scope-shadow case separate from
      # the separate type-inferer behavior when reading the param inside
      # the block.

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
    result = ze0(<<~'RUBY')
      # Array#inject and Array#reduce share compile_reduce_block but have
      # distinct dispatch entries. Cover both so a divergence at either
      # entry surfaces. The block param `i` must also shadow an outer
      # same-named local of a different C type without leaking back out.

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
    result = ze0(<<~'RUBY')
      # Array#reject on an int_array. The block param must shadow an outer
      # same-named local of a different C type. Body uses a constant
      # predicate so this isolates the shadow case from the separate
      # type-inferer behavior when reading the param inside the block.

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
    result = ze0(<<~'RUBY')
      # Array#select on an int_array. The block param must shadow an outer
      # same-named local of a different C type. Body uses a constant
      # predicate so this isolates the shadow case from the separate
      # type-inferer behavior when reading the param inside the block.

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
    result = ze0(<<~'RUBY')
      # Array#zip with a block on int_arrays. Both block params must shadow
      # outer same-named locals of a different C type. Body uses a counter
      # so this isolates the scope-shadow case from any param-read path.

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

  it "bsearch finds the first element the block accepts" do
    result = ze0(<<~'RUBY')
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
    result = ze0(<<~'RUBY')
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
    result = ze0(<<~'RUBY')
      # Issue #864: Enumerable#find_index with block returns the index
      # of the first element where the block is truthy, nil otherwise.
      # Pre-fix the block form wasn't dispatched (warn + emit 0).
      puts [1, 2, 3, 2].find_index { |x| x > 2 }
      puts [1, 2, 3].find_index { |x| x > 10 }.inspect
    RUBY

    _(result).must_answer <<~'OUT'
      2
      nil
    OUT
  end

  it "group_by buckets the elements by the block's value" do
    result = ze0(<<~'RUBY')
      # Array#group_by — standalone (no fused .each) returns a hash
      # keyed by the block result with arrays of matching elements.
      # Backed by poly_poly_hash + boxed poly_array values; key insertion
      # order is preserved.
      puts [1,2,3,4,5,6].group_by { |x| x % 3 }.inspect
      puts ["apple","ant","bee","cat","cow"].group_by { |s| s[0] }.inspect
    RUBY

    _(result).must_answer <<~'OUT'
      {1 => [1, 4], 2 => [2, 5], 0 => [3, 6]}
      {"a" => ["apple", "ant"], "b" => ["bee"], "c" => ["cat", "cow"]}
    OUT
  end

  it "join calls to_s on each element of a mixed array" do
    result = ze0(<<~'RUBY')
      # Array#join on a mixed-element (poly) array: each element is to_s'd and
      # joined with the separator. Homogeneous int_array/str_array have their
      # own join; these literals are heterogeneous so they use poly storage.
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
    result = ze0(<<~'RUBY')
      # Enumerable#member? is the documented alias of #include?. Both
      # need dispatching on typed arrays so the alias doesn't fall
      # through to the unresolved-call path.
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
    result = ze0(<<~'RUBY')
      # Array#product with a single array argument of a different element type
      # yields a poly_array of [recv_elem, arg_elem] pairs. Two int arrays keep
      # the homogeneous result.
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
    result = ze0(<<~'RUBY')
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
    result = ze0(<<~'RUBY')
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
    result = ze0(<<~'RUBY')
      # Enumerable#one?(x) — true iff exactly one element equals x.
      # The block form was already supported; the no-block / arg-form
      # fell through to unresolved-call.
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
    result = ze0(<<~'RUBY')
      # Enumerable#reduce(init, :op) — explicit init plus a symbol
      # operator. Single-arg sym form was already wired; the 2-arg form
      # (init + op-sym) fell through to unresolved-call.
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
    result = ze0(<<~'RUBY')
      # Array#zip on heterogeneous (poly_array) receivers — result is a
      # poly_array_ptr_array (array of poly_array pairs). The result type
      # was being misclassified as int_array_ptr_array, leaving inspect
      # walking raw sp_RbVal bytes as ints.
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
    result = ze0(<<~'RUBY')
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
    result = ze0(<<~'RUBY')
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
    result = ze0(<<~'RUBY')
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
    result = ze0(<<~'RUBY')
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
    result = ze0(<<~'RUBY')
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
    result = ze0(<<~'RUBY')
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
    result = ze0(<<~'RUBY')
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
    result = ze0(<<~'RUBY')
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
    result = ze0(<<~'RUBY')
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
    result = ze0(<<~'RUBY')
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
