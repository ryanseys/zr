# frozen_string_literal: true

require "spec_helper"

describe "Enumerable: enumeration" do
  it "blockless breadth returns enumerators everywhere" do
    result = ze0(<<~'RUBY')
      # The blockless breadth: iteration methods across
      # Integer/Range/Hash/String/Array answer real Enumerators (inspect shows
      # the captured receiver/method/args; `each` re-invokes the source).

      p 5.times.to_a
      p 2.upto(5).to_a
      p 5.downto(2).inspect
      p (1..10).step(3).to_a
      p({ a: 1, b: 2 }.each_value.to_a)
      p "hey".each_char.to_a
      p [3, 1].sort_by
      p 1.step(2.0, 0.5).to_a
      p 5.then.next
      p({ x: 1 }.each.next)
      p [1, 2, 3].each_slice(2).to_a
    RUBY

    _(result).must_answer <<~'OUT'
      [0, 1, 2, 3, 4]
      [2, 3, 4, 5]
      "#<Enumerator: 5:downto(2)>"
      [1, 4, 7, 10]
      [1, 2]
      ["h", "e", "y"]
      #<Enumerator: [3, 1]:sort_by>
      [1.0, 1.5, 2.0]
      5
      [:x, 1]
      [[1, 2], [3]]
    OUT
  end

  it "blockless enumerable enumerator" do
    result = ze0(<<~'RUBY')
      class Nums
        include Enumerable
        def initialize(*xs); @xs = xs; end
        def each; @xs.each { |x| yield x }; end
      end
      r001 = (Nums.new(1, 2, 3).sort_by.class rescue $!.class); p r001
      r002 = (Nums.new(1, 2, 3).group_by.class rescue $!.class); p r002
      r003 = (Nums.new(1, 2, 3).min_by.class rescue $!.class); p r003
      r004 = (Nums.new(1, 2, 3).find.class rescue $!.class); p r004
      p Nums.new(1,2,3).map.class
      p Nums.new(1,2,3).select.class
      p [1,2,3].sort_by.class
      p [1,2,3].group_by.class
      p [1,2,3].min_by.class
      p [1,2,3].find.class
      p [3,1,2].sort_by { |x| x }
      p [1,2,3].find { |x| x > 1 }
      p [1,2,3].group_by { |x| x.odd? }
    RUBY

    _(result).must_answer <<~'OUT'
      Enumerator
      Enumerator
      Enumerator
      Enumerator
      Enumerator
      Enumerator
      Enumerator
      Enumerator
      Enumerator
      Enumerator
      [1, 2, 3]
      2
      {true => [1, 3], false => [2]}
    OUT
  end

  it "blockless forms return real enumerators" do
    result = ze0(<<~'RUBY')
      # A blockless map returns a real Enumerator whose `each` re-invokes the
      # captured method. Oracle-verified.

      e = [1, 2].map
      p e.class
      p e
      p e.each { |x| x * 3 }
      p e.size
    RUBY

    _(result).must_answer <<~'OUT'
      Enumerator
      #<Enumerator: [1, 2]:map>
      [3, 6]
      2
    OUT
  end

  it "container read blockless enumerator" do
    result = ze0(<<~'RUBY')
      # A blockless enumerator on a value reached through a container -- a String
      # destructured out of an Array, an Array held as a Hash value -- materializes
      # like the statically typed receiver's does, instead of staying untyped.
      pair = [0, "hello"]
      i, text = pair
      p text.each_byte.reduce(0) { |a, b| a + b }
      p text.each_char.to_a
      p text.each_byte.to_a.size
      p text.each_char.map { |ch| ch.upcase }.join
      p text.each_line.to_a
      p text.each_codepoint.sum
      p text.upcase
      p text.length

      [[1, "ab"]].each do |n, s|
        p s.each_char.to_a
        p s.each_byte.sum
      end

      g = { "k" => [1, 2, 3, 4] }
      p g["k"].each_cons(2).map { |a, b| b - a }
      p g["k"].combination(2).select { |a, b| a < b }.size
      p g["k"].each_slice(2).to_a
      p g["k"].permutation(2).to_a.size
    RUBY

    _(result).must_answer <<~'OUT'
      532
      ["h", "e", "l", "l", "o"]
      5
      "HELLO"
      ["hello"]
      532
      "HELLO"
      5
      ["a", "b"]
      195
      [1, 1, 1]
      6
      [[1, 2], [3, 4]]
      12
    OUT
  end

  it "custom enum inject sym var" do
    result = ze0(<<~'RUBY')
      class Nums
        include Enumerable
        def initialize(*xs)
          @xs = xs
        end
        def each
          @xs.each { |x| yield x }
        end
      end
      s = :+
      p Nums.new(3, 1, 2).inject(s)
      p Nums.new(3, 1, 2).reduce(s)
    RUBY

    _(result).must_answer "6\n6\n"
  end

  it "each cons block destructure" do
    result = ze0(<<~'RUBY')
      # Enumerable#each_cons block destructure on typed arrays:
      # `|a, b|` against `each_cons(2)` binds each pair element to
      # its own scalar param rather than to a sub-array.

      ["a", "b", "c", "d"].each_cons(2) { |x, y| puts x + "," + y }
      puts "---"
      [1, 2, 3, 4, 5].each_cons(2) { |a, b| puts (a + b).to_s }
      puts "---"
      # `|pair|` (single block param) still gets the sub-array.
      [1, 2, 3, 4].each_cons(2) { |pair| puts pair.length }
    RUBY

    _(result).must_answer <<~'OUT'
      a,b
      b,c
      c,d
      ---
      3
      5
      7
      9
      ---
      2
      2
      2
    OUT
  end

  it "each cons map types" do
    result = ze0(<<~'RUBY')
      # each_cons(n).map { |a, b, ...| } destructures the n-window into element-typed
      # params, so arithmetic and comparison behave like the elements rather than the
      # window array. A single param |w| still binds the whole window.
      p [1, 2, 3, 4].each_cons(2).map { |a, b| a + b }               # [3, 5, 7]
      p [1, 2, 3, 4].each_cons(2).map { |a, b| a == 2 ? 99 : a + b }  # [3, 99, 7]
      p [1, 2, 3].each_cons(2).map { |a, b| [a, b] }                 # [[1, 2], [2, 3]]
      p [1, 2, 3, 4, 5].each_cons(3).map { |a, b, c| a + b + c }     # [6, 9, 12]
      p [1, 2, 3, 4].each_cons(2).map { |w| w.sum }                  # [3, 5, 7]
      p [1, 2, 3, 4].each_cons(2).map { |(a, b)| a * b }             # [2, 6, 12]
    RUBY

    _(result).must_answer <<~'OUT'
      [3, 5, 7]
      [3, 99, 7]
      [[1, 2], [2, 3]]
      [6, 9, 12]
      [3, 5, 7]
      [2, 6, 12]
    OUT
  end

  it "each cons with index map no double gets" do
    result = ze0(<<~'RUBY')
      # `.each_cons[.with_index].map { ... }` over a side-effecting inner
      # array must not re-emit the inner chain. Pre-fix compile_call_expr
      # emitted `rc` (the with_index/each_cons placeholder pair) before
      # routing to compile_map_expr's fusion path, which then re-emitted
      # the inner receiver. The inner block's side effects (`gets`, an
      # accumulator method, ...) ran twice -- consuming twice the input
      # lines or doubling the counter. Issue #621.

      $counter = 0
      def step
        $counter += 1
        $counter
      end

      # `3.times.map { step }` -> [1, 2, 3] (counter should advance by 3,
      # not by 6 from a duplicate emission).
      result = 3.times.map { step }.each_cons(2).with_index(1).map { |(x, y), i| [x - y, i] }
      result.each do |pair|
        puts pair.inspect
      end
      puts $counter
    RUBY

    _(result).must_answer <<~'OUT'
      [-1, 1]
      [-1, 2]
      3
    OUT
  end

  it "each hands one value per element" do
    result = ze0(<<~'RUBY')
      # Enumerable's methods read one value per element of `each`: the value
      # yielded, or the Array of them when each yields several, or nil for
      # none. Control flow in the caller's block, an each that keeps or
      # passes its block on, and a yield of two values all answer as ruby's.
      class Yielder
        include Enumerable
        def initialize(rows) = @rows = rows
        def each
          return to_enum(:each) unless block_given?
          @rows.each { |row| row.nil? ? yield : yield(*row) }
          self
        end
      end
      y = Yielder.new([[1], [2, 3], nil, [[4, 5]], [6]])
      p y.to_a, y.select { |v| v }, y.reject { |v| v.is_a?(Array) }, y.find { |v| v == 6 }, y.count, y.include?(nil)
      p y.min_by { |v| v.to_s }, y.sort_by { |v| v.to_s }, y.group_by { |v| v.class }, y.each_slice(2).to_a, y.take_while { |v| v }
      p y.each_with_index.to_a, y.each_with_object([]) { |v, acc| acc << v }, y.inject { |a, b| [a, b] }, y.first(2), y.to_set.size
      p y.each_entry.to_a, y.zip(y), y.partition { |v| v.nil? }, y.chunk_while { |a, b| !b.nil? }.to_a, y.tally
      r = y.select { |v| break :broke if v == 6; true }
      p r
      def early(y) = y.each_with_index { |v, i| return [v, i] if i == 2 }
      p early(y), y.map { |v| next :skipped if v.nil?; v }
      class Keeper
        include Enumerable
        def each(&b)
          @kept = b
          [1, 2, 3].each(&b)
        end
        def again = [4].each(&@kept)
      end
      k = Keeper.new
      p k.to_a, k.again, k.sort, k.select(&:even?), k.lazy.map { |v| v * 2 }.first(2)
      h = { a: 1, b: 2 }
      p h.select { |k, v| v > 1 }, h.map { |k, v| [k, v] }, h.min_by { |k, v| -v }, h.each_slice(1).to_a, h.find { |pair| pair[1] == 2 }
      p (1..4).each_cons(2).to_a, (1..4).select(&:even?), (1..3).inject(:+), [[1, 2], [3, 4]].each_with_index.map { |(a, b), i| a + b + i }


    RUBY

    _(result).must_answer <<~'OUT'
      [1, [2, 3], nil, [4, 5], 6]
      [1, [2, 3], [4, 5], 6]
      [1, nil, 6]
      6
      5
      true
      nil
      [nil, 1, 6, [2, 3], [4, 5]]
      {Integer => [1, 6], Array => [[2, 3], [4, 5]], NilClass => [nil]}
      [[1, [2, 3]], [nil, [4, 5]], [6]]
      [1, [2, 3]]
      [[1, 0], [[2, 3], 1], [nil, 2], [[4, 5], 3], [6, 4]]
      [1, [2, 3], nil, [4, 5], 6]
      [[[[1, [2, 3]], nil], [4, 5]], 6]
      [1, [2, 3]]
      5
      [1, [2, 3], nil, [4, 5], 6]
      [[1, 1], [[2, 3], [2, 3]], [nil, nil], [[4, 5], [4, 5]], [6, 6]]
      [[nil], [1, [2, 3], [4, 5], 6]]
      [[1, [2, 3]], [nil, [4, 5], 6]]
      {1 => 1, [2, 3] => 1, nil => 1, [4, 5] => 1, 6 => 1}
      :broke
      [nil, 2]
      [1, 2, :skipped, [4, 5], 6]
      [1, 2, 3, 4]
      [4]
      [1, 2, 3]
      [2]
      [2, 4]
      {b: 2}
      [[:a, 1], [:b, 2]]
      [:b, 2]
      [[[:a, 1]], [[:b, 2]]]
      [:b, 2]
      [[1, 2], [2, 3], [3, 4]]
      [2, 4]
      6
      [3, 8]
    OUT
  end

  it "each through the adapter with enumerators and lazy" do
    result = ze0(<<~'RUBY')
      # Enumerable methods over enumerators, lazy chains, an each that yields
      # to a kept block later, an each written in a module and refined, and
      # blocks that break, next, redo-free retry and raise through the
      # kernel's each adapter.
      class Rows
        include Enumerable
        def initialize(*rows) = @rows = rows
        def each(&b)
          return enum_for(:each) { @rows.size } unless b
          @rows.each(&b)
          self
        end
      end
      r = Rows.new(1, [2, 3], nil, 4)
      p r.each.size, r.each.next, r.lazy.select { |v| v }.map { |v| v.to_s }.first(2), r.each_slice(2).to_a
      p r.each_with_index.select { |v, i| i.even? }, r.each.with_object([]) { |v, acc| acc << v.class }, r.min_by { |v| v.to_s.size }
      p r.find_index(4), r.find_index { |v| v.nil? }, r.first, r.first(3), r.take(2), r.drop(2), r.include?([2, 3]), r.entries
      p r.select.with_index { |v, i| i > 1 }, r.each_entry.to_a.size, r.sort_by { |v| v.to_s }, r.reduce(:to_s) rescue p $!.class
      def raising(rows) = rows.select { |v| raise "boom" if v.nil?; v }
      p (raising(r) rescue $!.message)
      def broken(rows) = rows.each_with_index.to_a.size + rows.count { |v| break 10 if v.nil?; true }
      p broken(r)
      en = r.each
      p en.next, en.next, en.next, en.next, (en.next rescue $!.class), en.rewind.next
      p r.zip([1, 2, 3, 4]), r.chunk_while { |a, b| b.nil? }.to_a, r.slice_when { |a, b| b.is_a?(Array) }.to_a, r.tally.size
      p r.group_by { |v| v.class }.keys, r.partition { |v| v }, r.each_cons(3).to_a.size, r.flat_map { |v| [v, v] }.size, r.sum { |v| v.is_a?(Integer) ? v : 0 }
      p Rows.new.first, Rows.new.min, Rows.new.to_a, Rows.new.each_slice(2).to_a, Rows.new.inject(:+), Rows.new.count
      h = { a: 1, b: 2 }
      p h.each_with_index.to_a, h.min_by { |k, v| v }, h.find { |k, v| v == 2 }, h.select { |k, v| v > 1 }, h.map { |k, v| k }, h.each_entry.to_a
      p (1..Float::INFINITY).lazy.map { |v| v * 2 }.select { |v| v % 3 == 0 }.first(3), (1..4).each_slice(3).to_a, (1..4).inject { |a, b| a * b }

    RUBY

    _(result).must_answer <<~'OUT'
      4
      1
      ["1", "[2, 3]"]
      [[1, [2, 3]], [nil, 4]]
      [[1, 0], [nil, 2]]
      [Integer, Array, NilClass, Integer]
      nil
      3
      2
      1
      [1, [2, 3], nil]
      [1, [2, 3]]
      [nil, 4]
      true
      [1, [2, 3], nil, 4]
      TypeError
      "boom"
      14
      1
      [2, 3]
      nil
      4
      StopIteration
      1
      [[1, 1], [[2, 3], 2], [nil, 3], [4, 4]]
      [[1], [[2, 3], nil], [4]]
      [[1], [[2, 3], nil, 4]]
      4
      [Integer, Array, NilClass]
      [[1, [2, 3], 4], [nil]]
      2
      8
      5
      nil
      nil
      []
      []
      nil
      0
      [[[:a, 1], 0], [[:b, 2], 1]]
      [:a, 1]
      [:b, 2]
      {b: 2}
      [:a, :b]
      [[:a, 1], [:b, 2]]
      [6, 12, 18]
      [[1, 2, 3], [4]]
      24
    OUT
  end

  it "each with index enumerator" do
    result = ze0(<<~'RUBY')
      # A blockless Array#each_with_index / #each_index returns an external
      # Enumerator: each_with_index steps through [element, index] pairs, each_index
      # through the indices. #next / #peek / #rewind / #to_a / #size all work over the
      # materialized snapshot. The array is routed through a method so it is not
      # constant-folded at the call site.

      def ewi(a)
        a.each_with_index
      end

      e = ewi([10, 20, 30])
      p e.next
      p e.peek
      p e.next
      p e.next
      p e.size
      e.rewind
      p e.next

      # to_a materializes all pairs.
      p ewi([1, 2, 3]).to_a

      # each_index yields the indices.
      def eidx(a)
        a.each_index
      end

      g = eidx([9, 8, 7, 6])
      p g.next
      p g.next
      p g.to_a

      # string-element array pairs.
      p %w[a b c].each_with_index.to_a

      # StopIteration past the end.
      h = ewi([1])
      p h.next
      begin
        h.next
      rescue StopIteration
        puts "stop"
      end
    RUBY

    _(result).must_answer <<~'OUT'
      [10, 0]
      [20, 1]
      [20, 1]
      [30, 2]
      3
      [10, 0]
      [[1, 0], [2, 1], [3, 2]]
      0
      1
      [0, 1, 2, 3]
      [["a", 0], ["b", 1], ["c", 2]]
      [1, 0]
      stop
    OUT
  end

  it "each with index filter map" do
    result = ze0(<<~'RUBY')
      # Enumerator#filter_map over each_with_index: keep truthy block values.
      arr = [10, 20, 30, 40]
      puts arr.each_with_index.filter_map { |s, i| i if s > 15 }.inspect
      puts arr.each_with_index.filter_map { |s, i| s + i if i.even? }.inspect
      puts arr.each_with_index.filter_map { |s, i| "#{i}:#{s}" if s < 35 }.inspect

      # A numeric 0 / 0.0 (and "") block value is truthy in Ruby: filter_map keeps
      # it, dropping only nil/false. A C zero-falsy test would wrongly discard them.
      nums = [3, 0, 5]
      puts nums.each_with_index.filter_map { |v, i| v }.inspect
      puts nums.each_with_index.filter_map { |v, i| v * i * 1.0 }.inspect
      puts nums.each_with_index.filter_map { |v, i| v.to_s }.inspect

      # select/reject/count/any?/all? share the same truthiness path: a block that
      # yields a bare 0 is truthy, so select keeps every pair and reject none.
      puts [7, 0, 9].each_with_index.select { |v, i| v - v }.inspect
      puts [7, 0, 9].each_with_index.reject { |v, i| v - v }.inspect
      puts [7, 0, 9].each_with_index.count { |v, i| v - v }
      puts [7, 0, 9].each_with_index.all? { |v, i| v - v }
      puts [7, 0, 9].each_with_index.any? { |v, i| v - v }
    RUBY

    _(result).must_answer <<~'OUT'
      [1, 2, 3]
      [10, 32]
      ["0:10", "1:20", "2:30"]
      [3, 0, 5]
      [0.0, 0.0, 10.0]
      ["3", "0", "5"]
      [[7, 0], [0, 1], [9, 2]]
      []
      3
      true
      true
    OUT
  end

  it "each with index inject" do
    result = ze0(<<~'RUBY')
      # matz/spinel#1481: inject/reduce over each.with_index / each_with_index
      puts [10, 20, 30].each.with_index.inject(0) { |acc, (val, idx)| acc + idx }       # 3
      chars = [1, 2, 3]
      puts chars.each.with_index.inject(0) { |sum, (c, k)| sum + c * (26 ** k) }         # 2081 (base26)
      puts %w[a b c].each.with_index.inject("") { |str, (ch, n)| str + "#{ch}#{n}" }     # a0b1c2
      puts [10, 20].each.with_index.inject(0) { |t, pr| t + pr[0] + pr[1] }              # 31
      puts [5, 6, 7].each.with_index.reduce(100) { |r, (e, m)| r + e - m }               # 115
      puts [10, 20].each.with_index(10).inject(0) { |o, (x, w)| o + w }                  # 21
      puts [1, 2, 3].each_with_index.inject(0) { |q, (y, z)| q + z }                     # 3
    RUBY

    _(result).must_answer <<~'OUT'
      3
      2081
      a0b1c2
      31
      115
      21
      3
    OUT
  end

  it "each with index struct present" do
    result = ze0(<<~'RUBY')
      # `arr.each_with_index` with no block answers an Enumerator. A Struct gets an
      # Enumerable #each_with_index synthesized, and a user definition of the name
      # takes over the poly dispatch -- so the call typed as that Struct, and the
      # Enumerator it actually builds was assigned to a slot declared as a pointer to
      # the Struct (#4021).
      #
      # The receiver has to arrive boxed for the dispatch to be consulted at all,
      # which is what the destructured multi-value return in the report does.
      Line = Struct.new(:number)

      def first_pass(lines)
        layout = []
        lines.each { |line| layout << [0, line] }
        [{}, layout, 0]
      end

      def encode(line) = line.number

      symbols, layout, size = first_pass([Line.new(1), Line.new(2)])
      image = layout.map { |_addr, line| encode(line) }
      p image
      reencoded = layout.each_with_index.map { |(_a, line), i| encode(line) == image[i] }
      p reencoded

      # the enumerator itself, and the other blockless producer
      _s, lay2, _z = first_pass([Line.new(7)])
      e = lay2.each_with_index
      p e.class
      p e.to_a.size
      p lay2.each_index.to_a

      # a literal array is unaffected, as it always was
      lit = [[0, Line.new(3)]]
      p lit.each_with_index.map { |(_a, line), i| line.number + i }
      p lit.each_with_index.class
    RUBY

    _(result).must_answer <<~'OUT'
      [1, 2]
      [true, true]
      Enumerator
      1
      [0]
      [3]
      Enumerator
    OUT
  end

  it "each with index sum block" do
    result = ze0(<<~'RUBY')
      # A sum over an each_with_index enumerator folds [value, index] pairs, so a
      # 2-parameter block auto-splats each pair. The scalar-accumulator fold bound
      # only the first parameter and left the rest nil, so `a[i]` read index nil on
      # every iteration; and a parameter nothing reads had no slot at all, which
      # named an undeclared identifier in the generated C.
      p [0].each_with_index.sum { |e, i| 0 }
      p [0].each_with_index.sum { |e| 0 }

      a = [10, 20, 30]
      p a.each_with_index.sum { |v, i| a[i] }
      p a.each_with_index.sum { |v, i| v }
      p a.each_with_index.sum { |v, i| i }
      p a.each_with_index.sum { |v, i| v + i }

      b = [1.5, 2.5]
      p b.each_with_index.sum { |v, i| v * i }

      # the shape the report came from: a ring of structs indexed by the neighbour
      st = Struct.new(:x, :y)
      ring = [[-63.1, 46.2], [-63.2, 46.3]].map { |lon, lat| st.new(Float(lon), Float(lat)) }
      p ring.each_with_index.sum { |v, i|
        w = ring[i + 1 - ring.size]
        v.x * w.y - w.x * v.y
      }.round(6)

      # a plain array keeps binding the whole element to the first parameter
      p [[1, 2], [3, 4]].sum { |pair| pair[0] }
      p [1, 2].sum { |x| x }
    RUBY

    _(result).must_answer <<~'OUT'
      0
      0
      60
      60
      3
      63
      2.5
      0.0
      4
      3
    OUT
  end

  it "each with index terminals" do
    result = ze0(<<~'RUBY')
      p [10, 20, 30].each.with_index.to_a
      p [10, 20, 30].each.with_index.map { |v, i| i }
      p [10, 20, 30].each.with_index.any? { |v, i| i > 1 }
      p [10, 20, 30].each.with_index.select { |v, i| i > 0 }
      puts [10, 20, 30].each.with_index.count { |v, i| i > 0 }
      p [10, 20, 30].each.with_index.reject { |v, i| i > 0 }
      p [10, 20, 30].each.with_index.all? { |v, i| v > 5 }
      p [10, 20, 30].each.with_index.none? { |v, i| i > 5 }
      p %w[a b c].each.with_index.to_a
      p %w[a b c].each.with_index.select { |s, i| i.odd? }
      p [5, 6, 7].each_with_index.map { |v, i| v * i }
      p [10, 20].each.with_index(100).to_a
      p [1, 2, 3, 4].each.with_index.count { |v, i| v.even? }
      p [10, 20, 30].each.with_index.collect { |v, i| v + i }
    RUBY

    _(result).must_answer <<~'OUT'
      [[10, 0], [20, 1], [30, 2]]
      [0, 1, 2]
      true
      [[20, 1], [30, 2]]
      2
      [[10, 0]]
      true
      true
      [["a", 0], ["b", 1], ["c", 2]]
      [["b", 1]]
      [0, 6, 14]
      [[10, 100], [20, 101]]
      2
      [10, 21, 32]
    OUT
  end

  it "each with object empty seed" do
    result = ze0(<<~'RUBY')
      p({ a: 1 }.each_with_object([]) { |x, a| a })

      p({ a: 1 }.each_with_object({}) { |x, a| a })          # Ruby: {}   Spinel: compile abort
      p({}.each_with_object([]) { |x, a| a })                # Ruby: []   Spinel: compile abort
      v = { a: 1 }.each_with_object([]) { |x, a| a }; p v    # Ruby: []   Spinel: compile abort

      p({ a: 1 }.each_with_object([1]) { |x, a| a })         # => [1]
      p({ a: 1 }.each_with_object(0) { |x, a| a })           # => 0
      p({ a: 1 }.each_with_object("s") { |x, a| a })         # => "s"
      p({ a: 1 }.each_with_object([]) { |x, a| a << x })     # => [[:a, 1]]
      p({ a: 1 }.each_with_object([]) { |x, a| a.push(1) })  # => [1]
      p({ a: 1 }.inject([]) { |a, x| a })                    # => []

      p({ a: 1, b: 2 }.each_with_object({}) { |x, a| a[x[0]] = x[1] })
      p({ a: 1 }.each_with_object([]) { |(k, v), a| a << k })
      p([1, 2].each_with_object([]) { |x, a| a })
      p((1..2).each_with_object([]) { |x, a| a })
    RUBY

    _(result).must_answer <<~'OUT'
      []
      {}
      []
      []
      [1]
      0
      "s"
      [[:a, 1]]
      [1]
      []
      {a: 1, b: 2}
      [:a]
      []
      []
    OUT
  end

  it "each with object memo" do
    result = ze0(<<~'RUBY')
      # each_with_object accumulator element type is inferred from how the memo is
      # filled (`memo << e`), even when the seed is an empty `[]`. The inference
      # follows a forwarded callable value into its body, so `&proc` / `&->(){}` /
      # `&method(:m)` accumulate the right element type too. Distinct memo-param names
      # keep sibling blocks from sharing a typed C local; receivers route through a
      # method param to defeat constant folding.
      def ia(x) = x

      # --- literal blocks: empty [] seed, element type taken from the push ---
      p ia([1, 2, 3]).each_with_object([]) { |x, mi| mi << x * 2 }       # [2, 4, 6]
      p ia([1, 2, 3]).each_with_object([]) { |x, ms| ms << x.to_s }      # ["1", "2", "3"]
      p ia([1, 2, 3]).each_with_object([]) { |x, mf| mf << x / 2.0 }     # [0.5, 1.0, 1.5]
      p ia([1, 2, 3]).each_with_object([]) { |x, mp| mp << x; mp << x.to_s } # [1, "1", 2, "2", 3, "3"]
      p ia([1, 2, 3]).each_with_object([]) { |x, mu| mu.push(x.to_s) }   # ["1", "2", "3"] (push)
      p ia([1, 2, 3]).each_with_object([]) { |x, mn| mn }                # [] (no push -> empty)

      # --- non-empty typed seed keeps working ---
      p ia([1, 2, 3]).each_with_object(["seed"]) { |x, mt| mt << x.to_s } # ["seed", "1", "2", "3"]

      # --- forwarded callable values: body-of-callable inference ---
      add_dbl = ->(x, acc) { acc << x * 2 }
      p ia([1, 2, 3]).each_with_object([], &add_dbl)                     # [2, 4, 6]
      add_str = ->(x, acc) { acc << x.to_s }
      p ia([1, 2, 3]).each_with_object([], &add_str)                    # ["1", "2", "3"]
      p ia([1, 2, 3]).each_with_object([], &->(x, acc) { acc << x * 10 }) # [10, 20, 30]
      p ia([1, 2, 3]).each_with_object([], &->(x, acc) { acc << x.to_s }) # ["1", "2", "3"]

      def collect_s(x, acc) = acc << x.to_s
      p ia([1, 2, 3]).each_with_object([], &method(:collect_s))         # ["1", "2", "3"]

      # --- assigned result keeps a precise type (no fixpoint widening to poly) ---
      r = ia([1, 2, 3]).each_with_object([], &add_str)
      p r                                                               # ["1", "2", "3"]
    RUBY

    _(result).must_answer <<~'OUT'
      [2, 4, 6]
      ["1", "2", "3"]
      [0.5, 1.0, 1.5]
      [1, "1", 2, "2", 3, "3"]
      ["1", "2", "3"]
      []
      ["seed", "1", "2", "3"]
      [2, 4, 6]
      ["1", "2", "3"]
      [10, 20, 30]
      ["1", "2", "3"]
      ["1", "2", "3"]
      ["1", "2", "3"]
    OUT
  end

  it "enum map chain" do
    result = ze0(<<~'RUBY')
      a = [1, 2, 3]
      p a.each_index.map { |c| c }
      p a.each_index.collect { |c| c * 10 }
      p a.each_with_index.map { |v, i| v + i }
      p a.each_with_index.flat_map { |v, i| [v, i] }
      p a.each_index.filter_map { |c| c if c > 0 }
    RUBY

    _(result).must_answer <<~'OUT'
      [0, 1, 2]
      [0, 10, 20]
      [1, 3, 5]
      [1, 0, 2, 1, 3, 2]
      [1, 2]
    OUT
  end

  it "enum with index map" do
    result = ze0(<<~'RUBY')
      # Enumerator#with_index return value on a stored map/each enumerator (#2510)
      e = [1, 2, 3].map
      p(e.with_index { |x, i| x * 10 + i })   # map enumerator -> collected array
      g = [1, 2, 3].each
      p(g.with_index { |x, i| p [x, i] })     # each enumerator -> source receiver
      h = %w[a b].collect
      p(h.with_index(1) { |x, i| "#{x}#{i}" })
    RUBY

    _(result).must_answer <<~'OUT'
      [10, 21, 32]
      [1, 0]
      [2, 1]
      [3, 2]
      [1, 2, 3]
      ["a1", "b2"]
    OUT
  end

  it "enumerable chain enumerator" do
    result = ze0(<<~'RUBY')
      # Enumerable#chain / Enumerator#+ build an Enumerator::Chain over the
      # concatenated sources (#2545, #2548, #2551). The sources are materialized at
      # build time, so every terminal the sources support works on the chain.

      # Enumerator#+ reports Enumerator::Chain (#2545)
      p(([1, 2].each + [3, 4].each).class)
      p(([1, 2].each + [3, 4].each).to_a)
      p(([1].each + [2].each + [3].each).to_a)

      # Struct receiver, chain stored in a variable (#2548)
      Nums = Struct.new(:a, :b, :c)
      c1 = Nums.new(3, 1, 2).chain([4, 5])
      p c1.to_a
      p c1.class

      # user Enumerable: receiver, argument, stored in a local, block form (#2551)
      class E
        include Enumerable
        def initialize(*xs); @xs = xs; end
        def each; @xs.each { |x| yield x }; end
      end
      a = E.new(1, 2)
      c = a.chain([3, 4])
      p c.to_a
      p [9].chain(E.new(7, 8)).to_a
      out = []
      E.new(1, 2).chain([3, 4]).each { |x| out << x }
      p out

      # a user-defined #chain still wins over Enumerable's
      class Own
        include Enumerable
        def each; yield 1; end
        def chain(x); "own:#{x}"; end
      end
      p Own.new.chain(5)

      # shapes the eager .to_a path already served
      p([1, 2, 3].chain.to_a)
      p([1, 2].chain([3], [4, 5]).to_a)
      p((1..2).chain([3]).to_a)
      p({a: 1}.chain([[:b, 2]]).to_a)

      # other terminals over a chain
      p([1, 2].chain([3]).map { |x| x * 2 })
      p([1, 2].chain([3]).select { |x| x > 1 })
      p([1, 2].chain([3]).count)
      p([1, 2].chain([3]).sum)
      p([1, 2].chain([3]).include?(3))
    RUBY

    _(result).must_answer <<~'OUT'
      Enumerator::Chain
      [1, 2, 3, 4]
      [1, 2, 3]
      [3, 1, 2, 4, 5]
      Enumerator::Chain
      [1, 2, 3, 4]
      [9, 7, 8]
      [1, 2, 3, 4]
      "own:5"
      [1, 2, 3]
      [1, 2, 3, 4, 5]
      [1, 2, 3]
      [[:a, 1], [:b, 2]]
      [2, 4, 6]
      [2, 3]
      3
      6
      true
    OUT
  end

  it "enumerable reduce proc arg" do
    result = ze0(<<~'RUBY')
      # reduce/inject with a &proc block argument forwards through a literal
      # two-param block; the fold emitter keeps the proc call's prelude inside the
      # loop, so every iteration publishes its own arguments (#2684).
      pr = ->(a, x) { a + x }
      p([1, 2, 3, 4].reduce(&pr))
      p([1, 2, 3, 4].reduce(0, &pr))
      p([1, 2, 3, 4].inject(10, &->(a, x) { a + x }))
      mul = ->(a, x) { a * x }
      p([1, 2, 3, 4].inject(&mul))
      # the manual form the desugar lowers to (was returning 0 before the
      # fold-prelude fix)
      add = ->(a, b) { a + b }
      p [1, 2, 3].reduce { |a, b| add.call(a, b) }
      p [1, 2, 3].inject(10) { |a, b| add.call(a, b) }
      # string accumulator
      cat = ->(a, s) { a + s }
      p(["x", "y", "z"].reduce(&cat))
    RUBY

    _(result).must_answer <<~'OUT'
      10
      10
      20
      24
      6
      16
      "xyz"
    OUT
  end

  it "enumerator bare yield" do
    result = ze0(<<~'RUBY')
      # Enumerator.new with the bare `y.yield v` form (no parentheses). Prism parses
      # `y.yield v` and `y.yield(v)` into the same CallNode (the parens only change
      # opening_loc), so the yielder rewrite that turns `recv.yield ...` into
      # sp_Fiber_yield handles both forms identically. Covers single/multi/zero args,
      # a variable argument, the last-statement position, and an infinite generator
      # driven by `loop`.

      e = Enumerator.new do |y|
        a = 10
        y.yield a          # variable arg
        b = 20
        y.yield a, b       # multiple args -> array
        y.yield             # no args -> nil
        y.yield a + b       # last statement
      end
      p e.next
      p e.next
      p e.next
      p e.next

      # Infinite generator with bare yield inside loop, consumed by take / next.
      fib = Enumerator.new do |y|
        a = 0
        b = 1
        loop do
          y.yield a
          a, b = b, a + b
        end
      end
      p fib.take(6)
      p fib.next
      p fib.next

      # StopIteration after a finite bare-yield generator.
      g = Enumerator.new do |y|
        y.yield 1
        y.yield 2
      end
      p g.peek
      p g.next
      p g.next
      begin
        g.next
      rescue StopIteration
        puts "stopped"
      end
    RUBY

    _(result).must_answer <<~'OUT'
      10
      [10, 20]
      nil
      30
      [0, 1, 1, 2, 3, 5]
      0
      1
      1
      1
      2
      stopped
    OUT
  end

  it "enumerator block returns self" do
    result = ze0(<<~'RUBY')
      p([1, 2, 3].each.each_cons(2) { |a001| a001 })
      p([1, 2, 3].each.each_slice(2) { |a002| a002 })
      p([1, 2, 3].each.each_entry { |a003| a003 })
      p([1, 2, 3].each.each_with_index { |a, i| a })
    RUBY

    _(result).must_answer <<~'OUT'
      #<Enumerator: [1, 2, 3]:each>
      #<Enumerator: [1, 2, 3]:each>
      #<Enumerator: [1, 2, 3]:each>
      [1, 2, 3]
    OUT
  end

  it "enumerator blockless regroup" do
    result = ze0(<<~'RUBY')
      p([1, 2, 3].each.each_slice(2).to_a)
      p([1, 2, 3].each.each_cons(2).to_a)
      p([1, 2, 3].each.cycle.first(5))
      p([1, 2, 3].each.reverse_each.to_a)
      p((1..3).each.each_slice(2).to_a)
      p([1, 2, 3].each.each_with_index.to_a)
      a = [1, "x"]
      p(a.cycle.first(5))
    RUBY

    _(result).must_answer <<~'OUT'
      [[1, 2], [3]]
      [[1, 2], [2, 3]]
      [1, 2, 3, 1, 2]
      [3, 2, 1]
      [[1, 2], [3]]
      [[1, 0], [2, 1], [3, 2]]
      [1, "x", 1, "x", 1]
    OUT
  end

  it "enumerator chain new" do
    result = ze0(<<~'RUBY')
      a = [1, 2].each
      b = [3, 4].each
      p Enumerator::Chain.new(a, b).to_a
      p (a + b).to_a
    RUBY

    _(result).must_answer "[1, 2, 3, 4]\n[1, 2, 3, 4]\n"
  end

  it "enumerator each entry receiver" do
    result = ze0(<<~'RUBY')
      v = (1..3).each.each_entry { |x| x }
      p v
      v2 = (1..5).each.each_slice(2) { |s| s }
      p v2
      v3 = [1, 2, 3].each.each_entry { |x| x }
      p v3
      v4 = [1, 2, 3].each_entry { |x| x }
      p v4
      v5 = (1..3).each_entry { |x| x }
      p v5
    RUBY

    _(result).must_answer <<~'OUT'
      #<Enumerator: 1..3:each>
      #<Enumerator: 1..5:each>
      #<Enumerator: [1, 2, 3]:each>
      [1, 2, 3]
      1..3
    OUT
  end

  it "enumerator external" do
    result = ze0(<<~'RUBY')
      # Array#each with no block returns an external Enumerator. #next / #peek walk a
      # cursor and raise StopIteration past the end; #rewind resets it; #size reports
      # the element count. Kernel#loop rescues StopIteration to terminate.

      e = [10, 20, 30].each
      p e.class
      p e.is_a?(Enumerator)
      p e.size

      p e.next
      p e.peek      # peek does not advance
      p e.next
      p e.next
      begin
        e.next
      rescue StopIteration
        puts "stopped"
      end

      e.rewind
      p e.next      # back to the start

      # loop terminates cleanly on StopIteration
      e2 = [1, 2, 3, 4].each
      total = 0
      loop do
        total += e2.next
      end
      p total
      puts "after loop"

      # the yielded values are real values usable in expressions
      ws = ["ab", "cde"].each
      p(ws.next + "!")
      p ws.next.length

      # mixed (poly) array
      m = [1, "two", :three].each
      p m.next
      p m.next
      p m.next

      # a value-form loop broken explicitly still returns its break value
      e3 = [7, 8, 9].each
      r = loop do
        v = e3.next
        break v if v == 8
      end
      p r
    RUBY

    _(result).must_answer <<~'OUT'
      Enumerator
      true
      3
      10
      20
      20
      30
      stopped
      10
      10
      after loop
      "ab!"
      3
      1
      "two"
      :three
      8
    OUT
  end

  it "enumerator feed result" do
    result = ze0(<<~'RUBY')
      # Enumerator#feed and StopIteration#result -- the two halves of the generator
      # resume protocol. #feed sets the value the generator's next `y.yield` returns
      # (raising TypeError if set twice before a #next); when the generator body runs
      # off the end, its return value is carried as StopIteration#result.
      #
      # Note: for a materialized enumerator (arr.each) CRuby's StopIteration#result is
      # the receiver; Zeo reports nil there. Only the fiber-backed generator, whose
      # body value is well-defined, carries a result -- that is what is asserted here.

      # --- #feed: y.yield returns the fed value ---
      g = Enumerator.new { |y| got = y.yield(10); y << (got * 2) }
      p g.next          # 10
      g.feed(5)
      p g.next          # 10  (== 5 * 2)

      # with no feed, y.yield returns nil
      h = Enumerator.new { |y| a = y.yield(1); p a; y << 2 }
      h.next            # yields 1
      h.next            # a is nil -> prints nil, then yields 2

      # #feed returns nil
      k = Enumerator.new { |y| y.yield(1) }
      k.next
      p k.feed(:x)      # nil

      # feeding twice before #next raises TypeError
      m = Enumerator.new { |y| y.yield(1); y.yield(2) }
      m.next
      m.feed(:a)
      begin
        m.feed(:b)
      rescue TypeError => te
        p te.message
      end

      # --- StopIteration#result: the generator body's return value ---
      en = Enumerator.new { |y| y << 1; y << 2; :finished }
      begin
        en.next; en.next; en.next
      rescue StopIteration => ex
        p ex.result     # :finished
      end

      # a numeric terminal value, and the same result on a repeated past-end #next
      n = Enumerator.new { |y| y << 10; 99 }
      n.next
      begin; n.next; rescue StopIteration => ex; p ex.result; end   # 99
      begin; n.next; rescue StopIteration => ex; p ex.result; end   # 99 (cached)

      # rewind clears any pending feed and the captured result
      r = Enumerator.new { |y| got = y.yield(1); y << (got.nil? ? -1 : got) }
      r.feed(7)
      p r.next          # 1
      r.rewind
      p r.next          # 1 (fresh run)
      p r.next          # -1 (feed was cleared by rewind)

      # a generator whose LAST statement is y.yield: #result is that yield's return
      # value -- the fed value, or nil if unfed -- not forced to nil like a `<<`
      t = Enumerator.new { |y| y.yield(1) }
      t.next
      begin; t.next; rescue StopIteration => ex; p ex.result; end   # nil (unfed)
      w = Enumerator.new { |y| y.yield(1) }
      w.next
      w.feed(:z)
      begin; w.next; rescue StopIteration => ex; p ex.result; end   # :z (fed)
    RUBY

    _(result).must_answer <<~'OUT'
      10
      10
      nil
      nil
      "feed value already set"
      :finished
      99
      99
      1
      1
      -1
      nil
      :z
    OUT
  end

  it "enumerator feed sets yield return" do
    result = ze0(<<~'RUBY')
      # #feed sets the value the paused y.yield returns on the next #next;
      # feeding twice before a #next raises TypeError; #feed answers nil.

      g = Enumerator.new { |y| got = y.yield(10); y << (got * 2) }
      p g.next
      g.feed(5)
      p g.next
      k = Enumerator.new { |y| y.yield(1) }
      k.next
      p k.feed(:x)
      m = Enumerator.new { |y| y.yield(1); y.yield(2) }
      m.next
      m.feed(:a)
      begin
        m.feed(:b)
      rescue => e
        p e.message
      end
    RUBY

    _(result).must_answer <<~'OUT'
      10
      10
      nil
      "feed value already set"
    OUT
  end

  it "enumerator generator capture" do
    result = ze0(<<~'RUBY')
      # A block-form Enumerator.new that captures enclosing locals builds a capture
      # struct handed to the generator. That struct must be GC-rooted before the
      # enumerator is allocated, or a collection triggered by the enumerator's own
      # allocation can reclaim it (use-after-free). Run under SPINEL_GC_STRESS=1 to
      # exercise the rooting. The captured values are routed through a method so they
      # are real captures, not constants.

      def counter(base, step)
        Enumerator.new do |y|
          v = base
          5.times do
            y << v
            v += step
          end
        end
      end

      e = counter(10, 3)
      p e.next
      p e.next
      p e.take(4)
      p counter(100, -5).first(3)

      # A capture that is itself heap-allocated (a string), to exercise scanning the
      # rooted capture struct's pointer fields.
      def labeler(prefix)
        Enumerator.new do |y|
          3.times { |i| y << "#{prefix}#{i}" }
        end
      end

      p labeler("x").to_a
    RUBY

    _(result).must_answer <<~'OUT'
      10
      13
      [10, 13, 16, 19]
      [100, 95, 90]
      ["x0", "x1", "x2"]
    OUT
  end

  it "enumerator generator each" do
    result = ze0(<<~'RUBY')
      # A fiber-backed generator Enumerator (Enumerator.new { |y| ... }) and a
      # materialized enumerator both drive a block via #each: each drains the source
      # once and yields every value. next/peek/to_a/first/take/rewind already worked;
      # this adds the eager block form.

      # --- generator #each over integers ---
      gen = Enumerator.new { |y| y << 1; y << 2; y << 3 }
      collected = []
      gen.each { |x| collected << x }
      p collected

      # --- generator #each over strings ---
      Enumerator.new { |y| y << "a"; y << "b" }.each { |s| puts s }

      # --- generator whose body loops a bounded number of times ---
      squares = Enumerator.new { |y| 4.times { |i| y << i * i } }
      sum = 0
      squares.each { |n| sum += n }
      p sum

      # --- generator yielding arrays, destructured in the block ---
      pairs = Enumerator.new { |y| y << [1, 10]; y << [2, 20]; y << [3, 30] }
      pairs.each { |k, v| p [k, v, k + v] }

      # --- y.yield form drives #each too ---
      via_yield = Enumerator.new { |y| y.yield(100); y.yield(200) }
      via_yield.each { |n| p n }

      # --- the eager terminals still work alongside #each ---
      e = Enumerator.new { |y| y << 1; y << 2; y << 3 }
      p e.next
      p e.next
      e.rewind
      p e.to_a
      p e.first(2)
      p e.take(2)

      # --- an infinite generator is still bounded by first/take (no hang) ---
      naturals = Enumerator.new { |y| i = 0; loop { y << i; i += 1 } }
      p naturals.first(5)
      p naturals.take(3)

      # --- materialized enumerators drive #each as well ---
      ["x", "y", "z"].each.each { |c| print c }
      puts

      got = []
      [10, 20, 30].each.each { |n| got << n * 2 }
      p got

      "hi".each_char.each { |ch| p ch }
    RUBY

    _(result).must_answer <<~'OUT'
      [1, 2, 3]
      a
      b
      14
      [1, 10, 11]
      [2, 20, 22]
      [3, 30, 33]
      100
      200
      1
      2
      [1, 2, 3]
      [1, 2]
      [1, 2]
      [0, 1, 2, 3, 4]
      [0, 1, 2]
      xyz
      [20, 40, 60]
      "h"
      "i"
    OUT
  end

  it "enumerator generator lazy" do
    result = ze0(<<~'RUBY')
      # A lazy pipeline over a generator Enumerator streams values one at a time, so an
      # infinite generator is bounded by a downstream first(n) / take_while without
      # materializing the whole (unbounded) source. Finite generators and materialized
      # enumerators lazily evaluate the same way.

      # --- infinite generator, bounded by first(n) ---
      naturals = Enumerator.new { |y| i = 0; loop { y << i; i += 1 } }
      p naturals.lazy.map { |x| x * 2 }.first(3)
      p naturals.lazy.select { |x| x.even? }.first(4)
      p naturals.lazy.reject { |x| x.even? }.first(3)

      # --- chained ops on an infinite generator ---
      p naturals.lazy.map { |x| x * x }.select { |x| x.odd? }.first(3)
      p naturals.lazy.map { |x| x + 1 }.map { |x| x * 10 }.first(3)

      # --- take_while forces to a finite prefix ---
      p naturals.lazy.take_while { |x| x < 5 }.to_a
      p naturals.lazy.map { |x| x * x }.take_while { |x| x < 30 }.to_a

      # --- finite generator: map/select to_a and first ---
      finite = Enumerator.new { |y| y << 1; y << 2; y << 3; y << 4 }
      p finite.lazy.map { |x| x * 10 }.to_a
      p finite.lazy.select { |x| x > 1 }.first(2)
      p finite.lazy.map { |x| x * x }.reject { |x| x > 9 }.to_a

      # --- generator yielding strings ---
      words = Enumerator.new { |y| %w[apple berry cherry date].each { |w| y << w } }
      p words.lazy.map { |w| w.upcase }.first(2)
      p words.lazy.select { |w| w.length > 4 }.to_a

      # --- materialized enumerators lazily too ---
      p [1, 2, 3, 4, 5, 6].each.lazy.map { |x| x * 2 }.select { |x| x > 4 }.first(2)
      p "abcdef".each_char.lazy.map { |c| c.upcase }.first(3)
    RUBY

    _(result).must_answer <<~'OUT'
      [0, 2, 4]
      [0, 2, 4, 6]
      [1, 3, 5]
      [1, 9, 25]
      [10, 20, 30]
      [0, 1, 2, 3, 4]
      [0, 1, 4, 9, 16, 25]
      [10, 20, 30, 40]
      [2, 3]
      [1, 4, 9]
      ["APPLE", "BERRY"]
      ["apple", "berry", "cherry"]
      [6, 8]
      ["A", "B", "C"]
    OUT
  end

  it "enumerator idiom return self" do
    result = ze0(<<~'RUBY')
      # `return to_enum(:each) unless block_given?` … `self`: each emission decides
      # block_given? statically, so one of the two paths is dead -- but it was still
      # emitted, and its value had to fit the other path's slot. The receiver landed
      # in an Enumerator-typed result and the C compiler warned on every such method
      # (#3953).
      class Box
        include Enumerable
        def each
          return to_enum(:each) unless block_given?

          yield 1
          yield 2
          self
        end
        def to_a2 = each.to_a
      end

      p Box.new.each.to_a
      Box.new.each { |x| p x }
      p Box.new.map { |x| x * 3 }
      p Box.new.to_a2
      p Box.new.each.next
      p Box.new.select { |x| x > 1 }
      p Box.new.each_with_index.to_a
      p Box.new.include?(2)
      p Box.new.each.take(1)

      # a generator-backed Enumerator answers the span methods by draining first
      e = Box.new.each
      p [e.take(1), e.drop(1), e.first(2)]
      en = Enumerator.new { |y| y << 4; y << 5; y << 6 }
      p [en.take(2), en.drop(2)]
    RUBY

    _(result).must_answer <<~'OUT'
      [1, 2]
      1
      2
      [3, 6]
      [1, 2]
      1
      [2]
      [[1, 0], [2, 1]]
      true
      [1]
      [[1], [2], [1, 2]]
      [[4, 5], [6]]
    OUT
  end

  it "enumerator in container" do
    result = ze0(<<~'RUBY')
      e = [1, 2].each
      a = [e]
      p a[0].to_a
      e2 = [1, 2].each; h = { k: e2 }
      p h[:k].to_a
      e3 = [1, 2].each; [e3].each { |x| p x.to_a }
      e4 = [1, 2].each; a4 = [e4]
      p a4[0].next
      e5 = [1, 2].each
      p e5.to_a
      p e5.next
      n = [5]
      p n[0].next
      s = ["az"]
      p s[0].next
      p s[0].succ
    RUBY

    _(result).must_answer <<~'OUT'
      [1, 2]
      [1, 2]
      [1, 2]
      1
      [1, 2]
      1
      6
      "ba"
      "ba"
    OUT
  end

  it "enumerator lazy" do
    result = ze0(<<~'RUBY')
      # Enumerator::Lazy over an integer range or array: the whole chain of
      # map/select/reject/filter/take_while fuses into one loop that pulls only as
      # many elements as the terminal (first(n) / take(n) / to_a / force) needs, so an
      # endless range works.

      p (1..Float::INFINITY).lazy.map { |x| x * 2 }.first(5)
      p (1..Float::INFINITY).lazy.select { |x| x.even? }.first(3)
      p (1..).lazy.select { |x| x % 3 == 0 }.first(4)

      # chained transforms
      p (1..10).lazy.map { |x| x * x }.select { |x| x > 10 }.first(2)
      p (1..100).lazy.select { |x| x.even? }.map { |x| x * 10 }.first(3)
      p (1..20).lazy.reject { |x| x.even? }.first(5)

      # array source + to_a / take
      p [1, 2, 3, 4].lazy.map { |x| x + 1 }.to_a
      p [10, 20, 30, 40, 50].lazy.select { |x| x > 25 }.to_a
      p (1..10).lazy.take_while { |x| x < 5 }.to_a

      # first with no count still returns a single element (existing path)
      p (1..Float::INFINITY).lazy.select { |x| x > 100 }.first
    RUBY

    _(result).must_answer <<~'OUT'
      [2, 4, 6, 8, 10]
      [2, 4, 6]
      [3, 6, 9, 12]
      [16, 25]
      [20, 40, 60]
      [1, 3, 5, 7, 9]
      [2, 3, 4, 5]
      [30, 40, 50]
      [1, 2, 3, 4]
      101
    OUT
  end

  it "enumerator lazy take while" do
    result = ze0(<<~'RUBY')
      # `take_while` and `find` terminate over an endless Enumerator -- one built by
      # `Enumerator.produce`, and one whose generator block is an unbounded `loop`.
      # Neither needs `.lazy` to do it: the EAGER Enumerable methods stop the source
      # too, via the same break the lazy pipeline's `Flow::Stop` uses.
      #
      p(Enumerator.produce(1) { |n| n + 1 }.take_while { |n| n < 5 })
      p(Enumerator.new { |y| i = 0; loop { y << (i += 1) } }.take_while { |n| n < 4 })
      p([1, 2, 3].each.take_while { |n| n < 3 })
      p(Enumerator.produce(1) { |n| n + 1 }.find { |n| n > 3 })
      p([1, 2, 3].each.take_while { |n| n > 9 })
    RUBY

    _(result).must_answer <<~'OUT'
      [1, 2, 3, 4]
      [1, 2, 3]
      [1, 2]
      4
      []
    OUT
  end

  it "enumerator new" do
    result = ze0(<<~'RUBY')
      # Enumerator.new { |y| ... } is a fiber-backed external generator: `y << v`,
      # `y.yield(v)` and the bare `y.yield v` (no parentheses) all produce values
      # lazily, #next / #peek walk them, the generator terminates with StopIteration,
      # and #rewind restarts it. Works with infinite generators via #take / #first.
      # (See enumerator_bare_yield.rb for the no-parentheses form.)

      e = Enumerator.new do |y|
        y << 1
        y.yield(2)
        y << 3
      end
      p e.class
      p e.next
      p e.peek        # does not advance
      p e.next
      p e.next
      begin
        e.next
      rescue StopIteration
        puts "stopped"
      end
      e.rewind
      p e.next        # back to the start

      # An infinite generator + take / first (a fresh run each time, independent of
      # the #next cursor).
      fib = Enumerator.new do |y|
        a, b = 0, 1
        loop { y << a; a, b = b, a + b }
      end
      p fib.take(8)
      p fib.first(5)
      p fib.next
      p fib.next

      # A generator that captures an outer (read-only) value.
      base = 100
      g = Enumerator.new do |y|
        y << base
        y << base + 1
        y << base + 2
      end
      p g.take(3)
      p g.next
      p g.next

      # is_a? / class
      p e.is_a?(Enumerator)
    RUBY

    _(result).must_answer <<~'OUT'
      Enumerator
      1
      2
      2
      3
      stopped
      1
      [0, 1, 1, 2, 3, 5, 8, 13]
      [0, 1, 1, 2, 3]
      0
      1
      [100, 101, 102]
      100
      101
      true
    OUT
  end

  it "enumerator ops" do
    result = ze0(<<~'RUBY')
      # Enumerator ops: chained each_with_index, +, next_values/peek_values, product
      # (#2487, #2481, #2482, #2484)
      e = [10, 20].each.each_with_index
      e.each { |x, i| p [x, i] }            # 2487
      a = [1, 2].each; b = [3, 4].each
      p((a + b).to_a)                        # 2481
      c = [1, 2].each
      p(c.next_values)                       # 2482
      p(c.peek_values)
      p(Enumerator.product([1, 2], [3, 4]).to_a)          # 2484
      p(Enumerator.product([1, 2], [3], [4, 5]).to_a)     # 2484 (3 args)
    RUBY

    _(result).must_answer <<~'OUT'
      [10, 0]
      [20, 1]
      [1, 2, 3, 4]
      [1]
      [2]
      [[1, 3], [1, 4], [2, 3], [2, 4]]
      [[1, 3, 4], [1, 3, 5], [2, 3, 4], [2, 3, 5]]
    OUT
  end

  it "enumerator produce" do
    result = ze0(<<~'RUBY')
      # Enumerator.produce -> a fiber-backed infinite generator (#2483)
      e = Enumerator.produce(1) { |n| n * 2 }
      p(e.take(3))
      p(Enumerator.produce(1) { |n| n + 1 }.first(4))
      g = Enumerator.produce(0) { |n| n + 2 }
      p(g.next)
      p(g.next)
      p([Enumerator.produce(2) { |n| n * n }.take(3)])
    RUBY

    _(result).must_answer <<~'OUT'
      [1, 2, 4]
      [1, 2, 3, 4]
      0
      2
      [[2, 4, 16]]
    OUT
  end

  it "enumerator produce pair" do
    result = ze0(<<~'RUBY')
      p(Enumerator.produce([0, 1]) { |a, b| [b, a] }.first(2))
      p(Enumerator.produce([0, 1]) { |a, b| [b, a + b] }.take(5))
      p(Enumerator.produce(1) { |n| n + 1 }.first(3))
    RUBY

    _(result).must_answer <<~'OUT'
      [[0, 1], [1, 0]]
      [[0, 1], [1, 1], [1, 2], [2, 3], [3, 5]]
      [1, 2, 3]
    OUT
  end

  it "enumerator produce stop iteration" do
    result = ze0(<<~'RUBY')
      # `StopIteration` raised inside a block that an Enumerator is driving ENDS the
      # enumeration; it is not an error. zeo lets it escape from
      # `Enumerator.produce`, so the idiomatic "generate until done" loop aborts the
      # program instead of returning what it produced.
      #
      # `Enumerator.produce` exists to build a sequence from a step function, and
      # raising `StopIteration` from that function is the documented way to say the
      # sequence has ended (it is the only way -- `produce` has no length and no
      # terminating predicate). Ruby catches it in the enumeration driver, the same
      # place `loop` catches it.
      #
      # zeo already handles the sibling case: `loop` DOES stop on a StopIteration
      # from `next`, which is the line at the end here. What is missing is the same
      # catch around the block `produce` calls.

      p Enumerator.produce(1) { |x| raise StopIteration if x > 3; x + 1 }.to_a

      p Enumerator.produce([0, 1]) { |a, b| raise StopIteration if b > 20; [b, a + b] }
           .map(&:first).to_a

      e = Enumerator.produce(1) { |x| x + 1 }
      p [e.next, e.next]

      # `loop` already swallows it, from an enumerator that ran out.
      src = [1, 2].each
      n = 0
      loop { src.next; n += 1 }
      p n
    RUBY

    _(result).must_answer <<~'OUT'
      [1, 2, 3, 4]
      [0, 1, 1, 2, 3, 5, 8, 13]
      [1, 2]
      2
    OUT
  end

  it "enumerator records alias name" do
    result = ze0(<<~'RUBY')
      p [1, 2].collect.inspect
      p [1, 2].filter.inspect
      p [1, 2].find_all.inspect
      p({ a: 1 }.each_pair.inspect)
      p({ a: 1 }.keep_if.inspect)
    RUBY

    _(result).must_answer <<~'OUT'
      "#<Enumerator: [1, 2]:collect>"
      "#<Enumerator: [1, 2]:filter>"
      "#<Enumerator: [1, 2]:find_all>"
      "#<Enumerator: {a: 1}:each_pair>"
      "#<Enumerator: {a: 1}:keep_if>"
    OUT
  end

  it "enumerator result source" do
    result = ze0(<<~'RUBY')
      # A materialized enumerator (a blockless builtin iterator) carries its iterated
      # receiver, so a past-the-end StopIteration reports it as #result -- matching
      # CRuby, where e.g. Array#each returns the array. The receiver is threaded
      # through every array/hash constructor (each / each_slice / each_cons /
      # each_with_index / each_index / with_index) and the hash pair iterator.
      #
      # Note: Range#each (lowered to an integer-array snapshot) and String#each_char
      # (built directly from items) do not carry the original range/string, so their
      # #result is the materialized collection / nil -- a minor documented divergence.

      def result_of(en)
        en.next while true
      rescue StopIteration => e
        e.result
      end

      p result_of([1, 2, 3].each)
      p result_of([10, 20].each)
      p result_of([1, 2, 3, 4].each_slice(2))
      p result_of([1, 2, 3, 4].each_cons(2))
      p result_of([5, 6, 7].each_with_index)
      p result_of([5, 6, 7].each_index)
      p result_of({ "a" => 1, "b" => 2 }.each)
      p result_of([9, 8, 7].each.with_index)

      # a generator's #result is its own body value, not a receiver
      g = Enumerator.new { |y| y << 1; :done }
      p result_of(g)
    RUBY

    _(result).must_answer <<~'OUT'
      [1, 2, 3]
      [10, 20]
      [1, 2, 3, 4]
      [1, 2, 3, 4]
      [5, 6, 7]
      [5, 6, 7]
      {"a" => 1, "b" => 2}
      [9, 8, 7]
      :done
    OUT
  end

  it "enumerator size" do
    result = ze0(<<~'RUBY')
      # Enumerator#size: the size protocol that never iterates. A materialized
      # enumerator (a blockless builtin #each / each_slice / each_cons) reports its
      # snapshot length; a fiber-backed generator (Enumerator.new) reports the size it
      # was given -- nil when none, a stored value (Integer / Float::INFINITY), or the
      # result of a stored callable (Proc/lambda), which #size calls lazily.

      # --- a generator with no size -> nil ---
      p Enumerator.new { |y| y << 1 }.size

      # --- native materialized enumerators report their length ---
      p [10, 20, 30].each.size
      p [1, 2, 3, 4].each_slice(2).size
      p [1, 2, 3, 4].each_cons(2).size

      # --- Enumerator.new(size) { |y| }: value / infinity ---
      p Enumerator.new(5) { |y| y << 1 }.size
      p Enumerator.new(Float::INFINITY) { |y| y << 1 }.size

      # --- a stored callable size, called lazily by #size ---
      p Enumerator.new(lambda { 42 }) { |y| y << 1 }.size
      p Enumerator.new(proc { 7 }) { |y| y << 1 }.size

      # a size callable closing over a local
      n = 9
      p Enumerator.new(-> { n * 2 }) { |y| y << 1 }.size

      # --- #size never iterates the body ---
      e = Enumerator.new(3) { |y| raise "size must not iterate"; y << 1 }
      p e.size

      # --- a generator with an explicit size still iterates normally ---
      g = Enumerator.new(2) { |y| y << :a; y << :b }
      p g.size
      p g.to_a
      p g.size
    RUBY

    _(result).must_answer <<~'OUT'
      nil
      3
      2
      3
      5
      Infinity
      42
      7
      18
      3
      2
      [:a, :b]
      2
    OUT
  end

  it "enumerator size is lazy and oracle faithful" do
    result = ze0(<<~'RUBY')
      # `size` never iterates: receiver-derived for the same-size set, computed
      # for times/upto/each_slice, the stored hint for Enumerator.new, nil when
      # unknowable.

      p [1, 2, 3].each.size
      p [1, 2, 3].select.size
      p 5.times.size
      p 2.upto(9).size
      p [1, 2, 3].each_slice(2).size
      p "abc".each_char.size
      p Enumerator.new { |y| y << 1 }.size
      p Enumerator.new(4) { |y| y << 1 }.size
    RUBY

    _(result).must_answer <<~'OUT'
      3
      3
      5
      8
      2
      3
      nil
      4
    OUT
  end

  it "enumerator to a" do
    result = ze0(<<~'RUBY')
      # A bare (blockless) enumerator materializes with #to_a / #entries.
      # Array#each, Array#reverse_each, and String#each_char return an external
      # Enumerator; #to_a drains it into an array. Receivers are routed through a
      # method param to exercise the runtime path rather than a folded constant.
      # Distinct per-type helpers keep each one monomorphic (a shared helper would
      # go polymorphic and lose the receiver's type).
      def ints(x); x; end
      def strs(x); x; end
      def flts(x); x; end
      def str(x); x; end

      p ints([1, 2, 3]).each.to_a
      p ints([1, 2, 3]).each.entries
      p ints([1, 2, 3]).reverse_each.to_a
      p strs(["a", "b", "c"]).reverse_each.to_a
      p flts([1.5, 2.5]).each.to_a
      p str("abc").each_char.to_a
      p str("café").each_char.to_a

      # reverse_each materializes a snapshot; the receiver is not mutated
      nm = ints([1, 2, 3])
      p nm.reverse_each.to_a
      p nm

      # directly-typed empty array
      p [].each.to_a

      # to_a result is an ordinary array
      p ints([1, 2, 3]).each.to_a.map { |x| x * 2 }

      # a generator Enumerator also drains
      e = Enumerator.new { |y| y << 10; y << 20 }
      p e.to_a

      # the blockful forms are unchanged
      acc = []
      [1, 2, 3].reverse_each { |x| acc << x }
      p acc
      p "hi".each_char { |ch| }
    RUBY

    _(result).must_answer <<~'OUT'
      [1, 2, 3]
      [1, 2, 3]
      [3, 2, 1]
      ["c", "b", "a"]
      [1.5, 2.5]
      ["a", "b", "c"]
      ["c", "a", "f", "é"]
      [3, 2, 1]
      [1, 2, 3]
      []
      [2, 4, 6]
      [10, 20]
      [3, 2, 1]
      "hi"
    OUT
  end

  it "enumerator to s is the address form" do
    result = ze0(<<~'RUBY')
      # `Enumerator#to_s` is `Object#to_s` -- ruby never overrides it, so an
      # enumerator printed with `puts` or interpolated into a string shows its
      # address, and only `inspect` describes what it iterates. zeo renders both the
      # same way, from one shared row (`enumerator.rs`) and one arm in
      # `value.rs`'s `to_display_string`.
      #
      # It reads like a nicety until a program prints an enumerator INSIDE a string
      # it then parses or compares: the inspect form carries the receiver's own
      # inspect, so the text grows without bound for a nested chain, where ruby's
      # stays one short token.
      #
      # `Enumerator::Lazy#to_s` already answers the address form
      # (`tests/lazy_external_iteration.rb`), so the two halves of one rule
      # currently disagree with each other as well as with ruby.

      def norm(s) = s.sub(/0x\h+/, "0xADDR")

      e = (1..3).each
      puts norm(e.to_s)
      puts norm("#{e}")
      puts e.inspect

      c = [1, 2].each_slice(1)
      puts norm(c.to_s)
      puts c.inspect
    RUBY

    _(result).must_answer <<~'OUT'
      #<Enumerator:0xADDR>
      #<Enumerator:0xADDR>
      #<Enumerator: 1..3:each>
      #<Enumerator:0xADDR>
      #<Enumerator: [1, 2]:each_slice(1)>
    OUT
  end

  it "enumerator wave10" do
    result = ze0(<<~'RUBY')
      # lazy filter_map / flat_map (finite + infinite sources, array sources)
      p([1, 2, 3, 4].lazy.filter_map { |x| x }.to_a)
      p([1, 2, 3].lazy.flat_map { |x| [x, x] }.to_a)
      p((1..).lazy.flat_map { |x| [x, -x] }.first(5))
      p((1..).lazy.filter_map { |x| x * 2 if x.odd? }.first(4))
      p([1, 2, 3, 4].lazy.filter_map { |x| x if x.even? }.to_a)
      p([[1, 2], [3]].lazy.flat_map { |a| a }.to_a)
      # Enumerator#inspect / class
      e = [1, 2, 3].each
      p(e)
      p e.inspect
      p [4, 5].reverse_each
      p((1..3).each)
      p [1, 2, 3].each_slice(2)
      p((1..3).each.class)
      # stored-enumerator with_index / with_object
      ei = [1, 2, 3].each
      ei.with_index(10) { |x, i| p [x, i] }
      ei2 = [1, 2, 3].each
      ei2.with_index { |x, i| p [x, i] }
      eo = [4, 5].each
      p eo.with_object([]) { |x, acc| acc << x * 2 }
      p eo.with_object({}) { |x, h| h[x] = x * x }
    RUBY

    _(result).must_answer <<~'OUT'
      [1, 2, 3, 4]
      [1, 1, 2, 2, 3, 3]
      [1, -1, 2, -2, 3]
      [2, 6, 10, 14]
      [2, 4]
      [1, 2, 3]
      #<Enumerator: [1, 2, 3]:each>
      "#<Enumerator: [1, 2, 3]:each>"
      #<Enumerator: [4, 5]:reverse_each>
      #<Enumerator: 1..3:each>
      #<Enumerator: [1, 2, 3]:each_slice(2)>
      Enumerator
      [1, 10]
      [2, 11]
      [3, 12]
      [1, 0]
      [2, 1]
      [3, 2]
      [8, 10]
      {4 => 16, 5 => 25}
    OUT
  end

  it "enumerator with index gc" do
    result = ze0(<<~'RUBY')
      # A blockless <enum>.with_index materializes [element, index] pairs from the
      # source enumerator's snapshot. The source (a temporary `arr.each` /
      # `str.each_char` enumerator) must stay rooted while the pairs are built --
      # otherwise a collection during the build frees it and reads go out of bounds.
      p [10, 20, 30].each.with_index.to_a
      p [1, 2, 3, 4].each.with_index(1).to_a
      p [5, 6].each.with_index.size
      p "abc".each_char.with_index.to_a
      p (1..4).to_a.each.with_index.map { |x, i| x * 10 + i }
    RUBY

    _(result).must_answer <<~'OUT'
      [[10, 0], [20, 1], [30, 2]]
      [[1, 1], [2, 2], [3, 3], [4, 4]]
      2
      [["a", 0], ["b", 1], ["c", 2]]
      [10, 21, 32, 43]
    OUT
  end

  it "enumerator yielder forms" do
    result = ze0(<<~'RUBY')
      p(Enumerator.new { |y| y << 1 << 2 }.to_a)
      p(Enumerator.new { |y| y << "a" << "b" }.to_a)
      p(Enumerator.new { |y| (y << 1) << 2 }.to_a)
      p(Enumerator.new { |y| y << 1 << 2 << 3 }.to_a)
      p(Enumerator.new { |y| [1, 2, 3].each(&y) }.to_a)
      p(Enumerator.new { |y| [1, 2].map(&y) }.to_a)
      p(Enumerator.new { |y| (1..3).each(&y) }.first(2))
      e = Enumerator.new { |y| [10, 20].each(&y) }
      p e.next
      p e.next
    RUBY

    _(result).must_answer <<~'OUT'
      [1, 2]
      ["a", "b"]
      [1, 2]
      [1, 2, 3]
      [1, 2, 3]
      [1, 2]
      [1, 2]
      10
      20
    OUT
  end

  it "enumerators" do
    result = ze0(<<~'RUBY')
      # Phase 17.2 -- the fiber-backed Enumerator (per CRuby's enumerator.c):
      # blockless iteration methods return real Enumerators, external iteration
      # (#next/#peek) suspends a coroutine per element, StopIteration carries the
      # iteration's result, and Kernel#loop swallows it.

      e = [10, 20, 30].each
      p e
      r = loop do
        puts e.next
      end
      p r

      e2 = [1, 2].each
      p e2.peek
      p e2.peek
      p e2.next
      p e2.next
      begin
        e2.next
      rescue StopIteration => ex
        puts "done: #{ex.message}"
        p ex.result
      end
      e2.rewind
      p e2.next

      # Blockless breadth, chained through Enumerable.
      p [1, 2, 3].map
      p [1, 2, 3].map.each { |x| x * 3 }
      p 5.times.to_a
      p 2.upto(5).to_a
      p (1..10).step(3).to_a
      p "hey".each_char.to_a
      p({ a: 1, b: 2 }.each_value.to_a)
      p %w[a b c].each_with_index.to_a
      p [10, 20].map.with_index { |x, i| x * i }
      p [10, 20].each.with_index(5).to_a
      p [4, 2, 6].each.sort
      p [1, 2].each.with_object([]) { |x, memo| memo << x * 2 }

      # Enumerator.new: the generator/Yielder pair, lazy even when infinite.
      squares = Enumerator.new do |y|
        n = 1
        loop do
          y << n * n
          n += 1
        end
      end
      p squares.next
      p squares.next
      p squares.take(5)
      p squares.first(3)

      pairs = Enumerator.new { |y| y.yield 1, 2 }
      p pairs.next_values
      pairs.rewind
      p pairs.next

      # size never iterates.
      p [1, 2, 3].each.size
      p 5.times.size
      p [1, 2, 3].each_slice(2).size
      p Enumerator.new(4) { |y| y << 1 }.size

      # to_enum on a user class -- the real-Ruby blockless-each pattern.
      class Deck
        include Enumerable
        def initialize(cards)
          @cards = cards
        end
        def each
          return to_enum(:each) unless block_given?
          i = 0
          while i < @cards.length
            yield @cards[i]
            i += 1
          end
          self
        end
      end
      d = Deck.new([5, 3, 9])
      p d.each.next
      p d.each.sort
      p d.map.with_index { |c, i| "#{i}:#{c}" }

      # Struct's synthesized each uses the same pattern.
      Point = Struct.new(:x, :y)
      en = Point.new(1, 2).each
      p en.class
      p en.to_a

      p(loop { break 42 })
      p(loop { raise StopIteration })
    RUBY

    _(result).must_answer <<~'OUT'
      #<Enumerator: [10, 20, 30]:each>
      10
      20
      30
      [10, 20, 30]
      1
      1
      1
      2
      done: iteration reached an end
      [1, 2]
      1
      #<Enumerator: [1, 2, 3]:map>
      [3, 6, 9]
      [0, 1, 2, 3, 4]
      [2, 3, 4, 5]
      [1, 4, 7, 10]
      ["h", "e", "y"]
      [1, 2]
      [["a", 0], ["b", 1], ["c", 2]]
      [0, 20]
      [[10, 5], [20, 6]]
      [2, 4, 6]
      [2, 4]
      1
      4
      [1, 4, 9, 16, 25]
      [1, 4, 9]
      [1, 2]
      [1, 2]
      3
      5
      2
      4
      5
      [3, 5, 9]
      ["0:5", "1:3", "2:9"]
      Enumerator
      [1, 2]
      42
      nil
    OUT
  end

  it "enumerators chain and are enumerable" do
    result = ze0(<<~'RUBY')
      # Chaining: with_index/each_with_index wrap (blockless) and drive
      # (block-given), an Enumerator is itself Enumerable (reduce/sort/select
      # arrive via the real ancestor chain), and with_object threads its memo.

      e = ["a", "b", "c"].each_with_index
      p e.class
      p e.to_a
      p [10, 20].map.with_index { |x, i| x * i }
      p [10, 20].each.with_index(5).to_a
      p [4, 2, 6].each.reduce { |a, b| a + b }
      p [4, 2, 6].each.sort
      p [1, 2, 3, 4].each.select { |x| x.even? }
      p [1, 2].each.with_object([]) { |x, memo| memo << x * 2 }
    RUBY

    _(result).must_answer <<~'OUT'
      Enumerator
      [["a", 0], ["b", 1], ["c", 2]]
      [0, 20]
      [[10, 5], [20, 6]]
      12
      [2, 4, 6]
      [2, 4]
      [2, 4]
    OUT
  end

  it "external enumerator user object" do
    result = ze0(<<~'RUBY')
      # An external enumerator over a user object. sp_enum_items_from -- which is
      # what materializes an enumerator's elements -- had arms for every builtin
      # container and none for a user object, so it answered the EMPTY array and
      # `v.each.take(3)` yielded nothing (#4022).
      #
      # The report needed a `&:sym` map over an Array of the same class to see it:
      # that is what makes the object arrive boxed here rather than through a
      # spliced loop.
      class Box
        include Enumerable

        attr_reader :size

        def initialize(items)
          @items = items
          @size = items.size
        end

        def each
          return to_enum(:each) unless block_given?

          @items.each { |i| yield i }
          self
        end
      end

      boxes = [Box.new([0, 1]), Box.new([0, 1, 4, 9])]
      p boxes.map(&:size)
      v = boxes.last
      p v.each.take(3)
      p v.each.to_a
      p v.each.first(2)
      p v.to_a
      p v.map { |x| x * 2 }

      # and the same object without the map line ahead of it
      w = Box.new([7, 8, 9])
      p w.each.take(2)
    RUBY

    _(result).must_answer <<~'OUT'
      [2, 4]
      [0, 1, 4]
      [0, 1, 4, 9]
      [0, 1]
      [0, 1, 4, 9]
      [0, 2, 8, 18]
      [7, 8]
    OUT
  end

  it "ivar lazy init push via inherited getter" do
    result = ze0(<<~'RUBY')
      # #451: cross-class sequel to #430. The lazy-init getter
      # `def errors; @errors = [] if @errors.nil?; @errors; end` is
      # defined on a parent class; the push `errors << "..."` happens
      # from a child class method. Before the fix, scan_writer_calls
      # only inspected @current_class_idx for the getter, so the
      # parent's @errors stayed `sp_IntArray *` and the child's
      # String push failed C compile.

      class Base
        def errors
          @errors = [] if @errors.nil?
          @errors
        end
      end

      class Foo < Base
        def add_error(msg)
          errors << "#{msg} bad"
        end
      end

      f = Foo.new
      f.add_error("name")
      f.add_error("body")
      puts f.errors.length
      puts f.errors[0]
      puts f.errors[1]

      # Two levels of inheritance — getter on grandparent.
      class Tracker
        def events
          @events = [] if @events.nil?
          @events
        end
      end

      class TrackerMid < Tracker
      end

      class TrackerLeaf < TrackerMid
        def record(name)
          events << name
        end
      end

      t = TrackerLeaf.new
      t.record("a")
      t.record("b")
      puts t.events.length
      puts t.events.join(",")

      # Same-class case (post-#430) still works.
      class Same
        def items
          @items = [] if @items.nil?
          @items
        end

        def add(s)
          items << s
        end
      end

      s = Same.new
      s.add("x")
      s.add("y")
      puts s.items.join(":")
    RUBY

    _(result).must_answer <<~'OUT'
      2
      name bad
      body bad
      2
      a,b
      x:y
    OUT
  end

  it "lazy blockless take drop" do
    result = ze0(<<~'RUBY')
      # Enumerator::Lazy#take(n)/#drop(n) as blockless fused stages, including as the
      # first op before any block stage establishes an element type. Receivers are
      # routed through method params to exercise the runtime pipeline, not a fold.
      def take_only(a) = a.lazy.take(2).to_a
      p take_only([1, 2, 3, 4])

      def take_strs(a) = a.lazy.take(2).to_a
      p take_strs(%w[a b c d])

      def drop_only(a) = a.lazy.drop(1).to_a
      p drop_only([1, 2, 3, 4])

      def drop_then_map(a) = a.lazy.drop(1).map { |x| x * 10 }.to_a
      p drop_then_map([1, 2, 3, 4])

      def take_then_select(a) = a.lazy.take(4).select { |x| x.odd? }.to_a
      p take_then_select([1, 2, 3, 4, 5, 6])

      def map_then_take(a) = a.lazy.map { |x| x + 1 }.take(2).to_a
      p map_then_take([10, 20, 30, 40])

      def drop_take(a) = a.lazy.drop(2).take(2).to_a
      p drop_take([1, 2, 3, 4, 5, 6])

      def range_take(r) = r.lazy.take(3).to_a
      p range_take(1..100)

      def range_drop_first(r) = r.lazy.drop(2).first(2)
      p range_drop_first(1..100)

      def filtered_take(r) = r.lazy.select { |x| x.even? }.take(3).to_a
      p filtered_take(1..100)
    RUBY

    _(result).must_answer <<~'OUT'
      [1, 2]
      ["a", "b"]
      [2, 3, 4]
      [20, 30, 40]
      [1, 3]
      [11, 21]
      [3, 4]
      [1, 2, 3]
      [3, 4]
      [2, 4, 6]
    OUT
  end

  it "lazy crosses variable and method" do
    result = ze0(<<~'RUBY')
      # a lazy chain held in a local or returned from a method
      p [1, 2, 3].lazy.first
      p [1, 2, 3].lazy.first(2)
      p [1, 2, 3].lazy.to_a
      p ["a", "b"].lazy.first
      p (1..3).lazy.first

      z = [1, 2, 3].lazy
      p z.first
      y = [1, 2, 3].lazy
      p y.map { |i| i * 2 }.first
      x = (1..Float::INFINITY).lazy
      p x.select { |i| i % 3 == 0 }.first(2)

      def lz;  [1, 2, 3].lazy; end
      p lz.first
      p lz.class
      def lzr; (1..3).lazy; end
      p lzr.first
      def lzm; [1, 2, 3].lazy.map { |i| i * 2 }; end
      p lzm.first
      p lzm.to_a
    RUBY

    _(result).must_answer <<~'OUT'
      1
      [1, 2]
      [1, 2, 3]
      "a"
      1
      1
      2
      [3, 6]
      1
      Enumerator::Lazy
      1
      2
      [2, 4, 6]
    OUT
  end

  it "lazy enumerable private aliases" do
    result = ze0(<<~'RUBY')
      # Lazy's `_enumerable_*` privates: ruby snapshots the EAGER Enumerable
      # bodies onto Lazy before the lazy overrides land, then makes them private.
      lz = (1..5).lazy

      # Private, present, and correctly counted.
      p lz.class.private_instance_methods(false).grep(/\A_enumerable_/).sort.size
      p lz.respond_to?(:_enumerable_map)
      p lz.respond_to?(:_enumerable_map, true)

      # Each drives the EAGER body: an Array comes back, the chain runs at once.
      p lz.send(:_enumerable_map) { |x| x * 2 }
      p lz.send(:_enumerable_select, &:even?)
      p lz.send(:_enumerable_take, 2)
      p lz.send(:_enumerable_drop, 3)
      p lz.send(:_enumerable_grep, 2..3)
      p lz.send(:_enumerable_uniq)
      p lz.send(:_enumerable_zip, [9, 8, 7, 6, 5])
      p lz.send(:_enumerable_filter_map) { |x| x * 10 if x.odd? }

      # The odd one out snapshots Enumerator#with_index.
      p lz.send(:_enumerable_with_index, 10).to_a.first(2)

      # Visibility: a PUBLIC send refuses.
      begin
        lz.public_send(:_enumerable_map) { |x| x }
      rescue NoMethodError => e
        puts e.message.split("'").first + "'_enumerable_map'"
      end
    RUBY

    _(result).must_answer <<~'OUT'
      18
      false
      true
      [2, 4, 6, 8, 10]
      [2, 4]
      [1, 2]
      [4, 5]
      [2, 3]
      [1, 2, 3, 4, 5]
      [[1, 9], [2, 8], [3, 7], [4, 6], [5, 5]]
      [10, 30, 50]
      [[1, 10], [2, 11]]
      private method '_enumerable_map'
    OUT
  end

  it "lazy enumerator" do
    result = ze0(<<~'RUBY')
      # `Enumerable#lazy` returns an Enumerator::Lazy: a chain of transformations
      # that only runs on demand, so it can work over INFINITE sequences.

      # Only three elements are ever computed, even though the source is unbounded.
      p (1..Float::INFINITY).lazy.map { |x| x * 2 }.first(3)          # [2, 4, 6]
      p (1..Float::INFINITY).lazy.select(&:even?).first(3)            # [2, 4, 6]

      # Stages compose left to right and stay lazy until a terminal call.
      p (1..Float::INFINITY).lazy.select(&:even?).map { |x| x * x }.first(3)  # [4, 16, 36]

      # `take_while` bounds an infinite source; `to_a`/`force` then materializes it.
      p (1..Float::INFINITY).lazy.map { |x| x * x }.take_while { |x| x < 30 }.to_a  # [1, 4, 9, 16, 25]

      # take / drop / flat_map / uniq / compact / grep all have lazy forms.
      p (1..Float::INFINITY).lazy.take(5).to_a                        # [1, 2, 3, 4, 5]
      p [1, 2, 3, 4, 5, 6].lazy.drop(2).first(2)                      # [3, 4]
      p (1..Float::INFINITY).lazy.flat_map { |x| [x, -x] }.first(4)   # [1, -1, 2, -2]
      p [1, 1, 2, 3, 3, 1].lazy.uniq.to_a                             # [1, 2, 3]
      p [1, nil, 2, nil, 3].lazy.compact.to_a                         # [1, 2, 3]
      p (1..20).lazy.grep(5..10).to_a                                 # [5, 6, 7, 8, 9, 10]

      # A finite lazy is an ordinary enumerable once forced.
      p [1, 2, 3, 4].lazy.map { |x| x * 10 }.to_a                     # [10, 20, 30, 40]
      p [1, 2, 3].lazy.class.name                                     # "Enumerator::Lazy"
    RUBY

    _(result).must_answer <<~'OUT'
      [2, 4, 6]
      [2, 4, 6]
      [4, 16, 36]
      [1, 4, 9, 16, 25]
      [1, 2, 3, 4, 5]
      [3, 4]
      [1, -1, 2, -2]
      [1, 2, 3]
      [1, 2, 3]
      [5, 6, 7, 8, 9, 10]
      [10, 20, 30, 40]
      "Enumerator::Lazy"
    OUT
  end

  it "lazy enumerator hierarchy edges" do
    result = ze0(<<~'RUBY')
      # `Enumerator::Lazy < Enumerator` beyond the promoted gap shape: ancestry
      # answers, lazy zip semantics, and the inherited terminals.

      lz = (1..3).lazy

      # The reparent is visible to every ancestry question.
      p [lz.is_a?(Enumerator), lz.is_a?(Enumerable), lz.kind_of?(Enumerator::Lazy)]
      p(case lz when Enumerator then :enumerator_case end)

      # zip stays lazy on an ENDLESS receiver and pads with nil past a shorter
      # other's end.
      pairs = (1..Float::INFINITY).lazy.zip(%w[a b]).first(3)
      p pairs

      # zip size is the receiver's size.
      p (1..4).lazy.zip([9, 9]).size

      # zip composes with later links, still lazily.
      p (1..Float::INFINITY).lazy.zip([10, 20, 30]).map { |a, b| [a, b] }.first(2)

      # A block makes zip EAGER (the Enumerable row), answering nil like CRuby.
      got = []
      r = [1, 2].lazy.zip([3, 4]) { |pair| got << pair }
      p [r, got]

      # The inherited terminals drive the chain through Enumerator#each.
      doubled = (1..4).lazy.map { |x| x * 2 }
      p doubled.to_a
      p doubled.entries
      p doubled.first(2)
      p doubled.force

      # External iteration through the Enumerator rows, with a rewind restart.
      ext = (5..).lazy.select(&:even?)
      p [ext.next, ext.peek, ext.next]
      ext.rewind
      p ext.next

      # `eager` hands back a plain Enumerator over the same sequence.
      e = (1..3).lazy.map { |x| x + 1 }.eager
      p [e.class, e.to_a]

      # to_s stays the address form while inspect prints the chain.
      s = (1..2).lazy.map(&:to_s)
      p s.to_s.sub(/0x[0-9a-f]+/, "0xADDR")
      p s.inspect.include?("map")
    RUBY

    _(result).must_answer <<~'OUT'
      [true, true, true]
      :enumerator_case
      [[1, "a"], [2, "b"], [3, nil]]
      4
      [[1, 10], [2, 20]]
      [nil, [[1, 3], [2, 4]]]
      [2, 4, 6, 8]
      [2, 4, 6, 8]
      [2, 4]
      [2, 4, 6, 8]
      [6, 8, 8]
      6
      [Enumerator, [2, 3, 4]]
      "#<Enumerator::Lazy:0xADDR>"
      true
    OUT
  end

  it "lazy enumerator over infinite and finite sources" do
    result = ze0(<<~'RUBY')
      p (1..Float::INFINITY).lazy.select(&:even?).map { |x| x * x }.first(3)
      p [1, 2, 3, 4].lazy.map { |x| x + 1 }.to_a
      p [1, 2, 3].lazy.class.name
    RUBY

    _(result).must_answer <<~'OUT'
      [4, 16, 36]
      [2, 3, 4, 5]
      "Enumerator::Lazy"
    OUT
  end

  it "lazy external iteration" do
    result = ze0(<<~'RUBY')
      # An `Enumerator::Lazy` IS an Enumerator, so it answers `next`/`peek` and
      # iterates one element at a time on demand. zeo's lazy has no `next`
      # (`NoMethodError`), which removes the only way to consume an infinite lazy
      # chain incrementally rather than in `first(n)`-sized bites.
      #
      # `inspect` is the same omission seen from outside: ruby describes the chain it
      # has built -- `#<Enumerator::Lazy: #<Enumerator::Lazy: 1..3>:map>` -- so a
      # lazy value printed in a log or a debugger says what it will produce. zeo
      # answers a bare `#<Enumerator::Lazy>` for every one.
      #
      # The eager Enumerator already has both (`[1,2].each.next` and its inspect both
      # answer correctly below), so the machinery exists and Lazy does not reach it.

      l = (1..).lazy.map { _1 * 2 }
      p l.next
      p l.next
      p l.peek

      p (1..3).lazy.map { _1 }.inspect
      p (1..3).lazy.select(&:odd?).inspect

      # The eager side already works.
      e = [1, 2].each
      p [e.next, e.peek]
      p [1, 2].each.inspect

      # ...and the bulk lazy operations are fine.
      p (1..Float::INFINITY).lazy.select(&:even?).first(3)
    RUBY

    _(result).must_answer <<~'OUT'
      2
      4
      6
      "#<Enumerator::Lazy: #<Enumerator::Lazy: 1..3>:map>"
      "#<Enumerator::Lazy: #<Enumerator::Lazy: 1..3>:select>"
      [1, 2]
      "#<Enumerator: [1, 2]:each>"
      [2, 4, 6]
    OUT
  end

  it "lazy is not an enumerator" do
    result = ze0(<<~'RUBY')
      # `Enumerator::Lazy < Enumerator` in ruby. In zeo it is a plain Object that
      # includes Enumerable, so the parallel hierarchy is flat and every method a
      # lazy shares with an ordinary enumerator has to be re-declared on `Lazy`
      # itself. What a program sees is `.owner` and `instance_methods(false)`
      # answering `Enumerator::Lazy` where ruby says `Enumerator` or `Enumerable`.
      #
      # The behaviour those rows carry is already right (`next`/`peek`/`inspect`
      # match -- `tests/lazy_external_iteration.rb` is the control), so this is the
      # SHAPE alone. Closing it means giving `RLazy` the `EnumeratorData` payload
      # every inherited `Enumerator` row downcasts to, which is a different object
      # than the source+chain a lazy actually holds.
      #
      # `zip` comes along for the ride: ruby overrides it on Lazy so it stays lazy,
      # while zeo answers the eager `Enumerable#zip` Array.

      p Enumerator::Lazy.superclass
      p Enumerator::Lazy.ancestors.first(3)

      %i[first each to_a inspect size next peek rewind force eager].each do |m|
        puts "#{m}: #{Enumerator::Lazy.instance_method(m).owner}"
      end

      p (1..3).lazy.zip([1, 2, 3]).inspect
    RUBY

    _(result).must_answer <<~'OUT'
      Enumerator
      [Enumerator::Lazy, Enumerator, Enumerable]
      first: Enumerable
      each: Enumerator
      to_a: Enumerable
      inspect: Enumerator
      size: Enumerator
      next: Enumerator
      peek: Enumerator
      rewind: Enumerator
      force: Enumerator::Lazy
      eager: Enumerator::Lazy
      "#<Enumerator::Lazy: #<Enumerator::Lazy: 1..3>:zip([1, 2, 3])>"
    OUT
  end

  it "lazy method block local" do
    result = ze0(<<~'RUBY')
      # A local assigned inside a .lazy block whose chain is spliced from a method
      # body has to be declared where the chain lands, not where it was written.
      def f
        ["a 5"].lazy.map { |l| q1 = l.split(" "); q1[0] }
      end
      p f.to_a

      def g
        [1, 2, 3].lazy.map { |n| d = n * 2; d + 1 }
      end
      p g.to_a
      p g.first

      def h
        ["x,y"].lazy.map { |s| parts = s.split(","); parts.last }
      end
      p h.first

      # the same chain inline still works
      p ["a 5"].lazy.map { |l| q = l.split(" "); q[0] }.to_a
    RUBY

    _(result).must_answer <<~'OUT'
      ["a"]
      [3, 5, 7]
      3
      "y"
      ["a"]
    OUT
  end

  it "lazy nested chain" do
    result = ze0(<<~'RUBY')
      p([1, 2].lazy.map { |x| [1, 2].lazy.map { |y| y }.to_a }.to_a)
      p((1..3).lazy.map { |x| (1..x).lazy.map { |y| y * 2 }.to_a }.to_a)
      p((1..3).lazy.map { |x| (1..x).lazy.to_a }.to_a)
      p([1, 2].lazy.map { |x| [3, 4].map { |y| y + x } }.to_a)
      p((1..4).lazy.select { |x| x.even? }.first(2))
    RUBY

    _(result).must_answer <<~'OUT'
      [[1, 2], [1, 2]]
      [[2], [2, 4], [2, 4, 6]]
      [[1], [1, 2], [1, 2, 3]]
      [[4, 5], [5, 6]]
      [2, 4]
    OUT
  end

  it "lazy new constructs a lazy" do
    result = ze0(<<~'RUBY')
      # Enumerator::Lazy.new(source) { |yielder, *values| ... } builds a lazy over
      # the source with an explicit per-element body. zeo has no `new` row on Lazy
      # (NoMethodError); the class is only reachable through #lazy. Belongs to the
      # lazy-reparent work tracked in lazy_is_not_an_enumerator.rb.
      gen = Enumerator::Lazy.new([1, 2, 3]) { |y, v| y << v * 100 }
      puts gen.first(2).inspect
      puts gen.class
      inf = Enumerator::Lazy.new(1..Float::INFINITY) { |y, v| y << v if v.odd? }
      puts inf.first(3).inspect
    RUBY

    _(result).must_answer <<~'OUT'
      [100, 200]
      Enumerator::Lazy
      [1, 3, 5]
    OUT
  end

  it "lazy size" do
    result = ze0(<<~'RUBY')
      # Enumerator::Lazy#size: source size propagated through the chain (#2485)
      p((1..10).lazy.size)                              # 10 (the filed repro)
      p([1, 2, 3].lazy.size)                            # 3
      p([].lazy.size)                                   # 0
      p([1, 2, 3].lazy.map { |x| x * 2 }.size)          # 3 (map preserves)
      p([1, 2, 3].lazy.select { |x| x > 1 }.size)       # nil (filter unknown)
      p([1, 2, 3].lazy.take(2).size)                    # 2
      p([1, 2, 3].lazy.take(5).size)                    # 3 (min)
      p([1, 2, 3, 4, 5].lazy.drop(1).take(2).size)      # 2
      p((1..Float::INFINITY).lazy.size)                 # Infinity
      p((1..Float::INFINITY).lazy.map { |x| x }.size)   # Infinity
      p((1..Float::INFINITY).lazy.take(3).size)         # 3 (take bounds)
      # the fused pipeline forcing terminals still work
      p((1..Float::INFINITY).lazy.map { |x| x * 2 }.first(3))
    RUBY

    _(result).must_answer <<~'OUT'
      10
      3
      0
      3
      nil
      2
      3
      2
      Infinity
      Infinity
      3
      [2, 4, 6]
    OUT
  end

  it "map recv emitted once" do
    result = ze0(<<~'RUBY')
      # #540. `n, m = gets.split.map &:to_i` emitted `gets` twice in
      # the generated C: once via compile_call_expr's pre-compute of
      # the call recv (`rc = compile_expr_gc_rooted(recv)`) and once
      # inside compile_map_expr's own `compile_expr(@nd_receiver[nid])`.
      # For pure-function recvs the duplicate is wasted work, but for
      # `gets` (and any other side-effecting call) it consumed two
      # lines of stdin per iteration -- the multi-assign got the
      # second line's values, then the next loop iteration consumed
      # two more lines, and the loop's `break if n == 0` check never
      # saw the intended `0 0` row.
      #
      # Fix: compile_call_expr threads its pre-computed `rc` through
      # compile_enumerable_expr to compile_map_expr (and a new
      # `precomputed_rc` param defaults to "" on the
      # compile_body_return tail path that still wants to compile the
      # recv itself). compile_map_expr uses the passed temp directly
      # but still SP_GC_ROOTs it -- compile_expr_gc_rooted skips the
      # root for non-CallNode recvs (ArrayNode literals like
      # `[10,20,30,40].map { ... }` reach us unrooted), so the
      # transient-root emit has to happen here.

      # Counter-style verifies side-effect-once. Each call to `next!`
      # bumps the counter; the test asserts the counter only moves by
      # the expected amount across the multi-assign.
      $counter = 0
      def next!
        $counter += 1
        $counter.to_s + " " + ($counter + 100).to_s
      end

      # Multi-assign over a side-effecting recv. `next!` returns the
      # string; the chain splits/maps it.
      a, b = next!.split.map { |x| x.to_i }
      puts a
      puts b
      puts $counter  # was 2 pre-fix (called twice); 1 post-fix.

      # Nested map with array-literal recv (the GC-rooting concern --
      # the recv temp is the literal, no other root holds it).
      TBL = [10, 20, 30, 40].map { |a| (0...8).map { |j| a + j } }
      puts TBL.length         # 4
      puts TBL[0].length      # 8
      puts TBL[0][0]          # 10
      puts TBL[3][7]          # 47
    RUBY

    _(result).must_answer <<~'OUT'
      1
      101
      1
      4
      8
      10
      47
    OUT
  end

  it "max by count tie order" do
    result = ze0(<<~'RUBY')
      # max_by(n) returns tied elements in encounter order, descending by key
      # (#3255): a plain backward walk over the stable ascending sort reversed
      # ties, and a pre-ordering tail cut picked later-encountered boundary ties.
      a = [["Bob", 92], ["Eve", 92], ["Ann", 88]]
      p a.max_by(2) { |x| x[1] }
      b = [["Bob", 92], ["Eve", 92], ["Ann", 88], ["Zed", 92], ["Kim", 95]]
      p b.max_by(3) { |x| x[1] }
      p b.max_by(0) { |x| x[1] }
      p [3, 1, 2].max_by(2) { |x| x }
      p [1, 2].min_by(1) { |x| x }
    RUBY

    _(result).must_answer <<~'OUT', linux: <<~'LINUX'
      [["Bob", 92], ["Eve", 92]]
      [["Kim", 95], ["Bob", 92], ["Eve", 92]]
      []
      [3, 2]
      [1]
    OUT
      [["Bob", 92], ["Eve", 92]]
      [["Kim", 95], ["Eve", 92], ["Bob", 92]]
      []
      [3, 2]
      [1]
    LINUX
  end

  it "reduce acc shadow" do
    result = ze0(<<~'RUBY')
      # Array#reduce: the accumulator block param's type must come from the
      # seed (init_val), not from the element type. infer_type(acc) inside
      # the block must follow the seed in both directions — pointer seed
      # (string) over a value-typed outer, and value seed (int) over a
      # pointer-typed outer.

      def f
        total = [1, 2, 3].reduce("") { |acc, x| acc + x.to_s }
        puts total   # 123
      end
      f

      # Outer same-named local of a different type must not leak into the block.
      def g
        acc = 99
        out = [10, 20, 30].reduce("=") { |acc, x| acc + x.to_s }
        puts out   # =102030
        puts acc   # 99
      end
      g

      # Reverse direction: int seed must shadow an outer string acc without
      # the outer binding leaking into the block's `acc + x` (which would
      # dispatch as string concat instead of mrb_int addition).
      def h
        acc = "outer"
        sum = [1, 2, 3, 4, 5].reduce(0) { |acc, x| acc + x }
        puts sum   # 15
        puts acc   # outer
      end
      h
    RUBY

    _(result).must_answer <<~'OUT'
      123
      =102030
      99
      15
      outer
    OUT
  end

  it "reduce nil seed" do
    result = ze0(<<~'RUBY')
      # reduce(nil) -- folding with no natural identity
      p [1, 2, 3].reduce(nil) { |acc, t| acc.nil? ? t : t + acc }
      p [1, 2, 3].reduce(nil) { |acc, t| acc.nil? ? t : acc + t }
      p ["a", "b"].reduce(nil) { |acc, t| acc.nil? ? t : acc + t }
      p [1, 2, 3].reduce(nil) { |acc, t| next t if acc.nil?; acc + t }
      p [1, 2, 3].inject(nil)  { |acc, t| acc.nil? ? t : acc + t }
      p [].reduce(nil) { |acc, t| acc.nil? ? t : acc + t }
      p [1, 2, 3].reduce(0) { |acc, t| acc + t }

      acc = nil
      [1, 2, 3].each { |t| acc = acc.nil? ? t : acc + t }
      p acc

      x = [nil, Rational(2)].last
      p Rational(1) / x
      y = [nil, 4].last
      p 8 / y
    RUBY

    _(result).must_answer <<~'OUT'
      6
      6
      "ab"
      6
      6
      nil
      6
      6
      (1/2)
      2
    OUT
  end

  it "reduce seed kinds" do
    result = ze0(<<~'RUBY')
      # reduce/inject with an array-accumulator seed, and sum with a string init
      # and block.
      def f(xs); xs.reduce([]) { |a, x| a << x }; end
      def g(a); a.reduce([]) { |acc, x| acc << x }; end
      def h(xs); xs.inject([]) { |a, x| a << (x * 2) }; end

      p f([1, 2])            # [1, 2]
      p f([])                # []
      p g([1, "x"])          # [1, "x"]
      p h([3, 4])            # [6, 8]
      p [1, 2, 3].reduce(0) { |a, x| a + x }      # 6 (scalar seeds unchanged)
      p [1, 2].reduce(0.5) { |a, x| a + x }       # 3.5
      a = [1, 2, 3]
      p a.sum("") { |x| x.to_s }                  # "123"
      p ["a", "b"].sum("> ") { |x| x }            # "> ab"
      p [1, 2].sum(10) { |x| x * 2 }              # 16 (numeric unchanged)
    RUBY

    _(result).must_answer <<~'OUT'
      [1, 2]
      []
      [1, "x"]
      [6, 8]
      6
      3.5
      "123"
      "> ab"
      16
    OUT
  end

  it "sort by comparison failure names the operands" do
    result = ze0(<<~'RUBY')
      # A failed comparison inside `sort_by`/`min_by`/`max_by` names the operand
      # classes ("comparison of Float with NaN failed"); zeo says "comparison
      # failed" without them. Plain `sort` already names them. (Found by the
      # 2026-08-24 probe sweep.)
      begin
        [1.0, Float::NAN].sort_by { |x| x }
      rescue ArgumentError => e
        puts e.message
      end
      begin
        [1, "a"].min_by { |x| x }
      rescue ArgumentError => e
        puts e.message
      end
    RUBY

    _(result).must_answer "comparison of Float with NaN failed\ncomparison of String with 1 failed\n"
  end

  it "sort by tie order" do
    result = ze0(<<~'RUBY')
      # `sort_by` does NOT sort the way `sort` does. CRuby watches the keys go by
      # and, when every one of them is a fixnum or a Float, drops `ruby_qsort` for
      # `rb_uniform_intro_sort_2` -- its own introsort, which breaks a tie somewhere
      # else entirely. One key outside that set (a String, a Bignum) puts the whole
      # call back on the C library's `qsort_r`, so both orders are pinned below.
      #
      # The last two rows reach the branches n alone decides: 16 or fewer elements
      # is an insertion sort, and an already-ordered input is left untouched.
      #
      # TWO goldens: the `qsort_r` rows are libc's answer, and glibc's qsort does
      # not break a tie where BSD's does. `.expected` is macOS, `.linux.expected`
      # linux, both recorded from the same pinned ruby.

      def show(label)
        puts format("%-26s %s", label, (yield).inspect)
      rescue StandardError => e
        puts format("%-26s %s: %s", label, e.class, e.message)
      end

      pairs = Array.new(60) { |i| [i % 3, i] }

      show("fixnum keys") { pairs.sort_by { |x| x[0] }.first(8) }
      show("float keys") { pairs.sort_by { |x| x[0].to_f }.first(6) }
      show("mixed fixnum and float") do
        Array.new(40) { |i| [i.even? ? i % 4 : (i % 4).to_f, i] }.sort_by { |x| x[0] }.first(6)
      end
      show("string keys leave uniform") { pairs.sort_by { |x| x[0].to_s }.first(6) }
      show("a bignum leaves uniform") do
        Array.new(30) { |i| [i % 3 == 0 ? 10**25 : i % 3, i] }.sort_by { |x| x[0] }.first(4)
      end
      show("every key equal") { Array.new(600) { |i| i }.sort_by { 0 }.first(6) }
      show("descending keys") { Array.new(40) { |i| [i % 4, i] }.sort_by { |x| -x[0] }.first(5) }
      show("insertion sort, n <= 16") { Array.new(15) { |i| [i % 2, i] }.sort_by { |x| x[0] } }
      show("already ordered") { Array.new(40) { |i| [i / 10, i] }.sort_by { |x| x[0] }.first(5) }
      show("a nan fails the sort") { [1.0, Float::NAN, 2.0].sort_by { |x| x } }
      show("enumerator, not array") { pairs.each_with_index.sort_by { |x,| x[0] }.first(4) }
    RUBY

    _(result).must_answer <<~'OUT', linux: <<~'LINUX'
      fixnum keys                [[0, 57], [0, 54], [0, 51], [0, 48], [0, 45], [0, 42], [0, 39], [0, 36]]
      float keys                 [[0, 57], [0, 54], [0, 51], [0, 48], [0, 45], [0, 42]]
      mixed fixnum and float     [[0, 36], [0, 32], [0, 28], [0, 24], [0, 20], [0, 16]]
      string keys leave uniform  [[0, 3], [0, 21], [0, 0], [0, 39], [0, 24], [0, 9]]
      a bignum leaves uniform    [[1, 19], [1, 7], [1, 22], [1, 25]]
      every key equal            [0, 1, 2, 3, 4, 5]
      descending keys            [[3, 31], [3, 27], [3, 23], [3, 19], [3, 35]]
      insertion sort, n <= 16    [[0, 0], [0, 2], [0, 4], [0, 6], [0, 8], [0, 10], [0, 12], [0, 14], [1, 1], [1, 3], [1, 5], [1, 7], [1, 9], [1, 11], [1, 13]]
      already ordered            [[0, 0], [0, 1], [0, 2], [0, 3], [0, 4]]
      a nan fails the sort       ArgumentError: comparison of Float with NaN failed
      enumerator, not array      [[[0, 57], 57], [[0, 54], 54], [[0, 51], 51], [[0, 48], 48]]
    OUT
      fixnum keys                [[0, 57], [0, 54], [0, 51], [0, 48], [0, 45], [0, 42], [0, 39], [0, 36]]
      float keys                 [[0, 57], [0, 54], [0, 51], [0, 48], [0, 45], [0, 42]]
      mixed fixnum and float     [[0, 36], [0, 32], [0, 28], [0, 24], [0, 20], [0, 16]]
      string keys leave uniform  [[0, 0], [0, 24], [0, 54], [0, 3], [0, 36], [0, 42]]
      a bignum leaves uniform    [[1, 4], [1, 1], [1, 28], [1, 22]]
      every key equal            [0, 1, 2, 3, 4, 5]
      descending keys            [[3, 31], [3, 27], [3, 23], [3, 19], [3, 35]]
      insertion sort, n <= 16    [[0, 0], [0, 2], [0, 4], [0, 6], [0, 8], [0, 10], [0, 12], [0, 14], [1, 1], [1, 3], [1, 5], [1, 7], [1, 9], [1, 11], [1, 13]]
      already ordered            [[0, 0], [0, 1], [0, 2], [0, 3], [0, 4]]
      a nan fails the sort       ArgumentError: comparison of Float with NaN failed
      enumerator, not array      [[[0, 57], 57], [[0, 54], 54], [[0, 51], 51], [[0, 48], 48]]
    LINUX
  end

  it "sort by with index" do
    result = ze0(<<~'RUBY')
      # A blockless sort_by answers an Enumerator whose with_index feeds the index to
      # the key block. There was no Enumerator arm for it, so the chain raised
      # NoMethodError; the equivalent spelling over pairs serves it.
      a = ["b", "aa", "a"]
      p a.sort_by.with_index { |w, i| [-w.length, i] }
      p a.sort_by.with_index { |w, i| i }
      p a.sort_by.with_index { |w, i| -i }

      n = [3, 1, 2]
      p n.sort_by.with_index { |v, i| v }
      p n.sort_by.with_index { |v, i| [v % 2, i] }

      # a single element, and one where the key ties across every element
      p ["only"].sort_by.with_index { |w, i| i }
      p [5, 5, 5].sort_by.with_index { |v, i| 0 }

      # through a local, and over a computed receiver
      words = %w[delta a bb ccc]
      p words.sort_by.with_index { |w, i| [w.length, i] }
      p (words + ["x"]).sort_by.with_index { |w, i| w }

      # the plain forms still work
      p a.sort_by { |w| w.length }
      p a.each.with_index.to_a
      p a.map.with_index { |w, i| "#{w}#{i}" }
      p a.select.with_index { |w, i| i > 0 }
    RUBY

    _(result).must_answer <<~'OUT'
      ["aa", "b", "a"]
      ["b", "aa", "a"]
      ["a", "aa", "b"]
      [1, 2, 3]
      [2, 3, 1]
      ["only"]
      [5, 5, 5]
      ["a", "bb", "ccc", "delta"]
      ["a", "bb", "ccc", "delta", "x"]
      ["b", "a", "aa"]
      [["b", 0], ["aa", 1], ["a", 2]]
      ["b0", "aa1", "a2"]
      ["aa", "a"]
    OUT
  end

  it "sort by with index offset" do
    result = ze0(<<~'RUBY')
      a = ["bb", "a", "cccc"]
      p a.sort_by.with_index(1) { |s, i| i }
      p a.sort_by.with_index(1) { |s, i| -i }
      p a.sort_by.with_index { |s, i| -i }
      p a.sort_by.with_index(10) { |s, i| s.length * i }
      p [3, 1, 2].sort_by.with_index(2) { |x, i| x }
      e = [3, 1, 2].sort_by
      p e.class
      p [3, 1, 2].sort_by.class
    RUBY

    _(result).must_answer <<~'OUT'
      ["bb", "a", "cccc"]
      ["cccc", "a", "bb"]
      ["cccc", "a", "bb"]
      ["a", "bb", "cccc"]
      [1, 2, 3]
      Enumerator
      Enumerator
    OUT
  end

  it "sort min max block comparator" do
    result = ze0(<<~'RUBY')
      # Array#sort / min / max with a 2-param comparator block.
      # Block returns -1/0/1; sort uses it for ordering, min/max pick
      # the element that the comparator places at the extremum.

      # Sort with reverse comparator
      puts [3,1,4,1,5].sort { |a,b| b <=> a }.inspect
      puts ["c","a","b"].sort { |a,b| b <=> a }.inspect

      # Sort with custom comparator
      puts ["banana","cat","ape"].sort { |a,b| a.length <=> b.length }.inspect

      # min/max with reverse comparator inverts the result
      puts [3,1,4,1,5].min { |a,b| b <=> a }
      puts [3,1,4,1,5].max { |a,b| b <=> a }

      # min/max with length comparator
      puts ["banana","cat","ape"].min { |a,b| a.length <=> b.length }
      puts ["banana","cat","ape"].max { |a,b| a.length <=> b.length }
    RUBY

    _(result).must_answer <<~'OUT', linux: <<~'LINUX'
      [5, 4, 3, 1, 1]
      ["c", "b", "a"]
      ["cat", "ape", "banana"]
      5
      1
      cat
      banana
    OUT
      [5, 4, 3, 1, 1]
      ["c", "b", "a"]
      ["ape", "cat", "banana"]
      5
      1
      cat
      banana
    LINUX
  end

  it "sort mixed type raises" do
    result = ze0(<<~'RUBY')
      # Sorting an array whose elements are not mutually comparable raises
      # ArgumentError, matching CRuby (it previously sorted silently). Arrays are
      # built with a variable element so they stay heterogeneous PolyArrays.
      str = "x"
      num = 5
      fl  = 1.5

      begin
        a = [1, str, 2]
        a.sort
        puts "no raise (sort)"
      rescue ArgumentError
        puts "raised (sort)"
      end

      begin
        b = [3, str, 1]
        b.sort!
        puts "no raise (sort!)"
      rescue ArgumentError
        puts "raised (sort!)"
      end

      # A poly array of mutually comparable values still sorts.
      c = [3, num, 1]
      r = c.sort
      p r

      # Integer and Float are mutually comparable; no raise.
      d = [3, fl, 2]
      e = d.sort
      p e
      puts "done"

      # min / max over incomparable elements also raise (CRuby parity).
      begin
        [1, str, 2].min
        puts "no raise (min)"
      rescue ArgumentError
        puts "raised (min)"
      end

      begin
        [1, str, 2].max
        puts "no raise (max)"
      rescue ArgumentError
        puts "raised (max)"
      end

      # comparable min/max still work, including mixed Integer/Float.
      g = [3, num, 1, fl]
      p g.min
      p g.max
    RUBY

    _(result).must_answer <<~'OUT'
      raised (sort)
      raised (sort!)
      [1, 3, 5]
      [1.5, 2, 3]
      done
      raised (min)
      raised (max)
      1
      5
    OUT
  end

  it "sort with comparator" do
    result = ze0(<<~'RUBY')
      # `Array#sort` with a comparator block leaves equal keys wherever the C
      # library puts them: `ruby_qsort` IS the system `qsort_r`, and zeo calls the
      # same one, so the mixed-case word list below ("Apple"/"apple" compare equal)
      # and the 60-element tie table at the end are the tie order this pins.
      #
      # This was a decided divergence while zeo sorted stably. Imported from the
      # spinel corpus at c55d9bdb; see tests/spinel/UPSTREAM.md.
      #
      # TWO goldens, because the tie order is libc's and glibc's qsort is not BSD's:
      # `.expected` is macOS, `.linux.expected` linux.
      #
      a = [5, 3, 9, 1, 3, 7, 0, 3, 8, 2]
      p a.sort { |x, y| x <=> y }
      p a.sort { |x, y| y <=> x }
      p a
      b = a.dup
      b.sort! { |x, y| x <=> y }
      p b
      words = %w[pear Apple fig banana kiwi date apple Fig]
      p words.sort { |x, y| x.downcase <=> y.downcase }
      pairs = [[1, "a"], [0, "b"], [1, "c"], [0, "d"], [2, "e"], [1, "f"]]
      p pairs.sort { |x, y| x[0] <=> y[0] }
      f = [3.5, -1.0, 2.25, 0.0]
      p f.sort { |x, y| x <=> y }
      p [].sort { |x, y| x <=> y }
      p [7].sort { |x, y| x <=> y }
      p [2, 1].sort { |x, y| x <=> y }
      h = { "b" => 2, "a" => 1, "c" => 3 }
      p h.sort { |x, y| x[0] <=> y[0] }
      objs = [{ "k" => 3 }, { "k" => 1 }, { "k" => 2 }]
      p objs.sort { |x, y| x["k"] <=> y["k"] }.map { |h| h["k"] }

      # a big enough input that a quadratic sort would be visible, checked by value
      big = Array.new(2000) { |i| (i * 7919) % 2003 }
      sorted = big.sort { |x, y| x <=> y }
      p sorted == big.sort
      p sorted.first, sorted.last

      # stability: equal keys keep their original order
      tagged = Array.new(60) { |i| [i % 3, i] }
      p tagged.sort { |x, y| x[0] <=> y[0] }.first(6)
    RUBY

    _(result).must_answer <<~'OUT', linux: <<~'LINUX'
      [0, 1, 2, 3, 3, 3, 5, 7, 8, 9]
      [9, 8, 7, 5, 3, 3, 3, 2, 1, 0]
      [5, 3, 9, 1, 3, 7, 0, 3, 8, 2]
      [0, 1, 2, 3, 3, 3, 5, 7, 8, 9]
      ["apple", "Apple", "banana", "date", "fig", "Fig", "kiwi", "pear"]
      [[0, "b"], [0, "d"], [1, "a"], [1, "c"], [1, "f"], [2, "e"]]
      [-1.0, 0.0, 2.25, 3.5]
      []
      [7]
      [1, 2]
      [["a", 1], ["b", 2], ["c", 3]]
      [1, 2, 3]
      true
      0
      2002
      [[0, 3], [0, 21], [0, 0], [0, 39], [0, 24], [0, 9]]
    OUT
      [0, 1, 2, 3, 3, 3, 5, 7, 8, 9]
      [9, 8, 7, 5, 3, 3, 3, 2, 1, 0]
      [5, 3, 9, 1, 3, 7, 0, 3, 8, 2]
      [0, 1, 2, 3, 3, 3, 5, 7, 8, 9]
      ["apple", "Apple", "banana", "date", "fig", "Fig", "kiwi", "pear"]
      [[0, "d"], [0, "b"], [1, "a"], [1, "c"], [1, "f"], [2, "e"]]
      [-1.0, 0.0, 2.25, 3.5]
      []
      [7]
      [1, 2]
      [["a", 1], ["b", 2], ["c", 3]]
      [1, 2, 3]
      true
      0
      2002
      [[0, 0], [0, 24], [0, 54], [0, 3], [0, 36], [0, 42]]
    LINUX
  end

  it "ternary lazy arms" do
    result = ze0(<<~'RUBY')
      class D
        def initialize(t)
          @t = t
        end
        def t
          @t
        end
      end
      # untaken arm with a side effect must not run (File.read behind the guard)
      missing = "/tmp/spinel_ternary_lazy_missing_#{Process.pid}"
      d = File.exist?(missing) ? D.new(File.read(missing)) : D.new("")
      puts d.t.length
      # taken arm still evaluates its prelude (self-created file, platform-neutral)
      present = "/tmp/spinel_ternary_lazy_present_#{Process.pid}"
      File.write(present, "content")
      g = File.exist?(present) ? D.new(File.read(present)) : D.new("")
      puts g.t.length > 0
      File.delete(present)
    RUBY

    _(result).must_answer "0\ntrue\n"
  end

  it "user enumerable each and for" do
    result = ze0(<<~'RUBY')
      # A user class that mixes in Enumerable via a hand-written #each: its methods
      # (map/select/to_a/sum, direct #each return value) and `for x in obj` all
      # materialize through the synthesized element array. The bare-yield each
      # returns the last yielded block value (not self), matching CRuby.
      class Nums
        include Enumerable
        def initialize(*xs) = @xs = xs
        def each; @xs.each { |x| yield x }; end
      end

      nums = Nums.new(1, 2, 3, 4)
      p nums.map { |x| x * 2 }
      p nums.select(&:even?)
      p nums.to_a
      p nums.sum
      p nums.min
      p nums.include?(3)

      # `for` over the user Enumerable
      total = 0
      for x in nums
        total += x
      end
      p total

      def collect_for(e)
        out = []
        for v in e
          out << v * 10
        end
        out
      end
      p collect_for(Nums.new(5, 6))

      # bare-yield each returns the last yielded block value (CRuby semantics)
      class Y
        def each; yield 1; yield 2; yield 3; end
      end
      p(Y.new.each { |v| v * 100 })

      # multi-assignment for over pair-yielding each
      class Pairs
        include Enumerable
        def each; yield [1, :a]; yield [2, :b]; end
      end
      pairs = []
      for k, v in Pairs.new
        pairs << "#{k}:#{v}"
      end
      p pairs
    RUBY

    _(result).must_answer <<~'OUT'
      [2, 4, 6, 8]
      [2, 4]
      [1, 2, 3, 4]
      10
      1
      true
      10
      [50, 60]
      300
      ["1:a", "2:b"]
    OUT
  end
end
