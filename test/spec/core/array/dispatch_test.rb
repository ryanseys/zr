# frozen_string_literal: true

require "spec_helper"

describe "Array: dispatch" do
  it "clone of a nested array is a shallow copy, independent of the original at the top level" do
    result = zr(<<~'RUBY')
      # Array#clone aliases Array#dup for poly (nested) arrays: a shallow top-level
      # copy independent of the original. Covers a bare poly array and the clone of a
      # poly-array instance variable inside initialize_copy (the regressing shape).
      def via(x); x; end

      a = [[1], [2], [3]]
      b = via(a).clone
      b << [4]
      puts a.length        # 3 -- appending to the clone leaves the original alone
      puts b.length        # 4

      class Board
        def initialize; @table = [[1], [2]]; end
        def initialize_copy(orig); @table = @table.clone; end
        def push(row); @table.push(row); end
        def size; @table.length; end
      end

      orig = Board.new
      copy = orig.clone
      copy.push([9])
      puts orig.size       # 2 -- initialize_copy cloned @table, so the original is intact
      puts copy.size       # 3
    RUBY

    _(result).must_answer <<~'OUT'
      3
      4
      2
      3
    OUT
  end

  it "fill on a nested array boxes the value into the poly storage" do
    result = zr(<<~'RUBY')
      # `arr.fill(val)` on an array with mixed element types sets every
      # element to `val`.

      def make_arr
        arr = [1, "two", 3.14]   # heterogeneous elements
        arr.fill(42)
        arr
      end

      p make_arr   # [42, 42, 42]
    RUBY

    _(result).must_answer "[42, 42, 42]\n"
  end

  it "an empty container as an element makes the outer literal a poly array" do
    result = zr(<<~'RUBY')
      # An empty container literal as an array element is a non-scalar value: the
      # outer literal must become a poly array, not collapse to an int array that
      # stores the nested pointer as an integer.
      x = [[], 1, 2, 3]
      p x
      y = [{}, 5]
      p y.length
      p x[0] == []
    RUBY

    _(result).must_answer <<~'OUT'
      [[], 1, 2, 3]
      2
      true
    OUT
  end

  it "Array.new coerces a size that arrives as a poly expression" do
    result = zr(<<~'RUBY')
      # Array.new(size, fill) where the type of `size` is not known before run time.
      #
      # Mat#initialize's `ncols` gets an Integer from `Mat.new(2, 3)` and an untyped
      # ivar from `Mat.new(1, @d)`. The size `nrows * ncols` must still work as an
      # Integer.
      class Mat
        def initialize(nrows, ncols)
          @flat = Array.new(nrows * ncols, 0.0)
        end
        def len
          @flat.length
        end
      end

      # No code calls this method, but its call site passes an untyped ivar @d as
      # Mat#initialize's ncols. With Mat.new(2, 3) below, ncols gets two types of
      # argument.
      class Other
        def go
          Mat.new(1, @d)
        end
      end

      m = Mat.new(2, 3)
      puts m.len
    RUBY

    _(result).must_answer "6\n"
  end

  it "transpose swaps rows and columns of an untyped nested array, keeping each element's type" do
    result = zr(<<~'RUBY')
      # Array#transpose on an untyped nested array (an array of rows) swaps
      # rows and columns, preserving each element's runtime type. This
      # covers arrays built dynamically or returned from a method.

      ints = []
      ints.push([1, 2, 3])
      ints.push([4, 5, 6])
      p ints.transpose

      floats = []
      floats.push([1.0, 2.0])
      floats.push([3.0, 4.0])
      p floats.transpose

      strs = []
      strs.push(["a", "b"])
      strs.push(["c", "d"])
      p strs.transpose

      # transpose of a poly nested array returned from a method
      def grid
        g = []
        g.push([10, 20, 30])
        g.push([40, 50, 60])
        g
      end
      p grid.transpose

      # single row
      one = []
      one.push([7, 8, 9])
      p one.transpose
    RUBY

    _(result).must_answer <<~'OUT'
      [[1, 4], [2, 5], [3, 6]]
      [[1.0, 3.0], [2.0, 4.0]]
      [["a", "c"], ["b", "d"]]
      [[10, 40], [20, 50], [30, 60]]
      [[7], [8], [9]]
    OUT
  end

  it "empty array dispatch" do
    result = zr(<<~'RUBY')
      # Iterators called on an empty array literal receiver. The empty `[]` has no
      # element type, but it is still an Array.

      # The canonical case: `each` runs zero times and control continues.
      [].each { |x| print x }
      print "done\n"

      # Collection iterators over an empty literal produce the empty result without
      # ever running the block.
      p([].map { |x| x + 1 })
      p([].collect { |x| x * 2 })
      p([].select { |x| x > 0 })
      p([].filter { |x| x.even? })
      p([].reject { |x| x > 0 })
      p([].filter_map { |x| x if x > 0 })
      p([].flat_map { |x| [x, x] })
      p([].find { |x| x > 0 })
      p([].each_with_object([]) { |x, acc| acc << x })
      p([].group_by { |x| x })
      p([].sort_by { |x| -x })
      p([].min_by { |x| x })
      p([].max_by { |x| x })

      # Non-block / folded forms.
      p [].sum
      p [].min
      p [].first

      # The empty literal used as an assigned value gets its element type later.
      a = []
      a << 1
      a << 2
      p a
      p a.sum
    RUBY

    _(result).must_answer <<~'OUT'
      done
      []
      []
      []
      []
      []
      []
      []
      nil
      []
      {}
      []
      nil
      nil
      0
      nil
      nil
      [1, 2]
      3
    OUT
  end

  it "implicit alloc site holder poly array" do
    result = zr(<<~'RUBY')
      RowA = Struct.new(:id, :name)
      RowB = Struct.new(:id, :label)

      class Holder
        def initialize(record)
          @record = record
        end

        def record
          @record
        end
      end

      holders = []
      holders << Holder.new(RowA.new(1, "alpha"))
      holders << Holder.new(RowB.new(2, "beta"))

      first = holders[0]
      second = holders[1]

      puts first.record.name
      puts second.record.label
      puts first.record.id + second.record.id
    RUBY

    _(result).must_answer <<~'OUT'
      alpha
      beta
      3
    OUT
  end

  it "method dispatch poly array" do
    result = zr(<<~'RUBY')
      # An array can hold a `Method` object in one element and an
      # Integer array in another. `@arr[i][j]` then calls `[]` on the
      # element: a Method calls the method, and an Array indexes. A CPU
      # emulator dispatches memory reads in this shape, `@fetch[a][a]`.

      class C
        def peek(addr); 42; end
        def setup
          @arr = [nil] * 16
          range = [10, 20, 30, 40, 50, 60, 70, 80]
          @arr[5] = range            # IntArray
          @arr[10] = method(:peek)   # Method
        end
        def call_via(addr)
          (@arr[addr][addr & 0xff]).to_i
        end
      end

      c = C.new
      c.setup
      puts c.call_via(10)            # via Method peek_X → 42
      puts c.call_via(5)             # via IntArray range → range[5] = 60
    RUBY

    _(result).must_answer "42\n60\n"
  end

  it "nilable poly array" do
    result = zr(<<~'RUBY')
      # A method whose value is a mixed-element array or nil still gives an array, so
      # array methods work on the result.
      def gen(x)
        if x > 0
          [:begin, :a, :b]
        end          # implicit nil branch makes the return nilable
      end

      g = gen(5)
      p g                          # [:begin, :a, :b]
      p g.reject { _1 == :begin }  # [:a, :b]
      p g.map { |e| e.to_s }       # ["begin", "a", "b"]
      p g.join("-")                # "begin-a-b"
    RUBY

    _(result).must_answer <<~'OUT'
      [:begin, :a, :b]
      [:a, :b]
      ["begin", "a", "b"]
      "begin-a-b"
    OUT
  end

  it "poly array assoc" do
    result = zr(<<~'RUBY')
      # Array#assoc / #rassoc on a mixed array. Each element is itself a
      # sub-array; assoc(key) returns the sub-array whose first element
      # matches key, rassoc(val) matches against the second element.

      data = [[1, "one"], [2, "two"], [3, "three"]]
      puts data.assoc(2).inspect
      puts data.rassoc("three").inspect
      # Miss → nil.
      puts data.assoc(99).inspect
    RUBY

    _(result).must_answer <<~'OUT'
      [2, "two"]
      [3, "three"]
      nil
    OUT
  end

  it "poly array compact" do
    result = zr(<<~'RUBY')
      # `Array#compact` on an array with heterogeneous elements and
      # possible nils returns a new array with the nils removed.

      puts [1, nil, 2, nil, 3].compact.inspect

      # Heterogeneous (mix of int + string + nil) still works.
      a = [1, nil, "two", nil, :three, nil]
      puts a.compact.inspect

      # No-nil array passes through unchanged.
      puts [1, 2, 3].compact.inspect
    RUBY

    _(result).must_answer <<~'OUT'
      [1, 2, 3]
      [1, "two", :three]
      [1, 2, 3]
    OUT
  end

  it "poly array compact bang" do
    result = zr(<<~'RUBY')
      # Array#compact! on a mixed array removes the nils in place, and
      # returns the receiver. (It returns nil when nothing was removed,
      # and this example does not test that case.)
      a = [1, nil, 2, nil, 3]
      a.compact!
      puts a.inspect

      # Mixed types with nils interleaved
      b = ["a", nil, :sym, nil, 42]
      b.compact!
      puts b.inspect

      # Already nil-free
      c = [1, "two", :three]
      c.compact!
      puts c.inspect
    RUBY

    _(result).must_answer <<~'OUT'
      [1, 2, 3]
      ["a", :sym, 42]
      [1, "two", :three]
    OUT
  end

  it "poly array dup" do
    result = zr(<<~'RUBY')
      # `Array#dup` and a few sibling methods on an array with
      # mixed element types.
      #
      # Coverage:
      #   - dup: shallow copy preserves the element variant (length
      #     equal, types preserved).
      #   - to_a: alias for dup on Array.
      #   - empty?: edge case (zero-length array).
      #   - first / last: the named-method forms of `[0]` and `[-1]`.

      a = [1, "two", :three]
      b = a.dup
      puts b.length                  # 3

      # Element variants preserved across dup.
      c = a.to_a
      puts c.length                  # 3

      # empty? on a mixed array.
      empty = [1, "x"]
      puts empty.empty? ? "yes" : "no"   # no

      empty2 = [1, "x"]
      empty2.clear
      puts empty2.empty? ? "yes" : "no"  # yes

      # first / last on a mixed array.
      arr = [1, "two", :three]
      # Ruby's `first` on Array of mixed types returns the first elem.
      # This example does not print the values; it checks only that the
      # calls complete.
      arr.first
      arr.last
      puts "ok"                          # ok
    RUBY

    _(result).must_answer <<~'OUT'
      3
      3
      no
      yes
      ok
    OUT
  end

  it "poly array flatten" do
    result = zr(<<~'RUBY')
      # Array#flatten on a deep nested mixed array and on a uniform
      # array of Integer arrays (the `[[a,b],[c,d]]` form).

      # Deep recursive nesting: flatten goes into each nested array,
      # whatever its element type.
      puts [[1, [2, [3]]]].flatten.inspect

      # Heterogeneous mix of scalar + array elements.
      puts [1, "two", [3, [:four, 5.0]]].flatten.inspect

      # Uniform [[int...]] flattens to an array of Integers.
      puts [[1, 2], [3, 4], [5]].flatten.inspect

      # Empty array.
      puts [].flatten.inspect
    RUBY

    _(result).must_answer <<~'OUT'
      [1, 2, 3]
      [1, "two", 3, :four, 5.0]
      [1, 2, 3, 4, 5]
      []
    OUT
  end

  it "poly array index to h" do
    result = zr(<<~'RUBY')
      class Sector
        attr_reader :name

        def initialize(name)
          @name = name
        end
      end

      class Flat
        attr_reader :name

        def initialize(name)
          @name = name
        end
      end

      # --- index(value) on a poly array of objects (Doom: @map.sectors.index(sector)) ---
      a = Sector.new("a")
      b = Sector.new("b")
      c = Sector.new("c")
      sectors = [a, b, c]
      puts sectors.index(b)
      puts sectors.index(a)
      puts sectors.index(Sector.new("z")).inspect

      # --- index(value) on a mixed poly array of strings and ints ---
      mixed = [1, "two", 3, "four"]
      puts mixed.index("two")
      puts mixed.index(3)
      puts mixed.index("missing").inspect

      # --- index { |x| cond } on a poly array ---
      puts sectors.index { |s| s.name == "c" }
      puts sectors.index { |s| s.name == "nope" }.inspect
      puts mixed.index { |x| x == "four" }

      # --- to_h { |f| [f.name, f] } producing string keys (Doom: flats.to_h) ---
      flats = [Flat.new("floor"), Flat.new("ceil"), Flat.new("sky")]
      by_name = flats.to_h { |f| [f.name, f] }
      puts by_name.size
      puts by_name["floor"].name
      puts by_name["ceil"].name
      puts by_name["sky"].name

      # --- to_h with symbol keys over a poly array ---
      things = [1, "two"]
      sym_h = things.to_h { |t| [t.class.to_s.downcase.to_sym, t.to_s] }
      puts sym_h.size
      puts sym_h[:integer]
      puts sym_h[:string]
    RUBY

    _(result).must_answer <<~'OUT'
      1
      0
      nil
      1
      2
      nil
      2
      nil
      3
      3
      floor
      ceil
      sky
      2
      1
      two
    OUT
  end

  it "poly array intersect" do
    result = zr(<<~'RUBY')
      # Array#intersect? through a poly receiver.
      #
      # The typed-receiver forms all resolved, so only a union receiver was missing
      # an arm and the call raised NoMethodError naming Array -- which is what the
      # receiver was. Every array kind coerces to a poly array, so one arm serves
      # them all rather than one per element type.

      def pick(flag)
        flag ? [1, 2] : "no"
      end

      p [1, 2].intersect?([2, 3])
      p pick(true).intersect?([2, 3])
      p pick(true).intersect?([7, 8])
      p pick(true).intersect?([])

      def pick_s(flag)
        flag ? ["a", "b"] : 0
      end

      p pick_s(true).intersect?(["b", "c"])
      p pick_s(true).intersect?(["c"])

      def pick_f(flag)
        flag ? [1.5, 2.5] : nil
      end

      p pick_f(true).intersect?([2.5])
      p pick_f(true).intersect?([9.5])

      def pick_sym(flag)
        flag ? [:a, :b] : 0
      end

      p pick_sym(true).intersect?([:b])
      p pick_sym(true).intersect?([:z])

      # a mixed array, and a poly argument
      def pick_m(flag)
        flag ? [1, "a", :b] : 0
      end

      p pick_m(true).intersect?(["a"])
      p pick_m(true).intersect?([:b])
      p pick_m(true).intersect?([9])

      def other(flag)
        flag ? [2] : "x"
      end

      p pick(true).intersect?(other(true))

      # the shape it turned up in: a mapped receiver lands on the poly path
      CONST = ["t2", "t9"]
      rows = [["t1"], ["t2"]]
      p rows.map { |r| r[0] }.intersect?(CONST)
      p rows.map { |r| r[0] }.intersect?(["nope"])

      # an empty receiver
      def pick_e(flag)
        flag ? [1, 2].reject { |x| true } : "no"
      end

      p pick_e(true).intersect?([1])
    RUBY

    _(result).must_answer <<~'OUT'
      true
      true
      false
      false
      true
      false
      true
      false
      true
      false
      true
      true
      false
      true
      true
      false
      false
    OUT
  end

  it "poly array push with user push" do
    result = zr(<<~'RUBY')
      # A value that holds a builtin array must still append on push/<</append, even
      # when a user class defines push/<<. The user class's own push still runs for
      # its object receivers.
      class Stack
        def push(x)
          x
        end
      end

      def pick(flag)
        flag ? [1, 2] : ["a"]   # mixed element kinds -> poly array (poly receiver)
      end

      arr = pick(true)
      arr.push(99)
      arr << 100
      arr.append(101)
      puts arr.length
      puts arr.inspect

      puts Stack.new.push(7)    # the user push still works on its own object
    RUBY

    _(result).must_answer <<~'OUT'
      5
      [1, 2, 99, 100, 101]
      7
    OUT
  end

  it "poly array range aref" do
    result = zr(<<~'RUBY')
      # Range indexing on a poly (mixed-element) array: arr[a..b] / arr[a...b]
      # returns a subarray, like the typed-array receivers already did. Doom's WAD
      # reader slices its directory (a poly array of entries) between two markers:
      # `@directory[start_idx + 1...end_idx]`.
      arr = []
      arr << 1
      arr << "two"
      arr << :three
      arr << 4.5
      arr << [5]

      i = arr.index { |e| e == 1 }
      j = arr.index { |e| e == 4.5 }
      raise "missing marker" unless i && j

      p arr[i + 1...j]
      p arr[i..j]
      p arr[1..2]
      p arr[2..]
      p arr[1...1]
      p arr[-3..-2]
    RUBY

    _(result).must_answer <<~'OUT'
      ["two", :three]
      [1, "two", :three, 4.5]
      ["two", :three]
      [:three, 4.5, [5]]
      []
      [:three, 4.5]
    OUT
  end

  it "poly array readers" do
    result = zr(<<~'RUBY')
      # a stays a poly array (heterogeneous elements) through the method param.
      def probe(a)
        [a.reverse, a.uniq, a.first(2), a.last(2), a.first(0), a.last(10)]
      end

      r = probe(["x", 1, :y, "x", 2, 1])
      r.each { |x| p x }

      # edge: first/last beyond length, and negative -> ArgumentError
      def neg_first(a) = a.first(-1)
      begin
        neg_first([1, "a", :b])
      rescue ArgumentError => e
        puts "ArgumentError: #{e.message}"
      end
    RUBY

    _(result).must_answer <<~'OUT'
      [1, 2, "x", :y, 1, "x"]
      ["x", 1, :y, 2]
      ["x", 1]
      [2, 1]
      []
      ["x", 1, :y, "x", 2, 1]
      ArgumentError: negative array size
    OUT
  end

  it "poly array tally" do
    result = zr(<<~'RUBY')
      # Every argument is a genuinely heterogeneous (poly) array, so the parameter
      # stays a poly array and Array#tally dispatches through sp_PolyArray_tally.
      def tally_of(arr)
        arr.tally
      end

      p tally_of(["a", "b", "a", 1, 1, 1, :x, "a"])
      p tally_of([:red, "red", :red, 7, 7])
      p tally_of([true, false, true, nil, true, nil])

      counts = tally_of(["red", 1, "red", "red", 1, :red])
      puts counts["red"]
      puts counts[1]
      puts counts[:red]
      puts counts.length
    RUBY

    _(result).must_answer <<~'OUT'
      {"a" => 3, "b" => 1, 1 => 3, x: 1}
      {red: 2, "red" => 1, 7 => 2}
      {true => 3, false => 1, nil => 2}
      3
      2
      1
      3
    OUT
  end

  it "poly receiver sample" do
    result = zr(<<~'RUBY')
      # Array#sample on a receiver that is an array only at runtime, e.g. an object
      # field or hash value that holds an array. It must pick an element.
      N = Struct.new(:node, :follow)
      dic = { begin: N.new(:begin, []) }
      node = dic[:begin]
      node.follow << N.new(:a, [])
      node.follow << N.new(:b, [])

      s = node.follow.sample
      p s.nil?            # false
      p s.is_a?(N)        # true

      # a plain poly array receiver
      arr = [N.new(:x, []), N.new(:y, []), 100]
      p arr.sample.nil?   # false

      # empty poly value samples to nil
      empty = N.new(:e, [])
      p empty.follow.sample.nil?   # true
    RUBY

    _(result).must_answer <<~'OUT'
      false
      true
      false
      true
    OUT
  end

  it "poly recv dig splat" do
    result = zr(<<~'RUBY')
      # `dig(*keys)` on a receiver that can be a Hash or an Array: the key list only
      # exists at run time. Each step of the dig uses the class of the value at that
      # step.
      def lookup(config, keys)
        config.dig(*keys)
      end
      p lookup({ a: { b: 1 } }, [:a, :b])
      p lookup([[1, 2]], [0, 1])
      p lookup({ a: { b: 1 } }, [:a])
      p lookup([[1, 2]], [0])
      p lookup({ a: { b: 1 } }, [:missing])
      p lookup([[1, 2]], [9])

      # the block-parameter form, which reaches it through a different emitter
      box = [{ a: { b: 1 } }, [[1, 2]]]
      keys = [0, 1]
      box.each { |c| p c.dig(*keys) }

      # a positional key list over the same polymorphic receiver
      def lookup2(config, k1, k2)
        config.dig(k1, k2)
      end
      p lookup2({ a: { b: 5 } }, :a, :b)
      p lookup2([[7, 8]], 0, 1)

      # an Integer key on a symbol-keyed hash is a miss, not the symbol at that number
      h = { a: 1, b: 2 }
      p [h].map { |c| c.dig(0) }
      p [h].map { |c| c.dig(0, 1) }
      p [h].map { |c| c.dig(:a) }
    RUBY

    _(result).must_answer <<~'OUT'
      1
      2
      {b: 1}
      [1, 2]
      nil
      nil
      nil
      2
      5
      8
      [nil]
      [nil]
      [1]
    OUT
  end

  it "predicates on boxed array" do
    result = zr(<<~'RUBY')
      # all?/any?/none?/one? on an array bound from a destructured multi-value
      # return, then mapped. The blockless forms and the block form with an unused
      # parameter both work.
      def pass
        [[[0, "x"]], 2]
      end
      layout, size = pass
      r = layout.map { |a| a }
      p [r.all?, r.any?, r.none?, r.one?]
      p r.all? { |x| true }
      p r.any? { |x| x.size > 1 }
      s = layout.select { |a| true }
      p s.all?
      e = layout.each_with_index.map { |a, i| a }
      p e.all?
      n = [nil, false].map { |x| x }
      p [n.all?, n.any?, n.none?, n.one?]
      m = [nil, 1].map { |x| x }
      p [m.all?, m.any?, m.none?, m.one?]
      p size
    RUBY

    _(result).must_answer <<~'OUT'
      [true, true, false, true]
      true
      true
      true
      true
      [false, false, true, false]
      [false, true, false, true]
      2
    OUT
  end

  it "sized poly array nil n" do
    result = zr(<<~'RUBY')
      # `@arr = [nil] * N` makes an array of nils. The ivar also gets a
      # String and an Integer in other methods. Later writes of a
      # String, an Integer and a Symbol into the array keep each value
      # and its class.

      class C
        def init_arr_widen
          @arr = [nil] * 8
          @arr[0] = "string-payload"
          @arr[1] = 42
          @arr[2] = :sym
        end
        def init_str
          @arr = "scalar"
        end
        def init_int
          @arr = 7
        end
        def at(i)
          @arr[i]
        end
      end

      c = C.new
      c.init_arr_widen
      puts c.at(0).to_s   # "string-payload"
      puts c.at(1).to_i   # 42
      puts c.at(2).to_s   # "sym"
    RUBY

    _(result).must_answer <<~'OUT'
      string-payload
      42
      sym
    OUT
  end

  it "splat poly in array literal" do
    result = zr(<<~'RUBY')
      # Splatting a poly value into an array literal: whether it holds an array is
      # only known at runtime. An array is spliced one level, nil contributes nothing,
      # and any other scalar is inserted as-is (CRuby splat semantics). The receiver
      # `x` is a genuinely poly method parameter (called with arrays and scalars).
      def g(x)
        [:a, *x, :b]
      end

      p g([1, 2])        # [:a, 1, 2, :b]
      p g(nil)           # [:a, :b]
      p g(7)             # [:a, 7, :b]
      p g([])            # [:a, :b]
      p g(["s", :y])     # [:a, "s", :y, :b]
      p g(%i[foo bar])   # [:a, :foo, :bar, :b]  (poly holding a SymArray)

      # poly obtained via multiple assignment (a[0] is a poly array element)
      a = [[:x, :y], 5]
      pat, pr = a
      p [:begin, *pat, pr]   # [:begin, :x, :y, 5]
    RUBY

    _(result).must_answer <<~'OUT'
      [:a, 1, 2, :b]
      [:a, :b]
      [:a, 7, :b]
      [:a, :b]
      [:a, "s", :y, :b]
      [:a, :foo, :bar, :b]
      [:begin, :x, :y, 5]
    OUT
  end
end
