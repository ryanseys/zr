# frozen_string_literal: true

require "spec_helper"

describe "Enumerable: splitting and joining" do
  it "chunk family enumerator value" do
    result = ze0(<<~'RUBY')
      # chunk_while / slice_when / chunk with a block, standing on their own
      # (stored in a local, passed to p) rather than chained into .to_a: a
      # first-class Enumerator over the eagerly materialized runs, inspecting as
      # the Generator wrapper CRuby shows (address normalized below). Custom
      # Enumerable classes (redirected through __enum_to_a) and typed int/str
      # array receivers are all served; .to_a terminal chains keep their arms.
      class Nums
        include Enumerable
        def initialize(*xs); @xs = xs; end
        def each; @xs.each { |x| yield x }; end
      end
      norm = ->(s) { s.sub(/0x[0-9a-f]+/, "0xADDR") }
      e = Nums.new(1, 2, 4, 5).chunk_while { |a, b| b - a == 1 }
      puts norm.call(e.inspect)
      p e.to_a
      s = [1, 2, 4, 5].slice_when { |a, b| b - a > 1 }
      puts norm.call(s.inspect)
      p s.to_a
      i = [3, 4, 7].chunk_while { |a, b| b == a + 1 }
      puts norm.call(i.inspect)
      p i.to_a
      w = %w[aa ab ba].chunk_while { |a, b| a[0] == b[0] }
      p w.to_a
      p([1, 2, 4, 5].chunk_while { |a, b| b - a == 1 }.to_a)
    RUBY

    _(result).must_answer <<~'OUT'
      #<Enumerator: #<Enumerator::Generator:0xADDR>:each>
      [[1, 2], [4, 5]]
      #<Enumerator: #<Enumerator::Generator:0xADDR>:each>
      [[1, 2], [4, 5]]
      #<Enumerator: #<Enumerator::Generator:0xADDR>:each>
      [[3, 4], [7]]
      [["aa", "ab"], ["ba"]]
      [[1, 2], [4, 5]]
    OUT
  end

  it "chunk first class" do
    result = ze0(<<~'RUBY')
      # int_array.chunk { |x| key }.to_a returns a first-class array of [key, [members]]
      # pairs (consecutive equal keys grouped), so p/indexing/iteration work.
      p [1, 1, 2, 3, 3].chunk { |x| x }.to_a
      p [1, 2, 3, 4].chunk { |x| x.even? ? 1 : 0 }.to_a
      p [1, 1, 1].chunk { |x| x }.to_a
      p [5].chunk { |x| x }.to_a
      # the result is a real array: destructure pairs and chain
      p [1, 1, 2, 2, 2, 3].chunk { |x| x }.to_a.map { |k, grp| [k, grp.sum] }
      p [1, 1, 2, 3, 3].chunk { |x| x }.to_a.length
      # the existing inspect form still works
      p [1, 1, 2].chunk { |x| x }.to_a.inspect
    RUBY

    _(result).must_answer <<~'OUT'
      [[1, [1, 1]], [2, [2]], [3, [3, 3]]]
      [[0, [1]], [1, [2]], [0, [3]], [1, [4]]]
      [[1, [1, 1, 1]]]
      [[5, [5]]]
      [[1, 2], [2, 6], [3, 3]]
      3
      "[[1, [1, 1]], [2, [2]]]"
    OUT
  end

  it "chunk while" do
    result = ze0(<<~'RUBY')
      # Array#chunk_while { |a, b| } .to_a groups adjacent elements into runs: a and b
      # stay in the same run while the block is true, and a boundary falls where it is
      # false. Materialized as a first-class array of runs (poly array of int arrays),
      # so p / length / indexing work. Route the receiver through a method param.
      def ia(x) = x

      n = ia([1, 2, 4, 5, 7])
      p n.chunk_while { |a, b| b - a == 1 }.to_a        # [[1, 2], [4, 5], [7]]
      p n.chunk_while { |a, b| b - a == 1 }.to_a.length # 3

      # all-together and all-split boundaries
      p ia([1, 2, 3, 4]).chunk_while { |a, b| b - a == 1 }.to_a   # [[1, 2, 3, 4]]
      p ia([1, 3, 5]).chunk_while { |a, b| b == a + 1 }.to_a      # [[1], [3], [5]]
      p ia([42]).chunk_while { |a, b| true }.to_a                 # [[42]]

      # a non-difference predicate, plus indexing into the runs
      runs = ia([1, 2, 3, 1, 2]).chunk_while { |a, b| a <= b }.to_a
      p runs        # [[1, 2, 3], [1, 2]]
      p runs[0]     # [1, 2, 3]
      p runs[1]     # [1, 2]

      p ia([5, 5, 6, 7, 3]).chunk_while { |a, b| b >= a }.to_a    # [[5, 5, 6, 7], [3]]
    RUBY

    _(result).must_answer <<~'OUT'
      [[1, 2], [4, 5], [7]]
      3
      [[1, 2, 3, 4]]
      [[1], [3], [5]]
      [[42]]
      [[1, 2, 3], [1, 2]]
      [1, 2, 3]
      [1, 2]
      [[5, 5, 6, 7], [3]]
    OUT
  end

  it "chunk while without block" do
    result = ze0(<<~'RUBY')
      begin
        [1, 2, 3].chunk_while
      rescue ArgumentError => e
        p e.class
      end
      begin
        [1, 2, 3].slice_when
      rescue ArgumentError => e
        p e.class
      end
    RUBY

    _(result).must_answer "ArgumentError\nArgumentError\n"
  end

  it "sort_by, min_by, group_by, partition, flat_map and filter_map all match the oracle" do
    result = ze0(<<~'RUBY')
      p [3, 1, 2].sort_by { |x| -x }
      p [1, 2, 3, 4].min_by { |x| (x - 3).abs }
      p [1, 2, 3, 4].max_by { |x| (x % 3) }
      p [3, 1, 2].minmax
      p (1..6).group_by { |x| x % 3 }
      p [1, 2, 3, 4].partition { |x| x.even? }
      p [[1, 2], [3, 4]].flat_map { |a| a }
      p [1, 2, 3, 4, 5].filter_map { |x| x * 2 if x.odd? }
      acc = []
      (1..7).each_slice(3) { |s| acc << s }
      p acc
      acc2 = []
      (1..4).each_cons(2) { |c| acc2 << c }
      p acc2
      p [1, 2, 3].each_with_object([]) { |x, memo| memo << x * 10 }
      p [1, 2, 3, 4].take_while { |x| x < 3 }
      p [1, 2, 3, 4].drop_while { |x| x < 3 }
      p ["a", "b", "a", "c", "a"].tally
      p [1, 2, 2, 3].uniq
      p({ a: 1, b: 2 }.sort_by { |k, v| -v })
      acc3 = []
      [1, 2, 3].reverse_each { |x| acc3 << x }
      p acc3
      p [[:a, 1], [:b, 2]].to_h
      p({ a: 1 }.flat_map { |k, v| [k, v] })
      p (1..4).find_index { |x| x > 2 }
    RUBY

    _(result).must_answer <<~'OUT'
      [3, 2, 1]
      3
      2
      [1, 3]
      {1 => [1, 4], 2 => [2, 5], 0 => [3, 6]}
      [[2, 4], [1, 3]]
      [1, 2, 3, 4]
      [2, 6, 10]
      [[1, 2, 3], [4, 5, 6], [7]]
      [[1, 2], [2, 3], [3, 4]]
      [10, 20, 30]
      [1, 2]
      [3, 4]
      {"a" => 3, "b" => 1, "c" => 1}
      [1, 2, 3]
      [[:b, 2], [:a, 1]]
      [3, 2, 1]
      {a: 1, b: 2}
      [:a, 1]
      2
    OUT
  end

  it "the chunk family groups consecutive elements by a block-computed key" do
    result = ze0(<<~'RUBY')
      # The chunk family groups CONSECUTIVE elements of an enumerable.

      # `chunk` groups runs that share a block-computed key into [key, [run]] pairs.
      runs = [1, 1, 2, 3, 3, 3, 1].chunk { |x| x }.map { |key, group| [key, group.size] }
      p runs                                    # [[1, 2], [2, 1], [3, 3], [1, 1]]

      # Group numbers by even/odd.
      parity = [2, 4, 5, 7, 8].chunk(&:even?).to_a
      p parity                                  # [[true, [2, 4]], [false, [5, 7]], [true, [8]]]

      # `chunk_while` cuts between two adjacent elements when the block is false --
      # here, keeping ascending-by-one runs together.
      ascending = [1, 2, 4, 5, 6, 9].chunk_while { |i, j| i + 1 == j }.to_a
      p ascending                               # [[1, 2], [4, 5, 6], [9]]

      # `slice_when` is its negation: it cuts when the block is TRUE.
      gaps = [1, 2, 4, 9, 10, 11, 12, 0].slice_when { |i, j| i + 1 != j }.to_a
      p gaps                                    # [[1, 2], [4], [9, 10, 11, 12], [0]]
    RUBY

    _(result).must_answer <<~'OUT'
      [[1, 2], [2, 1], [3, 3], [1, 1]]
      [[true, [2, 4]], [false, [5, 7]], [true, [8]]]
      [[1, 2], [4, 5, 6], [9]]
      [[1, 2], [4], [9, 10, 11, 12], [0]]
    OUT
  end

  it "chunk answers one pair per run, so a repeated key opens a new run" do
    result = ze0("p [1, 1, 2, 2, 2, 3].chunk { |x| x }.map { |k, v| [k, v.size] }\n")

    _(result).must_answer "[[1, 2], [2, 3], [3, 1]]\n"
  end

  it "multiple producers one consumer sum is exact" do
    result = ze0(<<~'RUBY')
      q = Queue.new
      p1 = Thread.new { 10.times { q.push 1 } }
      p2 = Thread.new { 10.times { q.push 1 } }
      consumer = Thread.new do
        total = 0
        loop do
          v = q.pop
          break if v.nil?
          total += v
        end
        total
      end
      p1.join
      p2.join
      q.close
      puts consumer.value
    RUBY

    _(result).must_answer "20\n"
  end

  it "partition boxed predicate" do
    result = ze0(<<~'RUBY')
      # A partition block whose value is boxed: `if (rbval)` is not valid C, and
      # Ruby's truthiness is "not nil and not false" anyway. The C would not compile.
      e = [1, nil, 2]
      p e.partition { |x| x }
      p [1,2,3].partition { |x| x > 1 }
      p [nil, false, 1].partition { |x| x }
      p ["a", nil].partition { |x| x }
    RUBY

    _(result).must_answer <<~'OUT'
      [[1, 2], [nil]]
      [[2, 3], [1]]
      [[1], [nil, false]]
      [["a"], [nil]]
    OUT
  end

  it "safe nav chunk family" do
    result = ze0(<<~'RUBY')
      # `v&.chunk_while { }` on a nil receiver answers nil. The lowering that builds
      # the runs walked the receiver without looking at the operator, and the type of
      # the call disagreed with what that lowering renders.
      def pick(n) = n > 0 ? [1, 2, 4, 5] : nil

      [1, 0].each do |k|
        v = pick(k)
        cw = v&.chunk_while { |a, b| b == a + 1 }
        sw = v&.slice_when { |a, b| b != a + 1 }
        p cw.nil?
        p sw.nil?
        p(cw.nil? ? nil : cw.to_a)
        p(sw.nil? ? nil : sw.to_a)
      end

      # the same call with a `.to_a` terminal answers the runs, not an Enumerator,
      # whether the receiver is typed or poly
      def runs(v) = v.chunk_while { |a, b| b == a + 1 }.to_a
      p runs([1, 2, 4, 5])
      p runs(pick(1))
    RUBY

    _(result).must_answer <<~'OUT'
      false
      false
      [[1, 2], [4, 5]]
      [[1, 2], [4, 5]]
      true
      true
      nil
      nil
      [[1, 2], [4, 5]]
      [[1, 2], [4, 5]]
    OUT
  end
end
