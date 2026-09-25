# frozen_string_literal: true

require "spec_helper"

describe "BigDecimal programs" do
  it "allocate refuses where ruby refuses" do
    result = zr(<<~'RUBY', files: {"bigdecimal.rb" => fixture("stdlib/bigdecimal/bigdecimal.rb")})
      # `Class#allocate` on a native class zr has no blank value for must RAISE,
      # not hand back a generic object.
      #
      # A generic object would let `BigDecimal.allocate` succeed and only fail,
      # confusingly, on the next method call or in
      # `Marshal.load(Marshal.dump(BigDecimal("1.25")))`.
      #
      # Ruby's answer is `TypeError: allocator undefined for X`, and that is now
      # zr's, message included.

      require "bigdecimal"

      # `BigDecimal` is the one class in a 52-row differential probe where zr
      # allocated and ruby refused, and it is the one that aborted.
      begin
        BigDecimal.allocate
        puts "BigDecimal\tallocated"
      rescue TypeError => e
        puts "BigDecimal\t#{e.class}: #{e.message}"
      end

      # The classes ruby also refuses, so the message shape is checked on more
      # than one row.
      [Symbol, Integer, Float, Struct, Data, Encoding, Proc, Binding, Thread].each do |k|
        begin
          k.allocate
          puts "#{k}\tallocated"
        rescue TypeError => e
          puts "#{k}\t#{e.class}: #{e.message}"
        rescue NoMethodError
          puts "#{k}\tNoMethodError"
        end
      end

      # The OTHER refusal, which is a different exception class. Ruby `undef`s
      # `allocate` outright on these five, so the name is absent rather than
      # raising: `rescue TypeError` catches nothing here.
      [Rational, Complex, MatchData, Module].each do |k|
        begin
          k.allocate
          puts "#{k}\tallocated"
        rescue TypeError => e
          puts "#{k}\tTypeError: #{e.message}"
        rescue NoMethodError => e
          puts "#{k}\t#{e.class}: #{e.message}"
        end
      end

      # A plain runtime class still allocates: the refusal is for NATIVE classes
      # with no blank value, not for everything.
      Plain = Class.new
      puts "Plain\t#{Plain.allocate.class}"
      puts "Object\t#{Object.allocate.class}"
      puts "String\t#{String.allocate.inspect}"
      puts "Array\t#{Array.allocate.inspect}"
      puts "Hash\t#{Hash.allocate.inspect}"

      # A subclass of a plain runtime class allocates through its ancestor.
      Sub = Class.new(Plain)
      puts "Sub\t#{Sub.allocate.class}"
    RUBY

    _(result).must_answer <<~'OUT'
      BigDecimal	TypeError: allocator undefined for BigDecimal
      Symbol	TypeError: allocator undefined for Symbol
      Integer	TypeError: allocator undefined for Integer
      Float	TypeError: allocator undefined for Float
      Struct	TypeError: allocator undefined for Struct
      Data	TypeError: allocator undefined for Data
      Encoding	TypeError: allocator undefined for Encoding
      Proc	TypeError: allocator undefined for Proc
      Binding	TypeError: allocator undefined for Binding
      Thread	TypeError: allocator undefined for Thread
      Rational	NoMethodError: undefined method 'allocate' for class Rational
      Complex	NoMethodError: undefined method 'allocate' for class Complex
      MatchData	NoMethodError: undefined method 'allocate' for class MatchData
      Module	NoMethodError: undefined method 'allocate' for class Module
      Plain	Plain
      Object	Object
      String	""
      Array	[]
      Hash	{}
      Sub	Sub
    OUT
  end

  it "the version and the double-precision limits carry the shape upstream gives them" do
    result = zr(<<~'RUBY')
      # bigdecimal -- the native core: construction, engineering-notation to_s,
      # exact arithmetic, division to the documented precision rule, rounding
      # modes, mode/limit state, conversions, and the error shapes.
      require "bigdecimal"

      # The SHAPE, not the number: zr vendors bigdecimal's latest upstream release
      # (vendor/ext/bigdecimal) and the oracle reads the copy ruby 4.0.7 ships.
      p BigDecimal::VERSION.match?(/\A\d+\.\d+\.\d+\z/)
      p [BigDecimal::BASE, BigDecimal.double_fig]
      p [BigDecimal::ROUND_MODE, BigDecimal.mode(BigDecimal::ROUND_MODE), BigDecimal.mode(BigDecimal::EXCEPTION_ALL), BigDecimal.limit]

    RUBY

    _(result).must_answer <<~'OUT'
      true
      [1000000000, 16]
      [256, 3, 0, 0]
    OUT
  end

  it "a BigDecimal built from a string prints in engineering notation" do
    result = zr(<<~'RUBY')
      # bigdecimal -- the native core: construction, engineering-notation to_s,
      # exact arithmetic, division to the documented precision rule, rounding
      # modes, mode/limit state, conversions, and the error shapes.
      require "bigdecimal"

      p [BigDecimal("1.5"), BigDecimal("1.5").to_s, BigDecimal("1.5").inspect]
      p [BigDecimal("-0.003"), BigDecimal("123456789.123456789"), BigDecimal("1e100")]
      p [BigDecimal("0"), BigDecimal("-0"), BigDecimal("0").to_s]
      p [BigDecimal("Infinity"), BigDecimal("-Infinity"), BigDecimal("NaN")]
      p [BigDecimal(42), BigDecimal(-7), BigDecimal(10**30)]
      p [BigDecimal(3.14), BigDecimal(3.14, 3), BigDecimal(1.5, 2), BigDecimal(1e100)]
      p BigDecimal(Rational(1, 3), 5)
      p [BigDecimal("1_000"), BigDecimal(" 1.5 "), BigDecimal(".5"), BigDecimal("1.5e3")]
      p [BigDecimal("1.5").class, BigDecimal("1.5").frozen?]

    RUBY

    _(result).must_answer <<~'OUT'
      [0.15e1, "0.15e1", "0.15e1"]
      [-0.3e-2, 0.123456789123456789e9, 0.1e101]
      [0.0, -0.0, "0.0"]
      [Infinity, -Infinity, NaN]
      [0.42e2, -0.7e1, 0.1e31]
      [0.314e1, 0.314e1, 0.15e1, 0.1e101]
      0.33333e0
      [0.1e4, 0.15e1, 0.5e0, 0.15e4]
      [BigDecimal, true]
    OUT
  end

  it "to_s takes F, E, a digit grouping and a leading sign" do
    result = zr(<<~'RUBY')
      # bigdecimal -- the native core: construction, engineering-notation to_s,
      # exact arithmetic, division to the documented precision rule, rounding
      # modes, mode/limit state, conversions, and the error shapes.
      require "bigdecimal"

      s = BigDecimal("1234.5678")
      p [s.to_s("F"), s.to_s("E"), s.to_s(3), s.to_s("+"), s.to_s("3F")]
      p BigDecimal("0.000012345").to_s("F")
      p BigDecimal("1e30").to_s("F")
      p BigDecimal("-1234.5678").to_s
      p BigDecimal("-1234.5678").to_s("F")

    RUBY

    _(result).must_answer <<~'OUT'
      ["1234.5678", "0.12345678e4", "0.123 456 78e4", "+0.12345678e4", "1 234.567 8"]
      "0.000012345"
      "1000000000000000000000000000000.0"
      "-0.12345678e4"
      "-1234.5678"
    OUT
  end

  it "addition, subtraction, multiplication and division answer exactly" do
    result = zr(<<~'RUBY')
      # bigdecimal -- the native core: construction, engineering-notation to_s,
      # exact arithmetic, division to the documented precision rule, rounding
      # modes, mode/limit state, conversions, and the error shapes.
      require "bigdecimal"

      p BigDecimal("2") + BigDecimal("3.5")
      p BigDecimal("2") * BigDecimal("3.5")
      p BigDecimal("1") / BigDecimal("3")
      p BigDecimal("10") / 3
      p BigDecimal("100") / BigDecimal("7")
      p BigDecimal("1") / BigDecimal("3.00000000000000000001")
      p BigDecimal("1.2345") / 3
      p BigDecimal(1) / 0
      p BigDecimal("1e50") + 1
      p [BigDecimal("1.23456").mult(BigDecimal("2.34567"), 4), BigDecimal("1.23456").add(BigDecimal("2.34567"), 4), BigDecimal("1.23456").sub(BigDecimal("2.34567"), 4)]
      p [BigDecimal("10").div(3), BigDecimal("10").div(3, 5), BigDecimal("10").div(3).class]
      d = BigDecimal("10").divmod(3)
      p [d, d[0].class, d[1].class]
      p [BigDecimal("-10").divmod(3), BigDecimal("-10") % 3, BigDecimal("-10").remainder(3)]
      p [BigDecimal("10.5") % 3, BigDecimal("10.5").divmod(3)]

    RUBY

    _(result).must_answer <<~'OUT'
      0.55e1
      0.7e1
      0.33333333333333333333333333333333e0
      0.33333333333333333333333333333333e1
      0.14285714285714285714285714285714e2
      0.3333333333333333333322222222222222222e0
      0.4115e0
      Infinity
      0.100000000000000000000000000000000000000000000000001e51
      [0.2896e1, 0.358e1, -0.1111e1]
      [3, 0.33333e1, Integer]
      [[3, 0.1e1], Integer, BigDecimal]
      [[-4, 0.2e1], 0.2e1, -0.1e1]
      [0.15e1, [3, 0.15e1]]
    OUT
  end

  it "a comparison answers against a BigDecimal, an Integer and a Float alike" do
    result = zr(<<~'RUBY')
      # bigdecimal -- the native core: construction, engineering-notation to_s,
      # exact arithmetic, division to the documented precision rule, rounding
      # modes, mode/limit state, conversions, and the error shapes.
      require "bigdecimal"

      p [BigDecimal("1.5") <=> 2, BigDecimal("1.5") == 1.5, BigDecimal("2") > 1, BigDecimal("1.5").eql?(1.5)]
      p [1 + BigDecimal("0.5"), 1.5 + BigDecimal("1"), BigDecimal("1") + 0.5, BigDecimal("1") * 2r]
      p BigDecimal("1.5").coerce(1)
      p [BigDecimal("NaN") == BigDecimal("NaN"), BigDecimal("NaN") <=> 1, BigDecimal("Infinity") > 10**100]
      p [BigDecimal("1.5") <=> "x", BigDecimal("1.5") == "x"]

    RUBY

    _(result).must_answer <<~'OUT'
      [-1, true, true, true]
      [0.15e1, 0.25e1, 0.15e1, 0.2e1]
      [0.1e1, 0.15e1]
      [false, nil, true]
      [nil, false]
    OUT
  end

  it "round takes a half: mode, a digit count and a negative precision" do
    result = zr(<<~'RUBY')
      # bigdecimal -- the native core: construction, engineering-notation to_s,
      # exact arithmetic, division to the documented precision rule, rounding
      # modes, mode/limit state, conversions, and the error shapes.
      require "bigdecimal"

      p [BigDecimal("2.5").round, BigDecimal("2.5").round(half: :even), BigDecimal("2.345").round(2, :down)]
      p [BigDecimal("1.23456789").round(3), BigDecimal("123.45").round(-1)]
      p [BigDecimal("3.7").floor, BigDecimal("3.2").ceil, BigDecimal("-3.7").truncate]
      p [BigDecimal("2.5").ceil(1).class, BigDecimal("2.5").ceil.class, BigDecimal("123.45").round(-1).class]
      p [BigDecimal("3.75").fix, BigDecimal("3.75").frac, BigDecimal("-1.5").abs]

    RUBY

    _(result).must_answer <<~'OUT'
      [3, 0.2e1, 0.234e1]
      [0.1235e1, 120]
      [3, 4, -3]
      [BigDecimal, Integer, Integer]
      [0.3e1, 0.75e0, 0.15e1]
    OUT
  end

  it "to_i, to_f and to_r convert, and an infinity refuses to_i" do
    result = zr(<<~'RUBY')
      # bigdecimal -- the native core: construction, engineering-notation to_s,
      # exact arithmetic, division to the documented precision rule, rounding
      # modes, mode/limit state, conversions, and the error shapes.
      require "bigdecimal"

      p [BigDecimal("1.5").to_i, BigDecimal("1.5").to_f, BigDecimal("1.5").to_r]
      begin
        BigDecimal("Infinity").to_i
      rescue FloatDomainError => e
        p [e.class, e.message]
      end
      p [BigDecimal("1.5").zero?, BigDecimal("0").zero?, BigDecimal("1.5").nonzero?, BigDecimal("0").nonzero?]
      p [BigDecimal("1.5").finite?, BigDecimal("NaN").nan?, BigDecimal("-Infinity").infinite?]
      p [BigDecimal("-1.5").sign, BigDecimal("0").sign, BigDecimal("NaN").sign, BigDecimal("Infinity").sign]
      p [BigDecimal("123.45").exponent, BigDecimal("123.45").precision, BigDecimal("123.45").n_significant_digits]
      p [BigDecimal("1e20").precision, BigDecimal("1e-20").precision, BigDecimal("100").precision]
      p BigDecimal("123.45").split
      p BigDecimal("123.45").precision_scale

    RUBY

    _(result).must_answer <<~'OUT'
      [1, 1.5, (3/2)]
      [FloatDomainError, "Computation results in 'Infinity'"]
      [false, true, 0.15e1, nil]
      [true, true, -1]
      [-2, 1, 0, 3]
      [3, 5, 5]
      [21, 20, 3]
      [1, "12345", 10, 3]
      [5, 2]
    OUT
  end

  it "BigDecimal() raises ArgumentError for a string that names no number" do
    result = zr(<<~'RUBY')
      # bigdecimal -- the native core: construction, engineering-notation to_s,
      # exact arithmetic, division to the documented precision rule, rounding
      # modes, mode/limit state, conversions, and the error shapes.
      require "bigdecimal"

      begin
        BigDecimal("bogus")
      rescue ArgumentError => e
        p [e.class, e.message]
      end
      begin
        BigDecimal(nil)
      rescue TypeError => e
        p [e.class, e.message]
      end
      begin
        BigDecimal(0.1, 20)
      rescue ArgumentError => e
        p [e.class, e.message]
      end
      begin
        BigDecimal(Rational(1, 3))
      rescue ArgumentError => e
        p [e.class, e.message]
      end
      p [BigDecimal("1.5", exception: false), BigDecimal("x", exception: false), BigDecimal(nil, exception: false)]

    RUBY

    _(result).must_answer <<~'OUT'
      [ArgumentError, "invalid value for BigDecimal(): \"bogus\""]
      [TypeError, "can't convert nil into BigDecimal"]
      [ArgumentError, "precision too large."]
      [ArgumentError, "can't omit precision for a Rational."]
      [0.15e1, nil, nil]
    OUT
  end

  it "mode and limit are process-wide, and each experiment restores what it touched" do
    result = zr(<<~'RUBY')
      # bigdecimal -- the native core: construction, engineering-notation to_s,
      # exact arithmetic, division to the documented precision rule, rounding
      # modes, mode/limit state, conversions, and the error shapes.
      require "bigdecimal"

      # Mode and limit are process-wide; each experiment restores what it touched.
      begin
        BigDecimal.mode(BigDecimal::EXCEPTION_ZERODIVIDE, true)
        BigDecimal(1) / 0
      rescue FloatDomainError => e
        p [e.class, e.message]
      ensure
        BigDecimal.mode(BigDecimal::EXCEPTION_ZERODIVIDE, false)
      end
      begin
        BigDecimal.mode(BigDecimal::EXCEPTION_NaN, true)
        BigDecimal("NaN") + 1
      rescue FloatDomainError => e
        p [e.class, e.message]
      ensure
        BigDecimal.mode(BigDecimal::EXCEPTION_NaN, false)
      end
      p BigDecimal.limit(5)
      p BigDecimal("1") / BigDecimal("3")
      p BigDecimal("2") + BigDecimal("1.111111111")
      BigDecimal.limit(0)
      p BigDecimal.save_limit {
        BigDecimal.limit(3)
        BigDecimal("1") / BigDecimal("3")
      }
      p BigDecimal.limit
      p BigDecimal.save_rounding_mode {
        BigDecimal.mode(BigDecimal::ROUND_MODE, :down)
        BigDecimal("2.789").round(1)
      }
      p BigDecimal.mode(BigDecimal::ROUND_MODE)
      p BigDecimal.mode(BigDecimal::ROUND_MODE, :half_even)
      p BigDecimal("0.25").round(1)
      BigDecimal.mode(BigDecimal::ROUND_MODE, :half_up)

    RUBY

    _(result).must_answer <<~'OUT'
      [FloatDomainError, "Divide by zero"]
      [FloatDomainError, "Computation results in 'NaN' (Not a Number)"]
      0
      0.33333e0
      0.31111e1
      0.333e0
      0
      0.27e1
      3
      7
      0.2e0
    OUT
  end

  it "interpret_loosely reads the leading number and ignores the rest" do
    result = zr(<<~'RUBY')
      # bigdecimal -- the native core: construction, engineering-notation to_s,
      # exact arithmetic, division to the documented precision rule, rounding
      # modes, mode/limit state, conversions, and the error shapes.
      require "bigdecimal"

      p BigDecimal.interpret_loosely("1.5whatever")
      p BigDecimal.interpret_loosely("junk")
    RUBY

    _(result).must_answer <<~'OUT'
      0.15e1
      0.0
    OUT
  end

  it "the gem's own Ruby half compiles, so power, sqrt, BigMath and to_d answer to the digit" do
    result = zr(<<~'RUBY', files: {"bigdecimal.rb" => fixture("stdlib/bigdecimal/bigdecimal.rb")})
      # bigdecimal's RUBY half, compiled from the vendored gem: power/sqrt (in
      # lib/bigdecimal.rb), BigMath (math.rb), and util's to_d family. All of it
      # runs over the native core -- this golden is the north-star check that the
      # real gem code compiles and answers to the digit.
      require "bigdecimal"
      require "bigdecimal/math"
      require "bigdecimal/util"

      p BigDecimal("2") ** 10
      p BigDecimal("2").power(-2)
      p BigDecimal("2").power(10, 5)
      p BigDecimal("1.5").power(3)
      p BigDecimal("3") ** -3
      p BigDecimal("2") ** 0.5
      p BigDecimal("2").power(BigDecimal("0.5"))
      p BigDecimal("0.333333333333333333333333333333333").power(2)

      p BigDecimal("2").sqrt(10)
      p BigDecimal("2").sqrt(0)
      p BigDecimal("2").sqrt(40)
      begin
        BigDecimal("2").sqrt(-1)
      rescue ArgumentError => e
        p [e.class, e.message]
      end
      begin
        BigDecimal("-1").sqrt(10)
      rescue FloatDomainError => e
        p [e.class, e.message]
      end

      p BigMath.sqrt(BigDecimal("2"), 10)
      p BigMath.exp(BigDecimal("1"), 20)
      p BigMath.exp(BigDecimal("-1"), 20)
      p BigMath.log(BigDecimal("2"), 20)
      p BigMath.log(BigDecimal("10"), 30)
      p BigMath::PI(20)
      p BigMath::E(20)
      p BigMath.sin(BigDecimal("1"), 20)
      p BigMath.cos(BigDecimal("1"), 20)
      p BigMath.atan(BigDecimal("1"), 20)
      p BigMath.cbrt(BigDecimal("27"), 10)
      p BigMath.log2(BigDecimal("8"), 10)
      p BigMath.log10(BigDecimal("1000"), 10)

      p "1.23".to_d
      p 1.5.to_d
      p 1.5.to_d(2)
      p 42.to_d
      p (10**30).to_d
      p Rational(1, 3).to_d(10)
      p "x".to_d
      p "1.5abc".to_d
      p BigDecimal("1.5").to_digits
      p BigDecimal("1234.5678").to_digits
      p 0.5.to_d(0)
    RUBY

    _(result).must_answer <<~'OUT'
      0.1024e4
      0.25e0
      0.1024e4
      0.3375e1
      0.37037037037037037037037037037037e-1
      0.14142135623730950488016887242097e1
      0.14142135623730950488016887242097e1
      0.111111111111111111111111111111110888888888888888888888888888888889e0
      0.1414213562e1
      0.1414213562373095e1
      0.141421356237309504880168872420969807857e1
      [ArgumentError, "Negative precision for sqrt"]
      [FloatDomainError, "sqrt of negative value"]
      0.1414213562e1
      0.27182818284590452354e1
      0.3678794411714423216e0
      0.69314718055994530942e0
      0.230258509299404568401799145468e1
      0.31415926535897932385e1
      0.27182818284590452354e1
      0.84147098480789650665e0
      0.5403023058681397174e0
      0.78539816339744830962e0
      0.3e1
      0.3e1
      0.3e1
      0.123e1
      0.15e1
      0.15e1
      0.42e2
      0.1e31
      0.3333333333e0
      0.0
      0.15e1
      "1.5"
      "1234.5678"
      0.5e0
    OUT
  end

  it "round with a digits argument answers a BigDecimal, and only the bare form answers an Integer" do
    result = zr(<<~'RUBY', files: {"bigdecimal.rb" => fixture("stdlib/bigdecimal/bigdecimal.rb")})
      # `BigDecimal#round` with an explicit digits argument answers a
      # BigDecimal (only the no-argument form answers Integer); zr answers
      # Integer for the digits form too. (Found by the 2026-08-24 probe
      # sweep.)
      require "bigdecimal"
      p BigDecimal("2.5").round(0, half: :even)
      p BigDecimal("2.5").round(0).class
      p BigDecimal("2.5").round.class
    RUBY

    _(result).must_answer <<~'OUT'
      0.2e1
      Integer
      Integer
    OUT
  end

  it "json parser class options" do
    result = zr(<<~'RUBY', files: {"bigdecimal.rb" => fixture("stdlib/bigdecimal/bigdecimal.rb")})
      # JSON.parse's container-class options: `object_class:`/`array_class:`
      # build the parse result out of the given classes, and `decimal_class:`
      # parses floats into it (BigDecimal is the use case). zr ignores all
      # three. (Found by the 2026-08-24 probe sweep.)
      require "json"
      require "ostruct"
      require "bigdecimal"
      p JSON.parse('{"a":1}', object_class: OpenStruct).a
      h = Class.new(Hash)
      p JSON.parse('{"a":1}', object_class: h).class == h
      a = Class.new(Array)
      p JSON.parse("[1]", array_class: a).class == a
      p JSON.parse('{"x":1.5}', decimal_class: BigDecimal)["x"].class
    RUBY

    _(result).must_answer <<~'OUT'
      1
      true
      true
      BigDecimal
    OUT
  end

  it "marshal round trips a native value" do
    result = zr(<<~'RUBY', files: {"bigdecimal.rb" => fixture("stdlib/bigdecimal/bigdecimal.rb")})
      # `Marshal.load(Marshal.dump(x))` answers an equal `x` for every native value,
      # and writes ruby's own bytes doing it.
      #
      # `Marshal` allocates before it fills, so every class that could not allocate
      # could not be loaded either -- `Date`, `DateTime` and `BigDecimal` all raised.
      # Two more looked WORSE than raising, because they looked like they had
      # worked:
      #
      #   * a `Pathname` loaded back EMPTY. zr keeps the path in its payload where
      #     ruby keeps it in an `@path` ivar, and the generic object dump writes
      #     ivars -- so it wrote none. `RPathname` now answers to the ruby name
      #     through `ivar_pairs`/`ivar_set_named`, which fixes `instance_variables`
      #     at the same time.
      #   * an `Encoding` loaded back as a STRING. `Encoding._load` handed back the
      #     name it was given rather than resolving it, so the round trip changed
      #     the class.
      #
      # `Date` needed one more thing: `#marshal_load` has to fill the RECEIVER.
      # Marshal registers the allocated object in its link table BEFORE calling
      # `marshal_load`, so answering a fresh Date would make a second reference to
      # one date load as the blank. That is why `RDate`'s six scalars moved behind
      # one lock -- the only write on any path, and uncontended.

      require "date"
      require "set"
      require "pathname"
      require "bigdecimal"

      SAMPLES = {
        "Date" => -> { Date.new(2026, 8, 29) },
        "DateTime" => -> { DateTime.new(2026, 8, 29, 1, 2, 3) },
        "Set" => -> { Set[1, 2, 3] },
        "Pathname" => -> { Pathname.new("/tmp/x") },
        "BigDecimal" => -> { BigDecimal("1.25") },
        "Regexp" => -> { /ab+c/i },
        "Rational" => -> { Rational(3, 4) },
        "Complex" => -> { Complex(1, 2) },
        "Range" => -> { (1..5) },
        "Symbol" => -> { :hello },
        "Encoding" => -> { Encoding::UTF_8 },
        "Exception" => -> { RuntimeError.new("boom") },
        "Errno" => -> { Errno::ENOENT.new("nope") },
      }

      SAMPLES.each do |name, make|
        v = make.call
        back = Marshal.load(Marshal.dump(v))
        puts "#{name}\t#{back.inspect}\t#{back == v}\t#{back.class}"
      end

      # The ivar the payload now answers to, which is what the dump reads.
      puts "pathname ivars\t#{Pathname.new('/tmp/x').instance_variables.inspect}"

      # The link table: one date referenced twice loads as ONE object, which is what
      # `marshal_load` filling in place buys.
      d = Date.new(2026, 8, 29)
      pair = Marshal.load(Marshal.dump([d, d]))
      puts "shared date\t#{pair[0]}\t#{pair[0].equal?(pair[1])}"

      # `Encoding` is interned, so the round trip has to answer the SAME object, not
      # an equal one.
      puts "encoding identity\t#{Marshal.load(Marshal.dump(Encoding::UTF_8)).equal?(Encoding::UTF_8)}"

      # The bytes, for the four whose dump shape this pass changed.
      [Date.new(2026, 8, 29), Set[1], Pathname.new("/tmp/x"), Encoding::UTF_8].each do |v|
        puts "bytes #{v.class}\t#{Marshal.dump(v).inspect}"
      end

      # A class ruby refuses to dump is still refused: a Queue owns a condvar and a
      # parked-thread count, neither of which survives a round trip.
      begin
        Marshal.dump(Queue.new)
        puts "queue\tdumped"
      rescue TypeError => e
        puts "queue\t#{e.class}: #{e.message}"
      end
    RUBY

    _(result).must_answer <<~'OUT'
      Date	#<Date: 2026-08-29 ((2461282j,0s,0n),+0s,2299161j)>	true	Date
      DateTime	#<DateTime: 2026-08-29T01:02:03+00:00 ((2461282j,3723s,0n),+0s,2299161j)>	true	DateTime
      Set	Set[1, 2, 3]	true	Set
      Pathname	#<Pathname:/tmp/x>	true	Pathname
      BigDecimal	0.125e1	true	BigDecimal
      Regexp	/ab+c/i	true	Regexp
      Rational	(3/4)	true	Rational
      Complex	(1+2i)	true	Complex
      Range	1..5	true	Range
      Symbol	:hello	true	Symbol
      Encoding	#<Encoding:UTF-8>	true	Encoding
      Exception	#<RuntimeError: boom>	true	RuntimeError
      Errno	#<Errno::ENOENT: No such file or directory - nope>	true	Errno::ENOENT
      pathname ivars	[:@path]
      shared date	2026-08-29	true
      encoding identity	true
      bytes Date	"\x04\bU:\tDate[\vi\x00i\x03b\x8E%i\x00i\x00i\x00f\f2299161"
      bytes Set	"\x04\bo:\bSet\x06:\n@hash}\x06i\x06TF"
      bytes Pathname	"\x04\bo:\rPathname\x06:\n@pathI\"\v/tmp/x\x06:\x06ET"
      bytes Encoding	"\x04\bIu:\rEncoding\nUTF-8\x06:\x06EF"
      queue	TypeError: can't dump Thread::Queue
    OUT
  end

  it "native object protocol" do
    result = zr(<<~'RUBY', files: {"bigdecimal.rb" => fixture("stdlib/bigdecimal/bigdecimal.rb")})
      # Object's universal protocol -- `===`, `==`, `!=`, `equal?`, `eql?`,
      # `frozen?`, `freeze` -- over the native handle and value kinds, promoted
      # from `tests/gaps/` on 2026-08-21.
      #
      # The rule is not one rule. A heap HANDLE (Fiber, Mutex, Queue, Thread, IO,
      # Dir, MatchData) compares by IDENTITY and carries a frozen bit of its own.
      # A by-VALUE kind (Time, `Process::Tms`, a Struct-backed row) compares
      # structurally under `==` and `===`, answers no `equal?`, and -- for most of
      # them -- no `frozen?` either. A Range is the exception that is always
      # frozen.
      #
      # `eql?` follows NEITHER, which is why the last block pins it as a table.
      # `Set`, `Time`, `Date`, `Pathname` and `BigDecimal` answer it by value;
      # `FFI::Pointer` and an `Exception` answer `==` by value and `eql?` by
      # IDENTITY. Nothing zr can see predicts the split, so
      # `Kernel#eql?`'s `owns_value_eql` allowlist is measured against the oracle
      # and this table is what keeps it honest.
      #
      # Expected output is CRuby's.
      require "socket"
      require "ostruct"

      f = Fiber.new { }
      g = Fiber.new { }
      p [f === f, f === g, f == g, f != g, f.equal?(f), f.eql?(g), f.frozen?, f.freeze.frozen?]

      m = Mutex.new
      cv = ConditionVariable.new
      q = Queue.new
      th = Thread.new { }
      th.join
      p [m === m, m === cv, m == 1, m != "x", cv === cv, cv.equal?(cv), cv.eql?(ConditionVariable.new), cv.frozen?]
      p [q === q, q == q, q.equal?(Queue.new), th === th, th == th, th.eql?(th), q.frozen?]

      r = Random.new(7)
      r2 = Random.new(7)
      r3 = Random.new(8)
      p [r === r2, r == r2, r != r3, r == r3, r.equal?(r2), r.eql?(r2), r.eql?(r), r.frozen?, r.freeze.frozen?]

      os = OpenStruct.new(a: 1)
      os2 = OpenStruct.new(a: 1)
      boxed = [os, 1, OpenStruct.new(a: 1.0)]
      p [os === os2, os == os2, os != os2, os.equal?(os2), os.equal?(os), os.eql?(os2), os == boxed[0], os.eql?(boxed[1])]
      # eql? is the member table's: class-strict per member
      p [os == boxed[2], os.eql?(boxed[2]), os != boxed[0], os === boxed[0], os.equal?(boxed[0]), os.eql?(OpenStruct.new(a: 1.0))]

      t = Time.at(5)
      t2 = Time.at(5)
      t3 = Time.at(6)
      boxed_t = [t, 1]
      p [t === t2, t === t3, t == t2, t != t3, t.eql?(t2), t.eql?(t3), t.eql?(boxed_t[0]), t.eql?(boxed_t[1]), t == boxed_t[0], t != boxed_t[1]]

      tms = Process.times
      tms2 = tms.dup
      boxed_tms = [tms, 1]
      p [tms === tms2, tms == tms2, tms != tms2, tms.eql?(tms2), tms == 1, tms == boxed_tms[0], tms.eql?(boxed_tms[0]), tms != boxed_tms[1]]

      sr = ("a".."c")
      sr2 = ("a".."c")
      sr3 = ("a".."d")
      p [sr == sr2, sr != sr3, sr != sr2, sr.eql?(sr3), sr.frozen?]

      d = Dir.new(".")
      p [d === d, d == d, d != d, d.equal?(d), d.eql?(Dir.new(".")), d == 3, d.frozen?, d.freeze.frozen?]

      ai = Addrinfo.tcp("127.0.0.1", 80)
      ai2 = Addrinfo.tcp("127.0.0.1", 80)
      p [ai === ai, ai === ai2, ai == ai2, ai != ai2, ai.equal?(ai), ai.eql?(ai2), ai.eql?("x"), ai.frozen?]

      io = File.open("/dev/null")
      st = File.stat(".")
      p [io === io, io == File.open("/dev/null"), io != io, io.equal?(io), io.frozen?, io.freeze.frozen?]
      st2 = File.stat(".")
      root = File.stat("/")
      p [st === st, st.equal?(st), st.frozen?, st.freeze.frozen?]
      # File::Stat is Comparable over the modification time: two stats of one file are ==
      p [st == st2, st === st2, st != st2, st.eql?(st2), st.equal?(st2), st == root, st === root, st == io, io == st]

      me = 1.method(:+)
      en = [1].each
      p [me.frozen?, me.freeze.frozen?, en === en, en.equal?([1].each), en.frozen?]

      e = RuntimeError.new("x")
      e2 = RuntimeError.new("x")
      e3 = RuntimeError.new("y")
      boxed_e = [e, 1]
      p [e === e, e === e2, e === e3, e == e2, e != e3, e.equal?(e2), e === boxed_e[0], e.equal?(boxed_e[1]), e.frozen?, e.freeze.frozen?]
      p [e == boxed_e[0], e != boxed_e[0], e.eql?(boxed_e[0]), e == boxed_e[1]]

      md = /a/.match("a")
      md2 = /a/.match("a")
      boxed_m = [md, 1]
      p [md === md, md === md2, md == md2, md.equal?(md), md.equal?(md2), md === boxed_m[0], md.equal?(boxed_m[0]), md.equal?(boxed_m[1])]
      p [md.frozen?, md.freeze.frozen?]

      # a Range, Array or Bignum against an operand of another family
      big = 10**20
      p [(1..2) == [1, 2], (1..2) != [1, 2], (1..2) == (1..2), (1.0..2.0) == "x", ("a".."b") == [1], (1.0..2.0) != (1.0..2.0), (1.0..2.0) != (1.0..3.0)]
      p [[1] == 1, [1] != 1, [1] == [1.0], [1] != [1.0], [1.0] == [1], [1, 2].eql?([1.0, 2.0])]
      p [big.equal?("x"), big.eql?("x"), big == "x", big != :sym, big == big]

      case f
      when g then p :other
      when f then p :self
      end

      # case/when answers the way an explicit === does
      case e2
      when e3 then p :other_message
      when e then p :same_message
      end
      case os2
      when os then p :same_members
      else p :no
      end
      case Time.at(5)
      when t then p :same_instant
      else p :no
      end
      case md2
      when md then p :same_match
      else p :no
      end
      case 5
      when f then p :no
      else p :not_a_fiber
      end

      # the standard streams are static storage: freeze flips a flag of their own
      p $stderr.frozen?
      $stderr.freeze
      p $stderr.frozen?

      # a nil handle slot answers nil's frozen?
      class Holder
        attr_reader :io
        def open!
          @io = File.open("/dev/null")
        end
      end
      h = Holder.new
      p [h.io, h.io.frozen?]
      h.open!
      p h.io.frozen?

      # the receiver is evaluated once, first, whatever the operand holds
      def noisy
        puts "receiver"
        Dir.new(".")
      end
      mixed = [1, "s"]
      p(noisy == mixed[0])
      p(noisy === mixed[1])
      p(noisy != mixed[0])

      # The `eql?` table. A class here either owns a value `eql?` or inherits
      # Object's identity one; measured, because the split follows no rule.
      require "set"
      require "date"
      require "pathname"
      require "bigdecimal"
      require "ffi"
      def eql_row(label, a, b)
        print "#{label}: "
        p [a == b, a.eql?(b), a.equal?(b)]
      end
      eql_row("Set", Set[1, 2], Set[2, 1])
      eql_row("Time", Time.at(5), Time.at(5))
      eql_row("Date", Date.new(2020, 1, 1), Date.new(2020, 1, 1))
      eql_row("DateTime", DateTime.new(2020, 1, 1), DateTime.new(2020, 1, 1))
      eql_row("Pathname", Pathname.new("/a"), Pathname.new("/a"))
      eql_row("BigDecimal", BigDecimal("1.5"), BigDecimal("1.5"))
      eql_row("Encoding", Encoding::UTF_8, Encoding::UTF_8)
      eql_row("Range", (1..2), (1..2))
      eql_row("ArithSeq", 1.step(5, 2), 1.step(5, 2))
      eql_row("Rational", Rational(1, 2), Rational(1, 2))
      eql_row("Regexp", /a/, /a/)
      eql_row("Pointer", FFI::Pointer.new(8), FFI::Pointer.new(8))
      eql_row("Exception", ArgumentError.new("x"), ArgumentError.new("x"))
      eql_row("Lazy", [1].lazy, [1].lazy)
      eql_row("Enumerator", [1].each, [1].each)
      tms = Process.times
      eql_row("Tms", tms, tms.dup)
    RUBY

    _(result).must_answer <<~'OUT'
      [true, false, false, true, true, false, false, true]
      [true, false, false, true, true, true, false, false]
      [true, true, false, true, true, true, false]
      [true, true, true, false, false, false, true, false, true]
      [true, true, false, false, true, true, true, false]
      [true, false, false, true, true, false]
      [true, false, true, true, true, false, true, false, true, true]
      [true, true, false, true, false, true, true, true]
      [true, true, false, false, true]
      [true, true, false, true, false, false, false, true]
      [true, false, false, true, true, false, false, false]
      [true, false, false, true, false, true]
      [true, true, false, true]
      [true, true, false, false, false, false, false, false, false]
      [false, true, true, false, false]
      [true, true, false, true, true, false, true, false, false, true]
      [true, false, true, false]
      [true, true, true, true, false, true, true, false]
      [false, true]
      [false, true, true, false, false, false, true]
      [false, true, true, false, true, false]
      [false, false, false, true, true]
      :self
      :same_message
      :same_members
      :same_instant
      :same_match
      :not_a_fiber
      false
      true
      [nil, true]
      false
      receiver
      false
      receiver
      false
      receiver
      true
      Set: [true, true, false]
      Time: [true, true, false]
      Date: [true, true, false]
      DateTime: [true, true, false]
      Pathname: [true, true, false]
      BigDecimal: [true, true, false]
      Encoding: [true, true, true]
      Range: [true, true, false]
      ArithSeq: [true, true, false]
      Rational: [true, true, false]
      Regexp: [true, true, false]
      Pointer: [true, false, false]
      Exception: [true, false, false]
      Lazy: [false, false, false]
      Enumerator: [false, false, false]
      Tms: [true, true, false]
    OUT
  end

  it "to_s reads a sign flag before F, and round with a mode keeps a BigDecimal" do
    result = zr(<<~'RUBY')
      require "bigdecimal"
      x = BigDecimal("12345.678")
      p x.to_s("+F"), x.to_s(" F"), x.to_s("+3F"), x.to_s("E"), x.to_s(3)
      p x.to_s.encoding, x.inspect.encoding
      p BigDecimal("2.5").round(0, :half_even), BigDecimal("2.5").round, BigDecimal("2.5").round(half: :even)
    RUBY

    _(result).must_answer <<~'OUT'
      "+12345.678"
      " 12345.678"
      "+12 345.678"
      "0.12345678e5"
      "0.123 456 78e5"
      #<Encoding:US-ASCII>
      #<Encoding:BINARY (ASCII-8BIT)>
      0.2e1
      3
      0.2e1
    OUT
  end
end
