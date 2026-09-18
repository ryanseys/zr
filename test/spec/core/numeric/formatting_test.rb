# frozen_string_literal: true

require "spec_helper"

describe "Numeric: formatting and inspection" do
  it "bignum rational basic" do
    result = ze0(<<~'RUBY')
      # to_r / rationalize / quo on a Bignum build a boxed big Rational (numerator
      # exceeds mrb_int); construction, inspect/to_s/puts, to_f, class, and == are
      # wired. Arithmetic and <=> on a big Rational are follow-up work. The by-value
      # int Rational is unchanged. (#2469)
      p((10**30).to_r)
      p((10**30).rationalize)
      p((10**30).quo(3))
      p((10**30).quo(2**64))
      p((-(10**30)).to_r)
      p((10**30).to_r.to_f)
      p((10**30).to_r.class)
      p((10**30).to_r == (10**30).to_r)
      p((10**30).to_r == (10**31).to_r)
      puts((10**30).quo(7))
      a = [(10**30).quo(7), (10**40).to_r]
      p a
      # the int Rational path is unaffected
      p((1r/3))
      p(3.to_r)
      p((1r/2) + (1r/3))
      p(2.quo(3))
      p(0.5.to_r)
    RUBY

    _(result).must_answer <<~'OUT'
      (1000000000000000000000000000000/1)
      (1000000000000000000000000000000/1)
      (1000000000000000000000000000000/3)
      (931322574615478515625/17179869184)
      (-1000000000000000000000000000000/1)
      1.0e+30
      Rational
      true
      false
      1000000000000000000000000000000/7
      [(1000000000000000000000000000000/7), (10000000000000000000000000000000000000000/1)]
      (1/3)
      (3/1)
      (5/6)
      (2/3)
      (1/2)
    OUT
  end

  it "bignum recv int ord float toi" do
    result = ze0(<<~'RUBY')
      # Bignum-receiver conveniences (digits/to_s(base)/even?/odd?/abs),
      # Integer#ord/#integer?, and Float#to_i beyond int64 raising loudly
      # (Bignum promotion for statically-int results is tracked on #2024).
      x = 2 ** 100
      p(x.digits)
      p(x.to_s(16))
      p(x.even?)
      p(x.odd?)
      p(x.abs)
      y = x * -1
      p(y.abs)
      p(x.to_s(2).length)
      p(5.integer?)
      p(65.ord)
      n = 7
      p n.ord
      p n.integer?
      begin
        (1.5e20).to_i
      rescue RangeError => e
        puts "RangeError"
      end
      p 3.9.to_i
      p(-2.9.to_i)
    RUBY

    _(result).must_answer <<~'OUT'
      [6, 7, 3, 5, 0, 2, 3, 0, 7, 6, 9, 4, 1, 0, 4, 9, 2, 2, 8, 2, 2, 0, 0, 6, 0, 5, 6, 7, 6, 2, 1]
      "10000000000000000000000000"
      true
      false
      1267650600228229401496703205376
      1267650600228229401496703205376
      101
      true
      65
      7
      true
      3
      -2
    OUT
  end

  it "complex component class" do
    result = ze0(<<~'RUBY')
      # Complex components carry their CRuby class (Integer vs Float): rendering,
      # real/imaginary, abs/abs2, and arithmetic propagation.
      def ts(c) = c.to_s
      def ins(c) = c.inspect
      def re(c) = c.real
      def im(c) = c.imag
      def ab(c) = c.abs
      def ab2(c) = c.abs2

      # rendering keeps each component's class
      puts ts(Complex(1, 0.0))     # 1+0.0i
      puts ts(Complex(1.0, 2))     # 1.0+2i
      puts ins(Complex(3, 4))      # (3+4i)
      puts ins(Complex(3.0, 4.0))  # (3.0+4.0i)
      puts ins(3.0i)               # (0+3.0i)
      puts ins(4i)                 # (0+4i)
      # real / imaginary keep the component class
      p re(Complex(5, 2))          # 5
      p re(Complex(5.0, 2))        # 5.0
      p im(Complex(5, 2))          # 2
      p im(Complex(5, 2.5))        # 2.5
      # abs: Integer only via the zero-component shortcut on an all-Integer complex
      p ab(Complex(0, 2))          # 2
      p ab(Complex(-3, 0))         # 3
      p ab(Complex(3, 4))          # 5.0
      p ab(Complex(2, 0.0))        # 2.0
      p ab(Complex(0.5, 0))        # 0.5
      # abs2: Integer iff both components are Integer-classed
      p ab2(Complex(3, 4))         # 25
      p ab2(Complex(3.0, 4))       # 25.0
      p ab2(Complex(0.5, 0.5))     # 0.5
      # arithmetic propagates per component (add/sub) or poisons both (mul/div)
      p Complex(1, 2) + Complex(1, 3)      # (2+5i)
      p Complex(1.0, 2) + Complex(1, 3)    # (2.0+5i)
      p Complex(1, 2) * Complex(2, 3)      # (-4+7i)
      p Complex(1.0, 2) * Complex(2, 3)    # (-4.0+7.0i)
      p Complex(1, 2) - 1                  # (0+2i)
      p Complex(1, 2) + 0.5                # (1.5+2i)
      # polar constructor: exact right angles keep the magnitude's class
      p Complex.polar(2, 0)                # (2+0.0i)
      p Complex.polar(2.0, 0)              # (2.0+0.0i)
      p Complex.polar(5, Math::PI / 2)     # (0.0+5i)
      p Complex.polar(3, Math::PI)         # (-3+0.0i)
      p Complex.polar(2, 1)                # (1.0806046117362795+1.682941969615793i)
      # conjugate and negation keep classes
      p Complex(1, 2.5).conjugate          # (1-2.5i)
      p (-Complex(1.5, 2))                 # (-1.5-2i)
    RUBY

    _(result).must_answer <<~'OUT'
      1+0.0i
      1.0+2i
      (3+4i)
      (3.0+4.0i)
      (0+3.0i)
      (0+4i)
      5
      5.0
      2
      2.5
      2
      3
      5.0
      2.0
      0.5
      25
      25.0
      0.5
      (2+5i)
      (2.0+5i)
      (-4+7i)
      (-4.0+7.0i)
      (0+2i)
      (1.5+2i)
      (2+0.0i)
      (2.0+0.0i)
      (0.0+5i)
      (-3+0.0i)
      (1.0806046117362795+1.682941969615793i)
      (1-2.5i)
      (-1.5-2i)
    OUT
  end

  it "complex component class abs and division" do
    result = ze0(<<~'RUBY')
      # Complex#abs keeps the Integer class when a component is zero and both are
      # integers (Complex(0,2).abs == 2), else Float. Dividing by a real scalar
      # is componentwise: a Float 0.0 divisor yields Infinity, an Integer 0
      # raises. Non-finite imaginary parts render with `*i`.

      p Complex(0, 2).abs
      p Complex(-3, 0).abs
      p Complex(3, 4).abs
      p Complex(2, 0.0).abs
      p Complex(0, 2).polar[0]
      p(Complex(20, 40) / 0.0)
      p(Complex(21, 41) / 2.0)
      p(Complex(20, 40) / 4)
      r = (begin; Complex(20, 40) / 0; rescue ZeroDivisionError => e; e.message; end); p r
      p((Complex(3, 0) / 0.0).to_s)
    RUBY

    _(result).must_answer <<~'OUT'
      2
      3
      5.0
      2.0
      2
      (Infinity+Infinity*i)
      (10.5+20.5i)
      (5+10i)
      "divided by 0"
      "Infinity+NaN*i"
    OUT
  end

  it "complex division" do
    result = ze0(<<~'RUBY')
      # Complex#/ by a real scalar divides each component. Boxing the real into c+0i
      # and running the conjugate formula produced NaN at a zero divisor; MRI divides
      # componentwise, so a Float zero yields Infinity and an Integer zero raises
      # ZeroDivisionError (integer division rules).
      def df(a, b); a / b; end
      p df(Complex(20, 40), 0.0)              # (Infinity+Infinity*i)
      p df(Complex(21, 41), 2.0)             # (10.5+20.5i)
      p df(Complex(-20, 40), 0.0)            # (-Infinity+Infinity*i)

      def dnan(a, b); a / b; end
      p dnan(Complex(0, 0), 0.0)             # (NaN+NaN*i)

      def di(a, b); a / b; end
      p di(Complex(20, 40), 4)               # (5+10i)

      def dz(a, b); a / b; end
      begin
        dz(Complex(20, 40), 0)
        puts "no raise"
      rescue ZeroDivisionError => e
        puts e.message                        # divided by 0
      end

      # Complex / Complex still uses the full division.
      def dc(a, b); a / b; end
      p dc(Complex(20, 40), Complex(2, 0))   # (10+20i)

      # Infinity / NaN component formatting in inspect and to_s.
      def inf(a, b); a / b; end
      p inf(Complex(3, 0), 0.0).to_s          # "Infinity+NaN*i"  (0/0.0 imag is NaN)
    RUBY

    _(result).must_answer <<~'OUT'
      (Infinity+Infinity*i)
      (10.5+20.5i)
      (-Infinity+Infinity*i)
      (NaN+NaN*i)
      (5+10i)
      divided by 0
      (10+20i)
      "Infinity+NaN*i"
    OUT
  end

  it "complexes keep component classes" do
    result = ze0(<<~'RUBY')
      # Complex: imaginary literals, component-class preservation (exact
      # Integer/Rational components incl. the den==1 demotion inside complex
      # division), formatting (`(2/25)*i`), polar surface, and coercion errors.

      c = 4i
      puts c.class
      p c
      p 3 + 4i
      p Complex(1, 2) * Complex(3, 4)
      p Complex(1, 2) / Complex(3, 4)
      p Complex(1, 2) / 2
      p Complex(1, 2) ** 2
      p Complex(1.5, -2.5)
      puts Complex(1.5, -2.5)
      puts Complex(3, 4).abs
      p Complex(3, 4).abs2
      p Complex(3, 4).rect
      p Complex(1, -2).conjugate
      p Complex(2, 0) == 2
      p Complex(1, 2).real
      p Complex(1, 2).imaginary
      p 5.to_c
      begin
        Complex(1, 2) + "x"
      rescue TypeError => e
        puts "TypeError: #{e.message}"
      end
    RUBY

    _(result).must_answer <<~'OUT'
      Complex
      (0+4i)
      (3+4i)
      (-5+10i)
      ((11/25)+(2/25)*i)
      ((1/2)+1i)
      (-3+4i)
      (1.5-2.5i)
      1.5-2.5i
      5.0
      25
      [3, 4]
      (1+2i)
      true
      1
      2
      (5+0i)
      TypeError: String can't be coerced into Complex
    OUT
  end

  it "conv float truncation" do
    result = ze0(<<~'RUBY')
      # Floats truncate at NUM2LONG index sites (CRuby's rule).
      p "ab" * 2.9
      p [1, 2] * 2.9
      p [10, 20, 30][1.7]
      p [10, 20, 30].first(2.9)
      p [1, 2, 3].take(2.9)
      p [1, 2, 3].drop(1.5)
      p [1, 2, 3, 4].values_at(1.9)
      p [1, 2, 3].pop(2.9)
      p "abcde"[1.5, 2.9]
      p "10".to_i(2.9)
      p "a".center(10.5)
      p [1, 2, 3].fill(0, 1.5)
      s = +"abc"
      s[1.7] = "X"
      p s
      a = [1, 2, 3, 4]
      a[1.5..2] = 9
      p a
    RUBY

    _(result).must_answer <<~'OUT'
      "abab"
      [1, 2, 1, 2]
      20
      [10, 20]
      [1, 2]
      [2, 3]
      [2]
      [2, 3]
      "bc"
      2
      "    a     "
      [1, 0, 0]
      "aXc"
      [1, 9, 4]
    OUT
  end

  it "float scientific notation" do
    result = ze0(<<~'RUBY')
      # Float#to_s switches to scientific notation when the shortest-decimal point
      # position leaves -3..15 -- i.e. |x| >= 1e15 or |x| < 1e-4 -- matching CRuby.
      puts 999999999999999.0       # 999999999999999.0  (decpt 15, fixed)
      puts 1000000000000000.0      # 1.0e+15            (decpt 16, scientific)
      puts 1234567890123456.0      # 1.234567890123456e+15
      puts 6402373705728000.0      # 6.402373705728e+15  (18!)
      puts 1e16                    # 1.0e+16
      puts 0.0001                  # 0.0001             (decpt -3, fixed)
      puts 0.00009                 # 9.0e-05            (decpt -4, scientific)
      puts 2.220446049250313e-16   # Float::EPSILON
    RUBY

    _(result).must_answer <<~'OUT'
      999999999999999.0
      1.0e+15
      1.234567890123456e+15
      6.402373705728e+15
      1.0e+16
      0.0001
      9.0e-05
      2.220446049250313e-16
    OUT
  end

  it "float to s fixed 1e15" do
    result = ze0(<<~'RUBY')
      # Float#to_s uses plain decimal (not scientific) for a fractional value whose
      # integer part is 16 digits (1e15..1e16), matching CRuby (#2593).
      puts 4503599627370495.5
      puts 1000000000000000.5
      puts 1234567890123456.7
      puts 123456789012345.6
      # integer-valued 16-digit doubles still print scientific
      puts 9007199254740992.0
      puts 1e15
      puts 1e16
    RUBY

    _(result).must_answer <<~'OUT'
      4503599627370495.5
      1000000000000000.5
      1234567890123456.8
      123456789012345.6
      9.007199254740992e+15
      1.0e+15
      1.0e+16
    OUT
  end

  it "float to s scientific notation threshold" do
    result = ze0(<<~'RUBY')
      # Fixed for decpt in -3..=15, else scientific -- matches CRuby's Float#to_s.

      puts 999999999999999.0
      puts 1000000000000000.0
      puts 6402373705728000.0
      puts 0.0001
      puts 0.00009
    RUBY

    _(result).must_answer <<~'OUT'
      999999999999999.0
      1.0e+15
      6.402373705728e+15
      0.0001
      9.0e-05
    OUT
  end

  it "int opt p inspect" do
    result = ze0(<<~'RUBY')
      # `p` and inspect on a nullable int (int?) print "nil" for the
      # missing/zero-sentinel case, not blank or the raw sentinel.
      p 0.nonzero?
      p 42.nonzero?
      p [].first
      x = 0.nonzero?
      p x
      puts 0.nonzero?.inspect
    RUBY

    _(result).must_answer <<~'OUT'
      nil
      42
      nil
      nil
      nil
    OUT
  end

  it "integer extra methods" do
    result = ze0(<<~'RUBY')
      # Issues #875 #876 #873 #860 #894:
      # Integer methods that were not dispatched - magnitude (alias for abs),
      # modulo (alias for %), remainder (truncated division remainder, differs
      # from % for mixed-sign), size (bytes per mrb_int = 8), gcdlcm.
      puts (-42).magnitude
      puts 7.modulo(3)
      puts (-7).modulo(3)
      puts 7.remainder(3)
      puts (-7).remainder(3)
      puts 12.gcdlcm(18).inspect
      puts 1.size
      puts 256.size
    RUBY

    _(result).must_answer <<~'OUT'
      42
      1
      2
      1
      -1
      [6, 36]
      8
      8
    OUT
  end

  it "kernel float integer strict" do
    result = ze0(<<~'RUBY')
      # Kernel#Float / #Integer strictness, CRuby-parity edges:
      # - digit-separating underscores parse ("1_000.5"); misplaced ones raise
      # - an embedded NUL is invalid (a C-string scan would parse the prefix)
      # - ".5" and "5." both parse (CRuby 4.0 accepts a trailing dot)
      # - hex Float literals parse, including fractional and p-exponent forms
      #   ("0x1_1" -> 17.0, "0x1_1.0" -> 17.0, CRuby 4.0)
      # - "inf"/"nan" raise (strtod would parse them)
      # - Integer() auto-detects prefix bases, including leading-0 octal ("077" -> 63)
      def tf(s)
        Float(s)
      rescue ArgumentError
        "AE"
      end
      def ti(s)
        Integer(s)
      rescue ArgumentError
        "AE"
      end
      ["1_000.5", "1_0.5_5", "1e1_0", "0x1_1", "0x1_1.0", "1__0", "1_", "_1",
       "1_e3", "1e_3", ".5", "5.", "inf", "Infinity", "nan", " +3.25 "].each do |s|
        puts "F #{s.inspect} #{tf(s).inspect}"
      end
      puts "F NUL #{tf("1\0").inspect}"
      ["1_000", "077", "0x1A", "0b101", " -7 ", "1__0"].each do |s|
        puts "I #{s.inspect} #{ti(s).inspect}"
      end
      puts "I NUL #{ti("1\0").inspect}"
    RUBY

    _(result).must_answer <<~'OUT'
      F "1_000.5" 1000.5
      F "1_0.5_5" 10.55
      F "1e1_0" 10000000000.0
      F "0x1_1" 17.0
      F "0x1_1.0" 17.0
      F "1__0" "AE"
      F "1_" "AE"
      F "_1" "AE"
      F "1_e3" "AE"
      F "1e_3" "AE"
      F ".5" 0.5
      F "5." 5.0
      F "inf" "AE"
      F "Infinity" "AE"
      F "nan" "AE"
      F " +3.25 " 3.25
      F NUL "AE"
      I "1_000" 1000
      I "077" 63
      I "0x1A" 26
      I "0b101" 5
      I " -7 " -7
      I "1__0" "AE"
      I NUL "AE"
    OUT
  end

  it "the divmod, rounding, gcd, predicate and iteration families all match the oracle" do
    result = ze0(<<~'RUBY')
      # The Numeric/Integer/Float Tier A breadth: divmod matrices, the rounding
      # families, gcd/lcm/digits/chr/ord, predicates, step/times/upto/downto,
      # exact Float#to_r, and bignum-capable Float#to_i.

      puts 7.divmod(3).inspect
      puts (-7).divmod(3).inspect
      puts 7.divmod(2.5).inspect
      puts (-7).abs
      puts 2.5.abs
      puts 4.even?
      puts 3.odd?
      puts 5.succ
      puts 5.pred
      puts 65.chr
      puts "A".ord
      puts 10.digits.inspect
      puts 255.digits(16).inspect
      puts 4.gcd(6)
      puts 4.lcm(6)
      puts 4.gcdlcm(6).inspect
      puts 255.to_s(16)
      puts 10.to_s(2)
      puts 25.round(-1)
      puts 1234.round(-2)
      puts (-15).round(-1)
      puts 1234.floor(-2)
      puts 1234.ceil(-2)
      puts 7.fdiv(2)
      puts 3.7.round
      puts 3.14159.round(2)
      puts (-2.7).floor
      puts 2.2.ceil
      puts 5.9.truncate
      puts 1e20.to_i
      puts 0.125.to_r.inspect
      puts (1.0 / 0).infinite?
      puts 1.5.nan?
      puts 2.5.finite?
      puts 5.zero?
      puts 0.zero?
      puts 5.positive?
      puts (-5).negative?
      puts 5.numerator
      puts 5.denominator
      puts 0.5.numerator
      puts 0.5.denominator
      puts (-7).remainder(3)
      acc = []
      1.step(10, 3) { |i| acc << i }
      puts acc.inspect
      acc2 = []
      3.times { |i| acc2 << i }
      2.upto(4) { |i| acc2 << i }
      3.downto(1) { |i| acc2 << i }
      puts acc2.inspect
      puts 255.bit_length
      puts 5.to_f
      puts 5.to_r.inspect
    RUBY

    _(result).must_answer <<~'OUT'
      [2, 1]
      [-3, 2]
      [2, 2.0]
      7
      2.5
      true
      true
      6
      4
      A
      65
      [0, 1]
      [15, 15]
      2
      12
      [2, 12]
      ff
      1010
      30
      1200
      -20
      1200
      1300
      3.5
      4
      3.14
      -3
      3
      5
      100000000000000000000
      (1/8)
      1
      false
      true
      false
      true
      true
      true
      5
      1
      1
      2
      -1
      [1, 4, 7, 10]
      [0, 1, 2, 2, 3, 4, 3, 2, 1]
      8
      5.0
      (5/1)
    OUT
  end

  it "an Integer operation given nil raises TypeError rather than ending the process" do
    result = ze0(<<~'RUBY')
      # GAP -- imported from the spinel corpus at c55d9bdb.
      # An Integer operation with a nil argument PANICS the runtime
      # (crates/zeo-rt/src/builtins/integer.rs) instead of raising TypeError.
      #
      r001 = (1.5.coerce(nil) rescue $!.class)
      p r001

      r002 = (5.pow(nil) rescue $!.class); p r002        # Spinel: 1
      r003 = (5.fdiv(nil) rescue $!.class); p r003       # Spinel: Infinity
      r004 = (5.divmod(nil) rescue $!.class); p r004     # Spinel: ZeroDivisionError
      r005 = (5.round(nil) rescue $!.class); p r005      # Spinel: 5
      r006 = (5.digits(nil) rescue $!.class); p r006     # Spinel: ArgumentError
      r007 = (5.to_s(nil) rescue $!.class); p r007       # Spinel: ArgumentError
      r008 = (5.coerce(nil) rescue $!.class); p r008     # Spinel: [0, 5]
      r009 = (5[nil] rescue $!.class); p r009            # Spinel: 1
      r010 = (5.gcdlcm(nil) rescue $!.class); p r010     # Spinel: [5, 0]
      r011 = (5.div(nil) rescue $!.class); p r011        # Spinel: ZeroDivisionError
      r012 = (5.modulo(nil) rescue $!.class); p r012     # Spinel: ZeroDivisionError
      r013 = (5.remainder(nil) rescue $!.class); p r013  # Spinel: ZeroDivisionError
      r014 = (5.ceildiv(nil) rescue $!.class); p r014    # Spinel: ZeroDivisionError
      r015 = (1.5.fdiv(nil) rescue $!.class); p r015     # Spinel: Infinity
      r016 = (1.5.divmod(nil) rescue $!.class); p r016   # Spinel: ZeroDivisionError
      r017 = (1.5.round(nil) rescue $!.class); p r017    # Spinel: 2

      r018 = (5.between?(nil, 9) rescue $!.class); p r018   # Spinel: true

      r019 = (1.5 + nil rescue $!.class); p r019    # => TypeError
      r023 = (1.5 ** nil rescue $!.class); p r023   # => TypeError
      r024 = (1.5 % nil rescue $!.class); p r024    # => TypeError
      r025 = (5.gcd(nil) rescue $!.class); p r025   # => TypeError
      r026 = (5.lcm(nil) rescue $!.class); p r026   # => TypeError
      r027 = (5 + nil rescue $!.class); p r027      # => TypeError
      r028 = (5 < nil rescue $!.class); p r028      # => ArgumentError
    RUBY

    _(result).must_answer <<~'OUT'
      TypeError
      TypeError
      TypeError
      TypeError
      TypeError
      TypeError
      TypeError
      TypeError
      TypeError
      TypeError
      TypeError
      TypeError
      TypeError
      TypeError
      TypeError
      TypeError
      TypeError
      ArgumentError
      TypeError
      TypeError
      TypeError
      TypeError
      TypeError
      TypeError
      ArgumentError
    OUT
  end

  it "rect, polar, rationalize and the collection leaf rows each answer" do
    result = ze0(<<~'RUBY')
      p 5.rect
      p 5.polar
      p((-5).polar)
      p 2.5.polar
      p 5.rationalize
      p Rational(3, 2).polar
      p(nil =~ /x/)
      p [1, 2, 3, 4].rfind { |x| x.even? }
      p [10, 20, 30].fetch_values(0, 2)
      p([10, 20, 30].fetch_values(0, 5) { |i| i * 100 })
      p({ a: 1, b: 2 }.to_proc.call(:b))
      p({ a: 1, b: 2 }.transform_keys!(&:to_s))
      p((1..5).overlap?(5..8))
      p((1...5).overlap?(5..8))
      p((1..5).overlap?(6..8))
    RUBY

    _(result).must_answer <<~'OUT'
      [5, 0]
      [5, 0]
      [5, 3.141592653589793]
      [2.5, 0]
      (5/1)
      [(3/2), 0]
      nil
      4
      [10, 30]
      [10, 500]
      2
      {"a" => 1, "b" => 2}
      true
      false
      false
    OUT
  end

  it "the bignum Integer, Rational, Complex, coercion, Math and conversion rows all answer" do
    result = ze0(<<~'RUBY')
      # Phase 17.1 -- the numeric tower: full-bignum Integer, Rational, Complex,
      # the CRuby-exact coercion matrix, Math, and Kernel conversions.

      r = 1
      i = 2
      while i <= 30
        r = r * i
        i += 1
      end
      puts r
      puts 2 ** 100
      puts 9_223_372_036_854_775_807 + 1
      puts (2 ** 70) > (2 ** 69)

      p 2 ** -2
      p 1.quo(3)
      p Rational(4, 8) + Rational(1, 3)
      p Rational(1, 2) + 0.5
      p 3.75r * 4

      c = Complex(1, 2) * Complex(3, 4)
      p c
      p c.real
      p c.imaginary
      p 4i + 3
      p Complex(1, 2) / 2

      puts 7.divmod(3).inspect
      puts (-7).divmod(3).inspect
      puts 10.digits.inspect
      puts 4.gcd(6)
      puts 255.to_s(16)
      puts 25.round(-1)
      puts 3.14159.round(2)
      puts 7.fdiv(2)
      puts 1e20.to_i
      puts 0.125.to_r.inspect

      puts Math.sqrt(16)
      puts Math.hypot(3, 4)
      puts Math::PI
      begin
        Math.sqrt(-1)
      rescue Math::DomainError => e
        puts "domain: #{e.message}"
      end

      puts Integer("ff", 16)
      puts Integer(" -4_2 ")
      puts Float("1.5e3")
      begin
        Integer("nope")
      rescue ArgumentError => e
        puts "bad: #{e.message}"
      end
    RUBY

    _(result).must_answer <<~'OUT'
      265252859812191058636308480000000
      1267650600228229401496703205376
      9223372036854775808
      true
      (1/4)
      (1/3)
      (5/6)
      1.0
      (15/1)
      (-5+10i)
      -5
      10
      (3+4i)
      ((1/2)+1i)
      [2, 1]
      [-3, 2]
      [0, 1]
      2
      ff
      30
      3.14
      3.5
      100000000000000000000
      (1/8)
      4.0
      5.0
      3.141592653589793
      domain: Numerical argument is out of domain - sqrt
      255
      -42
      1500.0
      bad: invalid value for Integer(): "nope"
    OUT
  end

  it "p bignum" do
    result = ze0(<<~'RUBY')
      # `p` of a bignum-producing expression must print the integer, just as
      # `puts`/`print` already do (Integer#inspect == #to_s). Previously the
      # `p` argument emitter had no TY_BIGINT case and rejected these.
      p(10**30)
      p(2**100)
      p(10 ** 20 + 1)
      p(2**64)
      p(3**50)
    RUBY

    _(result).must_answer <<~'OUT'
      1000000000000000000000000000000
      1267650600228229401496703205376
      100000000000000000001
      18446744073709551616
      717897987691852588770249
    OUT
  end

  it "rational complex literals" do
    result = ze0(<<~'RUBY')
      # Issues #840 #841 #872: Imaginary, Rational literals + Integer#quo.
      # Both surface as value-type structs (sp_Complex, sp_Rational).
      # Integer#quo returns a Rational. v1 scope: literal forms +
      # .inspect/.to_s; arithmetic between mixed Integer/Rational/Complex
      # is deferred to a follow-up.

      # Imaginary literals
      puts 1i.inspect
      puts 2i.inspect
      puts 3.0i.inspect

      # Imaginary parts via .real / .imag
      puts 5i.real
      puts 5i.imaginary

      # Rational literals (reduced by prism)
      puts 3r.inspect
      puts 4r.inspect

      # Integer#quo
      puts 7.quo(2).inspect
      puts 10.quo(4).inspect
      puts 100.quo(5).inspect

      # numerator / denominator
      puts 7.quo(2).numerator
      puts 7.quo(2).denominator
    RUBY

    _(result).must_answer <<~'OUT'
      (0+1i)
      (0+2i)
      (0+3.0i)
      0
      5
      (3/1)
      (4/1)
      (7/2)
      (5/2)
      (20/1)
      7
      2
    OUT
  end

  it "truncate module method" do
    result = ze0(<<~'RUBY')
      # Issue #314: a user-defined module method named `truncate` was
      # matched by `infer_method_name_type`'s Float#truncate(n) → Float
      # arm purely on the method name, ignoring the receiver. Result: a
      # `ViewHelpers.truncate(s, length: 100)` call site (which returns
      # a string) inferred as float at the caller, and a poly-arg call
      # like `html_escape(truncate(s, length: 100))` boxed the string
      # return through `sp_box_float(const char *)` — invalid C.
      #
      # Surfaced via Roundhouse's emitted real-blog views; minimal repro
      # extracted from `app/views/articles/_article.rb`'s
      # `io << ViewHelpers.html_escape(ViewHelpers.truncate(article.body,
      # length: 100))` line.
      #
      # Fix: gate the rule on a Float receiver. Float#truncate(n) keeps
      # its float typing; module-method `truncate` falls through to the
      # user-method-return lookup so it picks up the actual declared
      # return type.

      module M
        def self.html_escape(s)
          return "" if s.nil?
          s.to_s
        end

        def self.truncate(s, length: 30, omission: "...")
          return "" if s.nil?
          str = s.to_s
          return str if str.length <= length
          cutoff = length - omission.length
          cutoff = 0 if cutoff < 0
          "#{str[0, cutoff]}#{omission}"
        end
      end

      # Force html_escape to take poly so the call site exercises the
      # arg-boxing path that picked sp_box_float pre-fix.
      puts M.html_escape(42)                                   # 42
      puts M.html_escape("hello")                              # hello
      puts M.html_escape(M.truncate("short text", length: 100)) # short text
      puts M.html_escape(M.truncate("a very long text indeed", length: 10)) # a very ...

      # Float#truncate(n) must still type as float — covers the rule's
      # original purpose.
      f = 1.234
      puts f.truncate(2)                                       # 1.23
      puts f.truncate(2) + 0.001                               # 1.2309999999999999
    RUBY

    _(result).must_answer <<~'OUT'
      42
      hello
      short text
      a very ...
      1.23
      1.2309999999999999
    OUT
  end
end
