# frozen_string_literal: true

require "spec_helper"

describe "Numeric: comparison and equality" do
  it "case eq scalar poly arg" do
    result = zr(<<~'RUBY')
      # `===` on a scalar-comparable receiver (bool/int/float/string/symbol) is case
      # equality == value equality. When the argument unifies to a poly type across
      # call sites while the receiver stays a single scalar type, Spinel previously
      # rejected the call; it now boxes the receiver and compares by the poly runtime
      # rule (numbers cross-compare, other tags by tag).

      # In each method the receiver keeps one scalar type; the second argument varies
      # across call sites (Integer / Float / true / nil / String / Symbol), so the
      # parameter unifies to poly.
      def beq(x, y); x === y; end     # x : bool
      p beq(true, 1)        # false (true only case-equals true)
      p beq(true, true)     # true
      p beq(true, nil)      # false
      p beq(false, false)   # true

      def ieq(x, y); x === y; end     # x : int
      p ieq(1, 1)           # true
      p ieq(1, 1.0)         # true  (numeric cross-compare)
      p ieq(2, "x")         # false
      p ieq(3, nil)         # false

      def seq(x, y); x === y; end     # x : string
      p seq("a", "a")       # true
      p seq("a", :a)        # false
      p seq("a", 1)         # false

      def yeq(x, y); x === y; end     # x : symbol
      p yeq(:sym, :sym)     # true
      p yeq(:sym, "sym")    # false
      p yeq(:sym, 9)        # false
    RUBY

    _(result).must_answer <<~'OUT'
      false
      true
      false
      true
      true
      true
      false
      false
      true
      false
      false
      true
      false
      false
    OUT
  end

  it "clamp nil open bounds" do
    result = zr(<<~'RUBY')
      # clamp(lo, hi) accepts nil for an open (unbounded) side on Integer and Float
      # receivers: a nil lo skips the lower comparison, a nil hi the upper.
      p 5.clamp(1, nil)
      p 0.clamp(1, nil)
      p 5.clamp(nil, nil)
      p 12.clamp(nil, 9)
      p 5.0.clamp(1.0, nil)
      p 5.0.clamp(nil, 3.0)
      p 2.0.clamp(nil, nil)
      p 0.0.clamp(1.0, nil)
    RUBY

    _(result).must_answer <<~'OUT'
      5
      1
      5
      9
      5.0
      3.0
      2.0
      1.0
    OUT
  end

  it "class spaceship" do
    result = zr(<<~'RUBY')
      class Animal; end
      class Dog < Animal; end
      class Cat < Animal; end

      p(Dog <=> Animal)
      p(Animal <=> Dog)
      p(Dog <=> Dog)
      p(Dog <=> Cat)
    RUBY

    _(result).must_answer <<~'OUT'
      -1
      1
      0
      nil
    OUT
  end

  it "comparable between short circuits" do
    result = zr(<<~'RUBY')
      p "Hello".between?("l", 0)
      p "Hello".between?("l", nil)
      p 1.between?(2, :a)
    RUBY

    _(result).must_answer <<~'OUT'
      false
      false
      false
    OUT
  end

  it "comparable between user type" do
    result = zr(<<~'RUBY')
      # Comparable#between? on a user type (`self >= min && self <= max`) must
      # dispatch through the class's <=>, not a raw struct comparison which
      # gcc rejects ("invalid operands to binary >="). Direct </>/<=/>= on
      # such types already worked via <=>; between? now does too.
      class Temp
        include Comparable
        attr_reader :deg
        def initialize(d); @deg = d; end
        def <=>(other); @deg <=> other.deg; end
      end

      a = Temp.new(10)
      puts a.between?(Temp.new(5), Temp.new(15))    # true
      puts a.between?(Temp.new(10), Temp.new(15))   # true (inclusive low)
      puts a.between?(Temp.new(5), Temp.new(10))    # true (inclusive high)
      puts a.between?(Temp.new(11), Temp.new(15))   # false
      puts a.between?(Temp.new(1), Temp.new(9))     # false

      # Direct comparisons still route through <=>
      puts (Temp.new(3) < Temp.new(7))
      puts (Temp.new(7) >= Temp.new(7))

      # Built-in receivers unaffected
      puts 5.between?(1, 10)
      puts "m".between?("a", "z")
      puts 2.5.between?(1.0, 3.0)
    RUBY

    _(result).must_answer <<~'OUT'
      true
      true
      true
      false
      false
      true
      true
      true
      true
      true
    OUT
  end

  it "comparable clamp exclusive range" do
    result = zr(<<~'RUBY')
      # Comparable#clamp over an exclusive range of user objects raises.
      class Ver
        include Comparable
        attr_reader :n
        def initialize(n); @n = n; end
        def <=>(o); n <=> o.n; end
      end
      p((Ver.new(5).clamp(Ver.new(1)...Ver.new(9)).n rescue $!.class))
      p(Ver.new(5).clamp(Ver.new(1)..Ver.new(9)).n)
      p(Ver.new(12).clamp(Ver.new(1)..Ver.new(9)).n)
    RUBY

    _(result).must_answer <<~'OUT'
      ArgumentError
      5
      9
    OUT
  end

  it "comparable clamp object range" do
    result = zr(<<~'RUBY')
      # Comparable#clamp with a one-sided (beginless/endless) or two-sided literal
      # Range whose bounds are instances of the receiver's class. An sp_Range cannot
      # carry the endpoints' class (its bounds are mrb_int), so these unfold to
      # sp_obj_clamp with a nil bound for the missing side. Regression for #2558.
      class Ver
        include Comparable
        attr_reader :n
        def initialize(n); @n = n; end
        def <=>(o); n <=> o.n; end
      end

      p(Ver.new(12).clamp(..Ver.new(9)).n)             # beginless: clamp down to 9
      p(Ver.new(3).clamp(..Ver.new(9)).n)              # beginless: in range, unchanged
      p(Ver.new(0).clamp(Ver.new(1)..).n)              # endless: clamp up to 1
      p(Ver.new(5).clamp(Ver.new(1)..).n)              # endless: in range, unchanged
      p(Ver.new(12).clamp(Ver.new(1)..Ver.new(9)).n)   # two-sided: clamp down
      p(Ver.new(0).clamp(Ver.new(1)..Ver.new(9)).n)    # two-sided: clamp up
      p(Ver.new(5).clamp(Ver.new(1)..Ver.new(9)).n)    # two-sided: in range

      # endless exclusive is fine (no end to apply)
      p(Ver.new(0).clamp(Ver.new(1)...).n)

      # a two-sided exclusive range cannot clamp -- CRuby raises ArgumentError
      begin
        Ver.new(5).clamp(Ver.new(1)...Ver.new(9))
        puts "no raise"
      rescue ArgumentError
        puts "excl raised"
      end
    RUBY

    _(result).must_answer <<~'OUT'
      9
      3
      1
      5
      9
      1
      5
      1
      excl raised
    OUT
  end

  it "comparable drives the includers spaceship" do
    result = zr(<<~'RUBY')
      class Temp
        include Comparable
        attr_reader :deg

        def initialize(d)
          @deg = d
        end

        def <=>(other)
          deg <=> other.deg
        end
      end

      a = Temp.new(50)
      b = Temp.new(70)
      puts a < b
      puts a > b
      puts a <= b
      puts b >= a
      puts a == Temp.new(50)
      puts a.between?(Temp.new(40), Temp.new(60))
      puts a.clamp(Temp.new(55), Temp.new(80)).deg
      puts a.clamp(Temp.new(20), Temp.new(30)).deg
    RUBY

    _(result).must_answer <<~'OUT'
      true
      false
      true
      true
      true
      true
      55
      30
    OUT
  end

  it "comparable nil spaceship" do
    result = zr(<<~'RUBY')
      # A <=> returning nil makes the ordering comparisons raise ArgumentError,
      # while Comparable#== instead answers false rather than raising.
      class Bad
        include Comparable
        def <=>(o); nil; end
      end
      begin; Bad.new < Bad.new;  rescue => e; p e.class; p e.message; end
      begin; Bad.new > Bad.new;  rescue => e; p e.class; p e.message; end
      begin; Bad.new <= Bad.new; rescue => e; p e.class; p e.message; end
      begin; Bad.new >= Bad.new; rescue => e; p e.class; p e.message; end
      p(Bad.new == Bad.new)
    RUBY

    _(result).must_answer <<~'OUT'
      ArgumentError
      "comparison of Bad with Bad failed"
      ArgumentError
      "comparison of Bad with Bad failed"
      ArgumentError
      "comparison of Bad with Bad failed"
      ArgumentError
      "comparison of Bad with Bad failed"
      false
    OUT
  end

  it "comparable rational operand" do
    result = zr(<<~'RUBY')
      # A `<=>` whose operand parameter settled on a boxed BUILTIN -- a Rational
      # operand types it that way -- had no arm in the dispatch table at all, so the
      # table came out empty and every comparison through Comparable reported the
      # pair as incomparable, even though the class compares them perfectly well
      # (#4038):
      #
      #   comparison of Fixed with Rational failed (ArgumentError)
      #
      # The user's own `<=>` also has to come before the Rational arm of the runtime
      # comparison, exactly as its own &/|/^ come before the integer coercion: that
      # arm answers for a numeric receiver, and a user object is not one.
      class Fixed
        include Comparable
        attr_reader :units
        def initialize(units) = @units = units

        def <=>(other)
          return nil unless other.is_a?(Rational)

          @units <=> (other * 100).round
        end
      end

      p(Fixed.new(1999) < Rational(40, 2))
      p(Fixed.new(1999) > Rational(40, 2))
      p(Fixed.new(1999) <=> Rational(40, 2))
      p(Fixed.new(2000) == Rational(20, 1))
      p(Fixed.new(1999).between?(Rational(1, 1), Rational(100, 1)))
      p [Fixed.new(300), Fixed.new(100)].map(&:units)

      # an operand the guard rejects is CRuby's ArgumentError, as before
      begin
        p(Fixed.new(1) < 5)
      rescue ArgumentError => e
        p e.class
      end

      # a Time-typed operand takes an arm the same way
      class Stamp
        include Comparable
        def initialize(t) = @t = t
        def <=>(other)
          return nil unless other.is_a?(Time)

          @t <=> other.to_i
        end
      end
      p(Stamp.new(100) < Time.at(200))
      p(Stamp.new(300) <=> Time.at(200))
    RUBY

    _(result).must_answer <<~'OUT'
      true
      false
      -1
      true
      true
      [300, 100]
      ArgumentError
      true
      1
    OUT
  end

  it "comparison operators return real booleans" do
    result = zr(<<~'RUBY')
      puts 5 < 3
      puts 5 > 3
      puts 5 == 5
      puts 5 != 3
      puts 5 <= 5
      puts 5 >= 6
      puts(1 <=> 2)
      puts(2 <=> 2)
      puts(3 <=> 2)
    RUBY

    _(result).must_answer <<~'OUT'
      false
      true
      true
      true
      true
      false
      -1
      0
      1
    OUT
  end

  it "comparison protocol validates spaceship clamp and sort" do
    result = zr(<<~'RUBY')
      class Temp
        include Comparable
        attr_reader :deg
        def initialize(d); @deg = d; end
        def <=>(o); (deg - o.deg).to_f; end
      end
      p [Temp.new(3), Temp.new(1), Temp.new(2)].sort.map(&:deg)
      p Temp.new(5) < Temp.new(9)
      p Temp.new(5).clamp(Temp.new(1), Temp.new(9)).deg
      p Temp.new(5) == Temp.new(5)

      class Ver
        include Comparable
        def initialize(n); @n = n; end
        attr_reader :n
        def <=>(o); o.is_a?(Ver) ? (n <=> o.n) : nil; end
      end
      a = Ver.new(1)
      p a == Ver.new(2)
      p a == a
      p(begin; a < "x"; rescue => e; e.class; end)

      p 5.clamp(1, nil)
      p 5.clamp(nil, 3)
      p(begin; 5.clamp(10, 1); rescue => e; e.message; end)
      p(begin; 5.clamp(1...10); rescue => e; e.message; end)

      x = "a"
      p(begin; [1, x, 2].min; rescue => e; e.message; end)
      p(begin; [1, x, 2].max; rescue => e; e.class; end)
      p({ b: 2, a: 1, c: 3 }.sort)
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
      "cannot clamp with an exclusive range"
      "comparison of String with 1 failed"
      ArgumentError
      [[:a, 1], [:b, 2], [:c, 3]]
    OUT
  end

  it "complex rational interop" do
    result = zr(<<~'RUBY')
      # Mixed Complex/Rational arithmetic computes in floats: the Rational operand
      # coerces via #to_f (docs/limitations.md "Rational precision and Complex
      # components"). The component CLASS deliberately differs from CRuby (float
      # instead of rational), so this pin compares float-normalized components,
      # which agree in both -- keeping the .expected oracle-regenerable.
      def comps(c)
        [c.real.to_f, c.imaginary.to_f]
      end
      p comps(Complex(1, 2) + Rational(1, 2))
      p comps(Complex(1, 2) - Rational(1, 2))
      p comps(Complex(1, 2) * Rational(1, 2))
      p comps(Complex(1, 2) / Rational(1, 2))
      p comps(Rational(1, 2) + Complex(1, 2))
      p comps(Rational(3, 2) * Complex(2, 4))
      p comps(Complex(Rational(1, 2), Rational(1, 3)))
      p comps(Complex(Rational(1, 2)))
      p comps(Complex(3, 4).quo(2))
      p comps(Complex(3, 4).quo(Rational(1, 2)))
      p(10.quo(4))
    RUBY

    _(result).must_answer <<~'OUT'
      [1.5, 2.0]
      [0.5, 2.0]
      [0.5, 1.0]
      [2.0, 4.0]
      [1.5, 2.0]
      [3.0, 6.0]
      [0.5, 0.3333333333333333]
      [0.5, 0.0]
      [1.5, 2.0]
      [6.0, 8.0]
      (5/2)
    OUT
  end

  it "container holding nan equals itself" do
    result = zr(<<~'RUBY')
      # An element inside a container compares by CRuby's `rb_equal`: the SAME
      # object is equal to itself, and `==` is never asked. The `==` OPERATOR
      # takes no such step, so the two answers differ exactly where identity and
      # `==` disagree -- which is what makes `[n] == [n]` true while `n == n` is
      # false for a NaN.
      #
      # Before the split, every container comparison went through the operator,
      # so a NaN anywhere inside one silently made it unequal to itself -- and a
      # NaN inside a container is what a YAML or JSON round trip produces from
      # `.nan`.
      #
      # ONE ROW IS DELIBERATELY ABSENT. CRuby heap-allocates a NaN (it is outside
      # the flonum range), so two SEPARATELY COMPUTED NaNs are different objects
      # and `[0.0/0.0] == [0.0/0.0]` is false there. Zeo's Float is an immediate,
      # so the two are one value and the answer is true. Giving a Float allocation
      # identity to recover that costs the whole numeric representation, and every
      # row below -- the ones a program actually writes -- already agrees.
      n = Float::NAN

      # The operator keeps IEEE's answer.
      p n == n
      p n.equal?(n)

      # Every container reads the element rule instead.
      p [n] == [n]
      p [Float::NAN] == [Float::NAN]
      p({ a: n } == { a: n })
      p [[n]] == [[n]]
      p({ n => 1 } == { n => 1 })
      p [n, [n, { a: n }]] == [n, [n, { a: n }]]

      # ... and so does every search that CRuby drives with `rb_equal`.
      p [n].include?(n)
      p [n].index(n)
      p [n].rindex(n)
      p [n].count(n)
      p [n].delete(n)
      p [[n, 1]].assoc(n)
      p [[1, n]].rassoc(n)
      p({ a: n }.value?(n))
      p({ a: n }.key(n))
      p({ a: n }.assoc(:a))
      p({ a: n }.rassoc(n))
      p({ a: n } <= { a: n })
      p [n].each_entry.include?(n)
      p [n].each_entry.count(n)
      p [n].each_entry.find_index(n)

      S = Struct.new(:x)
      s = S.new(n)
      p s == s
      p S.new(n) == S.new(n)

      # A user `==` that answers false for its own receiver loses to identity the
      # same way -- the container never asks.
      class Never
        def ==(_other) = false
        def inspect = "Never"
      end
      q = Never.new
      p q == q
      p [q] == [q]
      p [q].include?(q)
      p [q].index(q)
    RUBY

    _(result).must_answer <<~'OUT'
      false
      true
      true
      true
      true
      true
      true
      true
      true
      0
      0
      1
      NaN
      [NaN, 1]
      [1, NaN]
      true
      :a
      [:a, NaN]
      [:a, NaN]
      true
      true
      1
      0
      true
      true
      false
      true
      true
      0
    OUT
  end

  it "enumerable min max dispatch a user spaceship" do
    result = zr(<<~'RUBY')
      class Temp
        include Comparable
        attr_reader :deg

        def initialize(d)
          @deg = d
        end

        def <=>(other)
          deg <=> other.deg
        end
      end

      temps = [Temp.new(3), Temp.new(9), Temp.new(5)]
      puts temps.min.deg
      puts temps.max.deg
    RUBY

    _(result).must_answer "3\n9\n"
  end

  it "float bignum compare" do
    result = zr(<<~'RUBY')
      # GAP -- imported from the spinel corpus at fa06b601.
      #
      # Comparing a Float against a BIGNUM answers the wrong way for the values
      # that do not fit a double's integer range.
      #
      # CRuby compares exactly. zeo agrees on the ordinary pairs and diverges on
      # the ones where the conversion loses -- which is the dangerous direction:
      # the comparison silently answers, rather than raising.
      #
      # The original header follows. It describes the PREDECESSOR project's
      # version of this test and its own fix, not zeo's divergence above.
      #
      # A Float against a Bignum was coerced INTO a bignum, which truncates the
      # double to int64 and saturates there, so `1.0 / 0 > 10 ** 100` answered false
      # (with a conversion warning from the C compiler on the way past).
      #
      # Ordering compares as doubles, which is what the runtime's own sp_poly_cmp
      # does for the same pair. Equality is decided exactly, because 1.0e100 and
      # 10 ** 100 differ by one ulp and as doubles would compare equal.
      big = 10 ** 100
      p(1.0e200 > big)
      p(1.0e50 > big)
      p(1.0 > big)
      p(big > 1.0)
      p(big > 1.0e200)
      p(1.0 / 0 > big)
      p(-1.0 / 0 < big)
      p(2.5 < 10 ** 30)
      p(big <= 1.0e200)
      p(big >= 1.0e200)
      p(1.0e200 <=> big)

      p(1.0e100 == big)
      p(big == 1.0e100)
      p(big != 1.0e100)
      p(1.0e200 == big)
      p(big.to_f == big)
      p(1.5 == big)
      p(1.0 / 0 == big)
      p(2.0 == 2 ** 1)
      p(2.0 == 2 ** 70)
      p((2 ** 70).to_f == 2 ** 70)
    RUBY

    _(result).must_answer <<~'OUT'
      true
      false
      false
      true
      false
      true
      true
      true
      true
      false
      1
      false
      false
      true
      false
      false
      false
      false
      true
      false
      true
    OUT
  end

  it "float nan identity" do
    result = zr(<<~'RUBY')
      # GAP -- imported from the spinel corpus at c55d9bdb.
      # Two NaN floats do not compare identical under equal?/eql? the way ruby's
      # boxed NaN does.
      #
      n001 = Float::NAN
      h001 = { n001 => 1 }
      p h001[n001]
      p n001.equal?(n001)
      p [n001].include?(n001)
      p n001.eql?(n001)
      p(n001.hash == n001.hash)
      p(n001 == n001)
    RUBY

    _(result).must_answer <<~'OUT'
      1
      true
      true
      false
      true
      false
    OUT
  end

  it "float spaceship" do
    result = zr(<<~'RUBY')
      # Float#<=> 3-way compare returns -1 / 0 / 1, mirroring Integer#<=>.
      p(3.0 <=> 5.0)
      p(5.0 <=> 3.0)
      p(3.0 <=> 3.0)
      p(3.5 <=> 3)
      p(3 <=> 3.5)

      # A float comparator block now drives sort / min / max / minmax.
      p [3.5, 1.5, 2.5].sort { |a, b| a <=> b }
      p [3.5, 1.5, 2.5].min { |a, b| a <=> b }
      p [3.5, 1.5, 2.5].max { |a, b| a <=> b }
      p [3.5, 1.5, 2.5].minmax { |a, b| a <=> b }
      p [3.5, 1.5, 2.5].minmax { |a, b| b <=> a }
    RUBY

    _(result).must_answer <<~'OUT'
      -1
      1
      0
      1
      -1
      [1.5, 2.5, 3.5]
      1.5
      3.5
      [1.5, 3.5]
      [3.5, 1.5]
    OUT
  end

  it "integer and a float compare exactly" do
    result = zr(<<~'RUBY')
      # `Integer <=> Float` is decided EXACTLY (`rb_integer_float_cmp`), and an
      # incomparable pair answers FALSE rather than raising.
      #
      # Both halves were wrong. Promoting the Integer to a double and comparing
      # there answers `10**100 == 1.0e100` true -- they are different numbers and
      # the double cannot tell -- and the same promotion made `2**53 + 1` equal to
      # `2.0**53`, which is the shape that reaches ordinary code. The emitter's
      # inline `fcmp` for a mixed pair now gives up past 2**53 and lets the
      # runtime compare in integers.
      #
      # The NaN half: CRuby hand-writes `<`/`<=`/`>`/`>=` on Integer and Float so
      # that `<=>`'s nil becomes false. Only a Rational or Complex RECEIVER keeps
      # Comparable's `comparison of X with Y failed` -- which is why
      # `Float::NAN < Rational(1,2)` is false while `Rational(1,2) < Float::NAN`
      # raises.
      big = 10**100
      p [1.0e100 == big, big == 1.0e100, big.to_f == big, (2**70).to_f == 2**70]
      p [2**53 + 1 == 2.0**53, 2.0**53 == 2**53 + 1, 2**53 + 1 > 2.0**53, 2.0**53 < 2**53 + 1]
      p [(2**53 + 1) <=> 2.0**53, 2.0**53 <=> (2**53 + 1), 2**53 <=> 2.0**53]
      p [big <=> 1.0e100, 1.0e100 <=> big, big > 1.0e100, 1.0 / 0 > big]

      nan = Float::NAN
      p [1 < nan, 1 > nan, 1 <= nan, 1 >= nan, 1 == nan]
      p [big < nan, big > nan, big <= nan, big >= nan]
      p [nan < 1, nan > 1, nan < big, nan > big, nan < nan]
      p [nan < Rational(1, 2), nan > Rational(1, 2)]
      begin
        Rational(1, 2) < nan
      rescue ArgumentError => e
        p e.message
      end
      begin
        1 < "x"
      rescue ArgumentError => e
        p e.message
      end
    RUBY

    _(result).must_answer <<~'OUT'
      [false, false, false, true]
      [false, false, true, true]
      [1, -1, 0]
      [-1, 1, false, true]
      [false, false, false, false, false]
      [false, false, false, false]
      [false, false, false, false, false]
      [false, false]
      "comparison of Rational with NaN failed"
      "comparison of Integer with String failed"
    OUT
  end

  it "integer equality across types inline" do
    result = zr(<<~'RUBY')
      class Eq
        def ==(other) = other == 1
      end

      def cmp(a, b) = [a == b, a != b]

      p cmp(1, 1.0), cmp(1, 1.5), cmp(1, 1r), cmp(1, Eq.new)
      p cmp(1, 2), cmp(1, 1), cmp(1, nil), cmp(1, "1")
      p cmp(2**64, 2**64), cmp(1, 2**64)
      p cmp(-3, -3.0), cmp(0, -0.0)

    RUBY

    _(result).must_answer <<~'OUT'
      [true, false]
      [false, true]
      [true, false]
      [true, false]
      [false, true]
      [true, false]
      [false, true]
      [false, true]
      [true, false]
      [false, true]
      [true, false]
      [true, false]
    OUT
  end

  it "nil hashdefault complex followups" do
    result = zr(<<~'RUBY')
      # Variable-receiver NilClass conversions captured into locals, variable
      # Hash.new(default) folds, and the Complex query-method family.
      n = nil; v = (n.to_a); p v
      w = (n.to_r); p w
      h = (n.to_h); p h
      z = (n.to_c); p z
      a = Hash.new(7); p(a.default)
      b = Hash.new("d"); p(b["missing"])
      p(Complex(0, 0).zero?)
      p(Complex(2, 3).zero?)
      p(Complex(2, 3).real?)
      p(Complex(2, 3).integer?)
      p(Complex(2, 3).finite?)
      p(Complex(2, 3).infinite?)
      p(Complex(1.0/0.0, 0).infinite?)
      p(Complex(2, 3).eql?(Complex(2, 3)))
      p(Complex(2, 3).eql?(Complex(2, 4)))
      p(Complex(2, 0).rationalize)
    RUBY

    _(result).must_answer <<~'OUT'
      []
      (0/1)
      {}
      (0+0i)
      7
      "d"
      true
      false
      false
      false
      true
      nil
      1
      true
      false
      (2/1)
    OUT
  end

  it "nil spaceship variable" do
    result = zr(<<~'RUBY')
      # nil <=> nil is 0 (Integer), including when the nil is held in a variable
      # (a nil-only local widens to a boxed poly value, so this exercises the
      # poly <=> path, not the literal-nil fold).
      a = nil; b = nil
      p(a <=> b)
      p((a <=> b).class)
    RUBY

    _(result).must_answer "0\nInteger\n"
  end

  it "range eq across numeric" do
    result = zr(<<~'RUBY')
      # Range#== compares its endpoints with ==, and 1 == 1.0, so an Integer Range
      # equals the Float Range with the same endpoints (#3841).
      p((1..5) == (1.0..5.0))
      p((1.0..5.0) == (1..5))
      p((1..5) == (1.0..6.0))
      p((1...5) == (1.0..5.0))
      p((1...5) == (1.0...5.0))
      p((1..5) == (1..5))
      p((1..5) != (1.0..5.0))
    RUBY

    _(result).must_answer <<~'OUT'
      true
      true
      false
      false
      true
      true
      false
    OUT
  end

  it "rational eq poly operand" do
    result = zr(<<~'RUBY')
      # Rational#== / #eql? against an operand whose type is not known here -- a
      # Rational read out of an Array is the usual way that happens. A poly operand
      # is not a non-numeric operand, but the arm treated it as one and answered a
      # constant false, so the comparison was false one way round and true the other.
      [Rational(5, 6)].each { |r| p(Rational(5, 6) == r) }
      [Rational(5, 6)].each { |r| p(r == Rational(5, 6)) }
      [Rational(5, 6)].each { |r| p(Rational(5, 6) != r) }
      [Rational(5, 6)].each { |r| p(Rational(5, 6) === r) }

      x = [Rational(5, 6)].first
      p(Rational(5, 6) == x)
      p(Rational(1, 2) == x)

      # #eql? is #== plus a class check, so a poly operand must be asked at run time
      # whether it IS a Rational
      [Rational(5, 6)].each { |r| p(Rational(5, 6).eql?(r)) }
      [Rational(1, 1)].each { |r| p(Rational(1, 1) == r) }
      mixed = [Rational(1, 1), 1, "x"]
      p(Rational(1, 1) == mixed[0])
      p(Rational(1, 1) == mixed[1])
      p(Rational(1, 1).eql?(mixed[0]))
      p(Rational(1, 1).eql?(mixed[1]))
      p(Rational(1, 1) == mixed[2])

      p([Rational(5, 6)].select { |r| Rational(5, 6) == r }.size)
      p([Rational(5, 6)].map { |r| Rational(5, 6) <=> r })
    RUBY

    _(result).must_answer <<~'OUT'
      true
      true
      false
      true
      true
      false
      true
      true
      true
      true
      true
      false
      false
      1
      [0]
    OUT
  end

  it "rational step" do
    result = zr(<<~'RUBY')
      # Numeric#step on a Rational receiver walks the exact sequence, yielding
      # Rational/Integer values through the poly numeric tower (sp_poly_add keeps a
      # Rational operand rational). Block form iterates and returns self; the
      # blockless form materializes the sequence. Regression for #2566.
      Rational(1,2).step(Rational(5,2), 1) { |x| p x }
      p Rational(1,2).step(Rational(5,2), 1).to_a
      p Rational(5,2).step(Rational(1,2), Rational(-1,1)).to_a   # descending
      p Rational(1,1).step(3, 1).to_a                            # Integer limit and step
      p Rational(1,2).step(Rational(5,2), 1).map { |x| x * 2 }   # chained enumerator
      r = Rational(0,1)
      ret = r.step(Rational(1,1), Rational(1,2)) { |x| }
      p ret == r                                                 # block form returns self

      # step of 0 raises ArgumentError
      begin
        Rational(1,2).step(Rational(5,2), 0) { |x| }
        puts "no raise"
      rescue ArgumentError
        puts "zero raised"
      end

      # a boxed Rational also sorts/compares now (poly cmp fix)
      p [Rational(5,2), Rational(1,2), Rational(3,2)].sort
    RUBY

    _(result).must_answer <<~'OUT'
      (1/2)
      (3/2)
      (5/2)
      [(1/2), (3/2), (5/2)]
      [(5/2), (3/2), (1/2)]
      [(1/1), (2/1), (3/1)]
      [(1/1), (3/1), (5/1)]
      true
      zero raised
      [(1/2), (3/2), (5/2)]
    OUT
  end

  it "rational takes its order and division from numeric" do
    result = zr(<<~'RUBY')
      # Rational defines neither the comparisons nor div, modulo, remainder,
      # divmod, eql?, zero? and integer?: Comparable and Numeric answer them
      # over Rational's own <=>, / and floor, as CRuby's nurat leaves them.

      p Rational(7, 2) % 1.5, Rational(7, 2).divmod(Rational(1, 3)), Rational(-7, 2).remainder(2)
      p Rational(1, 2) < 1, Rational(1, 2) >= 0.5, Rational(0).zero?, Rational(1, 2).integer?
      p Rational(1, 2).eql?(Rational(1, 2)), Rational(1, 2).eql?(0.5)
      p Rational(5, 3).div(Rational(1, 2)), Rational(5, 3).modulo(2), Rational(-5, 3).divmod(2)
      [-> { Rational(1, 2) < "a" }, -> { Rational(1, 2) % 0.0 }, -> { Rational(1, 2).div(0) }].each do |bad|
        bad.call
      rescue => e
        p e
      end
      p Rational.public_instance_methods(false).sort
      p Rational.instance_method(:<).owner, Rational.instance_method(:div).owner

    RUBY

    _(result).must_answer <<~'OUT'
      0.5
      [10, (1/6)]
      (-3/2)
      true
      true
      true
      false
      true
      false
      3
      (5/3)
      [-1, (1/3)]
      #<ArgumentError: comparison of Rational with String failed>
      #<ZeroDivisionError: divided by 0>
      #<ZeroDivisionError: divided by 0>
      [:*, :**, :+, :-, :-@, :/, :<=>, :==, :abs, :ceil, :coerce, :denominator, :fdiv, :floor, :hash, :inspect, :magnitude, :negative?, :numerator, :positive?, :quo, :rationalize, :round, :to_f, :to_i, :to_r, :to_s, :truncate]
      Comparable
      Numeric
    OUT
  end

  it "spaceship incomparable nil" do
    result = zr(<<~'RUBY')
      # <=> between incomparable operands returns nil (it raised NoMethodError);
      # comparable pairs are unchanged, and a poly operand decides at runtime.
      p(1 <=> "a")
      p("a" <=> 1)
      p(1.0 <=> "x")
      p(:s <=> 3)
      p(1 <=> 2)
      p(1 <=> 2.0)
      p("a" <=> "b")
      p([1, 2] <=> [1, 3])
      mixed = [1, "a", 2]
      p(mixed[0] <=> mixed[1])
      p(mixed[0] <=> mixed[2])
    RUBY

    _(result).must_answer <<~'OUT'
      nil
      nil
      nil
      nil
      -1
      -1
      -1
      -1
      nil
      -1
    OUT
  end

  it "when splat rational complex" do
    result = zr(<<~'RUBY')
      # `when *array` is membership; `when <Rational>` / `when <Complex>` are
      # value equality. All three previously failed (splat never matched;
      # Rational/Complex produced a C compile error from `int == struct`).
      a = [1, 2, 3]
      case 2
      when *a then puts "in"
      else puts "out"
      end
      case 9
      when *a then puts "in"
      else puts "out"
      end

      case 0
      when 0r then puts "r-zero"
      else puts "r-other"
      end
      case 1
      when 0r then puts "r-zero"
      else puts "r-other"
      end

      case 0
      when 0i then puts "c-zero"
      else puts "c-other"
      end
      case 1
      when 0i then puts "c-zero"
      else puts "c-other"
      end
    RUBY

    _(result).must_answer <<~'OUT'
      in
      out
      r-zero
      r-other
      c-zero
      c-other
    OUT
  end
end
