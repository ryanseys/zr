# frozen_string_literal: true

require "spec_helper"

describe "Enumerable: blocks and yields" do
  it "an enumerable block can re enter its own driver" do
    result = ze0(<<~'RUBY')
      # The enumerable drivers accumulate into state the block can reach again: a
      # block that calls the SAME method on the SAME receiver runs a second driver
      # while the first is mid-element. Pinned because the accumulator moved from a
      # shared cell to one the driver owns, and a reentrant call must still get an
      # accumulator of its own.
      a = [1, 2, 3]
      double = proc { |x| x * 2 }
      nested = proc { |x| a.map(&double).sum + x }

      p a.map(&nested)
      p a.sum { |x| a.count { |y| y > x } }
      p a.count { |x| a.map(&double).include?(x * 2) }
      p a.map { |x| a.select { |y| y <= x }.length }

      # Three levels deep, and the receiver is mutated by an inner level.
      b = [1, 2]
      p b.map { |x| b.map { |y| b.count { |z| z >= y } * x }.sum }

      # Break out of the OUTER driver from inside a nested one.
      p(a.map { |x| x == 2 ? (break :stopped) : x })
      p(a.count { |x| x == 3 ? (break :halted) : true })
      p(a.sum { |x| x })

      # A non-Array Enumerable takes the sending path, not the own path.
      class Bag
        include Enumerable
        def initialize(*v) = @v = v
        def each(&b) = @v.each(&b)
      end
      bag = Bag.new(4, 5, 6)
      p bag.map { |x| bag.count { |y| y > x } }
      p bag.sum { |x| x * 2 }
      p bag.count { |x| x.odd? }
    RUBY

    _(result).must_answer <<~'OUT'
      [13, 14, 15]
      3
      3
      [1, 2, 3]
      [3, 6]
      :stopped
      :halted
      6
      [2, 1, 0]
      30
      1
    OUT
  end

  it "anonymous struct is enumerable and keeps its method block" do
    result = ze0(<<~'RUBY')
      # A native anonymous struct is Enumerable and honours a class-body method
      # block, exactly like the synthesized constant form.

      k = Struct.new(:a, :b, :c) do
        def sum
          to_a.sum
        end
      end
      o = k.new(1, 2, 3)
      p o.map { |v| v * 10 }
      p o.sum
      p o.select { |v| v.odd? }
    RUBY

    _(result).must_answer <<~'OUT'
      [10, 20, 30]
      6
      [1, 3]
    OUT
  end

  it "block autosplat minmax group" do
    result = ze0(<<~'RUBY')
      # min_by / max_by / minmax_by / group_by auto-splat a poly array's sub-array
      # elements across a 2+-param block, like map/sort_by. The winning element (or
      # grouped element) is the whole sub-array; a single param keeps it intact.
      # Receivers route through a method param so the runtime path runs. A poly helper
      # (sm) and an int-array helper (si) are kept separate: mixing the two element
      # kinds through one param would widen it to poly and bypass the typed path.
      def sm(x); x; end   # poly (nested) arrays
      def si(x); x; end   # int arrays

      # --- min_by / max_by over the second element ---
      p sm([["a", 3], ["b", 1]]).min_by { |k, v| v }         # ["b", 1]
      p sm([["a", 3], ["b", 1]]).max_by { |k, v| v }         # ["a", 3]
      p sm([[1, 9], [2, 1]]).min_by { |a, b| a + b }         # [2, 1]

      # --- minmax_by returns [min, max] elements ---
      p sm([[1, 5], [2, 1], [3, 9]]).minmax_by { |a, b| b }  # [[2, 1], [3, 9]]

      # --- group_by keys buckets by the block, storing whole elements ---
      p sm([[1, 2], [3, 4], [5, 2]]).group_by { |a, b| b }   # {2=>[[1,2],[5,2]], 4=>[[3,4]]}

      # --- 3 params ---
      p sm([[1, 2, 3], [4, 5, 6]]).max_by { |a, b, c| a + b + c }  # [4, 5, 6]

      # --- single param keeps the whole sub-array (no splat) ---
      p sm([[1, 9], [2, 1]]).min_by { |pair| pair[1] }       # [2, 1]

      # --- single-element receiver (loop binds once) ---
      p sm([[7, 2]]).min_by { |a, b| b }                     # [7, 2]

      # --- typed int array still works (no splat) ---
      p si([5, 1, 9, 3]).max_by { |x| x }                    # 9

      # --- numbered params auto-splat too ---
      p sm([[1, 2], [3, 4], [5, 0]]).min_by { _2 }           # [5, 0]
    RUBY

    _(result).must_answer <<~'OUT'
      ["b", 1]
      ["a", 3]
      [2, 1]
      [[2, 1], [3, 9]]
      {2 => [[1, 2], [5, 2]], 4 => [[3, 4]]}
      [4, 5, 6]
      [2, 1]
      [7, 2]
      9
      [5, 0]
    OUT
  end

  it "custom enumerable bare yield" do
    result = ze0(<<~'RUBY')
      class Nums
        include Enumerable
        def each
          yield 3
          yield 1
          yield 2
        end
      end
      n = Nums.new
      p n.to_a
      p n.sort
      p n.map { |x| x * 10 }
      p n.include?(2)
    RUBY

    _(result).must_answer <<~'OUT'
      [3, 1, 2]
      [1, 2, 3]
      [30, 10, 20]
      true
    OUT
  end

  it "enumerable find ifnone" do
    result = ze0(<<~'RUBY')
      class Nums
        include Enumerable
        def initialize(*xs); @xs = xs; end
        def each; @xs.each { |x| yield x }; end
      end
      p(Nums.new(1, 2, 3).find(-> { :none }) { |x| x > 9 })
      p(Nums.new(1, 2, 3).detect(-> { :none }) { |x| x > 9 })
      c007 = Nums.new(1, 2, 3).find(-> { :none }) { |x| x > 9 }
      p c007.class
      p(Nums.new(1, 2, 3).find(-> { :none }) { |x| x > 1 })
      p(Nums.new(1, 2, 3).find { |x| x > 1 })
      p([1, 2, 3].find(-> { :none }) { |x| x > 9 })
    RUBY

    _(result).must_answer <<~'OUT'
      :none
      :none
      Symbol
      2
      2
      :none
    OUT
  end

  it "enumerable multi value yield" do
    result = ze0(<<~'RUBY')
      # Imported from the spinel corpus at c55d9bdb.
      # `each` yielding more than one value per element. Enumerable packs them into
      # one array element, so `map`/`to_a`/`sort_by` see pairs.
      #
      # `for` does not: it is `obj.each { |targets| }` with the ordinary block
      # rules, so ONE target binds the first yielded value and drops the rest,
      # where several pack and destructure.
      class Pairs
        include Enumerable
        def each
          yield :a, 1
          yield :b, 2
        end
      end

      p(Pairs.new.map { |k, v| [k, v] })
      p(Pairs.new.map { |k, v| k })
      p(Pairs.new.to_a)
      p(Pairs.new.to_h)
      p(Pairs.new.sort_by { |k, v| -v })
      p(Pairs.new.select { |k, v| v > 1 })
      p(Pairs.new.first)
      p(Pairs.new.count)
      Pairs.new.each { |k, v| p [k, v] }

      # a single-value each keeps its flat elements
      class Ones
        include Enumerable
        def each
          yield 1
          yield 2
        end
      end

      p Ones.new.to_a
      p Ones.new.map { |x| x * 2 }
      p Ones.new.sum

      # `for` binds only as many values as it has index variables, so one variable
      # keeps the first of a multi-value yield rather than the packed element
      class OFor
        def each
          [[1, 2, 3], [4, 5, 6]].each { |a| yield(a[0], a[1], a[2]) }
        end
      end

      o = OFor.new
      qs = []
      for q in o
        qs << q
      end
      p qs
      p q

      rs = []
      for a, b in o
        rs << [a, b]
      end
      p rs

      ts = []
      for t in Ones.new
        ts << t
      end
      p ts

      # The rest of the target shapes take the FIRST yielded value too -- `for`
      # is `each` with the ordinary block rules, and one parameter is one parameter.
      class Two
        def each
          yield 1, 2
          yield 3, 4
        end
      end
      t = Two.new
      $g = nil
      for $g in t; end
      p $g
      class Box; attr_accessor :v; end
      bx = Box.new
      for bx.v in t; end
      p bx.v
      arr = [nil]
      for arr[0] in t; end
      p arr
      for (a, b) in t
        p [a, b]
      end
      for c, in t
        p c
      end

      # A yield of ONE array still auto-splats into several targets, and stays
      # whole under one.
      class Wrapped
        def each
          yield [7, 8]
        end
      end
      for w in Wrapped.new
        p w
      end
      for x, y in Wrapped.new
        p [x, y]
      end

      # A yield of NO values binds nil either way.
      class Empty
        def each
          yield
          yield
        end
      end
      es = []
      for e in Empty.new
        es << e
      end
      p es
    RUBY

    _(result).must_answer <<~'OUT'
      [[:a, 1], [:b, 2]]
      [:a, :b]
      [[:a, 1], [:b, 2]]
      {a: 1, b: 2}
      [[:b, 2], [:a, 1]]
      [[:b, 2]]
      [:a, 1]
      2
      [:a, 1]
      [:b, 2]
      [1, 2]
      [2, 4]
      3
      [1, 4]
      4
      [[1, 2], [4, 5]]
      [1, 2]
      3
      3
      [3]
      [1, 2]
      [3, 4]
      1
      3
      [7, 8]
      [7, 8]
      [nil, nil]
    OUT
  end

  it "enumerator block driving" do
    result = ze0(<<~'RUBY')
      # A materialized Enumerator (from a blockless each / reverse_each / each_char)
      # drives its block-taking Enumerable methods off its element array:
      # enum.map { } behaves as enum.to_a.map { }. Index-producing enumerators
      # (each_with_index / with_index) keep their own dedicated chain handling.

      nums = [1, 2, 3, 4, 5, 6]

      # --- value-producing Enumerable methods on an Array#each enumerator ---
      p nums.each.map { |x| x * 2 }
      p nums.each.select { |x| x.even? }
      p nums.each.reject { |x| x.even? }
      p nums.each.find { |x| x > 3 }
      p nums.each.flat_map { |x| [x, -x] }
      p nums.each.count { |x| x.even? }
      p nums.each.sort_by { |x| -x }
      p nums.each.group_by { |x| x % 3 }
      p nums.each.partition { |x| x < 3 }
      p nums.each.min_by { |x| (x - 3).abs }
      p nums.each.max_by { |x| (x - 3).abs }
      p nums.each.each_with_object([]) { |x, acc| acc << x * x }
      p nums.each.filter_map { |x| x * 10 if x.even? }
      p nums.each.all? { |x| x.positive? }
      p nums.each.any? { |x| x > 5 }
      p nums.each.none? { |x| x > 10 }
      p nums.each.take_while { |x| x < 4 }
      p nums.each.drop_while { |x| x < 4 }

      # --- String#each_char enumerator ---
      p "hello".each_char.map { |ch| ch.upcase }
      p "hello".each_char.select { |ch| "aeiou".include?(ch) }
      p "mississippi".each_char.group_by { |ch| ch }.transform_values(&:size)

      # --- reverse_each enumerator ---
      p [1, 2, 3].reverse_each.map { |x| x * 10 }

      # --- index-producing enumerators keep their dedicated chain handling ---
      p [10, 20, 30].each_with_index.map { |x, i| [i, x] }
      p [10, 20].each_with_index.to_a
      p %w[a b c].each.with_index(1).map { |ch, i| "#{i}:#{ch}" }

      # --- a blockless terminal still materializes directly (no delegation needed) ---
      p [1, 2, 3].each.to_a
      p [1, 2, 3].each.first(2)
    RUBY

    _(result).must_answer <<~'OUT'
      [2, 4, 6, 8, 10, 12]
      [2, 4, 6]
      [1, 3, 5]
      4
      [1, -1, 2, -2, 3, -3, 4, -4, 5, -5, 6, -6]
      3
      [6, 5, 4, 3, 2, 1]
      {1 => [1, 4], 2 => [2, 5], 0 => [3, 6]}
      [[1, 2], [3, 4, 5, 6]]
      3
      6
      [1, 4, 9, 16, 25, 36]
      [20, 40, 60]
      true
      true
      true
      [1, 2, 3]
      [4, 5, 6]
      ["H", "E", "L", "L", "O"]
      ["e", "o"]
      {"m" => 1, "i" => 4, "s" => 4, "p" => 2}
      [30, 20, 10]
      [[0, 10], [1, 20], [2, 30]]
      [[10, 0], [20, 1]]
      ["1:a", "2:b", "3:c"]
      [1, 2, 3]
      [1, 2]
    OUT
  end

  it "sum empty block body" do
    result = ze0(<<~'RUBY')
      # `sum {}` has no statements, so the fold that lowers a block sum found no tail
      # to type and refused the call, which then reached the run-time dispatch and
      # raised NoMethodError. An empty body answers nil for every element: an empty
      # receiver never runs it and keeps the 0 it starts from, and a non-empty one
      # raises on the first nil, as CRuby's "nil can't be coerced" does.
      a = []
      p a.sum {}
      p [].sum {}

      b = [1]
      begin
        p b.sum {}
      rescue => e
        p e.class
      end

      c = ["x"]
      begin
        p c.sum {}
      rescue => e
        p e.class
      end

      # a block that does answer something is unaffected
      p [1, 2].sum { |x| x }
      p [1.5, 2.5].sum { |x| x }
      p [1, 2].sum { 1 }
      p [].sum
      p [1, 2].sum(10) { |x| x }
    RUBY

    _(result).must_answer <<~'OUT'
      0
      0
      TypeError
      TypeError
      3
      4.0
      2
      0
      13
    OUT
  end

  it "zero arg resume binds nil block params" do
    _(ze0(<<~'RUBY')).must_answer "true\n"
      f = Fiber.new { |x| x.nil? }
      puts f.resume
    RUBY
  end
end
