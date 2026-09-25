# frozen_string_literal: true

require "spec_helper"

describe "Comparable: comparison and equality" do
  it "bigint compare object operand" do
    result = zr(<<~'RUBY')
      # `obj == 2**64` calls the object's own `==`, and `obj < 2**64` calls its own
      # `<`. A big Integer operand does not change which method runs.
      class Exp
        def initialize(v) = @v = v
        def ==(other)
          @v == other ? "eq" : "ne"
        end
        def <(other) = "lt-called"
      end

      def wrap(v) = Exp.new(v)
      p(wrap(2**64) == 18446744073709551616)
      p(wrap(1) == 18446744073709551616)
      p(wrap(1) < 18446744073709551616)

      # the numeric comparisons themselves are unchanged
      p(2**64 == 18446744073709551616)
      p(2**64 == 5)
      p(5 == 2**64)
      p((2**64) > 5)
      p(5 < 2**64)
      p((2**64) <=> 5)
    RUBY

    _(result).must_answer <<~'OUT'
      "eq"
      "ne"
      "lt-called"
      true
      false
      false
      true
      true
      1
    OUT
  end

  it "collections compare element wise and objects default to identity" do
    result = zr(<<~'RUBY')
      puts [1, [2, 3]] == [1, [2, 3]]
      puts({ a: 1, b: [2] } == { a: 1, b: [2] })
      puts({ a: 1 } == { a: 2 })

      class Blank
      end

      b1 = Blank.new
      b2 = Blank.new
      puts b1 == b1
      puts b1 == b2
    RUBY

    _(result).must_answer <<~'OUT'
      true
      true
      false
      true
      false
    OUT
  end

  it "the operators and clamp read a Float <=> result by its sign" do
    result = zr(<<~'RUBY')
      # Comparable operators/clamp validate the user <=> result type: a Float
      # result compares by sign. A statically non-Integer/nil <=> result (String,
      # Array, ...) is a protocol violation caught at compile time, not a
      # runtime error, so it is not exercised here.
      class FDiff
        include Comparable
        attr_reader :n
        def initialize(n); @n = n; end
        def <=>(o); (@n - o.n).to_f; end
      end
      p(FDiff.new(9) < FDiff.new(5))
      p(FDiff.new(5).between?(FDiff.new(1), FDiff.new(9)))
      p(FDiff.new(12).clamp(FDiff.new(1), FDiff.new(9)).n)
      # a <=> that returns nil (incomparable) stays a runtime concern: ordering
      # raises ArgumentError, == is just false.
      class NilCmp
        include Comparable
        def <=>(o); nil; end
      end
      r = (NilCmp.new < NilCmp.new rescue $!.class); p r
      p(NilCmp.new == NilCmp.new)
    RUBY

    _(result).must_answer <<~'OUT'
      false
      true
      9
      ArgumentError
      false
    OUT
  end

  it "a base-class <=> that calls a name only its descendants write types as the unify of their returns" do
    result = zr(<<~'RUBY')
      # A base-class method calling a name defined ONLY in descendants (here
      # Comparable's <=> reading `area`) types as the unify of the descendant
      # returns. The call gives the value of the descendant's method, not nil.
      class Shape
        include Comparable
        def <=>(other) = area <=> other.area
      end
      class Rect < Shape
        def initialize(a) = (@a = a)
        def area = @a
      end
      class Circ < Shape
        def initialize(a) = (@a = a)
        def area = @a * 1.0
      end
      p(Rect.new(4) > Rect.new(2))
      p(Rect.new(3) <=> Circ.new(2))
      p(Circ.new(5) < Circ.new(6))
      p(Rect.new(2) == Circ.new(2))
    RUBY

    _(result).must_answer <<~'OUT'
      true
      1
      true
      true
    OUT
  end

  it "a <=> that answers nil for a mixed operand raises, naming the operand by its inspect" do
    result = zr(<<~'RUBY')
      # Comparable <,>,<=,>=,between?,clamp on a class whose `<=>` returns nil
      # for an incomparable (mixed-type) operand. The operators check the `<=>`
      # result also for a small VALUE-TYPE class, a scalar-typed `<=>` param works,
      # and the ArgumentError message
      # describes a special-constant operand by its inspect ("with 3"), not its
      # class name ("with Integer"), like CRuby's rb_cmperr.
      class VerN
        include Comparable
        attr_reader :n
        def initialize(n); @n = n; end
        def <=>(o); return nil unless o.is_a?(VerN); n <=> o.n; end
      end
      a = VerN.new(5)
      p(a < VerN.new(9))
      p(a > VerN.new(9))
      p(a <= VerN.new(5))
      p(a >= VerN.new(5))
      p(a.between?(VerN.new(1), VerN.new(9)))
      p(a.clamp(VerN.new(1), VerN.new(3)).n)
      begin; p(a < 3); rescue ArgumentError => e; puts "AE: #{e.message}"; end
      begin; p(a.between?(1, 9)); rescue ArgumentError => e; puts "AE: #{e.message}"; end
      begin; p(a.clamp(1, 9)); rescue ArgumentError => e; puts "AE: #{e.message}"; end

      # heap-class twin (an extra ivar of another type defeats value-type detection)
      class HeapV
        include Comparable
        def initialize(n); @n = n; @tag = "h#{n}"; end
        attr_reader :n, :tag
        def <=>(o); return nil unless o.is_a?(HeapV); n <=> o.n; end
      end
      h = HeapV.new(5)
      p(h < HeapV.new(9))
      begin; p(h < :sym); rescue ArgumentError => e; puts "AE: #{e.message}"; end
      begin; p(h > nil); rescue ArgumentError => e; puts "AE: #{e.message}"; end
    RUBY

    _(result).must_answer <<~'OUT'
      true
      false
      true
      true
      true
      3
      AE: comparison of VerN with 3 failed
      AE: comparison of VerN with 1 failed
      AE: comparison of VerN with 1 failed
      true
      AE: comparison of HeapV with :sym failed
      AE: comparison of HeapV with nil failed
    OUT
  end

  it "an incomparable pair raises for the operators and between?, while == is false without raising" do
    result = zr(<<~'RUBY')
      # Object <, <=, >, >=, ==, != and between? via a user <=> that can return nil:
      # an incomparable pair raises the Comparable ArgumentError for the operators
      # and between?, while == is false (and != true) without raising, and identity
      # is always equal -- matching CRuby compar.c. A <=> that always returns an
      # Integer keeps working (the fast inline path).
      class Weight
        include Comparable
        attr_reader :g
        def initialize(g); @g = g; end
        # nil for a negative operand: forces a runtime-nil <=> between same-class
        # operands so the checked path is exercised
        def <=>(other); other.g < 0 ? nil : (g <=> other.g); end
      end

      class Money
        include Comparable
        attr_reader :cents
        def initialize(cents); @cents = cents; end
        def <=>(other); cents <=> other.cents; end
      end

      def w_id(x); x; end
      def m_id(x); x; end

      w1 = w_id(Weight.new(1))
      w2 = w_id(Weight.new(2))
      bad = w_id(Weight.new(-5))

      # comparable pairs work
      p w1 < w2
      p w2 > w1
      p w1 <= w1
      p w2 >= w2
      p w1.between?(w1, w2)
      p w1 == w_id(Weight.new(1))
      p w1 != w2

      # incomparable operands raise for the operators...
      begin
        w1 < bad
      rescue ArgumentError => e
        puts e.message
      end
      begin
        w1 >= bad
      rescue ArgumentError => e
        puts e.message
      end
      begin
        w2.between?(w1, bad)
      rescue ArgumentError => e
        puts e.message
      end

      # ...but == is false (never raises), != is true, and identity always wins
      p w1 == bad
      p w1 != bad
      p bad == bad

      # an always-Integer <=> class keeps working
      m1 = m_id(Money.new(10))
      m2 = m_id(Money.new(20))
      p m1 < m2
      p m1.between?(m1, m2)
      p m1 == m_id(Money.new(10))
    RUBY

    _(result).must_answer <<~'OUT'
      true
      true
      true
      true
      true
      true
      true
      comparison of Weight with Weight failed
      comparison of Weight with Weight failed
      comparison of Weight with Weight failed
      false
      true
      true
      true
      true
      true
    OUT
  end

  it "a user <=> drives Comparable, and its result is validated the way rb_cmpint validates one" do
    result = zr(<<~'RUBY')
      # The comparison protocol: a user `<=>` drives Comparable, and its result is
      # validated the way CRuby's `rb_cmpint` does.

      # `<=>` may return any numeric type; only its SIGN matters, so a Float result
      # works just like an Integer one.
      class Temp
        include Comparable
        attr_reader :deg
        def initialize(deg) = @deg = deg
        def <=>(other) = (deg - other.deg).to_f
      end

      p [Temp.new(3), Temp.new(1), Temp.new(2)].sort.map(&:deg)   # [1, 2, 3]
      p Temp.new(5) < Temp.new(9)                                 # true
      p Temp.new(5).clamp(Temp.new(1), Temp.new(9)).deg           # 5
      p Temp.new(5) == Temp.new(5)                                # true

      # A `<=>` that answers `nil` (incomparable) makes ordering raise, but `==`
      # stays false and identity always wins.
      class Ver
        include Comparable
        def initialize(n) = @n = n
        attr_reader :n
        def <=>(other) = other.is_a?(Ver) ? (n <=> other.n) : nil
      end
      a = Ver.new(1)
      p a == Ver.new(2)                                  # false
      p a == a                                           # true (identity)
      p(begin; a < "x"; rescue => e; e.class; end)       # ArgumentError

      # clamp: nil bounds are open on that side; reversed bounds raise; an exclusive
      # range cannot clamp.
      p 5.clamp(1, nil)                                            # 5
      p 5.clamp(nil, 3)                                            # 3
      p(begin; 5.clamp(10, 1); rescue => e; e.message; end)       # min argument ...
      p 5.clamp(1..10)                                            # 5
      p(begin; 5.clamp(1...10); rescue => e; e.message; end)      # cannot clamp ...

      # min/max/sort over mutually incomparable elements raise ArgumentError (built
      # from a variable so the array stays heterogeneous).
      x = "a"
      p(begin; [1, x, 2].min; rescue => e; e.message; end)        # String with 1
      p(begin; [1, x].sort; rescue => e; e.class; end)            # ArgumentError

      # Hash#sort orders the [key, value] pairs through the array comparison.
      p({ b: 2, a: 1, c: 3 }.sort)                  # [[:a, 1], [:b, 2], [:c, 3]]
    RUBY

    _(result).must_answer <<~'OUT'
      [1, 2, 3]
      true
      5
      true
      false
      true
      ArgumentError
      5
      3
      "min argument must be less than or equal to max argument"
      5
      "cannot clamp with an exclusive range"
      "comparison of String with 1 failed"
      ArgumentError
      [[:a, 1], [:b, 2], [:c, 3]]
    OUT
  end

  it "no block cmp" do
    result = zr(<<~'RUBY')
      # No-block sort/min/max/clamp over a user class that mixes in Comparable must
      # dispatch the user `<=>` (not the built-in poly comparator). A nil `<=>` result
      # (incomparable operands) raises ArgumentError, matching CRuby. Receivers are
      # routed through a method param so the calls hit the runtime comparator path.
      class Money
        include Comparable
        attr_reader :cents
        def initialize(cents); @cents = cents; end
        def <=>(other); cents <=> other.cents; end
      end

      # distinct monomorphic helpers per receiver shape (a shared one would go poly)
      def bag_id(x); x; end
      def money_id(x); x; end
      def wbag_id(x); x; end

      bag = bag_id([Money.new(30), Money.new(10), Money.new(20)])

      p bag.sort.map(&:cents)
      p bag.min.cents
      p bag.max.cents

      # clamp keeps the receiver's class (returns self or a bound)
      p money_id(Money.new(50)).clamp(Money.new(10), Money.new(30)).cents
      p money_id(Money.new(5)).clamp(Money.new(10), Money.new(30)).cents
      p money_id(Money.new(20)).clamp(Money.new(10), Money.new(30)).cents

      # a `<=>` that yields nil for foreign operands makes the comparison raise
      class Weight
        include Comparable
        attr_reader :g
        def initialize(g); @g = g; end
        def <=>(other); other.is_a?(Weight) ? (g <=> other.g) : nil; end
      end

      begin
        wbag_id([Weight.new(3), "kg", Weight.new(1)]).sort
        puts "no raise"
      rescue ArgumentError => e
        puts e.message
      end

      # the recorded pair must be deterministic (libc-independent): exercise the
      # foreign operand at every position of 2- and 3-element arrays; the receiver
      # in the message is whichever operand the fixed merge schedule compares first
      def try_sort(a)
        begin
          a.sort
          puts "no raise"
        rescue ArgumentError => e
          puts e.message
        end
      end

      try_sort(["kg", Weight.new(1)])
      try_sort([Weight.new(1), "kg"])
      try_sort(["kg", Weight.new(1), Weight.new(2)])
      try_sort([Weight.new(1), Weight.new(2), "kg"])

      # minmax (no block) via the user <=>; min(n)/max(n) route through the sorted
      # order; Array#<=> compares object arrays elementwise
      p bag.minmax.map(&:cents)
      p bag.min(2).map(&:cents)
      p bag.max(2).map(&:cents)
      p (bag <=> bag_id([Money.new(30), Money.new(10), Money.new(20)]))
      p (bag <=> bag_id([Money.new(30), Money.new(99)]))
      empty = bag_id([])
      p empty.minmax
    RUBY

    _(result).must_answer <<~'OUT', linux: <<~'LINUX'
      [10, 20, 30]
      10
      30
      30
      10
      20
      comparison of Weight with String failed
      comparison of String with Weight failed
      comparison of Weight with String failed
      comparison of String with Weight failed
      comparison of Weight with String failed
      [10, 30]
      [10, 20]
      [30, 20]
      0
      -1
      [nil, nil]
    OUT
      [10, 20, 30]
      10
      30
      30
      10
      20
      comparison of Weight with String failed
      comparison of String with Weight failed
      comparison of Weight with String failed
      comparison of Weight with String failed
      comparison of String with Weight failed
      [10, 30]
      [10, 20]
      [30, 20]
      0
      -1
      [nil, nil]
    LINUX
  end
    it "two Strings compare through the core's own <=> until a class or String itself writes another" do
      result = zr(<<~'RUBY')
        p ["a" < "b", "b" <= "b", "c" > "b", "a" >= "b", "abc".between?("abb", "abd"), "z".clamp("a", "m")]
        p ["\xff".b < "a", "é" > "e", "a".encode("UTF-16LE") >= "a"]
        class Loud < String
          def <=>(other) = -(super)
        end
        p [Loud.new("a") < "b", "a" < Loud.new("b"), Loud.new("a").between?("b", "c")]
        begin
          "a" < 1
        rescue ArgumentError => e
          p e.message
        end
        module Backwards
          refine String do
            def <=>(other) = 0
          end
        end
        using Backwards
        p ["a" < "b", "a" <=> "b"]
        class String
          def <=>(other) = other.size <=> size
        end
        p ["a" < "bb", "bb" < "a", %w[x yyy zz].max]
      RUBY

      _(result).must_answer <<~'OUT'
        [true, true, true, false, true, "m"]
        [false, true, true]
        [false, true, false]
        "comparison of String with 1 failed"
        [true, 0]
        [false, true, "x"]
      OUT
    end
end
