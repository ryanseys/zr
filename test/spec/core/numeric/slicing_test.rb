# frozen_string_literal: true

require "spec_helper"

describe "Numeric: slicing" do
  it "bignum bit length" do
    result = ze0(<<~'RUBY')
      # Integer#bit_length on a Bignum (a value larger than int64): the parser lexes
      # the literal into a bigint, and bit_length answers the number of bits, an int.

      p 9223372036854775808.bit_length     # 64  (2**63, the first value past int64)
      p 18446744073709551616.bit_length    # 65  (2**64)
      p (2 ** 64).bit_length               # 65  (computed bignum)
      p (2 ** 100).bit_length              # 101
      p (10 ** 30).bit_length              # 100

      # through a poly-returning method, so the bigint flows across a call boundary
      def id(x) = x
      p id(2 ** 70).bit_length             # 71
    RUBY

    _(result).must_answer <<~'OUT'
      64
      65
      65
      101
      100
      71
    OUT
  end

  it "bignum range endpoint is an integer range" do
    result = ze0(<<~'RUBY')
      # A `Range` whose endpoint is a BIGNUM is an integer range like any other.
      #
      # zeo's range machinery narrowed every endpoint to a machine integer and
      # treated a `BigInt` as a non-integer, so `each`, `to_a`, `first(n)`,
      # `last(n)`, `bsearch` and `size` all raised `TypeError: can't iterate from
      # Integer` -- a message that names `Integer` as the thing it cannot iterate
      # from, which was the tell. The neighbours that DID work said where the line
      # was: `min`, `max`, `step`, `include?` and `cover?` all agreed already,
      # because they compare rather than iterate.
      #
      # `big_endpoint` is the shared view -- an integer endpoint at full width,
      # whichever the value arrived in -- and `big_in_range` its bound test. The
      # counter decides the width, not the endpoint, so `(2**70..2**70+2)` narrows
      # back down as it goes.
      #
      # Two rows were WORSE than a divergence: `(1..2**70).sum` and `.count` HUNG,
      # because zeo iterated where ruby answers in closed form. Those closed forms
      # are why ruby answers at all -- Gauss for `sum`, `size` for `count` -- and
      # `size` is the same story (`end - begin + 1`, which is also why it is
      # instant).

      B = 2**70

      p [(1..B).size, (B..B + 2).size, (B..B * 2).size, (1...B).size]
      # An empty range at full width is 0, not a negative count.
      p [(B...B).size, (B..B - 1).size]
      p [(1..B).min, (1..B).max, (B..B + 5).min, (B..B + 5).max]

      p (B..B + 5).each.first(2)
      p (B..B + 2).to_a
      p (B..B + 4).step(2).to_a
      p [(B..B + 2).include?(B + 1), (B..B + 2).cover?(B + 1), (B..B + 2).include?(B + 9)]

      # Both bsearch modes, and the no-hit answer.
      p (B..B + 8).bsearch { |x| x >= B + 3 }
      p (B..B + 8).bsearch { |x| B + 3 <=> x }
      p (B..B + 8).bsearch { false }

      p [(B..B + 5).first(2), (B..B + 5).last(2), (B..B + 5).first, (B..B + 5).last]
      p (B..B + 3).map { |x| x - B }
      p (B..B + 3).select(&:even?).map { |x| x - B }
      p (B..B + 3).each_slice(2).to_a.map { |a| a.map { |x| x - B } }
      p ((-B)..(-B + 2)).to_a.map { |x| x + B }
      p (B..).first(2)
      p (1..B).lazy.map { |x| x * 2 }.first(3)

      # The closed forms, which are what makes these terminate at all.
      p (1..B).sum
      p (1..B).count
      p (1...B).sum
      p (B..B + 3).sum - 4 * B
      p (B..B + 3).count

      # ... and the shapes that must still walk.
      p [(1..5).sum, (1..5).sum(10), (1..5).sum { |x| x * 2 }, (1..5).sum(0.0)]
      p [(5..1).sum, (5..1).count]
      p ("a".."c").sum("")
      p [(1..3).count { |x| x > 1 }, (1..3).count(2)]
    RUBY

    _(result).must_answer <<~'OUT'
      [1180591620717411303424, 3, 1180591620717411303425, 1180591620717411303423]
      [0, 0]
      [1, 1180591620717411303424, 1180591620717411303424, 1180591620717411303429]
      [1180591620717411303424, 1180591620717411303425]
      [1180591620717411303424, 1180591620717411303425, 1180591620717411303426]
      [1180591620717411303424, 1180591620717411303426, 1180591620717411303428]
      [true, true, false]
      1180591620717411303427
      1180591620717411303427
      nil
      [[1180591620717411303424, 1180591620717411303425], [1180591620717411303428, 1180591620717411303429], 1180591620717411303424, 1180591620717411303429]
      [0, 1, 2, 3]
      [0, 2]
      [[0, 1], [2, 3]]
      [0, 1, 2]
      [1180591620717411303424, 1180591620717411303425]
      [2, 4, 6]
      696898287454081973173581491830620002713600
      1180591620717411303424
      696898287454081973172400900209902591410176
      6
      4
      [15, 25, 30, 15.0]
      [0, 0]
      "abc"
      [2, 1]
    OUT
  end

  it "bignum times counts from zero" do
    result = ze0(<<~'RUBY')
      # `(10**30).times` counts from 0 like any receiver: ruby yields lazily, so an
      # early `break` works even when the full count is physically unrunnable. A
      # negative receiver yields nothing and answers itself.
      got = []
      r = (10**30).times do |i|
        got << i
        break :early if i >= 2
      end
      p got
      p r
      p((-(10**30)).times { raise "unreachable" })
      p (10**30).times.first(2)
    RUBY

    _(result).must_answer <<~'OUT'
      [0, 1, 2]
      :early
      -1000000000000000000000000000000
      [0, 1]
    OUT
  end

  it "clamp accepts a range as well as two bounds" do
    result = ze0(<<~'RUBY')
      p 0.clamp(1..5)
      p 9.clamp(1..5)
      p 3.clamp(1..5)
      p 0.clamp(1..)
      p 99.clamp(..5)
      p 9.clamp(1, 5)
      begin
        9.clamp(1...5)
      rescue ArgumentError => e
        puts "ArgumentError"
      end
    RUBY

    _(result).must_answer <<~'OUT'
      1
      5
      3
      1
      5
      5
      ArgumentError
    OUT
  end

  it "clamp bounds" do
    result = ze0(<<~'RUBY')
      # clamp must raise ArgumentError when the minimum bound exceeds the maximum,
      # and Float#clamp must also raise when any operand is NaN (comparisons with
      # NaN are undefined). Receiver and bounds are routed through method params so
      # the runtime helpers are exercised, not a compile-time fold.
      def show_i(label, x, lo, hi)
        print label, ": "
        p x.clamp(lo, hi)
      rescue => e
        puts "#{e.class}: #{e.message}"
      end

      def show_ir(label, x)
        print label, ": "
        p x.clamp(10..2)
      rescue => e
        puts "#{e.class}: #{e.message}"
      end

      def show_f(label, x, lo, hi)
        print label, ": "
        p x.clamp(lo, hi)
      rescue => e
        puts "#{e.class}: #{e.message}"
      end

      nan = 0.0 / 0.0

      show_i("int ok", 5, 1, 9)
      show_i("int min>max", 5, 10, 2)
      show_ir("int range bad", 5)
      show_f("float ok", 5.0, 1.5, 3.5)
      show_f("float min>max", 5.0, 2.0, 1.0)
      show_f("float recv nan", nan, 1.0, 2.0)
      show_f("float lo nan", 1.5, nan, 2.0)
      show_f("float hi nan", 1.5, 1.0, nan)
    RUBY

    _(result).must_answer <<~'OUT'
      int ok: 5
      int min>max: ArgumentError: min argument must be less than or equal to max argument
      int range bad: ArgumentError: min argument must be less than or equal to max argument
      float ok: 3.5
      float min>max: ArgumentError: min argument must be less than or equal to max argument
      float recv nan: ArgumentError: comparison of Float with 1.0 failed
      float lo nan: ArgumentError: comparison of Float with 2.0 failed
      float hi nan: ArgumentError: comparison of Float with NaN failed
    OUT
  end

  it "fdiv and divmod take any operand ruby does" do
    result = ze0(<<~'RUBY')
      # fdiv divides big Integers before it rounds, so a quotient in range
      # comes out even when each side is past a double; Float#divmod coerces
      # an operand it does not know, as every Float operator does.
      def t = yield rescue [$!.class, $!.message]

      p t { (10**400).fdiv(10**399) }, t { -(10**400).fdiv(10**399) }, t { (10**400).fdiv(3) }
      p t { (2**100).fdiv(2**99) }, t { 1.fdiv(3) }, t { 10.fdiv(4) }, t { 1.fdiv(0) }
      p t { (10**400).fdiv(1e300) }, t { 7.fdiv(2r) }, t { (3**200).fdiv(7**90) }

      p t { 1.5.divmod(1r) }, t { -7.5.divmod(2r) }, t { 1.5.divmod(2) }
      p t { 1.5.divmod("x") }, t { 1.5.div(1r) }

    RUBY

    _(result).must_answer <<~'OUT'
      10.0
      -10.0
      Infinity
      2.0
      0.3333333333333333
      2.5
      Infinity
      1.0e+100
      3.5
      2.3196760719186784e+19
      [1, 0.5]
      [-4, 0.5]
      [0, 1.5]
      [TypeError, "String can't be coerced into Float"]
      1
    OUT
  end

  it "float operator redefinition" do
    result = ze0(<<~'RUBY')
      # Redefining an operator on the numeric fast-path MRO stands the native
      # fast paths down for that operator (per lane), so the user body wins at
      # statically-typed sites, poly sites, and send alike -- while untouched
      # operators and the other lane keep their native paths (1 + 2, 7 * 6,
      # and Integer#+ under a Float-only redefinition stay native).
      class Float
        def +(other) = "float-plus(#{self},#{other})"
      end
      module Comparable
        def <=>(other) = nil
      end
      p 1.5 + 2.0
      p 1 + 2
      p 1 + 2.5
      x = [1.5].first
      p x + 3.0
      p 2.5.send(:+, 4.0)
      p(-1.5)
      p 7 * 6
    RUBY

    _(result).must_answer <<~'OUT'
      "float-plus(1.5,2.0)"
      3
      3.5
      "float-plus(1.5,3.0)"
      "float-plus(2.5,4.0)"
      -1.5
      42
    OUT
  end

  it "float range endpoint kind" do
    result = ze0(<<~'RUBY')
      # A range is a Float range when EITHER endpoint is one, and its endpoint
      # methods answer the endpoint the caller wrote (#3837).
      p((-Float::INFINITY..5).max)
      p((-Float::INFINITY..5).last)
      p((1..5.0).min)
      p((1.0..5.0).max)
      p((1..5).max)
      p((0.5..5).max)
      p((1..5.5).min)
    RUBY

    _(result).must_answer <<~'OUT'
      5
      5
      1
      5.0
      5
      5
      1
    OUT
  end

  it "float range minmax" do
    result = ze0(<<~'RUBY')
      r001 = ((1.0..5.0).minmax rescue $!.class); p r001
      a002 = (1.0..5.0); r002 = (a002.minmax rescue $!.class); p r002
      p((1.0..5.0).min)
      p((1.0..5.0).max)
      r003 = ((1.0...5.0).minmax rescue $!.class); p r003
      p((1..5).minmax)
      p(("a".."e").minmax)
    RUBY

    _(result).must_answer <<~'OUT'
      [1.0, 5.0]
      [1.0, 5.0]
      1.0
      5.0
      TypeError
      [1, 5]
      ["a", "e"]
    OUT
  end

  it "integer clamp float bound" do
    result = ze0(<<~'RUBY')
      # Integer#clamp returns the applied operand unchanged, so a Float bound that
      # clamps yields a Float while an in-range Integer receiver stays an Integer.
      # Receiver and bounds route through a method param so the runtime helper is
      # exercised rather than a compile-time fold.
      def s(x); x; end

      # clamped to a Float bound -> Float
      p s(5).clamp(1.0, 3.0)
      p s(0).clamp(1.0, 10.0)
      # in range with Float bounds -> Integer receiver kept
      p s(5).clamp(1.0, 10.0)
      # one int bound, one float bound
      p s(5).clamp(1, 3.0)
      p s(2).clamp(1, 3.5)
      p s(7).clamp(1, 3.5)
      # pure-int bounds still Integer
      p s(5).clamp(1, 10)
      p s(-4).clamp(0, 9)
      # classes
      p s(5).clamp(1.0, 3.0).class
      p s(5).clamp(1.0, 10.0).class
      p s(2).clamp(1, 3.5).class

      # exceptional: disordered / NaN bounds raise ArgumentError with CRuby messages
      def show(x, lo, hi)
        p x.clamp(lo, hi)
      rescue => e
        puts "#{e.class}: #{e.message}"
      end
      nan = 0.0 / 0.0
      show(s(5), 10, 2)
      show(s(5), nan, 2.0)
      show(s(5), 1.0, nan)
      show(s(5), 1, nan)
      show(s(5), nan, 2)
    RUBY

    _(result).must_answer <<~'OUT'
      3.0
      1.0
      5
      3.0
      2
      3.5
      5
      0
      Float
      Integer
      Integer
      ArgumentError: min argument must be less than or equal to max argument
      ArgumentError: comparison of Float with 2.0 failed
      ArgumentError: comparison of Float with NaN failed
      ArgumentError: comparison of Integer with NaN failed
      ArgumentError: comparison of Float with 2 failed
    OUT
  end

  it "integer gcd arg check" do
    result = ze0(<<~'RUBY')
      # GAP -- imported from the spinel corpus at c55d9bdb.
      # Integer#gcd with a non-integer raises the coercion message; ruby raises
      # "not an integer".
      #
      # Integer#gcd / #lcm / #gcdlcm take an Integer; anything else is CRuby's
      # "not an integer" TypeError. Only a Float was caught, so a String went into
      # the mrb_int slot as a pointer and the result was computed from its address.
      p((5.gcd("x") rescue $!.message))
      p((5.lcm(nil) rescue $!.message))
      p((5.gcd(1.5) rescue $!.message))
      p((5.gcd(:a) rescue $!.message))
      p((5.lcm([1]) rescue $!.message))
      p(5.gcd(10))
      p(4.lcm(6))
      p(4.gcdlcm(6))
    RUBY

    _(result).must_answer <<~'OUT'
      "not an integer"
      "not an integer"
      "not an integer"
      "not an integer"
      "not an integer"
      5
      12
      [2, 12]
    OUT
  end

  it "numeric long tail ranges bignum iteration and hex float" do
    result = ze0(<<~'RUBY')
      # Symbol range iterates by name succession.
      p (:a..:e).to_a
      # Float range: O(1) min/max, drift-free step, float bsearch, and each
      # raises (can't iterate a float range).
      p (1.0..3.0).min
      p (1.0..3.0).max
      p (1.0..3.0).step(0.5).to_a
      p (0.0..10.0).bsearch { |x| x >= 3.5 }
      p(begin; (1.0..3.0).to_a; rescue => e; e.message; end)
      # Negative integer step walks a descending range.
      p (10..2).step(-2).to_a
      # downto/upto beyond i64 iterate as BigInt, and .size is exact.
      big = 2 ** 100
      p big.downto(big - 2).to_a
      p big.downto(big - 2).size
      # downto with a Float limit yields integers.
      p 5.downto(2.0).to_a
      # C99 hex-float strings.
      p Float("0x1p4")
      p Float("0xa")
    RUBY

    _(result).must_answer <<~'OUT'
      [:a, :b, :c, :d, :e]
      1.0
      3.0
      [1.0, 1.5, 2.0, 2.5, 3.0]
      3.5
      "can't iterate from Float"
      [10, 8, 6, 4, 2]
      [1267650600228229401496703205376, 1267650600228229401496703205375, 1267650600228229401496703205374]
      3
      [5, 4, 3, 2]
      16.0
      10.0
    OUT
  end

  it "numeric reopen resolves down the mro" do
    result = ze0(<<~'RUBY')
      # A `class Numeric` reopen materializes onto Integer AND Float (the mro
      # machinery) and is found on both static receivers and dynamic Poly ones
      # (the per-ancestor value-method walk).

      class Numeric
        def double
          self * 2
        end
      end

      puts 5.double
      puts 2.5.double
      puts [7].first.double
    RUBY

    _(result).must_answer <<~'OUT'
      10
      5.0
      14
    OUT
  end

  it "numeric tower methods" do
    result = ze0(<<~'RUBY')
      # Integer#bit_length, Integer#fdiv / Float#fdiv, Float#eql? (type-strict),
      # and Math.gamma. fdiv always returns a Float; eql? is true only for a Float
      # of equal value (no numeric coercion).
      p 42.bit_length
      p 0.bit_length
      p 255.bit_length
      p 1024.bit_length

      p 10.fdiv(3)
      p 7.fdiv(2)
      p 2.5.fdiv(2)

      p 1.0.eql?(1)
      p 1.0.eql?(1.0)
      p 2.0.eql?(2)

      # eql? is never true for NaN: it returns false when either side is NaN, matching
      # CRuby (a NaN matches as a hash key only by object identity, not via eql?). Both
      # the float-typed and the boxed-argument paths go through value equality.
      def nan; 0.0 / 0.0; end
      p nan.eql?(nan)
      mixed = [0.0 / 0.0, 7]
      p nan.eql?(mixed.first)

      p Math.gamma(5)
      p Math.gamma(1)

      def bl(n)
        n.bit_length
      end
      p bl(65535)

      # Math.gamma raises Math::DomainError at the negative-integer poles, but 0.0
      # is +Infinity (not a raising pole).
      begin
        Math.gamma(-1.0)
      rescue Math::DomainError => e
        puts e.message
      end
      p Math.gamma(0.0)

      # fdiv unboxes a polymorphic argument (here an element of a mixed array).
      bases = [2, "x"]
      p 10.fdiv(bases.first)
      p 2.5.fdiv(bases.first)
    RUBY

    _(result).must_answer <<~'OUT'
      6
      0
      8
      11
      3.3333333333333335
      3.5
      1.25
      false
      true
      false
      false
      false
      24.0
      1.0
      16
      Numerical argument is out of domain - gamma
      Infinity
      5.0
      1.25
    OUT
  end

  it "numeric tower remainder" do
    result = ze0(<<~'RUBY')
      # Numeric tower remainder: Integer#[start, len] (the len-bit field starting at
      # bit `start`) and Math.lgamma (which returns [log(|gamma(x)|), sign]). The
      # integer receiver goes through a method param to exercise the runtime path.
      def i(x); x; end

      # bit-range field extraction
      p i(0b1011010)[1, 3]
      p i(255)[0, 4]
      p i(255)[4, 4]
      p i(0b110100)[2, 4]
      p i(42)[2]

      # Out-of-range start/len must not trigger an undefined shift: a len at/above
      # the word width keeps every shifted bit, a non-positive len or a start past
      # the width behaves as CRuby's two's-complement model does.
      def br(n, s, l); n[s, l]; end
      p br(255, 2, 100)
      p br(5, 2, -1)
      p br(5, -1, 3)
      p br(255, 0, -5)
      p br(-1, 60, 8)
      p br(255, 100, 4)
      p br(1, 64, 1)
      p br(7, 0, 0)

      # Math.lgamma -> [value, sign]. The value is computed in-tree (Stirling's
      # series + the Gamma recurrence) and ultimately depends on libm log()/sin(),
      # whose last ULP is not portable across implementations, so assert it within a
      # tight tolerance rather than pinning the exact bits. The exact points
      # (lgamma(1) = lgamma(2) = 0) and the sign are bit-stable and checked directly.
      g5 = Math.lgamma(5)                                  # ~ log(24)
      p(g5[0] > 3.1780538303 && g5[0] < 3.1780538304)
      p g5[1]
      gh = Math.lgamma(0.5)                                # ~ log(sqrt(pi))
      p(gh[0] > 0.5723649429 && gh[0] < 0.5723649430)
      p gh[1]
      p Math.lgamma(1)
      p Math.lgamma(2)
    RUBY

    _(result).must_answer <<~'OUT'
      5
      15
      15
      13
      0
      63
      1
      2
      255
      255
      0
      0
      0
      true
      1
      true
      1
      [0.0, 1]
      [0.0, 1]
    OUT
  end

  it "random float seed" do
    result = ze0(<<~'RUBY')
      # Random.new(Float): CRuby truncates to an integer seed. An out-of-range float
      # must still yield a reproducible generator (a plain C cast would be UB).
      p(Random.new(1e300).rand(1000) == Random.new(1e300).rand(1000))
      p(Random.new(2.0**70).rand(1000) == Random.new(2.0**70).rand(1000))
      p(Random.new(3.9).rand(1000) == Random.new(3.9).rand(1000))
      p(Random.new(1e300).rand(1000) != Random.new(2e300).rand(1000))
      p(Random.new(3.9).rand(100) >= 0)
    RUBY

    _(result).must_answer <<~'OUT'
      true
      true
      true
      true
      true
    OUT
  end

  it "range float begin iterate" do
    result = ze0(<<~'RUBY')
      begin; p (1.0..5.0).sum; rescue TypeError => e; puts "sum: #{e.message}"; end
      begin; (1.0..5.0).each { |x| p x }; rescue TypeError => e; puts "each: #{e.message}"; end
      begin; p (1.0..5.0).to_a; rescue TypeError => e; puts "to_a: #{e.message}"; end
      begin; p (1.0..5.0).map { |x| x * 2 }; rescue TypeError => e; puts "map: #{e.message}"; end
      begin; p (1.0..5.0).count; rescue TypeError => e; puts "count: #{e.message}"; end
      begin; p (1.0..5.0).size; rescue TypeError => e; puts "size: #{e.message}"; end
      p (1..5.0).to_a
      p (1.0..5.0).include?(2.5)
      r = (2.0..9.0)
      begin; p r.sum; rescue TypeError => e; puts "local: #{e.message}"; end
      p (1.0..5.0).step(2.0).to_a
    RUBY

    _(result).must_answer <<~'OUT'
      sum: can't iterate from Float
      each: can't iterate from Float
      to_a: can't iterate from Float
      map: can't iterate from Float
      count: can't iterate from Float
      size: can't iterate from Float
      [1, 2, 3, 4, 5]
      true
      local: can't iterate from Float
      [1.0, 3.0, 5.0]
    OUT
  end

  it "range float type" do
    result = ze0(<<~'RUBY')
      # Distinct Float range type (1.0..3.0)
      r = (1.0..3.0)
      p r
      p r.begin
      p r.end
      p r.first
      p r.last
      p r.min
      p r.max
      p r.include?(2.0)
      p r.include?(5.0)
      p r.include?(0.0)
      p r.cover?(1.5)
      p r.cover?(3.0)
      p r.exclude_end?
      p r === 2.5
      p r === 3.5
      p (1.0...3.0).exclude_end?
      p (1.0...3.0).cover?(3.0)
      p r == (1.0..3.0)
      p r == (1.0..4.0)
      p r.eql?(1.0..3.0)
      p r.to_s
      p r.inspect
      puts r
      p r.step(0.5).to_a
      p (0.0..1.0).step(0.25).to_a
      p (3.0..1.0).step(0.5).to_a
      p (1.0..3.0).class
      p r.frozen?

      # exclusive max raises
      begin
        (1.0...3.0).max
      rescue TypeError => e
        puts "max-excl: TypeError"
      end

      # iteration raises
      begin
        (1.0..3.0).to_a
      rescue TypeError => e
        puts "to_a: #{e.message}"
      end
      begin
        (1.0..3.0).each { |x| p x }
      rescue TypeError => e
        puts "each: #{e.message}"
      end

      # bsearch bisects the reals
      p (0.0..10.0).bsearch { |x| x >= 3.5 }

      # case/when membership
      case 2.5
      when 1.0..3.0 then puts "in"
      else puts "out"
      end
      case 9.9
      when 1.0..3.0 then puts "in"
      else puts "out"
      end

      # an ordinary int range is unaffected
      ir = (1..3)
      p ir
      p ir.to_a
      p ir.include?(2)
    RUBY

    _(result).must_answer <<~'OUT'
      1.0..3.0
      1.0
      3.0
      1.0
      3.0
      1.0
      3.0
      true
      false
      false
      true
      true
      false
      true
      false
      true
      false
      true
      false
      true
      "1.0..3.0"
      "1.0..3.0"
      1.0..3.0
      [1.0, 1.5, 2.0, 2.5, 3.0]
      [0.0, 0.25, 0.5, 0.75, 1.0]
      []
      Range
      true
      max-excl: TypeError
      to_a: can't iterate from Float
      each: can't iterate from Float
      3.5
      in
      out
      1..3
      [1, 2, 3]
      true
    OUT
  end

  it "range size covers endless and float ends" do
    result = ze0(<<~'RUBY')
      p (1..5).size
      p (1...5).size
      p (1..).size
      p (1..5.5).size
      p (1...5.5).size
      p (10..1).size
      p Proc.new { |x| x * 3 }.call(4)
    RUBY

    _(result).must_answer <<~'OUT'
      5
      4
      Infinity
      5
      5
      0
      12
    OUT
  end

  it "range step" do
    result = ze0(<<~'RUBY')
      # Issue #731. `(a..b).step(k)` without a block should return an
      # IntArray of stepped values. spinel used to fall through to the
      # unresolved-call warning, then `.to_a` on the int 0 segfaulted.

      puts (1..10).step(3).to_a.inspect
      puts (0..20).step(5).to_a.inspect

      # Inclusive vs exclusive end:
      puts (1...10).step(3).to_a.inspect

      # step larger than range -> single element.
      puts (1..10).step(100).to_a.inspect

      # step exactly hits the end.
      puts (1..10).step(1).to_a.inspect
    RUBY

    _(result).must_answer <<~'OUT'
      [1, 4, 7, 10]
      [0, 5, 10, 15, 20]
      [1, 4, 7]
      [1]
      [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]
    OUT
  end

  it "range step bad stride" do
    result = ze0(<<~'RUBY')
      r1 = ((1.0..10.0).step("x").to_a rescue $!.message)
      p r1
      r2 = ((1.0..10.0).step(:s).to_a rescue $!.message)
      p r2
      r3 = ((1.0..10.0).step(nil).to_a rescue $!.message)
      p r3
      r4 = ((1.0..10.0).step([1]).to_a rescue $!.message)
      p r4
      r5 = ((1.0..10.0).step(true).to_a rescue $!.message)
      p r5

      s1 = (("a".."e").step(:s).to_a rescue $!.message)
      p s1
      s2 = (("a".."e").step(nil).to_a rescue $!.message)
      p s2
      s3 = (("a".."e").step([1]).to_a rescue $!.message)
      p s3
      s4 = (("a".."e").step(true).to_a rescue $!.message)
      p s4

      i1 = ((1..10).step("x").to_a rescue $!.message)
      p i1
      i2 = ((1..10).step(:s).to_a rescue $!.message)
      p i2
      i3 = ((1..10).step(nil).to_a rescue $!.message)
      p i3
      i4 = ((1..10).step(true).to_a rescue $!.message)
      p i4

      b = "x"
      i5 = ((1..10).step(b).to_a rescue $!.message)
      p i5
      i6 = ((1.0..9.0).step(b).to_a rescue $!.message)
      p i6

      p((1.0..3.0).step(0.5).to_a)
      p((1..10).step(2).to_a)
      p(("a".."e").step(2).to_a)
      n = 2
      p((1..10).step(n).to_a)
      f = 0.5
      p((1.0..3.0).step(f).to_a)
      (1..6).step(2) { |x| p x }
      (1.0..3.0).step(0.5) { |x| p x }
    RUBY

    _(result).must_answer <<~'OUT'
      "String can't be coerced into Float"
      ":s can't be coerced into Float"
      "nil can't be coerced into Float"
      "Array can't be coerced into Float"
      "true can't be coerced into Float"
      "no implicit conversion of Symbol into String"
      "no implicit conversion of nil into String"
      "no implicit conversion of Array into String"
      "no implicit conversion of true into String"
      "String can't be coerced into Integer"
      ":s can't be coerced into Integer"
      "nil can't be coerced into Integer"
      "true can't be coerced into Integer"
      "String can't be coerced into Integer"
      "String can't be coerced into Float"
      [1.0, 1.5, 2.0, 2.5, 3.0]
      [1, 3, 5, 7, 9]
      ["a", "c", "e"]
      [1, 3, 5, 7, 9]
      [1.0, 1.5, 2.0, 2.5, 3.0]
      1
      3
      5
      1.0
      1.5
      2.0
      2.5
      3.0
    OUT
  end

  it "range step endless" do
    result = ze0(<<~'RUBY')
      p((1..10).step(2).to_a)
      p((10..1).step(2).to_a)
      p((1...10).step(3).to_a)
      p((-5..5).step(3).to_a)
      p((1..1).step(2).to_a)
      p((1...1).step(2).to_a)
      p(10.step(1, -2).to_a)
      p(1.step(5).to_a)
      p((1..10000000).step(1000000).to_a)
    RUBY

    _(result).must_answer <<~'OUT'
      [1, 3, 5, 7, 9]
      []
      [1, 4, 7]
      [-5, -2, 1, 4]
      [1]
      []
      [10, 8, 6, 4, 2]
      [1, 2, 3, 4, 5]
      [1, 1000001, 2000001, 3000001, 4000001, 5000001, 6000001, 7000001, 8000001, 9000001]
    OUT
  end

  it "range step endless block" do
    result = ze0(<<~'RUBY')
      r001 = []; (1..).step(3) { |x001| break if x001 > 10; r001 << x001 }; p r001
      a002 = (1..); r002 = []; a002.step(2) { |x002| break if x002 > 5; r002 << x002 }; p r002
      r004 = []; (1..).each { |x004| break if x004 > 5; r004 << x004 }; p r004
      r006 = []; (1..10).step(3) { |x006| r006 << x006 }; p r006
      r003 = ((..5).step(2) { |x003| x003 } rescue $!.class); p r003
      r007 = ((1..10).step(-1) { |x| x } rescue $!.class); p r007
      r008 = []; (1...10).step(3) { |x| r008 << x }; p r008
    RUBY

    _(result).must_answer <<~'OUT'
      [1, 4, 7, 10]
      [1, 3, 5]
      [1, 2, 3, 4, 5]
      [1, 4, 7, 10]
      ArgumentError
      1..10
      [1, 4, 7]
    OUT
  end

  it "range step float" do
    result = ze0(<<~'RUBY')
      # Range#step materialises a typed array -- float when the step or a range bound
      # is float -- and iterates faithfully: no float drift, correct exclusivity,
      # descending negative steps, and ArgumentError on a zero step (CRuby parity).
      # A non-literal step (through a method param) previously truncated to int and
      # looped forever; a literal float step tripped clang -Werror.
      def s(x); x; end

      # --- float steps, no block ---
      puts (1.0..2.0).step(0.5).to_a.inspect      # float bounds
      puts (1..3).step(0.5).to_a.inspect          # int bounds, float step
      puts (1...3).step(0.5).to_a.inspect         # exclusive
      puts (2.0..1.0).step(-0.5).to_a.inspect     # descending
      puts (1.0..2.0).step(-0.5).to_a.inspect     # wrong direction -> empty
      puts (0.0..1.0).step(0.1).to_a.inspect      # drift: 1.0 must be included
      puts (1.0..6.4).step(1.8).to_a.inspect      # uneven final step
      puts (1.0..2.0).step(s(0.5)).to_a.inspect   # non-literal step (runtime path)

      # --- int steps, no block ---
      puts (1..10).step(3).to_a.inspect
      puts (1...10).step(3).to_a.inspect          # exclusive
      puts (10..1).step(-2).to_a.inspect          # descending
      puts (10...1).step(-1).to_a.inspect         # descending exclusive
      puts (1..10).step(-1).to_a.inspect          # wrong direction -> empty
      puts (5..5).step(1).to_a.inspect            # single element

      # --- block form (statement position) ---
      acc = []; (1..10).step(3) { |i| acc << i }; puts acc.inspect
      fac = []; (1.0..2.0).step(0.5) { |x| fac << x }; puts fac.inspect
      exc = []; (1...3).step(0.5) { |x| exc << x }; puts exc.inspect

      # --- exceptional: a zero step raises ArgumentError ---
      begin; (1.0..2.0).step(0).to_a; rescue => e; puts "#{e.class}: #{e.message}"; end
      begin; (1.0..2.0).step(0.0).to_a; rescue => e; puts "#{e.class}: #{e.message}"; end
      begin; (1..10).step(0).to_a; rescue => e; puts "#{e.class}: #{e.message}"; end
      begin; (1..10).step(s(0)) { |i| }; rescue => e; puts "#{e.class}: #{e.message}"; end
    RUBY

    _(result).must_answer <<~'OUT'
      [1.0, 1.5, 2.0]
      [1.0, 1.5, 2.0, 2.5, 3.0]
      [1.0, 1.5, 2.0, 2.5]
      [2.0, 1.5, 1.0]
      []
      [0.0, 0.1, 0.2, 0.30000000000000004, 0.4, 0.5, 0.6000000000000001, 0.7000000000000001, 0.8, 0.9, 1.0]
      [1.0, 2.8, 4.6, 6.4]
      [1.0, 1.5, 2.0]
      [1, 4, 7, 10]
      [1, 4, 7]
      [10, 8, 6, 4, 2]
      [10, 9, 8, 7, 6, 5, 4, 3, 2]
      []
      [5]
      [1, 4, 7, 10]
      [1.0, 1.5, 2.0]
      [1.0, 1.5, 2.0, 2.5]
      ArgumentError: step can't be 0
      ArgumentError: step can't be 0
      ArgumentError: step can't be 0
      ArgumentError: step can't be 0
    OUT
  end

  it "range step without argument" do
    result = ze0(<<~'RUBY')
      p (1..3).step.to_a
      p ("a".."e").step(2).to_a
      p ((1..10) % 3).to_a
      p (1..5).step(2).size
    RUBY

    _(result).must_answer <<~'OUT'
      [1, 2, 3]
      ["a", "c", "e"]
      [1, 4, 7, 10]
      3
    OUT
  end

  it "rational opassign and destructured range" do
    result = ze0(<<~'RUBY')
      # `rational += <boxed>` and a Range bounded by a destructured block parameter.
      b = [Rational(1), Rational(2)]
      acc = Rational(0)
      acc += b[0]
      p acc
      acc += b[1]
      p acc
      acc -= b[0]
      p acc
      acc *= b[1]
      p acc
      acc /= b[1]
      p acc

      cx = [Complex(1, 1)]
      z = Complex(0, 0)
      z += cx[0]
      p z
      z *= cx[0]
      p z

      [[2026, 7]].each do |(y, m)|
        p (1...m).reduce(0) { |s, mm| s + mm }
        p (1...m).inject { |s, mm| s + mm }
        p (1..m).reduce(0) { |s, mm| s + mm }
        p (1...m).sum
        p (1...m).to_a
        p (1...m).select { |v| v.even? }
      end
    RUBY

    _(result).must_answer <<~'OUT'
      (1/1)
      (3/1)
      (2/1)
      (4/1)
      (2/1)
      (1+1i)
      (0+2i)
      21
      21
      28
      21
      [1, 2, 3, 4, 5, 6]
      [2, 4, 6]
    OUT
  end
end
