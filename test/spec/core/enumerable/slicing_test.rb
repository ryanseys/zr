# frozen_string_literal: true

require "spec_helper"

describe "Enumerable: slicing" do
  it "container read max by element" do
    result = ze0(<<~'RUBY')
      # max_by / min_by on an Array reached through a container return the winning
      # element, typed like the one sort_by(...).first or find return -- not an
      # untyped value every later call rejects.
      S = Struct.new(:n) do
        def m = n * 2
      end
      g = { "k" => [S.new(1), S.new(3)] }
      p g["k"].max_by { |x| x.m }.n
      p g["k"].min_by { |x| x.m }.n
      p g["k"].max_by(&:m).n
      p g["k"].min_by(&:m).n
      buckets = [S.new(1), S.new(2), S.new(3), S.new(4)].group_by { |x| x.n % 2 }
      p buckets[0].max_by { |x| x.n }.n
      p buckets[1].min_by { |x| x.n }.n
      h = { "a" => [3, 1, 2] }
      p h["a"].max_by { |v| v }
      p h["a"].min_by { |v| v }
      p h["a"].max_by { |v| -v }
      e = { "e" => [] }
      p e["e"].max_by { |v| v }.nil?
    RUBY

    _(result).must_answer <<~'OUT'
      3
      1
      3
      1
      4
      1
      3
      1
      1
      true
    OUT
  end

  it "enumerable chunking and slicing" do
    result = ze0(<<~'RUBY')
      a = [1, 2, 4, 9, 10, 11, 12, 15]
      p a.slice_when { |i, j| i + 1 != j }.to_a
      p a.chunk_while { |i, j| i + 1 == j }.to_a
      p [1, 1, 2, 3, 3].chunk_while { |i, j| i == j }.to_a
      p [1, 2, 3, 4, 5].slice_before { |x| x.even? }.to_a
      p [1, 2, 3, 4, 5].slice_after { |x| x.even? }.to_a
      p [1, 2, 3, 4, 5].slice_before(3).to_a
      p [1, 2, 3, 4, 5].slice_after(3).to_a
      p ["a", "b1", "c"].slice_before(/\d/).to_a
    RUBY

    _(result).must_answer <<~'OUT'
      [[1, 2], [4], [9, 10, 11, 12], [15]]
      [[1, 2], [4], [9, 10, 11, 12], [15]]
      [[1, 1], [2], [3, 3]]
      [[1], [2, 3], [4, 5]]
      [[1, 2], [3, 4], [5]]
      [[1, 2], [3, 4, 5]]
      [[1, 2, 3], [4, 5]]
      [["a"], ["b1", "c"]]
    OUT
  end

  it "enumerable min and max take a count" do
    result = ze0(<<~'RUBY')
      p (1..10).min(3)
      p (1..10).max(3)
      p [5, 1, 4, 2].min(2)
      p [5, 1, 4, 2].max(2)
      p [1, 2].min(9)
      p [1, 2].min(0)
    RUBY

    _(result).must_answer <<~'OUT'
      [1, 2, 3]
      [10, 9, 8]
      [1, 2]
      [5, 4]
      [1, 2]
      []
    OUT
  end

  it "first resume args bind to the fiber blocks params" do
    _(ze0(<<~'RUBY')).must_answer "7\n"
      h = Fiber.new do |a, b|
        a + b
      end
      puts h.resume(3, 4)
    RUBY
  end

  it "lazy first no stage" do
    result = ze0(<<~'RUBY')
      # `first` needs no stage between it and the lazy source: `e.lazy.first(2)` is
      # as well defined as `e.lazy.map { }.first(2)`, but only the staged form was
      # recognized and the bare one answered nil.
      p([1, 2, 3].each.lazy.first(2))
      p([1, 2, 3].each.lazy.first)
      p([1, 2, 3].lazy.first(2))
      p([1, 2, 3].each.lazy.to_a)
      p([1, 2, 3].each.to_a)
      p((1..9).each.lazy.first(3))
      p([1, 2, 3].each.lazy.map { |x| x * 2 }.first(2))
      p((1..Float::INFINITY).lazy.first(3))
    RUBY

    _(result).must_answer <<~'OUT'
      [1, 2]
      1
      [1, 2]
      [1, 2, 3]
      [1, 2, 3]
      [1, 2, 3]
      [2, 4]
      [1, 2, 3]
    OUT
  end

  it "minmax by and the one pass methods walk each" do
    result = ze0(<<~'RUBY')
      p((1..4).minmax_by { -_1 })
      p(%w[a bb cc d].minmax_by(&:size))
      p([].minmax_by { _1 })
      p([5].minmax_by { _1 })
      p(%w[x y z].minmax_by { 0 })
      p(%w[p q r s t].minmax_by { |w| w == "q" || w == "s" ? 1 : 0 })
      p({foo: 0, bar: 1, baz: 2}.minmax_by { |k, v| -v })
      p([3, 1, 2].each.minmax_by { _1 })
      p((1..3).minmax_by.size)
      begin; [1, "a"].minmax_by { _1 }; rescue => e; p e.class, e.message; end
      p [1, 2, 3].inject(:+), (1..4).reduce(10) { _1 * _2 }, [[1, 2]].inject { break 9 }
      p (1..3).each_slice(2).to_a, (1..3).each_cons(5).to_a
      o = Object.new
      def o.each = (yield 1; yield 2)
      def o.size = 1
      o.extend(Enumerable)
      p o.each_cons(2).to_a
      p o.each_cons(2) { p :never }.equal?(o)
      p o.collect_concat { [_1, _1] }, o.collect { _1 * 3 }, o.min, o.max(1), o.zip([3]), o.uniq, o.entries
      p o.minmax_by { -_1 }, o.reverse_each.to_a, o.cycle.first(3)

    RUBY

    _(result).must_answer <<~'OUT'
      [4, 1]
      ["a", "bb"]
      [nil, nil]
      [5, 5]
      ["x", "x"]
      ["p", "q"]
      [[:baz, 2], [:foo, 0]]
      [1, 3]
      3
      ArgumentError
      "comparison of Integer with String failed"
      6
      240
      [1, 2]
      [[1, 2], [3]]
      []
      []
      true
      [1, 1, 2, 2]
      [3, 6]
      1
      [2]
      [[1, 3], [2, nil]]
      [1, 2]
      [1, 2]
      [2, 1]
      [2, 1]
      [1, 2, 1]
    OUT
  end

  it "sum adds floats with compensation" do
    result = ze0(<<~'RUBY')
      # Enumerable#sum adds exactly while it can and, from the first Float,
      # with Kahan-Babuska compensation, as Array#sum and CRuby's enum_sum do.
      def t = yield rescue [$!.class, $!.message]

      p t { {a: 0.1, b: 0.2, c: 0.3}.sum { _2 } }, t { [0.1, 0.2, 0.3].each.sum }, t { (1..3).sum { 0.1 } }
      p t { ([0.1] * 10).each.sum }, t { [1, 2, 0.1, 0.2, 0.3].each.sum }, t { [0.1, 1r, 0.2].each.sum }
      p t { [1r, 2r].each.sum }, t { [1, 2**70, 3].each.sum }, t { %w[a b].each.sum("") }, t { [[1], [2]].each.sum([]) }
      p t { [0.1, Float::INFINITY, 0.2].each.sum }, t { [Float::INFINITY, -Float::INFINITY].each.sum }, t { [0.1, Float::NAN].each.sum }
      p t { [1e100, 1.0, -1e100].each.sum }, t { [3, 0.1, 0.2, 0.3].each.sum(0.0) }, t { {x: 1}.sum }

    RUBY

    _(result).must_answer <<~'OUT'
      0.6
      0.6
      0.30000000000000004
      1.0
      3.6
      1.3
      (3/1)
      1180591620717411303428
      "ab"
      [1, 2]
      Infinity
      NaN
      NaN
      1.0
      3.6
      [TypeError, "Array can't be coerced into Integer"]
    OUT
  end

  it "user enumerable first boxed" do
    result = ze0(<<~'RUBY')
      class Nums
        include Enumerable
        def initialize(*xs); @xs = xs; end
        def each; @xs.each { |x| yield x }; end
      end

      p([Nums.new(1, 2), Nums.new(3, 4)].map { |n001| n001.first })

      [Nums.new(1, 2)].each { |n002| p n002.first }   # Ruby: 1   Spinel: nil

      arr = [Nums.new(1, 2), Nums.new(3, 4)]
      p(arr.map { |n003| n003.sum })         # => [3, 7]
      p(arr.map { |n004| n004.count })       # => [2, 2]
      p(arr.map { |n005| n005.max })         # => [2, 4]
      p(arr.map { |n006| n006.min })         # => [1, 3]
      p(arr.map { |n007| n007.include?(1) }) # => [true, false]
      p(arr.map { |n008| n008.sort })        # => [[1, 2], [3, 4]]
      def hd(n010); n010.first; end
      p(hd(Nums.new(1, 2)))                  # => 1
      p(Nums.new(1, 2).first)                # => 1
    RUBY

    _(result).must_answer <<~'OUT'
      [1, 3]
      1
      [3, 7]
      [2, 2]
      [2, 4]
      [1, 3]
      [true, false]
      [[1, 2], [3, 4]]
      1
      1
    OUT
  end
end
