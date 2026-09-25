# frozen_string_literal: true

require "spec_helper"

describe "Numeric: arithmetic" do
  it "arith adds integer literals" do
    result = zr("puts 1 + 1\n")

    _(result).must_answer "2\n"
  end

  it "arithmetic on a plain method parameter works" do
    result = zr(<<~'RUBY')
      # The operands are method params, not literals or locals, so their
      # types are known only at run time.

      class Adder
        def add(a, b)
          a + b
        end
      end
      puts Adder.new.add(3, 4)
    RUBY

    _(result).must_answer "7\n"
  end

  it "bigint literal pow" do
    result = zr(<<~'RUBY')
      # A literal integer power whose result exceeds int64 is a Bignum in every
      # overflow mode (CRuby). A power that fits stays a plain Integer.
      puts 10 ** 30
      puts 2 ** 70
      puts 2 ** 64
      puts 3 ** 40
      puts 2 ** 10
      puts 7 ** 2
      y = 10 ** 25
      puts y + 1
      puts y * 2
    RUBY

    _(result).must_answer <<~'OUT'
      1000000000000000000000000000000
      1180591620717411303424
      18446744073709551616
      12157665459056928801
      1024
      49
      10000000000000000000000001
      20000000000000000000000000
    OUT
  end

  it "bigint poly arith" do
    result = zr(<<~'RUBY')
      # Arithmetic on a Bignum read back from a mixed array uses Bignum arithmetic.
      b = 1
      i = 0
      while i < 70
        b = b * 2
        i = i + 1
      end
      arr = [b, "x"]      # heterogeneous -> arr[0] is a Bignum
      x = arr[0]
      puts(x + 1)
      puts(x - 1)
      puts(x * 2)
      puts(x + x)
    RUBY

    _(result).must_answer <<~'OUT'
      1180591620717411303425
      1180591620717411303423
      2361183241434822606848
      2361183241434822606848
    OUT
  end

  it "bigint pow shift" do
    result = zr(<<~'RUBY')
      # Bigint `**`, `<<` and `>>` keep arbitrary precision. `b` is promoted to
      # bigint by `b = b * 2` in the loop; the power and the shifts must not fall
      # back to the int path (which would truncate the receiver to 64 bits).
      b = 1
      i = 0
      while i < 70
        b = b * 2
        i = i + 1
      end

      puts b
      puts(b ** 2)
      puts(b << 5)
      puts(b >> 3)
      # negative shifts route through the opposite primitive
      puts(b << -3)
      puts(b >> -5)

      # a down-shift that lands back inside small-int range
      c = 1
      j = 0
      while j < 65
        c = c * 2
        j = j + 1
      end
      puts(c >> 60)
    RUBY

    _(result).must_answer <<~'OUT'
      1180591620717411303424
      1393796574908163946345982392040522594123776
      37778931862957161709568
      147573952589676412928
      147573952589676412928
      37778931862957161709568
      32
    OUT
  end

  it "bignum modulo bit pow" do
    result = zr(<<~'RUBY')
      # Bignum modulo / % / remainder / divmod / #[] / modular pow.
      b = 2 ** 100
      p b.modulo(7)
      p((-b).modulo(7))
      p b.remainder(7)
      p((-b).remainder(7))
      p b.divmod(7)
      p b[100]
      p b[0]
      p b.pow(2, 7)
      p b % 7
    RUBY

    _(result).must_answer <<~'OUT'
      2
      5
      2
      -2
      [181092942889747057356671886482, 2]
      1
      0
      4
      2
    OUT
  end

  it "bignum rational arith" do
    result = zr(<<~'RUBY')
      # big Rational arithmetic and comparison. One operand is already a big Rational,
      # and the other numeric operand becomes a Rational with Bignum parts.
      r = (10**30).to_r
      p(r + (1r/3))
      p(r - r)
      p(r * 2)
      p(r / 2)
      p(r + 1)
      p((10**30).quo(3) + (10**30).quo(6))
      p((10**30).quo(3) * 3)
      p(r <=> (10**30).to_r)
      p(r <=> (10**31).to_r)
      p(r > (10**29).to_r)
      p(r < (10**31).to_r)
      p((2**70).quo(2**69) == 2)
      p(r == (10**30).to_r)
      p(r.to_f)
      p([(10**30).to_r, (1r/2), (10**20).to_r].sort)
    RUBY

    _(result).must_answer <<~'OUT'
      (3000000000000000000000000000001/3)
      (0/1)
      (2000000000000000000000000000000/1)
      (500000000000000000000000000000/1)
      (1000000000000000000000000000001/1)
      (500000000000000000000000000000/1)
      (1000000000000000000000000000000/1)
      0
      -1
      true
      true
      true
      true
      1.0e+30
      [(1/2), (100000000000000000000/1), (1000000000000000000000000000000/1)]
    OUT
  end

  it "bignum receiver methods" do
    result = zr(<<~'RUBY')
      # Bignum-receiver methods that return an Integer/Float/bool without a Rational
      # (to_r/rationalize/quo need a bigint-backed Rational and stay unsupported).
      p(~(2**100))
      p(~(-(2**100)))
      p((2**70).div(3))
      p((2**64).div(-(2**32)))
      p((2**70).gcd(2**69))
      p((2**70).gcd(0))
      p((2**70).lcm(6))
      p((2**70).lcm(0))
      p((2**70).gcdlcm(6))
      p((2**100).nonzero?)
      p((0 - (2**100)) + (2**100))         # zero bignum path
      x = 2**100; p x.size
      p((2**127).size)
      p((10**30).numerator)
      p((10**30).denominator)
      p((10**30).fdiv(2))
      p((2**70).pow(2))
      p((2**70).ord)
      p((14 * 2**64).allbits?(6))
      p((2**64).anybits?(1))
      p((2**64).nobits?(1))
      p((2**70).ceildiv(3))
      # Fixnum receivers of the same methods still work
      p(6.gcd(4))
      p(12.lcm(8))
      p(7.ceildiv(2))
    RUBY

    _(result).must_answer <<~'OUT'
      -1267650600228229401496703205377
      1267650600228229401496703205375
      393530540239137101141
      -4294967296
      590295810358705651712
      1180591620717411303424
      3541774862152233910272
      0
      [2, 3541774862152233910272]
      1267650600228229401496703205376
      0
      13
      16
      1000000000000000000000000000000
      1
      5.0e+29
      1393796574908163946345982392040522594123776
      1180591620717411303424
      false
      false
      true
      393530540239137101142
      2
      24
      4
    OUT
  end

  it "complex arithmetic" do
    result = zr(<<~'RUBY')
      # Complex arithmetic. Operators and display for the common cases match CRuby.
      a = Complex(1, 2)
      b = Complex(3, -1)
      puts a
      puts a.inspect
      p a
      p Complex(2, 3)
      puts(a + b)
      puts(a - b)
      puts(a * b)
      puts(a ** 2)
      puts(a ** 3)
      puts(-a)
      puts(+a)
      puts a.conjugate
      puts a.conj
      puts a.abs
      puts(Complex(3, 4).abs)
      puts(a == Complex(1, 2))
      puts(a == b)
      puts(a != b)
      puts "c=#{a} sum=#{a + b}"
      puts(2 + Complex(0, 3))
      puts(1 + 2i)
      puts(5 - Complex(1, 1))
      puts(Complex(2, 0) == 2)
      puts(Complex(8, 4) / Complex(2, 0))
      puts(Complex(6, 2) / 2)
      def cadd(x, y); x + y; end
      puts(cadd(Complex(1, 1), Complex(2, 2)))
    RUBY

    _(result).must_answer <<~'OUT'
      1+2i
      (1+2i)
      (1+2i)
      (2+3i)
      4+1i
      -2+3i
      5+5i
      -3+4i
      -11-2i
      -1-2i
      1+2i
      1-2i
      1-2i
      2.23606797749979
      5.0
      true
      false
      true
      c=1+2i sum=4+1i
      2+3i
      1+2i
      4-1i
      true
      4+2i
      3+1i
      3+3i
    OUT
  end

  it "complex polar" do
    result = zr(<<~'RUBY')
      # Built-in `Complex`, as optcarrot's `nestopia_palette` uses it:
      #   iq = Complex.polar(s, theta)
      #   iq += Complex.polar(level1, theta2)
      #   clr = y + (Complex.polar(g, t) * iq.conjugate).real
      #
      # Methods: `Complex.polar(magnitude, angle)`, instance-side
      # `.real / .imaginary / .conjugate`, plus `+ *` between two
      # Complex values.

      # Polar form: r=2, theta=0 → (2, 0)
      a = Complex.polar(2.0, 0.0)
      puts a.real            # 2.0
      puts a.imaginary       # 0.0

      # r=1, theta=PI/2 → (~0, 1)
      b = Complex.polar(1.0, Math::PI / 2)
      puts b.real.abs < 1e-9    # true (cos(pi/2) ~ 0)
      puts (b.imaginary - 1.0).abs < 1e-9  # true

      # Addition: a + b
      c = a + b
      puts (c.real - 2.0).abs < 1e-9       # true
      puts (c.imaginary - 1.0).abs < 1e-9  # true

      # Conjugate flips the sign of imag
      d = b.conjugate
      puts d.real.abs < 1e-9    # true
      puts (d.imaginary + 1.0).abs < 1e-9  # true

      # Multiplication: (1, 1) * (1, -1) = (1*1 - 1*-1, 1*-1 + 1*1) = (2, 0)
      e = Complex.polar(Math.sqrt(2), Math::PI / 4)  # ~ (1, 1)
      f = e * e.conjugate                            # |e|^2 = 2 + 0i
      puts (f.real - 2.0).abs < 1e-9       # true
      puts f.imaginary.abs < 1e-9          # true
    RUBY

    _(result).must_answer <<~'OUT'
      2.0
      0.0
      true
      true
      true
      true
      true
      true
      true
      true
    OUT
  end

  it "float and int mixed arithmetic promotes to float" do
    result = zr(<<~'RUBY')
      class Adder
        def add(a, b)
          a + b
        end
      end
      puts Adder.new.add(1, 2.5)
      puts Adder.new.add(2.5, 1)
    RUBY

    _(result).must_answer "3.5\n3.5\n"
  end

  it "float div int literal" do
    result = zr(<<~'RUBY')
      # Float arithmetic with an INTEGER operand is a float operation. So `1.0 / 0`
      # answers Infinity, the same as `1.0 / 0.0` or a variable divisor.
      p(1.0 / 0)
      p(-1.0 / 0)
      p(0.0 / 0)
      x = 1.0
      p(x / 0)
      p(1.0 / 2)
      p(3 / 2.0)
      p(1.0 + 2)
      p(2 * 1.5)
      p(7.5 - 2)
      p(2.0 ** 3)
      begin
        p(1 / 0)
      rescue ZeroDivisionError => e
        p e.message
      end
      begin
        p(1.0 % 0)
      rescue ZeroDivisionError => e
        p e.message
      end
      p(1.0 / 0 > 10 ** 100)
    RUBY

    _(result).must_answer <<~'OUT'
      Infinity
      -Infinity
      NaN
      Infinity
      0.5
      1.5
      3.0
      3.0
      5.5
      8.0
      "divided by 0"
      "divided by 0"
      true
    OUT
  end

  it "float literals and arithmetic" do
    result = zr(<<~'RUBY')
      puts 1.5 + 2.5
      puts 3.0 - 1
      puts 2.0 * 3
      puts 7.0 / 2
      puts 7.5 % 2
      puts 2.0 ** 3
      puts 1.0 == 1
      puts 1.5 < 2.5
      puts(1.5 <=> 2.5)
      puts(-1.5)
      puts 1.0
      puts 100.0
      puts 3.14
    RUBY

    _(result).must_answer <<~'OUT'
      4.0
      2.0
      6.0
      3.5
      1.5
      8.0
      true
      true
      -1
      -1.5
      1.0
      100.0
      3.14
    OUT
  end

  it "float modulo" do
    result = zr(<<~'RUBY')
      # Float#% (and Integer % Float). Ruby's float modulo is floored: a NONZERO
      # result takes the sign of the DIVISOR, unlike C fmod which follows the
      # dividend (-5.5 % 2 == 0.5). A ZERO result instead keeps
      # the sign of the DIVIDEND (matching fmod / CRuby's flodivmod), so -2.0 % 2.0 is
      # -0.0 while 2.0 % -2.0 is 0.0. The `modulo` alias shares these semantics.
      def f(x); x; end
      def i(x); x; end

      # Nonzero results: sign follows the divisor.
      p(f(5.5) % 2)        # 1.5
      p(f(5.5) % 2.0)      # 1.5
      p(f(-5.5) % 2)       # 0.5
      p(f(5.5) % -2)       # -0.5
      p(f(-5.5) % -2)      # -1.5
      p(f(5.5) % 2.5)      # 0.5
      p(f(-5.5) % 2.5)     # 2.0
      p(i(5) % 2.0)        # 1.0   (Integer % Float -> Float)
      p(f(7.0) % 3)        # 1.0
      p(5.5 % 2)           # 1.5   (constant-folds, but exercises the literal path)

      # Zero results: sign follows the dividend.
      p(f(-2.0) % 2.0)     # -0.0
      p(f(2.0) % -2.0)     # 0.0
      p(f(2.0) % 2.0)      # 0.0
      p(f(-2.0) % -2.0)    # -0.0
      p(i(4) % 2.0)        # 0.0
      p(i(-4) % 2.0)       # -0.0

      # modulo alias
      p(f(5.5).modulo(2))    # 1.5
      p(f(-5.5).modulo(2))   # 0.5
      p(f(5.5).modulo(-2))   # -0.5
      p(f(-2.0).modulo(2.0)) # -0.0
      p(f(2.0).modulo(-2.0)) # 0.0
    RUBY

    _(result).must_answer <<~'OUT'
      1.5
      1.5
      0.5
      -0.5
      -1.5
      0.5
      2.0
      1.0
      1.0
      1.5
      -0.0
      0.0
      0.0
      -0.0
      0.0
      -0.0
      1.5
      0.5
      -0.5
      -0.0
      0.0
    OUT
  end

  it "float pow negative fractional" do
    result = zr(<<~'RUBY')
      # A negative Float ** a fractional exponent gives a Complex, as in CRuby.
      begin
        p((-2.0) ** 0.5)
      rescue => e
        puts "#{e.class}: raised"
      end
      p(2.0 ** 0.5)
      p((-2.0) ** 2.0)
      p((-8.0) ** (1.0 / 3)) rescue puts "raised2"
    RUBY

    _(result).must_answer <<~'OUT', linux: <<~'LINUX'
      (0.0+1.4142135623730951i)
      1.4142135623730951
      4.0
      (1.0+1.7320508075688772i)
    OUT
      (0.0+1.4142135623730951i)
      1.4142135623730951
      4.0
      (1.0000000000000002+1.7320508075688772i)
    LINUX
  end

  it "float quo step by" do
    result = zr(<<~'RUBY')
      # Float#quo is float division (Integer#quo stays Rational), and
      # Numeric#step keyword forms (to:/by:, in either order, and the
      # limit-plus-by mix) lower to the positional form.
      p 10.0.quo(3)
      p 2.5.quo(0.5)
      1.0.step(2.0, by: 0.5) { |f| p f }
      1.0.step(by: 0.25, to: 1.5) { |f| p f }
      5.step(1, by: -2) { |i| p i }
    RUBY

    _(result).must_answer <<~'OUT'
      3.3333333333333335
      5.0
      1.0
      1.5
      2.0
      1.0
      1.25
      1.5
      5
      3
      1
    OUT
  end

  it "float rational arith" do
    result = zr(<<~'RUBY')
      # Float <op> Rational (either side) coerces to Float like CRuby;
      # comparisons are bool; ** goes through pow.
      p(0.5 + Rational(1, 2))
      p(0.5 - Rational(1, 2))
      p(0.5 * Rational(1, 2))
      p(0.5 / Rational(1, 2))
      p(Rational(3, 2) + 0.25)
      p(Rational(1, 2) == 0.5)
      p(0.75 > Rational(1, 2))
      p(2.0 ** Rational(1, 2))
    RUBY

    _(result).must_answer <<~'OUT'
      1.0
      0.0
      0.25
      1.0
      1.75
      true
      true
      1.4142135623730951
    OUT
  end

  it "float rationalize simplest" do
    result = zr(<<~'RUBY')
      # Float#rationalize returns the SIMPLEST rational that round-trips to the float,
      # not the exact power-of-two bit ratio that Float#to_r yields.
      p 0.75.rationalize    # (3/4)
      p 0.1.rationalize     # (1/10)
      p 0.3.rationalize     # (3/10)
      p 0.5.rationalize     # (1/2)
      p 6.0.rationalize     # (6/1)
      p 2.5.rationalize     # (5/2)
      p(-0.75.rationalize)  # (-3/4)
      p 3.14.rationalize    # (157/50)
      p 0.0.rationalize     # (0/1)

      # to_r stays the exact ratio (unchanged), and the eps arg form still works.
      p 0.75.to_r == Rational(3, 4)       # true
      p 0.3.rationalize(0.01)             # (3/10)

      # param-routed so it exercises the runtime helper, not a folded literal.
      def r(x); x.rationalize; end
      p r(0.1)              # (1/10)
    RUBY

    _(result).must_answer <<~'OUT'
      (3/4)
      (1/10)
      (3/10)
      (1/2)
      (6/1)
      (5/2)
      (-3/4)
      (157/50)
      (0/1)
      true
      (3/10)
      (1/10)
    OUT
  end

  it "float round half" do
    result = zr(<<~'RUBY')
      # Float#round(half:) picks the tie-break mode: :even (banker's), :down
      # (toward zero), :up (the default away-from-zero).
      p 2.5.round(half: :even)
      p 3.5.round(half: :even)
      p 2.5.round(half: :up)
      p 2.5.round(half: :down)
      p(-2.5.round(half: :even))
      p(-2.5.round(half: :down))
      p 2.345.round(2, half: :even)
      p 2.5.round(0, half: :even)
      p 2.5.round
    RUBY

    _(result).must_answer <<~'OUT'
      2
      4
      3
      2
      -2
      -2
      2.35
      2
      3
    OUT
  end

  it "float round half mode" do
    result = zr(<<~'RUBY')
      hm001 = :even
      r001 = (1.5.round(half: hm001) rescue $!.class); p r001
      r002 = (1.5.round(half: nil) rescue $!.class); p r002
      hm003 = :even; r003 = (1.5.floor(half: hm003) rescue $!.class); p r003
      hm004 = :even; r004 = (1.5.round(2, half: hm004) rescue $!.class); p r004
      r005 = (1.5.round(2, half: nil) rescue $!.class); p r005
      p(1.5.round(half: :even))
      p(2.5.round(half: :even))
      p(2.5.round(half: :up))
      p(2.5.round(half: :down))
    RUBY

    _(result).must_answer <<~'OUT'
      2
      2
      TypeError
      1.5
      1.5
      2
      2
      3
      2
    OUT
  end

  it "float round nonliteral" do
    result = zr(<<~'RUBY')
      # A non-literal ndigits is used, not ignored: 1.234.round(n) with n = 2 is
      # 1.23. Positive ndigits gives a Float, as in CRuby. For ndigits <= 0 the
      # example calls to_i, so it checks only the value.
      n2 = 2
      p 1.234.round(n2)        # 1.23 (Float, matches CRuby)
      p 3.14159.round(n2)      # 3.14
      p 2.71828.ceil(n2)       # 2.72
      p 2.71828.floor(n2)      # 2.71
      p 9.876.truncate(n2)     # 9.87

      nm1 = -1
      p 1234.5.round(nm1).to_i # 1230
      p 1250.0.floor(nm1).to_i # 1250
      p 1241.0.ceil(nm1).to_i  # 1250

      n0 = 0
      p 1.9.round(n0).to_i     # 2
      p 7.8.truncate(n0).to_i  # 7
    RUBY

    _(result).must_answer <<~'OUT'
      1.23
      3.14
      2.72
      2.71
      9.87
      1230
      1250
      1250
      2
      7
    OUT
  end

  it "float round past the exact powers of ten" do
    result = zr(<<~'RUBY')
      # Past DBL_DIG places the power of ten a scaled round would use is not
      # exact, so ruby rounds the exact value the double holds. `ceil(n)`
      # takes no correction step, unlike `floor(n)`.
      p 66471.846.ceil(3)
      p [1.0.round(15), 1.0.round(16), 0.1.round(15), 0.1.round(16), 0.1.round(17)]
      p [1.23456789012345678.round(16), 1.23456789012345678.floor(16), 1.23456789012345678.ceil(16)]
      p [5e-16.round(15), 5e-16.round(15, half: :even), 5e-16.round(15, half: :down)]
      p [1.0e20.round(5), 1.0e-300.round(5), 0.0.round(5), (-0.0).round(5)]
      p [(-1.5).round(15), (-0.1).ceil(16), (-0.1).floor(16)]
      p [1.5.round(1000), 1.5.floor(1000), 1.5.ceil(1000), 1.5.truncate(1000)]
      p [0.30000000000000004.round(16), 0.30000000000000004.round(17)]
    RUBY

    _(result).must_answer <<~'OUT'
      66471.847
      [1.0, 1.0, 0.1, 0.1, 0.1]
      [1.2345678901234567, 1.2345678901234567, 1.2345678901234567]
      [1.0e-15, 1.0e-15, 1.0e-15]
      [1.0e+20, 0.0, 0.0, -0.0]
      [-1.5, -0.1, -0.1000000000000001]
      [1.5, 1.5, 1.5, 1.5]
      [0.3, 0.30000000000000004]
    OUT
  end

  it "float round value based type" do
    result = zr(<<~'RUBY')
      # CRuby's Float rounding return type is value-based on ndigits:
      # Integer when ndigits <= 0 (or absent), Float when > 0. So round(0) and
      # round(-1) give an Integer.
      p 1.9.round
      p 1.9.round.class
      p 1.9.round(0)
      p 1.9.round(0).class
      p 1234.5.round(-1)
      p 1234.5.round(-1).class
      p 1.234.round(2)
      p 1.234.round(2).class
      p 1.5.ceil(0)
      p 1.5.ceil(0).class
      p 1.23.floor(1)
      p 1.23.floor(1).class
      p 19.9.truncate(-1)
      p 19.9.truncate(-1).class
    RUBY

    _(result).must_answer <<~'OUT'
      2
      Integer
      2
      Integer
      1230
      Integer
      1.23
      Float
      2
      Integer
      1.2
      Float
      10
      Integer
    OUT
  end

  it "float round zero" do
    result = zr(<<~'RUBY')
      # Float#round/ceil/floor/truncate return type matches CRuby's
      # value-based rule for a literal ndigits: no-arg and ndigits <= 0 return
      # Integer, ndigits > 0 returns Float. (A non-literal ndigits stays
      # Float.) See docs/float-rounding.md.
      puts 3.5.round(0).inspect
      puts 3.5.round.inspect
      puts 3.5.round(1).inspect
      puts 3.5.round(2).inspect

      puts 3.7.ceil(0).inspect
      puts 3.7.ceil.inspect
      puts 3.7.ceil(1).inspect

      puts 3.7.floor(0).inspect
      puts 3.7.floor.inspect

      puts 3.7.truncate(0).inspect
      puts 3.7.truncate.inspect
    RUBY

    _(result).must_answer <<~'OUT'
      4
      4
      3.5
      3.5
      4
      4
      3.7
      3
      3
      3
      3
    OUT
  end

  it "a small Integer argument binds a parameter another call site passes a bignum" do
    result = zr(<<~'RUBY')
      # A parameter can get a small Integer from one call and a Bignum from
      # another. Each value must keep its own width, whatever way it reaches
      # the parameter.

      def any(x)
        x.to_s
      end
      p any(1)
      p any(2**200)

    RUBY

    _(result).must_answer <<~'OUT'
      "1"
      "1606938044258990275541962092341162602522202993782792835301376"
    OUT
  end

  it "arithmetic inside that parameter answers for both widths" do
    result = zr(<<~'RUBY')
      # A parameter can get a small Integer from one call and a Bignum from
      # another. Each value must keep its own width, whatever way it reaches
      # the parameter.

      def arith(n)
        n * 2 + 1
      end
      p arith(3)
      p arith(2**70)

    RUBY

    _(result).must_answer <<~'OUT'
      7
      2361183241434822606849
    OUT
  end

  it "a comparison inside that parameter answers for both widths" do
    result = zr(<<~'RUBY')
      # A parameter can get a small Integer from one call and a Bignum from
      # another. Each value must keep its own width, whatever way it reaches
      # the parameter.

      def cmp(a, b)
        a > b
      end
      p cmp(5, 2**80)
      p cmp(2**80, 5)

    RUBY

    _(result).must_answer <<~'OUT'
      false
      true
    OUT
  end

  it "a default value binds the same widened slot" do
    result = zr(<<~'RUBY')
      # A parameter can get a small Integer from one call and a Bignum from
      # another. Each value must keep its own width, whatever way it reaches
      # the parameter.

      # the default-value path binds the same slot
      def opt(x = 7)
        x.to_s
      end
      p opt
      p opt(2**100)

    RUBY

    _(result).must_answer <<~'OUT'
      "7"
      "1267650600228229401496703205376"
    OUT
  end

  it "a keyword and a splat argument reach the widened slot too" do
    result = zr(<<~'RUBY')
      # A parameter can get a small Integer from one call and a Bignum from
      # another. Each value must keep its own width, whatever way it reaches
      # the parameter.

      # keyword and splat arguments reach it too
      def kw(x:, y: 3)
        (x + y).to_s
      end
      p kw(x: 1)
      p kw(x: 2**90, y: 2)

    RUBY

    _(result).must_answer <<~'OUT'
      "4"
      "1237940039285380274899124226"
    OUT
  end

  it "a rest parameter holds both widths at once" do
    result = zr(<<~'RUBY')
      # A parameter can get a small Integer from one call and a Bignum from
      # another. Each value must keep its own width, whatever way it reaches
      # the parameter.

      def rest(*xs)
        xs.map { |v| v.to_s }
      end
      p rest(1, 2**70)

    RUBY

    _(result).must_answer <<~'OUT'
      ["1", "1180591620717411303424"]
    OUT
  end

  it "a constructor argument binds the same widened slot" do
    result = zr(<<~'RUBY')
      # A parameter can get a small Integer from one call and a Bignum from
      # another. Each value must keep its own width, whatever way it reaches
      # the parameter.

      # a constructor argument is the same binding
      class Box
        def initialize(v)
          @v = v.to_s
        end

        def show
          @v
        end
      end
      p Box.new(9).show
      p Box.new(2**90).show

    RUBY

    _(result).must_answer <<~'OUT'
      "9"
      "1237940039285380274899124224"
    OUT
  end

  it "an ivar written from both widths holds each" do
    result = zr(<<~'RUBY')
      # A parameter can get a small Integer from one call and a Bignum from
      # another. Each value must keep its own width, whatever way it reaches
      # the parameter.

      # The same is true for an ivar or class variable: it can hold a Bignum at one
      # time and a small Integer, such as `@n = 0`, at another.
      class Acc
        attr_reader :n

        def initialize(seed = 0)
          @n = seed
        end

        def add(v)
          @n = @n + v
          @n
        end

        def bump
          @n += 1     # op-assign on a Bignum value
          @n
        end

        def reset
          @n = 0
        end
      end

      a = Acc.new
      p a.add(1)
      p a.add(2**80)
      p a.bump
      p a.n
      p a.reset
      p a.add(2**64)
      p Acc.new(5).add(2**70)

    RUBY

    _(result).must_answer <<~'OUT'
      1
      1208925819614629174706177
      1208925819614629174706178
      1208925819614629174706178
      0
      18446744073709551616
      1180591620717411303429
    OUT
  end

  it "a class variable written from both widths holds each" do
    result = zr(<<~'RUBY')
      # A parameter can get a small Integer from one call and a Bignum from
      # another. Each value must keep its own width, whatever way it reaches
      # the parameter.

      class Tally
        @@total = 0

        def self.bump(x)
          @@total = @@total + x
          @@total
        end
      end
      p Tally.bump(1)
      p Tally.bump(2**80)

    RUBY

    _(result).must_answer <<~'OUT'
      1
      1208925819614629174706177
    OUT
  end

  it "a conditional whose arms are an Integer and a bignum answers both" do
    result = zr(<<~'RUBY')
      # A parameter can get a small Integer from one call and a Bignum from
      # another. Each value must keep its own width, whatever way it reaches
      # the parameter.

      # a conditional whose arms are an int and a Bignum
      class Either
        def initialize(f)
          @v = f ? 0 : 2**90
        end

        def show = @v.to_s
      end
      p Either.new(true).show
      p Either.new(false).show
    RUBY

    _(result).must_answer <<~'OUT'
      "0"
      "1237940039285380274899124224"
    OUT
  end

  it "int arithmetic" do
    result = zr(<<~'RUBY')
      x = 5
      y = 3
      puts x + y
      puts x - y
      puts x * y
      puts x / y
      puts x % y
      puts(x ** y)
    RUBY

    _(result).must_answer <<~'OUT'
      8
      2
      15
      1
      2
      125
    OUT
  end

  it "int ceil floor round" do
    result = zr(<<~'RUBY')
      # Integer#ceil / floor / round / truncate without a precision arg
      # return self per CRuby.
      puts 3.ceil
      puts 3.floor
      puts 3.round
      puts 3.truncate
      puts (-3).ceil
      puts (-3).floor
      puts (-3).round
      puts (-3).truncate
    RUBY

    _(result).must_answer <<~'OUT'
      3
      3
      3
      3
      -3
      -3
      -3
      -3
    OUT
  end

  it "int overflow op assign" do
    result = zr(<<~'RUBY')
      # Every integer operator that overflows 64 bits gives a Bignum, as in CRuby,
      # in the binary form and in the op-assign form (`x *= y`, +=, <<=, **=).
      # So `1 << 63` and a runtime `a ** 64` print their exact values.
      def try
        yield
      rescue RangeError => e
        puts "RangeError: #{e.message}"
      end

      a = 999_999_999_999
      try { a *= 999_999_999_999 }
      b = 10
      try { b += 9_223_372_036_854_775_800 }

      c = 1
      try { puts c << 63 }
      try { puts c << 64 }
      puts c << 62
      d = 1
      try { d <<= 63 }
      puts d

      pw = 2
      try { puts pw ** 64 }
      puts pw ** 62
      f = 5
      f **= 3
      puts f

      # op-assign division uses Ruby's floored semantics
      g = -7
      g /= 2
      puts g
      h = -7
      h %= 3
      puts h

      # ivar op-assign works the same way
      class Acc
        attr_reader :n
        def initialize = (@n = 999_999_999_999)
        def blow = (@n *= 999_999_999_999)
      end
      acc = Acc.new
      begin
        acc.blow
      rescue RangeError => e
        puts "ivar RangeError: #{e.message}"
      end
    RUBY

    _(result).must_answer <<~'OUT'
      9223372036854775808
      18446744073709551616
      4611686018427387904
      9223372036854775808
      18446744073709551616
      4611686018427387904
      125
      -4
      2
    OUT
  end

  it "int overflow promote" do
    result = zr(<<~'RUBY')
      # `x *= y` inside a while loop gives the full arbitrary-precision
      # Ruby answer, not a wrapped int64. A value just past 2^63 prints
      # as a positive number: `2**63` is `9223372036854775808`.

      # 2**63 -- the first value past the int64 range.
      m = 1
      i = 0
      while i < 63
        m = m * 2
        i = i + 1
      end
      puts m

      # 2**100 -- deeper into multi-limb territory.
      m = 1
      i = 0
      while i < 100
        m = m * 2
        i = i + 1
      end
      puts m

      # Factorial of 25 -- classic bigint, well past int64.
      n = 1
      i = 1
      while i <= 25
        n = n * i
        i = i + 1
      end
      puts n
    RUBY

    _(result).must_answer <<~'OUT'
      9223372036854775808
      1267650600228229401496703205376
      15511210043330985984000000
    OUT
  end

  it "int overflow raises" do
    result = zr(<<~'RUBY')
      # Integer arithmetic that overflows int64 gives a Bignum, as in
      # CRuby. It does not wrap and does not raise, so no rescue runs.
      #
      # Non-overflowing arithmetic must still produce the expected
      # result.

      # Sanity: non-overflowing arithmetic still works.
      puts 100 + 200
      puts 1000 - 500
      puts 6 * 7

      # Each of the three operators overflows into a Bignum.
      [:plus, :minus, :mul].each do |op|
        begin
          huge = 9_223_372_036_854_775_000
          case op
          when :plus
            x = huge + 9_223_372_036_854_775_000
          when :minus
            x = -huge - 9_223_372_036_854_775_000
          when :mul
            x = huge * 1000
          end
          puts "no raise from #{op}: #{x}"
        rescue RangeError => e
          puts "#{op}: caught #{e.message}"
        end
      end
    RUBY

    _(result).must_answer <<~'OUT'
      300
      500
      42
      no raise from plus: 18446744073709550000
      no raise from minus: -18446744073709550000
      no raise from mul: 9223372036854775000000
    OUT
  end

  it "int round large precision" do
    result = zr(<<~'RUBY')
      # Integer#round/ceil/floor/truncate(ndigits) must use exact integer
      # arithmetic: a double-based implementation loses precision above 2^53
      # and casting pow(10,-nd) is undefined once 10^(-nd) > INT64_MAX.
      p 1000000000000000005.round(-1)   # 1000000000000000010 (>2^53: float would drop the 5)
      p 9007199254740993.round(-3)      # 9007199254741000
      p 9007199254740993.floor(-3)      # 9007199254740000
      p 9007199254740993.ceil(-3)       # 9007199254741000
      p 9007199254740993.truncate(-3)   # 9007199254740000
      p(-1000000000000000005.round(-1)) # -1000000000000000010
      p 123.round(-20)                  # 0  (10^20 unrepresentable -> 0, no UB)
      p 123.ceil(-20)                   # 0
    RUBY

    _(result).must_answer <<~'OUT'
      1000000000000000010
      9007199254741000
      9007199254740000
      9007199254741000
      9007199254740000
      -1000000000000000010
      0
      100000000000000000000
    OUT
  end

  it "integer div by zero" do
    result = zr(<<~'RUBY')
      # Integer division / modulo / divmod / ceildiv by zero raises
      # ZeroDivisionError, and a rescue can catch it.
      #
      # The test uses `puts e`, which prints the message string.

      # Bare / catches as ZeroDivisionError
      begin
        x = 10 / 0
        puts "no raise: #{x}"
      rescue ZeroDivisionError => e
        puts "caught div: #{e}"
      end

      # Bare % catches as ZeroDivisionError
      begin
        x = 10 % 0
        puts "no raise: #{x}"
      rescue ZeroDivisionError => e
        puts "caught mod: #{e}"
      end

      # divmod
      begin
        10.divmod(0)
        puts "no raise"
      rescue ZeroDivisionError => e
        puts "caught divmod: #{e}"
      end

      # ceildiv
      begin
        x = 10.ceildiv(0)
        puts "no raise: #{x}"
      rescue ZeroDivisionError => e
        puts "caught ceildiv: #{e}"
      end

      # pow with mod=0
      begin
        x = 2.pow(10, 0)
        puts "no raise: #{x}"
      rescue ZeroDivisionError => e
        puts "caught powmod: #{e}"
      end

      # /= compound assignment
      begin
        x = 10
        x /= 0
        puts "no raise: #{x}"
      rescue ZeroDivisionError => e
        puts "caught /=: #{e}"
      end

      # %= compound assignment
      begin
        x = 10
        x %= 0
        puts "no raise: #{x}"
      rescue ZeroDivisionError => e
        puts "caught %=: #{e}"
      end

      # Bare rescue also catches (no class filter at all).
      begin
        10 / 0
      rescue => e
        puts "bare-rescue: #{e}"
      end

      # Float division by zero is NOT affected — IEEE 754 returns
      # Infinity / NaN, as in CRuby; no exception is raised.
      puts (1.0 / 0.0).infinite?
      puts (0.0 / 0.0).nan?
    RUBY

    _(result).must_answer <<~'OUT'
      caught div: divided by 0
      caught mod: divided by 0
      caught divmod: divided by 0
      caught ceildiv: divided by 0
      caught powmod: divided by 0
      caught /=: divided by 0
      caught %=: divided by 0
      bare-rescue: divided by 0
      1
      true
    OUT
  end

  it "integer division and modulo by zero raise a catchable zero division error" do
    result = zr(<<~'RUBY')
      # Integer division or modulo by zero raises a catchable
      # `ZeroDivisionError`, as in real Ruby. This is true for literal
      # operands and for method-parameter operands.

      begin
        puts(5 % 0)
      rescue ZeroDivisionError
        puts "mod zero div"
      end
      class Calc
        def divide(a, b)
          a / b
        end
      end
      begin
        puts Calc.new.divide(10, 0)
      rescue ZeroDivisionError
        puts "param zero div"
      end
    RUBY

    _(result).must_answer "mod zero div\nparam zero div\n"
  end

  it "integer literal no int32 overflow" do
    result = zr(<<~'RUBY')
      # A constant expression of integer literals whose value is more
      # than the int32 maximum keeps its exact value. It must not wrap
      # to a negative number. optcarrot has constants of this shape, for
      # example `APU::Mixer::TND_1 = 100 * 24329 * 256 / 500`.

      # Each chain straddles int32: max 2^31 - 1 = 2,147,483,647.
      A = 24329 * 256 * 500           # 3,114,112,000
      B = 100000 * 100000              # 10,000,000,000
      C = 65535 * 65535                # 4,294,836,225
      D = 2 ** 40                      # 1,099,511,627,776
      E = 1_000_000_000 + 1_000_000_000 # 2,000,000,000 — sum overflow

      puts A
      puts B
      puts C
      puts D
      puts E
    RUBY

    _(result).must_answer <<~'OUT'
      3114112000
      10000000000
      4294836225
      1099511627776
      2000000000
    OUT
  end

  it "integer pow negative exponent" do
    result = zr(<<~'RUBY')
      # Integer ** with a literal negative exponent yields a Rational (CRuby
      # semantics), typed statically. A statically int-typed runtime exponent keeps
      # the Integer result and raises on a negative value (see limitations.md).
      # Integer#pow(negative, mod) raises RangeError with CRuby's message.
      puts 2 ** 10
      puts 0 ** 0
      puts 3 ** 4
      puts(2.0 ** -1)
      p(2 ** -1)        # (1/2)
      p(2 ** -2)        # (1/4)
      p((-2) ** -2)     # (1/4)
      p((-2) ** -3)     # (-1/8)
      begin
        p(0 ** -1)
      rescue ZeroDivisionError => e
        puts "#{e.class}: #{e.message}"
      end
      begin
        2.pow(-1, 5)
      rescue RangeError => e
        puts "#{e.class}: #{e.message}"
      end
    RUBY

    _(result).must_answer <<~'OUT'
      1024
      1
      81
      0.5
      (1/2)
      (1/4)
      (1/4)
      (-1/8)
      ZeroDivisionError: divided by 0
      RangeError: Integer#pow() 1st argument cannot be negative when 2nd argument specified
    OUT
  end

  it "nil from int container arithmetic" do
    result = zr(<<~'RUBY')
      # A miss on an Integer-element Hash or Array is nil, so arithmetic on it
      # raises rather than computing on the sentinel that represents it: nil on the
      # left is NoMethodError, nil on the right is the coercion TypeError, exactly
      # as CRuby reports them. Reading the value and asking nil? still work.
      h = { 0 => 0 }
      a = [1, 2, 3]

      v = h[9]
      p v.nil?
      p v.inspect
      p v.class

      begin
        p(h[9] + 1)
      rescue NoMethodError => e
        puts "#{e.class}: #{e.message}"
      end

      begin
        p(a[99] - 1)
      rescue NoMethodError => e
        puts "#{e.class}: #{e.message}"
      end

      begin
        p(1 + h[9])
      rescue TypeError => e
        puts "#{e.class}: #{e.message}"
      end

      begin
        p(a[99] * 2)
      rescue NoMethodError => e
        puts "#{e.class}: #{e.message}"
      end

      begin
        p(h[9] / 2)
      rescue NoMethodError => e
        puts "#{e.class}: #{e.message}"
      end

      begin
        p(a[99] % 2)
      rescue NoMethodError => e
        puts "#{e.class}: #{e.message}"
      end

      begin
        p h[9].abs
      rescue NoMethodError => e
        puts "#{e.class}: #{e.message}"
      end

      # a present key still computes
      p h[0] + 1
      p a[0] * 3
      p a[-1] - 1

      # and the usual nil-guarding idioms are unaffected
      p(h[9] || 7)
      p(h.fetch(9, 7) + 1)
      p(a[99].nil? ? 0 : 1)
    RUBY

    _(result).must_answer <<~'OUT'
      true
      "nil"
      NilClass
      NoMethodError: undefined method '+' for nil
      NoMethodError: undefined method '-' for nil
      TypeError: nil can't be coerced into Integer
      NoMethodError: undefined method '*' for nil
      NoMethodError: undefined method '/' for nil
      NoMethodError: undefined method '%' for nil
      NoMethodError: undefined method 'abs' for nil
      1
      3
      2
      7
      8
      0
    OUT
  end

  it "non finite float literals compile" do
    result = zr(<<~'RUBY')
      # `1e400` overflows to Infinity at parse time. Infinity has no finite
      # float LITERAL to emit, so codegen must emit the constant another way
      # instead -- the value is perfectly ordinary Ruby.

      big = 1e400
      p big
      p(-1e400)
      p big.infinite?
      p (big - big).nan?
      p [1e400, -1e400].max
    RUBY

    _(result).must_answer <<~'OUT'
      Infinity
      -Infinity
      1
      true
      Infinity
    OUT
  end

  it "poly arith" do
    result = zr(<<~'RUBY')
      # Test arithmetic on polymorphic values

      def calc(a, b)
        a + b
      end

      puts calc(10, 20)         # 30
      puts calc(1.5, 2.5)       # 4.0
      puts calc("hello", " world")  # hello world

      # Mixed numeric
      def double(x)
        x * 2
      end

      puts double(5)     # 10
      puts double(3.14)  # 6.28

      # Comparison
      def bigger?(a, b)
        a > b
      end

      puts bigger?(10, 5)     # true
      puts bigger?(1.0, 2.0)  # false

      # to_s on poly
      def show(x)
        puts x.to_s
      end
      show(42)
      show("hi")

      puts "done"
    RUBY

    _(result).must_answer <<~'OUT'
      30
      4.0
      hello world
      10
      6.28
      true
      false
      42
      hi
      done
    OUT
  end

  it "promote shl pow bigint" do
    result = zr(<<~'RUBY')
      # A runtime << past the word and a runtime ** whose result overflows give a
      # Bignum (CRuby semantics); in-range results stay exact Integers, also above
      # 2^53. Bignum receivers shift and power as Bignums.
      a = 1
      p(a << 70)
      b = 2; e = 100
      p(b ** e)
      x = 3; p(x ** 5)
      y = 1; p(y << 10)
      z = 3; p(z ** 39)
      big = 10 ** 30
      p(big << 4)
      p(big ** 2)
      f = 1; (1..25).each { |k| f = f * k }; p(f)
    RUBY

    _(result).must_answer <<~'OUT'
      1180591620717411303424
      1267650600228229401496703205376
      243
      1024
      4052555153018976267
      16000000000000000000000000000000
      1000000000000000000000000000000000000000000000000000000000000
      15511210043330985984000000
    OUT
  end

  it "rational arithmetic" do
    result = zr(<<~'RUBY')
      # Rational arithmetic with Integer numerators and denominators.
      a = Rational(2, 4)
      b = Rational(1, 3)
      puts a
      puts a.inspect
      puts(a + b)
      puts(a - b)
      puts(a * b)
      puts(a / b)
      puts(a ** 3)
      puts(a ** -2)
      puts a.numerator
      puts a.denominator
      puts a.to_f
      puts a.to_i
      puts(-a)
      puts a.abs
      puts Rational(-3, 9).abs
      puts "interp: #{a} and #{a + b}"
      p a
      p Rational(7, 2)

      # comparisons
      puts(a < b)
      puts(a > b)
      puts(a <= Rational(1, 2))
      puts(a == Rational(1, 2))
      puts(a <=> b)

      # mixed Integer/Rational
      puts(1 + Rational(1, 2))
      puts(2 / 3r)
      puts(3 * Rational(2, 9))
      puts(Rational(1, 2) + 1)
      puts(Rational(3, 1) == 3)
      puts(1 < Rational(3, 2))

      # through a method (param typing)
      def sumr(x, y)
        x + y
      end
      puts(sumr(Rational(1, 4), Rational(1, 4)))

      # Integer#quo
      puts(10.quo(4))
    RUBY

    _(result).must_answer <<~'OUT'
      1/2
      (1/2)
      5/6
      1/6
      1/6
      3/2
      1/8
      4/1
      1
      2
      0.5
      0
      -1/2
      1/2
      1/3
      interp: 1/2 and 5/6
      (1/2)
      (7/2)
      false
      true
      true
      true
      1
      3/2
      2/3
      2/3
      3/2
      true
      true
      1/2
      5/2
    OUT
  end

  it "rational bigint and complex zero" do
    result = zr(<<~'RUBY')
      # Rational() with a bignum operand, and Complex#zero? on a poly receiver
      p Rational(-(10**30), 3)
      p Rational(10**30, -3)
      p Rational(10**30)
      p Rational(10**30, 10**28)
      p Rational(3, 4)
      p Rational(6, 4)

      def sign(v) = "#{v.zero?} #{v.positive?} #{v.negative?}"
      def sign_via(pair) = sign(pair[1])
      puts sign_via([:x, Rational(-(10**30), 3)])
      puts sign_via([:x, Rational(10**30, 3)])

      def z(v) = v.zero?
      def z_via(pair) = z(pair[1])
      p z_via([:x, Complex(0, 0)])
      p z_via([:x, Complex(1, 2)])
      p z_via([:x, Complex(0, 1)])
      r = (z_via([:x, "abc"]) rescue $!.class); p r
      r2 = (z_via([:x, nil]) rescue $!.class); p r2
    RUBY

    _(result).must_answer <<~'OUT'
      (-1000000000000000000000000000000/3)
      (-1000000000000000000000000000000/3)
      (1000000000000000000000000000000/1)
      (100/1)
      (3/4)
      (3/2)
      false false true
      false true false
      true
      false
      false
      NoMethodError
      NoMethodError
    OUT
  end

  it "rational div family" do
    result = zr(<<~'RUBY')
      # Rational quo / fdiv / div, and round / truncate with a precision argument.
      # Receivers and some precisions go through method params, so their values are
      # known only at run time. Each operand kind has its own helper method.
      def q_r(a, b) = a.quo(b)
      def q_i(a, b) = a.quo(b)
      def q_f(a, b) = a.quo(b)
      def fd_r(a, b) = a.fdiv(b)
      def fd_i(a, b) = a.fdiv(b)
      def fd_f(a, b) = a.fdiv(b)
      def dv_r(a, b) = a.div(b)
      def dv_i(a, b) = a.div(b)
      def dv_f(a, b) = a.div(b)
      def rnd(a) = a.round
      def rnd2(a) = a.round(2)
      def rnd0(a) = a.round(0)
      def rndm1(a) = a.round(-1)
      def rndn(a, n) = a.round(n)
      def trc2(a) = a.truncate(2)
      def trcm1(a) = a.truncate(-1)
      def trcn(a, n) = a.truncate(n)

      r = Rational(22, 7)
      # quo: Rational / Integer / Float operands
      p q_r(Rational(1, 2), Rational(1, 3))   # (3/2)
      p q_i(Rational(3, 4), 2)                # (3/8)
      p q_f(Rational(3, 4), 0.5)              # 1.5
      p q_r(Rational(-1, 2), Rational(1, 3))  # (-3/2)
      # fdiv: always Float
      p fd_r(Rational(3, 2), Rational(1, 2))  # 3.0
      p fd_i(Rational(3, 2), 3)               # 0.5
      p fd_f(Rational(3, 2), 0.5)             # 3.0
      # div: floor division to Integer
      p dv_r(Rational(7, 2), Rational(1, 1))  # 3
      p dv_r(Rational(-7, 2), Rational(1, 1)) # -4
      p dv_i(Rational(7, 2), 2)               # 1
      p dv_i(Rational(-7, 2), 2)              # -2
      p dv_f(Rational(7, 2), 1.5)             # 2
      # round: ties away from zero; literal precisions pick the class statically
      p rnd(r)                   # 3
      p rnd(Rational(-22, 7))    # -3
      p rnd(Rational(5, 2))      # 3
      p rnd(Rational(-5, 2))     # -3
      p rnd2(r)                  # (157/50)
      p rnd0(r)                  # 3
      p rndm1(Rational(157, 2))  # 80
      # non-literal precision: class chosen from the runtime value
      p rndn(r, 2)               # (157/50)
      p rndn(r, 0)               # 3
      p rndn(r, -1)              # 0
      # truncate: toward zero
      p trc2(r)                  # (157/50)
      p trcm1(Rational(157, 2))  # 70
      p trcn(r, 1)               # (31/10)
      p trcn(r, 0)               # 3
      # zero divisors raise
      begin
        dv_r(Rational(1, 2), Rational(0, 1))
      rescue ZeroDivisionError => e
        puts "#{e.class}: #{e.message}"
      end
      begin
        q_r(Rational(1, 2), Rational(0, 1))
      rescue ZeroDivisionError => e
        puts "#{e.class}: #{e.message}"
      end
    RUBY

    _(result).must_answer <<~'OUT'
      (3/2)
      (3/8)
      1.5
      (-3/2)
      3.0
      0.5
      3.0
      3
      -4
      1
      -2
      2
      3
      -3
      3
      -3
      (157/50)
      3
      80
      (157/50)
      3
      0
      (157/50)
      70
      (31/10)
      3
      ZeroDivisionError: divided by 0
      ZeroDivisionError: divided by 0
    OUT
  end

  it "rational round family takes precision" do
    result = zr(<<~'RUBY')
      # floor/ceil/truncate WITH a precision keep the fraction: 157/50 is
      # 3.14, so floor(1)=3.1=(31/10), ceil(1)=3.2=(16/5), truncate(1)=(31/10)
      # (checked against ruby 4.0.7).

      r = Rational(157, 50)
      p r.round(2)
      p r.round(-1)
      p r.round
      p r.floor(1)
      p r.ceil(1)
      p r.truncate(1)
      p Rational(-7, 2).round
    RUBY

    _(result).must_answer <<~'OUT'
      (157/50)
      0
      3
      (31/10)
      (16/5)
      (31/10)
      -4
    OUT
  end

  it "rational round precision" do
    result = zr(<<~'RUBY')
      # Rational#round/floor/ceil/truncate take an optional precision: a positive
      # ndigits answers a Rational, zero or negative an Integer.
      r = Rational(157, 50)   # 3.14
      p r.round
      p r.round(2)
      p r.round(1)
      p r.round(-1)
      p r.floor(1)
      p r.ceil(1)
      p r.truncate(1)
      p Rational(-7, 2).round      # ties away from zero
      p Rational(-7, 2).truncate   # toward zero
      p Rational(25, 10).round(-1)
    RUBY

    _(result).must_answer <<~'OUT'
      3
      (157/50)
      (31/10)
      0
      (31/10)
      (16/5)
      (31/10)
      -4
      -3
      0
    OUT
  end

  it "round half mode" do
    result = zr(<<~'RUBY')
      # round(digits, half: mode) uses the mode with digits too, and a mode that
      # CRuby does not know raises.
      p(0.125.round(2, half: :even))
      p(0.125.round(2, half: :down))
      p(1.25.round(1, half: :even))
      p((-0.125).round(2, half: :even))
      v001 = 0.125; c001 = (v001.round(2, half: :even)); p c001

      r002 = (1.5.round(half: :bogus) rescue $!.class); p r002
      r003 = (1.5.round(2, half: :bogus) rescue $!.class); p r003
      r004 = (15.round(-1, half: :bogus) rescue $!.class); p r004
      p(1.5.round(half: :even))
      p(2.5.round(half: :even))
      p(2.5.round(half: :up))
      p(2.5.round(half: :down))
      p(15.round(-1, half: :even))
      p(25.round(-1, half: :even))
      p(0.125.round(2))
      p(1.25.round(1))
    RUBY

    _(result).must_answer <<~'OUT'
      0.12
      0.12
      1.2
      -0.12
      0.12
      ArgumentError
      ArgumentError
      ArgumentError
      2
      2
      3
      2
      20
      20
      0.13
      1.3
    OUT
  end

  it "std stream dup survives a reopen round trip" do
    result = zr(<<~'RUBY')
      # `$stdout.dup` has to be a REAL descriptor, not a second name for fd 1:
      # saving the old stream before a `reopen` and restoring it afterwards is the
      # whole point, and mkmf's `Logging.open` is that exact sequence.
      log = File.open("round-trip.log", "wb")
      saved = $stdout.dup
      puts "a fresh descriptor: #{saved.fileno != $stdout.fileno}"
      puts "a plain IO:         #{saved.class}"

      $stdout.reopen(log)
      puts "into the log"
      $stdout.reopen(saved)
      puts "back on the console"

      log.close
      saved.close
      puts "the log holds: #{File.read("round-trip.log").split("\n").inspect}"
      File.unlink("round-trip.log")

      # A dup of a closed stream still raises, and a File dup still reads the file.
      File.write("payload.txt", "abc")
      f = File.open("payload.txt")
      g = f.dup
      puts "a File dup reads:   #{g.read}"
      f.close
      g.close
      File.unlink("payload.txt")
    RUBY

    _(result).must_answer <<~'OUT'
      a fresh descriptor: true
      a plain IO:         IO
      back on the console
      the log holds: ["into the log"]
      a File dup reads:   abc
    OUT
  end

  it "** refuses an exponent past ruby's limit, and pow with a modulus of one is zero" do
    result = zr(<<~'RUBY')
      def t = (yield rescue $!.message)
      p t { 2**(2**40) }, t { 3**(2**64) }, t { (2**70)**(2**30) }
      p 1**(2**64), (-1)**(2**64 + 1), 0**(2**64)
      p 5.pow(0, 1), 5.pow(0, -1), 5.pow(0, -5), 2.pow(3, -5)
    RUBY

    _(result).must_answer <<~'OUT'
      "exponent is too large"
      "exponent is too large"
      "exponent is too large"
      1
      -1
      0
      0
      0
      -4
      -2
    OUT
  end

  it "round with half: and digits, prev_float of infinity, gamma's poles, log's fused sum and float steps" do
    result = zr(<<~'RUBY')
      p 1.005.round(2, half: :even), 4.45.round(1, half: :even), 0.285.round(2, half: :down), 25.4.round(-1, half: :even)
      p Float::INFINITY.prev_float, (-Float::INFINITY).next_float
      p Math.gamma(-0.0), Math.gamma(Float::INFINITY), Math.gamma(Float::NAN).nan?
      p Math.log(2, 1), Math.log(2, 2**1000), Math.log(2**2000), Math.log(10**400, 2**2000)
      p (1.0..2.0).step(0.1).to_a
      p 5.pow(0, 1)
    RUBY

    _(result).must_answer <<~'OUT'
      1.0
      4.5
      0.28
      20
      1.7976931348623157e+308
      -1.7976931348623157e+308
      -Infinity
      Infinity
      true
      NaN
      0.001
      1386.2943611198905
      3.547450783405683e+17
      [1.0, 1.1, 1.2, 1.3, 1.4, 1.5, 1.6, 1.7, 1.8, 1.9000000000000001, 2.0]
      0
    OUT
  end

  it "to_r and to_c read as parse_rat and read_comp do, and upto yields a start longer than the end" do
    result = zr(<<~'RUBY')
      p "1/2.5".to_r, "1_000.5_5".to_r, "1__2".to_r, ".5".to_r
      p "1+2j".to_c, "1+2I".to_c, "Infinity".to_c
      p Rational(".5")
      begin
        Rational("1.e3")
      rescue ArgumentError => e
        p e.message
      end
      p "aa".upto("b").to_a, ("a9".."b").to_a
    RUBY

    _(result).must_answer <<~'OUT'
      (2/5)
      (20011/20)
      (1/1)
      (1/2)
      (1+2i)
      (1+2i)
      (0+1i)
      (1/2)
      "invalid value for convert(): \"1.e3\""
      ["aa"]
      ["a9"]
    OUT
  end
end
