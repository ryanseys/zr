# frozen_string_literal: true

require "spec_helper"

describe "String: enumeration" do
  it "each cons each slice argument panic" do
    result = ze0(<<~'RUBY')
      begin
        [1, 2, 3].each_cons("l")
      rescue TypeError => e
        p e.class
      end
      begin
        [1, 2, 3].each_slice(:a)
      rescue TypeError => e
        p e.class
      end
    RUBY

    _(result).must_answer <<~'OUT'
      TypeError
      TypeError
    OUT
  end

  it "filter map" do
    result = ze0(<<~'RUBY')
      # Enumerable#filter_map (Ruby 2.7+): map, then drop falsy results, in one pass.
      # The result is a (boxed) array of the kept values; output matches whether the
      # block body is a nilable `expr if cond` or a plain transform.
      p [1, 2, 3, 4].filter_map { |x| x * 2 if x.even? }   # [4, 8]
      p [1, 2, 3].filter_map { |x| x * 2 }                 # always truthy -> like map
      p ["a", "", "b", ""].filter_map { |s| s.upcase unless s.empty? }
      p [1, 2, 3, 4, 5].filter_map { |x| x if x > 2 }

      # assigned and chained
      evens_doubled = [1, 2, 3, 4, 5, 6].filter_map { |x| x * 2 if x.even? }
      p evens_doubled
      p [1, 2, 3, 4, 5, 6].filter_map { |x| x * 2 if x.even? }.sum

      # nil and false are both dropped
      p [1, 2, 3].filter_map { |x| x.even? ? x : false }
    RUBY

    _(result).must_answer <<~'OUT'
      [4, 8]
      [2, 4, 6]
      ["A", "B"]
      [3, 4, 5]
      [4, 8, 12]
      24
      [2]
    OUT
  end

  it "inject symbol op" do
    result = ze0(<<~'RUBY')
      # inject/reduce with an arithmetic operator passed as a symbol-to-proc block
      # (inject(&:+)). Previously emitted an empty accumulation loop with an
      # undeclared accumulator. The positional-symbol forms are unchanged. The
      # symbol-to-proc fold seeds with the first element (no-init-value form).
      p [1, 2, 3].inject(&:+)
      p [1, 2, 3, 4].inject(&:*)
      p [10, 3, 2].inject(&:-)
      p [1, 2, 3].inject(:+)
      p [1, 2, 3].inject(10, :+)
      p [100, 20, 3].inject(&:+)
      p [2, 3, 4].inject(&:*)
    RUBY

    _(result).must_answer <<~'OUT'
      6
      24
      5
      6
      16
      123
      24
    OUT
  end

  it "inject symbol to proc" do
    result = ze0(<<~'RUBY')
      # Enumerable#inject / #reduce with a symbol-to-proc argument
      # (`inject(&:&)`) and the seedless first-element fold.
      #
      # `inject(&:sym)` on a non-int_array receiver reached compile_reduce_block
      # with a synthetic accumulator `_acc` that was never declared in C
      # (`'lv__acc' undeclared`). The seedless fold also seeded the accumulator
      # with `0`/NULL and iterated from index 0 instead of seeding with the
      # first element and iterating from index 1 — wrong for non-additive ops
      # (`*` gave 0) and a NULL deref for array elements (`a & b` segfaulted).
      #
      # Fix: seed seedless folds with arr[0] (loop from 1), type the result as
      # the element type in analyze, declare the synthetic `_acc`, and lower
      # `&:sym` / `:sym` to `acc.sym(x)` for the modeled element/op pairs.

      # 1. Symbol-to-proc set operations on an array of int arrays.
      p [[1, 2, 3], [2, 3, 4]].inject(&:&)        #=> [2, 3]
      p [[1, 2], [2, 3], [3, 4]].inject(&:|)      #=> [1, 2, 3, 4]
      p [[1, 2, 3, 4], [2, 3]].inject(&:-)        #=> [1, 4]

      # 2. Single-element array: the fold returns that element (loop body
      #    never runs).
      p [[5, 6, 7]].inject(&:&)                   #=> [5, 6, 7]

      # 3. Symbol-to-proc arithmetic on int arrays (folds inline upstream).
      p [1, 2, 3, 4].inject(&:+)                  #=> 10
      p [1, 2, 3, 4].inject(&:*)                  #=> 24

      # 4. Seedless explicit-block fold seeds with the first element, not 0.
      p [1, 2, 3, 4].inject { |a, b| a * b }      #=> 24
      p [10, 3, 2].inject { |a, b| a - b }        #=> 5

      # 5. Seedless explicit-block fold over an array of arrays (was a NULL
      #    deref segfault when the accumulator seeded as NULL).
      p [[1, 2, 3], [2, 3, 4]].inject { |a, b| a & b }   #=> [2, 3]

      # 6. Result flows through a local, exercising the inferred result type.
      inter = [[1, 2, 3], [2, 3, 4], [3, 2, 5]].inject(&:&)
      puts inter.length                           #=> 2
      p inter                                     #=> [2, 3]

      puts "done"
    RUBY

    _(result).must_answer <<~'OUT'
      [2, 3]
      [1, 2, 3, 4]
      [1, 4]
      [5, 6, 7]
      10
      24
      24
      5
      [2, 3]
      2
      [2, 3]
      done
    OUT
  end

  it "inject symbol variable" do
    result = ze0(<<~'RUBY')
      # inject/reduce with the operator Symbol held in a VARIABLE: the sole-
      # assignment lookthrough resolves the op statically, in both the emit and
      # the result-type inference (was: typed as the symbol itself).
      s = :+
      p [3, 1, 2].inject(s)
      p [3, 1, 2].reduce(s)
      m = :*
      p [2, 3, 4].reduce(m)
      p [2.5, 1.5].inject(10.0, s)
    RUBY

    _(result).must_answer <<~'OUT'
      6
      6
      24
      14.0
    OUT
  end

  it "lazy each cons slice" do
    result = ze0(<<~'RUBY')
      # `Enumerator::Lazy#each_cons`/`#each_slice` are lazy: an endless source is
      # workable, and the chain only advances as far as the terminal asks.
      p (1..Float::INFINITY).lazy.each_cons(3).first(2)
      p (1..Float::INFINITY).lazy.each_slice(3).first(2)
      p (1..10).lazy.each_slice(3).to_a
      p (1..7).lazy.each_cons(3).to_a
      p (1..2).lazy.each_cons(3).to_a
      p (1..10).lazy.each_cons(2).class
      p (1..10).lazy.each_cons(2).size
      p (1..Float::INFINITY).lazy.each_cons(2).size
      p (1..10).lazy.each_slice(3).size
      p (1..10).lazy.each_slice(4).size
      p (1..3).lazy.each_cons(5).size
      p (1..10).lazy.select { |x| x > 1 }.each_cons(2).size
      p [1, 2, 3].lazy.each_cons(2).each_cons(2).to_a
      p({ a: 1, b: 2, c: 3 }.lazy.each_cons(2).to_a)
      p (1..6).lazy.each_cons(2).with_index.first(2)
      p (1..6).lazy.each_cons(2).select { |a, b| a.odd? }.to_a
      p (1..8).lazy.each_slice(3).map { |g| g.sum }.to_a
      p (1..6).lazy.each_cons(0).to_a rescue p $!.message
      p (1..6).lazy.each_slice(0).to_a rescue p $!.message

      # a block runs the chain at once for its side effects and answers the receiver
      seen = []
      r = (1..6).lazy.each_cons(2) { |w| seen << w }
      p seen
      p r.first(3)
    RUBY

    _(result).must_answer <<~'OUT'
      [[1, 2, 3], [2, 3, 4]]
      [[1, 2, 3], [4, 5, 6]]
      [[1, 2, 3], [4, 5, 6], [7, 8, 9], [10]]
      [[1, 2, 3], [2, 3, 4], [3, 4, 5], [4, 5, 6], [5, 6, 7]]
      []
      Enumerator::Lazy
      9
      Infinity
      4
      3
      0
      nil
      [[[1, 2], [2, 3]]]
      [[[:a, 1], [:b, 2]], [[:b, 2], [:c, 3]]]
      [[[1, 2], 0], [[2, 3], 1]]
      [[1, 2], [3, 4], [5, 6]]
      [6, 15, 15]
      "invalid size"
      "invalid slice size"
      [[1, 2], [2, 3], [3, 4], [4, 5], [5, 6]]
      [1, 2, 3]
    OUT
  end

  it "poly reduce operator symbol" do
    result = ze0(<<~'RUBY')
      # `reduce(init, :+)` on a receiver that stayed boxed -- one of the two arrays
      # `partition` answers -- fell through to the Hash/Enumerable face, which
      # converts the receiver to a hash and refuses an Array at run time. The poly
      # arm that coerces to an array and re-enters the fold emitter required a BLOCK,
      # and the operator-symbol form carries none (#4079).
      class Fixed
        attr_reader :units

        def initialize(units) = @units = units
        def +(other) = Fixed.new(@units + other.units)
        def *(other) = Fixed.new(@units * other.units)
        def negative? = @units.negative?
        def to_s = @units.to_s
      end

      deltas = [Fixed.new(3), Fixed.new(-2), Fixed.new(5)]
      credits, debits = deltas.partition { |d| !d.negative? }

      puts credits.reduce(Fixed.new(0), :+)
      puts debits.reduce(Fixed.new(0), :+)
      puts credits.inject(Fixed.new(1), :*)

      # the block form on the same receiver, which already worked
      puts credits.reduce(Fixed.new(0)) { |a, b| a + b }

      # the seedless form, and Integers through the same shape
      ns = [1, 2, 3, 4]
      evens, odds = ns.partition(&:even?)
      p evens.reduce(0, :+)
      p evens.reduce(:+)
      p odds.inject(:+)

      # receivers that were never boxed keep answering
      p ns.reduce(0, :+)
      p ns.inject(:+)
      p [[1, 2], [3]].map { |x| x.reduce(:+) }

      # and a Hash really does take the face
      h = { "a" => 1, "b" => 2 }
      p h.reduce(0) { |s, (k, v)| s + v }
    RUBY

    _(result).must_answer <<~'OUT'
      8
      -2
      15
      8
      6
      6
      4
      10
      10
      [3, 3]
      3
    OUT
  end

  it "reduce symbol only method" do
    result = ze0(<<~'RUBY')
      # `reduce(:sym)` / `inject(seed, :sym)` names the method by Symbol, which is not
      # a CallNode, so the reachability walk never saw the name and pruned the method.
      # The fold then fell through to the unresolved-call raise -- "undefined method
      # '^' for an instance of F" for a method the program plainly defines. Only a
      # method with NO other call site was affected, which is what made it look like
      # an operator problem rather than a reachability one (#4069).
      class F
        attr_reader :u
        def initialize(u) = @u = u
        def ^(other) = F.new(u + other.u)
        def to_s = u.to_s
      end
      p [F.new(1), F.new(2)].reduce(F.new(0), :^).to_s

      class G
        attr_reader :n
        def initialize(n) = @n = n
        def +(o) = G.new(n + o.n)
        def merge_with(o) = G.new(n * o.n)
      end
      p [G.new(1), G.new(2)].reduce(:+).n
      p [G.new(1), G.new(2)].inject(G.new(10), :+).n
      p [G.new(2), G.new(3)].reduce(:merge_with).n
      p [G.new(2), G.new(3)].inject(G.new(4), :merge_with).n

      # a method that also has an ordinary call site still works
      class H
        attr_reader :v
        def initialize(v) = @v = v
        def |(o) = H.new(v + o.v)
      end
      p (H.new(1) | H.new(2)).v
      p [H.new(1), H.new(2)].reduce(H.new(0), :|).v
    RUBY

    _(result).must_answer <<~'OUT'
      "3"
      3
      13
      6
      24
      3
      3
    OUT
  end

  it "str array sort by" do
    result = ze0(<<~'RUBY')
      # sort_by on str_array previously bombed at C compile time:
      # `cannot resolve call to 'sort_by' on str_array`, then the
      # pointer slot got assigned (mrb_int)0. Explicit block and the
      # `&:length` / `&:bytesize` / `&:to_i` symbol-to-proc shortcuts
      # are now handled.
      puts ["bb", "a", "ccc"].sort_by(&:length).inspect
      puts ["bb", "a", "ccc"].sort_by { |s| s.length }.inspect
      puts ["10", "1", "100"].sort_by(&:to_i).inspect
      puts ["zzz", "a", "bb"].sort_by { |s| s.length }.inspect
      # Equal-key elements keep their original order (bubble sort is stable).
      puts ["bb", "a", "cc"].sort_by(&:length).inspect
    RUBY

    _(result).must_answer <<~'OUT'
      ["a", "bb", "ccc"]
      ["a", "bb", "ccc"]
      ["1", "10", "100"]
      ["a", "bb", "zzz"]
      ["a", "bb", "cc"]
    OUT
  end

  it "string each with index chain" do
    result = ze0(<<~'RUBY')
      Line = Struct.new(:number, :label)
      lines = []
      "a\nb\n".each_line.with_index do |raw, number|
        lines << Line.new(number, raw.to_s)
      end
      p lines.map(&:number)
      p Line.new(99, "x").number

      "a\nb\n".each_line.with_index { |l, i| p [l, i] }
      "ab".each_byte.with_index { |b, i| p [b, i] }
      "ab".each_char.with_index { |ch, i| p [ch, i] }
      "a\nb\n".each_line.with_index(10) { |l, i| p [l, i] }
      "a|b".each_line("|").with_index { |l, i| p [l, i] }
      p("a\nb\n".each_line.with_index.to_a)
      p("ab".each_byte.with_index.map { |b, i| b + i })

      "a\nb\n".each_line.with_index do |raw, number|
        p number.class
      end
    RUBY

    _(result).must_answer <<~'OUT'
      [0, 1]
      99
      ["a\n", 0]
      ["b\n", 1]
      [97, 0]
      [98, 1]
      ["a", 0]
      ["b", 1]
      ["a\n", 10]
      ["b\n", 11]
      ["a|", 0]
      ["b", 1]
      [["a\n", 0], ["b\n", 1]]
      [97, 99]
      Integer
      Integer
    OUT
  end

  it "string param dead each branch" do
    result = ze0(<<~'RUBY')
      # A String|Hash parameter that this program only ever calls with a String.
      # `opts` is therefore monomorphically String, so the `else` (Hash) branch is
      # statically dead. `String#each` is a genuine NoMethodError in Ruby and never
      # runs here (CRuby always takes the is_a?(String) branch), so it lowers to a
      # runtime stub via the NoMethodError gate rather than aborting compilation (#1434).
      class Conn
        def initialize(opts)
          @kind = ""
          if opts.is_a?(String)
            @kind = "string:" + opts
          else
            opts.each { |k, v| @kind = @kind + k + "=" + v }
          end
        end
        def kind; @kind; end
      end
      puts Conn.new("hello").kind
      puts Conn.new("world").kind
    RUBY

    _(result).must_answer <<~'OUT'
      string:hello
      string:world
    OUT
  end
end
