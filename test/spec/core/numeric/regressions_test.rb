# frozen_string_literal: true

require "spec_helper"

describe "Numeric: regressions" do
  it "integer bit index" do
    result = zr(<<~'RUBY')
      # `Integer#[N]` returns bit N (0-indexed from the LSB) of the
      # integer. `data[5]` was previously falling through to the
      # unknown-method 0-fallback. Lower as `((rc >> idx) & 1)`.

      # Static index
      n = 0b10110100
      puts n[0]    # 0
      puts n[1]    # 0
      puts n[2]    # 1
      puts n[3]    # 0
      puts n[4]    # 1
      puts n[5]    # 1
      puts n[6]    # 0
      puts n[7]    # 1

      # Dynamic index
      i = 0
      while i < 4
        puts n[i]
        i += 1
      end
      # 0 0 1 0
    RUBY

    _(result).must_answer <<~'OUT'
      0
      0
      1
      0
      1
      1
      0
      1
      0
      0
      1
      0
    OUT
  end

  it "allbits? is true only when every bit in the mask is set" do
    result = zr(<<~'RUBY')
      # Basic, subset, zero mask, single bit, large value and a negative
      # receiver -- the same matrix nobits? and anybits? are held to.

      puts 255.allbits?(255)
      puts 255.allbits?(128)
      puts 0.allbits?(0)
      puts 42.allbits?(0)
      puts 5.allbits?(6)
      puts 8.allbits?(3)
      puts 4.allbits?(4)
      puts 4.allbits?(2)
      puts 0xFFFF.allbits?(0xFF00)
      puts((-1).allbits?(255))
      puts 0.allbits?(1)
    RUBY

    _(result).must_answer <<~'OUT'
      true
      true
      true
      true
      false
      false
      true
      false
      true
      true
      false
    OUT
  end

  it "nobits? is true only when no bit in the mask is set" do
    result = zr(<<~'RUBY')
      puts 256.nobits?(1)
      puts 256.nobits?(255)
      puts 8.nobits?(4)
      puts 255.nobits?(1)
      puts 6.nobits?(2)
      puts 0.nobits?(0)
      puts 42.nobits?(0)
      puts 4.nobits?(2)
      puts 4.nobits?(4)
      puts((-1).nobits?(1))
      puts((-4).nobits?(2))
      puts 0xFF00.nobits?(0x00FF)
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
      false
      false
      true
      true
    OUT
  end

  it "anybits? is true when at least one bit in the mask is set" do
    result = zr(<<~'RUBY')
      puts 255.anybits?(128)
      puts 255.anybits?(1)
      puts 0.anybits?(1)
      puts 16.anybits?(8)
      puts 4.anybits?(2)
      puts 0.anybits?(0)
      puts 42.anybits?(0)
      puts 6.anybits?(4)
      puts 6.anybits?(2)
      puts((-1).anybits?(1))
      puts((-4).anybits?(4))
      puts 0xFF00.anybits?(0x0100)
    RUBY

    _(result).must_answer <<~'OUT'
      true
      true
      false
      false
      false
      false
      false
      true
      true
      true
      true
      true
    OUT
  end

  it "integer ceildiv" do
    result = zr(<<~'RUBY')
      # basic
      puts 7.ceildiv(2)
      puts 10.ceildiv(5)
      puts 11.ceildiv(5)

      # exact division
      puts 6.ceildiv(3)

      # zero dividend
      puts 0.ceildiv(3)

      # one
      puts 1.ceildiv(1)

      # negative
      puts((-7).ceildiv(2))
      puts 7.ceildiv(-2)
      puts((-7).ceildiv(-2))

      # large
      puts 1000001.ceildiv(1000)
    RUBY

    _(result).must_answer <<~'OUT'
      4
      2
      3
      2
      0
      1
      -3
      -3
      4
      1001
    OUT
  end

  it "integer divmod" do
    result = zr(<<~'RUBY')
      p 100.divmod(7)
      # Float#divmod returns [Integer, Float] — exercises the
      # tuple:int,float inspect arm.
      p 5.5.divmod(2)
    RUBY

    _(result).must_answer "[14, 2]\n[2, 1.5]\n"
  end

  it "integer lcm" do
    result = zr(<<~'RUBY')
      # basic
      puts 6.lcm(4)
      puts 4.lcm(6)

      # zero
      puts 0.lcm(5)
      puts 5.lcm(0)
      puts 0.lcm(0)

      # negative
      puts((-4).lcm(6))
      puts 6.lcm(-4)
      puts((-3).lcm(-7))

      # same
      puts 7.lcm(7)

      # one
      puts 1.lcm(5)
      puts 5.lcm(1)

      # coprime
      puts 8.lcm(9)

      # divisor — one divides the other
      puts 3.lcm(9)
      puts 9.lcm(3)

      # primes
      puts 7.lcm(13)

      # one with one
      puts 1.lcm(1)

      # large
      puts 12345.lcm(67890)
    RUBY

    _(result).must_answer <<~'OUT'
      12
      12
      0
      0
      0
      12
      12
      21
      7
      5
      5
      72
      9
      9
      91
      1
      55873470
    OUT
  end

  it "integer powmod" do
    result = zr(<<~'RUBY')
      # basic
      puts 2.pow(10, 1000)
      puts 5.pow(2, 3)
      puts 3.pow(3, 8)

      # exp zero
      puts 2.pow(0, 5)
      puts 0.pow(0, 5)

      # mod one — always zero
      puts 2.pow(100, 1)
      puts 999.pow(999, 1)

      # negative base
      puts((-2).pow(3, 5))
      puts((-3).pow(2, 7))

      # large exponent
      puts 2.pow(20, 1000000)
      puts 7.pow(15, 100)

      # base larger than mod
      puts 100.pow(3, 7)

      # base zero
      puts 0.pow(5, 3)

      # base one
      puts 1.pow(999, 7)

      # mod two
      puts 7.pow(3, 2)

      # exp one
      puts 5.pow(1, 3)

      # negative mod
      puts 2.pow(2, -3)
      puts 2.pow(3, -5)

      # one-arg pow
      puts 2.pow(10)
      puts 3.pow(3)
    RUBY

    _(result).must_answer <<~'OUT'
      24
      1
      3
      1
      1
      0
      0
      2
      2
      48576
      43
      1
      0
      1
      1
      2
      -2
      -2
      1024
      27
    OUT
  end

  it "integer pred" do
    result = zr(<<~'RUBY')
      # basic
      puts 5.pred
      puts 1.pred
      puts 0.pred

      # negative
      puts((-1).pred)
      puts((-100).pred)

      # large
      puts 1000000.pred
    RUBY

    _(result).must_answer <<~'OUT'
      4
      0
      -1
      -2
      -101
      999999
    OUT
  end

  it "integer sqrt" do
    result = zr(<<~'RUBY')
      p Integer.sqrt(0)
      p Integer.sqrt(1)
      p Integer.sqrt(16)
      p Integer.sqrt(99)
      p Integer.sqrt(100)
      p Integer.sqrt(101)
      p Integer.sqrt(1_000_000)

      # Large-integer precision — beyond the 53-bit double mantissa.
      # A double-based sqrt would round and produce off-by-one results
      # for values above ~2^53; the Newton-method helper stays exact.
      p Integer.sqrt(2**53)
      p Integer.sqrt(2**53 + 1)
      p Integer.sqrt(2**60)
      p Integer.sqrt(2**62 - 1)
    RUBY

    _(result).must_answer <<~'OUT'
      0
      1
      4
      9
      10
      10
      1000
      94906265
      94906265
      1073741824
      2147483647
    OUT
  end

  it "catch" do
    result = zr(<<~'RUBY')
      # Test catch/throw

      result = catch(:done) do
        throw :done, 42
        999  # unreachable
      end
      puts result  # 42

      # catch without throw returns block value
      result2 = catch(:nope) do
        100
      end
      puts result2  # 100

      # Nested catch (same type)
      result3 = catch(:outer) do
        catch(:inner) do
          throw :outer, 77
        end
        0
      end
      puts result3  # 77

      puts "done"
    RUBY

    _(result).must_answer <<~'OUT'
      42
      100
      77
      done
    OUT
  end

  it "class threeq" do
    result = zr(<<~'RUBY')
      # Class#=== — case-when membership for primitive type names.
      # Compile-time decided based on the arg's inferred type.
      p Integer === 5
      p Integer === 5.0
      p Integer === "x"
      p Numeric === 5
      p Numeric === 5.0
      p Comparable === 5
      p Float === 5.0
      p Float === 5
      p String === "hi"
      p String === :hi
      p Symbol === :hi
      p Symbol === "hi"
      p Array === [1, 2, 3]
      p Array === "x"
      p Range === (1..3)
      p Range === 5
      p TrueClass === true
      p FalseClass === false
      p NilClass === nil
      p Object === 5
      p Object === "x"

      # More true/false coverage for the remaining primitive arms.
      p Hash === {a: 1}
      p Hash === [1, 2, 3]
      p Numeric === "5"
      p Numeric === :sym
      p Comparable === 1.5
      p Comparable === [1, 2]
      p TrueClass === false
      p FalseClass === true
      p NilClass === 0
      p NilClass === false

      # Kernel and BasicObject — Ruby's universal ancestors. Every receiver
      # is in the Object hierarchy, so `=== anything` is true.
      p Kernel === 5
      p Kernel === "x"
      p Kernel === nil
      p BasicObject === 5
      p BasicObject === [1]
    RUBY

    _(result).must_answer <<~'OUT'
      true
      false
      false
      true
      true
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
      false
      true
      true
      true
      true
      true
      true
      false
      false
      false
      true
      false
      false
      false
      false
      false
      true
      true
      true
      true
      true
    OUT
  end

  it "do while post test loop" do
    result = zr(<<~'RUBY')
      # Prism's PM_LOOP_FLAGS_BEGIN_MODIFIER (= 4, bit 2) marks
      # `begin..end while cond` / `begin..end until cond` as post-test
      # loops — body runs at least once. Spinel was treating them as
      # plain pre-test `while`, so a body that should have run once but
      # whose condition was false on entry never ran at all.

      ran = 0
      begin
        ran += 1
      end while ran > 99      # cond false on entry → post-test runs body once
      puts ran                # 1

      ran2 = 0
      begin
        ran2 += 1
      end until ran2 < 99     # cond true on entry → post-test runs body once
      puts ran2               # 1

      # Sanity: bare pre-test `while` with cond false on entry runs zero
      # times.
      ran3 = 0
      while ran3 > 99 do ran3 += 1 end
      puts ran3               # 0
    RUBY

    _(result).must_answer <<~'OUT'
      1
      1
      0
    OUT
  end

  it "fiber" do
    result = zr(<<~'RUBY')
      # Test Fiber (cooperative concurrency)

      # Basic yield/resume
      f = Fiber.new {
        Fiber.yield(10)
        Fiber.yield(20)
        30
      }
      puts f.resume  # 10
      puts f.resume  # 20
      puts f.resume  # 30

      # Value passing
      f2 = Fiber.new { |first|
        second = Fiber.yield(first * 2)
        second * 3
      }
      puts f2.resume(5)   # 10
      puts f2.resume(7)   # 21

      # String passing
      f3 = Fiber.new {
        Fiber.yield("hello")
        Fiber.yield("world")
        "done"
      }
      puts f3.resume  # hello
      puts f3.resume  # world
      puts f3.resume  # done

      # alive?
      f4 = Fiber.new {
        Fiber.yield(1)
        2
      }
      puts f4.alive?   # true
      f4.resume
      puts f4.alive?   # true
      f4.resume
      puts f4.alive?   # false

      # Fiber.current
      cur = Fiber.current
      puts cur.alive?  # true

      # FiberError on dead fiber
      f5 = Fiber.new { 42 }
      f5.resume
      begin
        f5.resume
        puts "ERROR"
      rescue FiberError
        puts "caught FiberError"
      end
    RUBY

    _(result).must_answer <<~'OUT'
      10
      20
      30
      10
      21
      hello
      world
      done
      true
      true
      false
      true
      caught FiberError
    OUT
  end

  it "reduces a float array to its min, max, sum, first and last" do
    result = zr(<<~'RUBY')
      arr = [1.5, 2.5, 0.5, 3.5]
      puts arr.min     # 0.5
      puts arr.max     # 3.5
      puts arr.first   # 1.5
      puts arr.last    # 3.5

      neg = [-1.5, -3.25, 2.75]
      puts neg.min     # -3.25
      puts neg.max     # 2.75

      one = [4.5]
      puts one.min     # 4.5
      puts one.max     # 4.5

      # Sum with non-integer-valued result (avoids the stale-type truncation
      # that would print "4" instead of "4.5").
      sum = [1.5, 2.5, 0.5]
      puts sum.sum     # 4.5
    RUBY

    _(result).must_answer <<~'OUT'
      0.5
      3.5
      1.5
      3.5
      -3.25
      2.75
      4.5
      4.5
      4.5
    OUT
  end

  it "slices a float array by a range and by start and length" do
    result = zr(<<~'RUBY')
      a = [1.5, 2.5, 3.5, 4.5, 5.5]
      b = a[1..3]
      puts b.length    # 3
      puts b[0]        # 2.5
      puts b[1]        # 3.5
      puts b[2]        # 4.5
      c = a[1, 2]
      puts c.length    # 2
      puts c[0]        # 2.5
      puts c[1]        # 3.5
      d = a[-2, 2]
      puts d.length    # 2
      puts d[0]        # 4.5
      puts d[1]        # 5.5
      e = a[2, 100]
      puts e.length    # 3 (clamped)
      puts e[0]        # 3.5
      puts e[2]        # 5.5
      puts a[0]        # 1.5
      puts a[-1]       # 5.5
      puts a[1..3].sum # 10.5
    RUBY

    _(result).must_answer <<~'OUT'
      3
      2.5
      3.5
      4.5
      2
      2.5
      3.5
      2
      4.5
      5.5
      3
      3.5
      5.5
      1.5
      5.5
      10.5
    OUT
  end

  it "shift takes the front of a float array until it is empty" do
    result = zr(<<~'RUBY')
      arr = [1.5, 2.5, 3.5, 4.5]
      puts arr.shift  # 1.5
      puts arr.length # 3
      puts arr[0]     # 2.5
      while arr.length > 0
        puts arr.shift
      end
      puts arr.length # 0
    RUBY

    _(result).must_answer <<~'OUT'
      1.5
      3
      2.5
      2.5
      3.5
      4.5
      0
    OUT
  end

  it "ceil, floor, round and truncate take a number of decimal places" do
    result = zr(<<~'RUBY')
      puts 3.14159.round(2)
      puts 3.14159.round(4)
      puts 1.5.round(1)
      puts 2.5.round(1)
      puts 3.14159.ceil(2)
      puts 3.14159.ceil(4)
      puts 1.001.ceil(2)
      puts 3.14159.floor(2)
      puts 3.14159.floor(4)
      puts 1.999.floor(2)
      puts 3.14159.truncate(2)
      puts 3.14159.truncate(4)
      puts (-1.567).truncate(2)
      puts 3.14.round
      puts 3.14.ceil
      puts 3.14.floor
      puts 3.14.truncate
      # Negative precision: bool-compare for type-stable output across
      # CRuby's Integer-return rule vs. Spinel's uniform Float inference.
      puts 12345.6789.floor(-2) == 12300
      puts 12345.6789.ceil(-2) == 12400
      puts 12345.6789.round(-1) == 12350
      puts 12345.6789.truncate(-2) == 12300
      puts (-12345.6789).floor(-2) == -12400
      puts (-12345.6789).ceil(-2) == -12300
    RUBY

    _(result).must_answer <<~'OUT'
      3.14
      3.1416
      1.5
      2.5
      3.15
      3.1416
      1.01
      3.14
      3.1415
      1.99
      3.14
      3.1415
      -1.56
      3
      4
      3
      3
      true
      true
      true
      true
      true
      true
    OUT
  end

  it "prints a float as the shortest decimal that reads back as itself" do
    result = zr(<<~'RUBY')
      # Shortest decimal that round-trips; fixed-point inside CRuby's
      # [-4, 15] decimal-exponent window, scientific (`d.ddde+NN`)
      # outside.
      puts 1.0
      puts 100.0
      puts(-3.25)
      puts 1234567890.0
      puts 1234567890.5
      puts 0.1
      puts 0.3
      puts 0.30000000000000004
      puts 0.0001
      puts 0.00001
      puts 1.5e14
      puts 1.0e15
      puts 9.99e15
      puts 1.0e16
      puts 1.0e100
      puts(-0.0)
      puts Float::INFINITY
      puts(-Float::INFINITY)
      puts Float::NAN
      p 1.0
      p 1234567890.5
      p 1.0e16
      p(-0.0)
    RUBY

    _(result).must_answer <<~'OUT'
      1.0
      100.0
      -3.25
      1234567890.0
      1234567890.5
      0.1
      0.3
      0.30000000000000004
      0.0001
      1.0e-05
      150000000000000.0
      1.0e+15
      9.99e+15
      1.0e+16
      1.0e+100
      -0.0
      Infinity
      -Infinity
      NaN
      1.0
      1234567890.5
      1.0e+16
      -0.0
    OUT
  end

  it "Kernel#Float coerces a string, an integer and a float" do
    result = zr(<<~'RUBY')
      puts Float("3.14")        # 3.14
      puts Float("0")           # 0.0
      puts Float("-2.5")        # -2.5
      puts Float(1)             # 1.0
      puts Float(42)            # 42.0
      puts Float(2.71)          # 2.71
      puts Float("1e2")         # 100.0
    RUBY

    _(result).must_answer <<~'OUT'
      3.14
      0.0
      -2.5
      1.0
      42.0
      2.71
      100.0
    OUT
  end

  it "math" do
    result = zr(<<~'RUBY')
      # Math module methods. All should return Float.

      # Trig (in radians)
      puts (Math.sin(0.0) * 1000).to_i        # 0
      puts (Math.cos(0.0) * 1000).to_i        # 1000
      puts (Math.tan(0.0) * 1000).to_i        # 0
      puts (Math.sin(0.5) * 1000).to_i        # 479
      puts (Math.cos(0.5) * 1000).to_i        # 877
      puts (Math.tan(0.5) * 1000).to_i        # 546

      # Inverse trig
      puts (Math.atan(1.0) * 1000).to_i       # 785
      puts (Math.atan2(1.0, 1.0) * 1000).to_i # 785
      puts (Math.asin(1.0) * 1000).to_i       # 1570
      puts (Math.acos(0.0) * 1000).to_i       # 1570

      # Powers / logs
      puts (Math.sqrt(2.0) * 1000).to_i       # 1414
      puts (Math.log(1.0) * 1000).to_i        # 0
      puts (Math.log2(8.0) * 1000).to_i       # 3000
      puts (Math.log10(100.0) * 1000).to_i    # 2000
      puts (Math.exp(0.0) * 1000).to_i        # 1000

      # Float-typed result (would print "1" / "0" if inferred as int).
      # Use the *1000+to_i idiom to dodge precision-formatting differences
      # between Spinel's float-puts and CRuby's.
      puts (Math.log2(3.0) * 1000).to_i       # 1584
      puts (Math.log10(3.0) * 1000).to_i      # 477

      # Hypot
      puts (Math.hypot(3.0, 4.0) * 1000).to_i # 5000

      # Hyperbolic
      puts (Math.tanh(0.5) * 1000).to_i       # 462
      puts (Math.tanh(1.0) * 1000).to_i       # 761
      puts (Math.sinh(1.0) * 1000).to_i       # 1175
      puts (Math.cosh(1.0) * 1000).to_i       # 1543

      # Inverse hyperbolic
      puts (Math.atanh(0.5) * 1000).to_i      # 549
      puts (Math.asinh(1.0) * 1000).to_i      # 881
      puts (Math.acosh(2.0) * 1000).to_i      # 1316

      # PI
      puts (Math::PI * 1000).to_i             # 3141
    RUBY

    _(result).must_answer <<~'OUT'
      0
      1000
      0
      479
      877
      546
      785
      785
      1570
      1570
      1414
      0
      3000
      2000
      1000
      1584
      477
      5000
      462
      761
      1175
      1543
      549
      881
      1316
      3141
    OUT
  end

  it "misc2" do
    result = zr(<<~'RUBY')
      # Test format/sprintf
      puts format("%d:%02d", 5, 3)
      puts sprintf("hello %s %d", "world", 42)

      # Test inline rescue as expression
      x = raise("oops") rescue 42
      puts x

      # Test symbol key hash (string values -> sp_RbHash)
      h = {running: "green", waiting: "yellow"}
      puts h[:running]
      puts h[:waiting]

      # Test symbol key hash with integer values (-> sp_StrIntHash)
      h2 = {a: 1, b: 2}
      puts h2[:a]
      puts h2[:b]
    RUBY

    _(result).must_answer <<~'OUT'
      5:03
      hello world 42
      42
      green
      yellow
      1
      2
    OUT
  end

  it "the arithmetic, rounding, predicate and conversion rows each answer" do
    result = zr(<<~'RUBY')
      # Test numeric methods and conversions

      puts (-5).abs     # 5
      puts 3.14.to_i    # 3
      puts 3.14.ceil    # 4
      puts 3.14.floor   # 3
      puts 3.14.round   # 3
      puts 3.75.round   # 4

      # Integer methods
      puts 7.even?      # false
      puts 8.even?      # true
      puts 7.odd?       # true
      puts 10.zero?     # false
      puts 0.zero?      # true

      # Numeric abs
      puts (-3.14).abs  # 3.14

      # Power
      puts 2 ** 10      # 1024
    RUBY

    _(result).must_answer <<~'OUT'
      5
      3
      4
      3
      3
      4
      false
      true
      true
      false
      true
      3.14
      1024
    OUT
  end

  it "safe nav" do
    result = zr(<<~'RUBY')
      # Test safe navigation operator &.

      s = "hello"
      puts s&.length    # 5
      puts s&.upcase    # HELLO

      arr = Array.new
      arr.push(10)
      arr.push(20)
      puts arr&.length  # 2

      # Chain
      puts "world"&.upcase&.length  # 5

      puts "done"
    RUBY

    _(result).must_answer <<~'OUT'
      5
      HELLO
      2
      5
      done
    OUT
  end

  it "shuffle" do
    result = zr(<<~'RUBY')
      arr = [1, 2, 3, 4, 5]
      s = arr.shuffle
      puts s.length
      puts s.sort.join(",")
      puts arr.join(",")

      words = ["foo", "bar", "baz", "qux"]
      s2 = words.shuffle
      puts s2.length
      puts s2.include?("foo")
      puts s2.include?("bar")
      puts s2.include?("baz")
      puts s2.include?("qux")
      puts words.join(",")

      nums = [10, 20, 30]
      nums.shuffle!
      puts nums.length
      puts nums.sort.join(",")

      # FloatArray
      floats = [1.5, 2.5, 3.5, 4.5]
      fs = floats.shuffle
      puts fs.length            # 4
      puts floats.length        # 4 (original unchanged)
      floats.shuffle!
      puts floats.length        # 4 (in-place, length stable)

      # Empty / single-element edge cases stay stable.
      empty = []
      empty.shuffle!
      puts empty.length         # 0
      one = [42]
      one.shuffle!
      puts one[0]               # 42
    RUBY

    _(result).must_answer <<~'OUT'
      5
      1,2,3,4,5
      1,2,3,4,5
      4
      true
      true
      true
      true
      foo,bar,baz,qux
      3
      10,20,30
      4
      4
      4
      0
      42
    OUT
  end

  it "float array sort" do
    result = zr(<<~'RUBY')
      a = [3.5, 1.25, 2.0, 0.75, 4.125]
      b = a.sort
      puts b.length

      i = 0
      while i < b.length
        puts b[i]
        i = i + 1
      end

      # Source unchanged.
      puts a[0]
      puts a[1]
    RUBY

    _(result).must_answer <<~'OUT'
      5
      0.75
      1.25
      2.0
      3.5
      4.125
      3.5
      1.25
    OUT
  end

  it "integer literal large" do
    result = zr(<<~'RUBY')
      mod = 4_294_967_296
      puts mod
      puts 16_777_621 % mod

      hash = 2_166_136_261
      data = "spinel"
      i = 0
      while i < data.length
        hash = (hash * 16_777_619 + data.getbyte(i)) % mod
        i += 1
      end

      puts hash
    RUBY

    _(result).must_answer <<~'OUT'
      4294967296
      16777621
      3601407474
    OUT
  end

  it "program name gvar" do
    result = zr(<<~'RUBY')
      # `$PROGRAM_NAME` / `$0` are Ruby's standard aliases.
      puts $PROGRAM_NAME.length > 0
      puts $0.length > 0
    RUBY

    _(result).must_answer "true\ntrue\n"
  end

  it "multi write as expression" do
    result = zr(<<~'RUBY')
      # #554. `(a, b = 10, 11)` used as an expression returns the RHS array.
      p( (a, b = 10, 11)[1] )
      p a
      p b

      arr = (x, y = "hi", "lo")
      p arr[0]
      p arr[1]
      p x
      p y
    RUBY

    _(result).must_answer <<~'OUT'
      11
      10
      11
      "hi"
      "lo"
      "hi"
      "lo"
    OUT
  end

  it "range predicate block" do
    result = zr(<<~'RUBY')
      # (a..b).any?/all?/none?/one? { |i| ... }
      puts (0..5).all? {|i| i >= 0 }      # true
      puts (0..5).all? {|i| i < 3 }       # false
      puts (0..3).all? {|i| (0..3).cover?(i) }  # true

      puts (0..5).any? {|i| i == 3 }      # true
      puts (0..5).any? {|i| i > 100 }     # false

      puts (0..5).none? {|i| i > 100 }    # true
      puts (0..5).none? {|i| i == 3 }     # false

      puts (0..5).one? {|i| i == 3 }      # true
      puts (0..5).one? {|i| i >= 4 }      # false
      puts (0..5).one? {|i| i > 100 }     # false
    RUBY

    _(result).must_answer <<~'OUT'
      true
      false
      true
      true
      false
      true
      false
      true
      false
      false
    OUT
  end

  it "fetch nil default distinguishes zero" do
    result = zr(<<~'RUBY')
      # #682: hash.fetch(k, nil).nil? distinguishes missing-key from a 0 value.
      h0 = {k: 0}
      v0 = h0.fetch(:k, nil)
      puts v0.nil? ? "missing" : "found-0"

      hm = {}
      vm = hm.fetch(:k, nil)
      puts vm.nil? ? "missing" : "found-m"

      h1 = {k: 42}
      v1 = h1.fetch(:k, nil)
      puts v1.nil? ? "missing" : "found-#{v1}"

      hs = {"a" => 0}
      vs = hs.fetch("a", nil)
      puts vs.nil? ? "missing-str" : "found-str-#{vs}"

      hsm = {}
      vsm = hsm.fetch("a", nil)
      puts vsm.nil? ? "missing-str-key" : "found-str-bad"
    RUBY

    _(result).must_answer <<~'OUT'
      found-0
      missing
      found-42
      found-str-0
      missing-str-key
    OUT
  end

  it "stdlib" do
    result = zr(<<~'RUBY')
      # Array#join
      arr = (1..5).to_a
      puts arr.join(", ")

      # Array#uniq
      nums = (1..5).to_a
      nums.push(3)
      nums.push(1)
      uniq = nums.uniq
      puts uniq.length

      # srand/rand
      srand(0)
      r = rand(100)
      puts r >= 0

      # ARGV.length
      puts ARGV.length

      puts "done"
    RUBY

    _(result).must_answer <<~'OUT'
      1, 2, 3, 4, 5
      5
      true
      0
      done
    OUT
  end

  it "math fn parity" do
    result = zr(<<~'RUBY')
      # End-to-end exercise of every recognized Math fn.
      puts Math.sqrt(16.0).to_i.to_s
      puts Math.cos(0.0).to_i.to_s
      puts Math.sin(0.0).to_i.to_s
      puts Math.tan(0.0).to_i.to_s
      puts Math.acos(1.0).to_i.to_s
      puts Math.asin(0.0).to_i.to_s
      puts Math.atan(0.0).to_i.to_s
      puts Math.sinh(0.0).to_i.to_s
      puts Math.cosh(0.0).to_i.to_s
      puts Math.tanh(0.0).to_i.to_s
      puts Math.asinh(0.0).to_i.to_s
      puts Math.acosh(1.0).to_i.to_s
      puts Math.atanh(0.0).to_i.to_s
      puts Math.log(1.0).to_i.to_s
      puts Math.log2(1.0).to_i.to_s
      puts Math.log10(1.0).to_i.to_s
      puts Math.exp(0.0).to_i.to_s
      puts Math.atan2(0.0, 1.0).to_i.to_s
      puts Math.hypot(3.0, 4.0).to_i.to_s
    RUBY

    _(result).must_answer <<~'OUT'
      4
      1
      0
      0
      0
      0
      0
      0
      1
      0
      0
      0
      0
      0
      0
      0
      1
      0
      5
    OUT
  end

  it "float infinite nil" do
    result = zr(<<~'RUBY')
      # Float#infinite?: nil for a finite value, -1 / +1 for -Inf / +Inf.
      p 0.0.infinite?
      p 3.14.infinite?
      p (1.0 / 0.0).infinite?
      p (-1.0 / 0.0).infinite?
      puts((1.0 / 0.0).infinite? ? "inf" : "finite")
      puts(2.5.infinite? ? "inf" : "finite")
    RUBY

    _(result).must_answer <<~'OUT'
      nil
      nil
      1
      -1
      inf
      finite
    OUT
  end

  it "float next prev" do
    result = zr(<<~'RUBY')
      # Float#next_float / prev_float — adjacent IEEE 754 representable
      # values via libm's nextafter.
      puts 1.0.next_float
      puts 1.0.prev_float
      puts 0.0.next_float
      puts 0.0.prev_float
    RUBY

    _(result).must_answer <<~'OUT'
      1.0000000000000002
      0.9999999999999999
      5.0e-324
      -5.0e-324
    OUT
  end

  it "float zero p" do
    result = zr(<<~'RUBY')
      # Float#zero?: true only for 0.0 / -0.0.
      p 0.0.zero?
      p(-0.0.zero?)
      p 3.5.zero?
      p (1.0 - 1.0).zero?
      puts(0.0.zero? ? "z" : "nz")
    RUBY

    _(result).must_answer <<~'OUT'
      true
      true
      false
      true
      z
    OUT
  end

  it "int step expr block" do
    result = zr(<<~'RUBY')
      # Integer#step with a block in expression position — CRuby returns
      # the receiver, not 0. Previously fell through to the unresolved-
      # call path and emitted 0 (and analyze inferred int_array, which
      # then SEGV'd when result was used as a pointer).
      result = 1.step(5) { |x| x }
      puts result.inspect
      puts result.class
    RUBY

    _(result).must_answer "1\nInteger\n"
  end

  it "integer nonzero" do
    result = zr(<<~'RUBY')
      # Issue #874: Integer#nonzero? returns nil when receiver is 0,
      # self otherwise. Surfaces as int? (nullable int).
      puts 0.nonzero?.inspect
      puts 42.nonzero?.inspect
      puts(-5.nonzero? || "default")
    RUBY

    _(result).must_answer <<~'OUT'
      nil
      42
      -5
    OUT
  end

  it "range size exclusive" do
    result = zr(<<~'RUBY')
      # Range#size with exclusive range
      # (1...5).size should return 4, not 5.

      puts (1..5).size
      puts (1...5).size
    RUBY

    _(result).must_answer "5\n4\n"
  end

  it "range size string" do
    result = zr(<<~'RUBY')
      # A String range has no integer size; CRuby Range#size returns nil.
      # Integer ranges keep returning their element count.
      p (1..10).size
      p (1...10).size
      p ("a".."z").size
      p ("a".."z").size.nil?
      p ("a".."e").size
    RUBY

    _(result).must_answer <<~'OUT'
      10
      9
      nil
      true
      nil
    OUT
  end

  it "integer bignum batch2" do
    result = zr(<<~'RUBY')
      # Integer/Bignum conformance (KieranP #2418-#2423, #2425)
      p((2 ** 100).magnitude)
      p((2 ** 100).abs)
      p(1.coerce(2 ** 100))
      p(Integer.sqrt(2 ** 100))
      r = (5 & 2.0 rescue $!.class)
      p r
      p(1 | (2 ** 100))
      p(1 ^ (2 ** 100))
      a = 20
      b = -2
      p(a << b)
      sh = 3
      p(a << sh)
      p(a >> sh)
      p(7.div(2.5))
      p(7.ceildiv(2.5))
      p(6.abs2)
    RUBY

    _(result).must_answer <<~'OUT'
      1267650600228229401496703205376
      1267650600228229401496703205376
      [1267650600228229401496703205376, 1]
      1125899906842624
      TypeError
      1267650600228229401496703205377
      1267650600228229401496703205377
      5
      160
      2
      2
      3
      36
    OUT
  end

  it "between? compares a bignum receiver against bignum bounds" do
    result = zr(<<~'RUBY')
      p((2 ** 150).between?(1, 2 ** 100))
      p((2 ** 150).between?(2 ** 100, 2 ** 200))
      p((10 ** 40).between?(10 ** 39, 10 ** 41))
    RUBY

    _(result).must_answer <<~'OUT'
      false
      true
      true
    OUT
  end

  it "between? compares a small Integer against bignum bounds" do
    result = zr(<<~'RUBY')
      p 50.between?(1, 2 ** 100)
      p 50.between?(2 ** 100, 2 ** 200)
      p (2 ** 100).between?(1, 2 ** 200)
      p 5.between?(1, 10)
    RUBY

    _(result).must_answer <<~'OUT'
      true
      false
      true
      true
    OUT
  end

  it "the operator assignments keep a Rational local a Rational" do
    result = zr(<<~'RUBY')
      # Rational operator-assignment (`r += x`, `-=`, `*=`, `/=`) on a Rational local.
      t = Rational(0, 1)
      t += Rational(1, 2)
      p t
      t -= Rational(1, 4)
      p t
      t *= 3
      p t
      t /= Rational(3, 2)
      p t
    RUBY

    _(result).must_answer <<~'OUT'
      (1/2)
      (1/4)
      (3/4)
      (1/2)
    OUT
  end

  it "round with a digit count dispatches on the value's runtime type" do
    result = zr(<<~'RUBY')
      # `.round(ndigits)` on a poly value (a zip-sum divided by a Float): the
      # digit-taking round must dispatch on the runtime tag, not raise NoMethodError.
      p ([1, 2].zip([3, 4]).sum { |x, y| x * y } / 2.0).round(2)
      a = [3.14159, 2.71828]
      x = a.sum { |v| v * 1 }
      p x.round(2)
      p x.round(-1)
      b = [12345]
      y = b.sum { |v| v }
      p y.round(-2)
    RUBY

    _(result).must_answer <<~'OUT'
      5.5
      5.86
      10
      12300
    OUT
  end

  it "numerator and denominator answer for a Rational read out of a container" do
    result = zr(<<~'RUBY')
      # numerator/denominator on a Rational read out of a poly container: the
      # poly receiver must dispatch on the runtime tag, not return an opaque value.
      arr = [Rational(1, 3), Rational(1, 2)]
      p arr[0].numerator + arr[1].numerator
      p arr[0].denominator
      a = [Rational(3, 4), 7]
      p a[1].numerator
      p a[1].denominator
    RUBY

    _(result).must_answer <<~'OUT'
      2
      3
      7
      1
    OUT
  end

  it "a sum block runs its leading statement before the value it answers with" do
    result = zr(<<~'RUBY')
      # A sum block with a leading statement (a block-local) feeding a nested
      # Array#find: the leading statement must run, not be dropped.
      UNITS = [["d", 86400], ["h", 3600], ["m", 60], ["s", 1]]
      p ["1h", "30m"].sum { |t| label = t[-1]; UNITS.find { |l, _| l == label }[1] }
      # leading statement in an integer sum block
      p [1, 2, 3].sum { |x| y = x * 2; y }
      # leading statement in a float sum block
      p [1.0, 2.0].sum { |x| z = x + 1.0; z }
    RUBY

    _(result).must_answer <<~'OUT'
      3660
      12
      5.0
    OUT
  end

  it "conjugate and conj negate the imaginary part of a Complex read out of a container" do
    result = zr(<<~'RUBY')
      # conjugate/conj on a Complex read out of a poly container: dispatch on the
      # runtime tag (negate the imaginary part) instead of returning an opaque value.
      xs = [Complex(1, 2), Complex(3, 4)]
      p xs[1].conjugate.real.round(3)
      p xs[0].conjugate.imaginary
      p xs[1].conj.real
    RUBY

    _(result).must_answer <<~'OUT'
      3
      -2
      3
    OUT
  end

  it "a nested write lands on the inner array when both subscripts came from destructuring" do
    result = zr(<<~'RUBY')
      # A nested write g[r][c] = v where r/c are poly (from destructuring) must land
      # on the inner array, not be dropped -- sp_poly_set_poly lacked Str/Float array
      # cases.
      grid = [["a", "b"], ["c", "d"]]
      cells = [[0, 1]]
      r, c = cells.first
      grid[r][c] = "X"
      p grid
      fg = [[1.0, 2.0]]
      fr, fc = [[0, 1]].first
      fg[fr][fc] = 9.0
      p fg
    RUBY

    _(result).must_answer <<~'OUT'
      [["a", "X"], ["c", "d"]]
      [[1.0, 9.0]]
    OUT
  end

  it "a sum block written with do...end runs its leading assignment" do
    result = zr(<<~'RUBY')
      # Array#sum with a do...end block containing a leading local assignment: the
      # per-iteration leading statements must not emit a #line directive mid
      # statement-expression (a stray '#').
      r = [1, 2, 3].sum do |t|
        x = t * 2
        x
      end
      p r
      f = [1.0, 2.0].sum do |t|
        y = t + 1.0
        y
      end
      p f
    RUBY

    _(result).must_answer "12\n5.0\n"
  end

  it "a Complex raised to a Rational power" do
    result = zr(<<~'RUBY')
      p(Complex(2, 3) ** Rational(2, 1))
      p(Complex(2, 3) ** Rational(1, 2))
      p(Complex(2, 3) ** Rational(3, 1))
    RUBY

    _(result).must_answer <<~'OUT'
      (-5+12i)
      (1.6741492280355401+0.895977476129838i)
      (-46+9i)
    OUT
  end

  it "a Float compares against a bignum by value" do
    result = zr(<<~'RUBY')
      p(3.0 <=> (10**30))
      p((10**30) <=> 3.0)
      p(3.0 <=> (10**30) * -1)
      p(1e40 <=> (10**30))
      p(3.0 <=> 3)
    RUBY

    _(result).must_answer <<~'OUT'
      -1
      1
      1
      1
      0
    OUT
  end

  it "Float#step with a NaN bound yields nothing, and an infinite start never ends" do
    result = zr(<<~'RUBY')
      Float::NAN.step(2.0, 0.5) { |x| p x }; puts "a"
      1.0.step(Float::NAN, 0.5) { |x| p x }; puts "b"
      n = 0
      Float::INFINITY.step(2.0, 0.5) { |x| n += 1; break if n > 3 }
      p n
      1.0.step(3.0, 0.5) { |x| p x }
    RUBY

    _(result).must_answer <<~'OUT'
      a
      b
      0
      1.0
      1.5
      2.0
      2.5
      3.0
    OUT
  end

  it "Math.lgamma is exactly [Infinity, 1] at every non-positive integer pole" do
    result = zr(<<~'RUBY')
      # poles at non-positive integers are exactly [Infinity, 1]
      p Math.lgamma(-1.0)
      p Math.lgamma(-2.0)
      p Math.lgamma(0.0)
      p Math.lgamma(-3.0)
      p Math.lgamma(-10.0)
      # finite values: spinel's own series diverges in the last ULPs from libm by
      # design (machine-independent golden output), so check only sign + finiteness
      r = Math.lgamma(5.0);  p [r[0].finite?, r[1]]
      r = Math.lgamma(-0.5); p [r[0].finite?, r[1]]
      r = Math.lgamma(0.5);  p [r[0].finite?, r[1]]
    RUBY

    _(result).must_answer <<~'OUT'
      [Infinity, 1]
      [Infinity, 1]
      [Infinity, 1]
      [Infinity, 1]
      [Infinity, 1]
      [true, 1]
      [true, -1]
      [true, 1]
    OUT
  end

  it "Rational#round takes the rounding rule as half:" do
    result = zr(<<~'RUBY')
      p Rational(5, 2).round(half: :even)
      p Rational(5, 2).round(half: :up)
      p Rational(5, 2).round(half: :down)
      p Rational(5, 2).round
      p Rational(7, 2).round(half: :even)
      p Rational(-5, 2).round(half: :even)
      p Rational(-5, 2).round(half: :down)
      p Rational(3, 2).round(half: :even)
    RUBY

    _(result).must_answer <<~'OUT'
      2
      3
      2
      3
      4
      -2
      -2
      2
    OUT
  end

  it "Rational#rationalize answers the simplest fraction inside the tolerance" do
    result = zr(<<~'RUBY')
      p Rational(1,3).rationalize(Rational(1,10))
      p Rational(5000,10001).rationalize(Rational(1,100))
      p Rational(22,7).rationalize(0.01)
      p Rational(3,4).rationalize(Rational(1,10))
      p Rational(1,3).rationalize
    RUBY

    _(result).must_answer <<~'OUT'
      (1/3)
      (1/2)
      (22/7)
      (2/3)
      (1/3)
    OUT
  end

  it "Range#bsearch over floats takes the find-minimum form and the find-any form" do
    result = zr(<<~'RUBY')
      p((0.0..10.0).bsearch { |x| x * x - 4 >= 0 ? x * x - 4 : nil })
      p((0.0..10.0).bsearch { |x| 4 - x*x })
      p((0.0..10.0).bsearch { |x| x*x - 4 })
      p((0.0..10.0).bsearch { |x| x >= 3.0 })
      p((0.0..10.0).bsearch { |x| x >= 3.0 ? true : nil })
      p((1.0..9.0).bsearch { |x| nil })
    RUBY

    _(result).must_answer <<~'OUT'
      nil
      2.0
      nil
      3.0
      3.0
      nil
    OUT
  end

  it "Signal.signame truncates a Float signal number" do
    result = zr(<<~'RUBY')
      p Signal.signame(2.9)
      p Signal.signame(2)
      p Signal.signame(9.99)
    RUBY

    _(result).must_answer <<~'OUT'
      "INT"
      "INT"
      "KILL"
    OUT
  end

  it "a **kwargs parameter collects every keyword, whatever the values are" do
    result = zr(<<~'RUBY')
      def f(**k); p k; end
      f(value: ["x"])
      f(value: {x: "x"})
      f(a: 1, b: [2, 3])
      f(name: "n", tags: [:a, :b])
      f()
    RUBY

    _(result).must_answer <<~'OUT'
      {value: ["x"]}
      {value: {x: "x"}}
      {a: 1, b: [2, 3]}
      {name: "n", tags: [:a, :b]}
      {}
    OUT
  end

  it "Math.lgamma answers sign -1 at negative zero and 1 at positive zero" do
    result = zr(<<~'RUBY')
      p Math.lgamma(-0.0)
      p Math.lgamma(0.0)
      p Math.lgamma(-1.0)
      p Math.lgamma(-2.0)
    RUBY

    _(result).must_answer <<~'OUT'
      [Infinity, -1]
      [Infinity, 1]
      [Infinity, 1]
      [Infinity, 1]
    OUT
  end

  it "pop and first answer through a method that took the array as a parameter" do
    result = zr(<<~'RUBY')
      def fn(opts) = opts.pop
      def fn2(*opts) = fn(opts)
      p fn([""])
      p fn([1, 2, 3])
      p fn([1.5, 2.5])
      def g(a) = a.first
      p g([10, 20])
    RUBY

    _(result).must_answer <<~'OUT'
      ""
      3
      2.5
      10
    OUT
  end

  it "Integer#[] takes a bit index, a range of bits and a start and length on a bignum" do
    result = zr(<<~'RUBY')
      p((2 ** 100)[10..20])
      p((2 ** 100)[100])
      p((2 ** 100)[99])
      p((2 ** 100)[10, 5])
      p((2 ** 100)[95..105])
      p((2 ** 100)[100..])
      p((2 ** 70)[68, 4])
    RUBY

    _(result).must_answer <<~'OUT'
      0
      1
      0
      0
      32
      1
      4
    OUT
  end

  it "sum over a row answers in the row's own type" do
    result = zr(<<~'RUBY')
      mat = [[Rational(1, 2), Rational(1, 3)]]
      p mat[0].sum
      fmat = [[1.5, 2.5]]
      p fmat[0].sum
      imat = [[1, 2, 3]]
      p imat[0].sum
    RUBY

    _(result).must_answer <<~'OUT'
      (5/6)
      4.0
      6
    OUT
  end

  it "a wrapper that splats both *args and **kwargs passes them on unchanged" do
    result = zr(<<~'RUBY')
      def build(name, **extra)
        "#{name}/#{extra.size}"
      end
      def wrapper(*args, **kwargs)
        build(*args, **kwargs)
      end
      puts wrapper("dave", role: "dev")
      puts wrapper("amy", role: "dev", team: "x")
      puts wrapper("joe")
    RUBY

    _(result).must_answer <<~'OUT'
      dave/1
      amy/2
      joe/0
    OUT
  end

  it "Float#rationalize answers the simplest fraction inside the tolerance" do
    result = zr(<<~'RUBY')
      p 0.333333.rationalize(Rational(1, 1000))
      p 0.5.rationalize(Rational(1, 100))
      p 0.333333.rationalize(0.001)
      p 0.333333.rationalize
    RUBY

    _(result).must_answer <<~'OUT'
      (1/3)
      (1/2)
      (1/3)
      (333333/1000000)
    OUT
  end

  it "between? and clamp take a Rational bound against an Integer receiver" do
    result = zr(<<~'RUBY')
      p(2.between?(1, Rational(5, 2)))
      p(5.clamp(1, Rational(9, 2)))
      p(5.clamp(1, Rational(11, 2)))
      p(2.5.clamp(1, Rational(9, 2)))
      p(2.between?(Rational(1, 1), 5))
    RUBY

    _(result).must_answer <<~'OUT'
      true
      (9/2)
      5
      2.5
      true
    OUT
  end

  it "Rational#clamp and #between? answer in the bound's type" do
    result = zr(<<~'RUBY')
      p(Rational(5, 2).clamp(1, 2))
      p(Rational(5, 2).clamp(1.0, 2.0))
      p(Rational(5, 2).clamp(Rational(0, 1), Rational(3, 1)))
      p(Rational(5, 2).between?(1, 3))
      p(Rational(1, 2).clamp(1, 3))
    RUBY

    _(result).must_answer <<~'OUT'
      2
      2.0
      (5/2)
      true
      1
    OUT
  end

  it "Kernel#Integer takes a base, and refuses anything that is not a string" do
    result = zr(<<~'RUBY')
      class Item
        attr_reader :kind
        def initialize(kind) = @kind = kind

        def parse(param)
          case kind
          when :int then Integer(param, 10)
          when :str then param
          end
        end
      end

      def parse(item, param)
        if item.kind == :bool
          param = nil
          return true
        end
        item.parse(param)
      end

      values = [parse(Item.new(:bool), ""), parse(Item.new(:int), "1"), parse(Item.new(:str), "x")]
      raise "FAIL" unless values == [true, 1, "x"]
      puts "ok"

      def conv(x)
        Integer(x, 16)
      end

      p conv("ff")
      p(begin; conv(nil); rescue ArgumentError => e; e.class; end)
      p(begin; conv(3); rescue ArgumentError => e; e.class; end)
    RUBY

    _(result).must_answer <<~'OUT'
      ok
      255
      ArgumentError
      ArgumentError
    OUT
  end

  it "the Integer enumerators chain through with_index and with_object" do
    result = zr(<<~'RUBY')
      p 4.times.with_index(1).to_a
      p 3.upto(5).with_index(1).to_a
      p 5.downto(3).with_index(1).to_a
      p 4.times.with_index.to_a

      acc = []
      3.times.with_index(10) { |x, i| acc << [x, i] }
      p acc

      p 3.times.each_with_index.to_a
      p 2.upto(4).with_object([]) { |x, memo| memo << x * 2 }
    RUBY

    _(result).must_answer <<~'OUT'
      [[0, 1], [1, 2], [2, 3], [3, 4]]
      [[3, 1], [4, 2], [5, 3]]
      [[5, 1], [4, 2], [3, 3]]
      [[0, 0], [1, 1], [2, 2], [3, 3]]
      [[0, 10], [1, 11], [2, 12]]
      [[0, 0], [1, 1], [2, 2]]
      [4, 6, 8]
    OUT
  end

  it "with_index and each_with_index answer the receiver when given a block" do
    result = zr(<<~'RUBY')
      p(4.times.with_index(1) { |x, i| x })
      acc = []
      p(3.upto(5).with_index(10) { |x, i| acc << [x, i] })
      p acc
      p(5.downto(3).each_with_index { |x, i| acc << [x, i] })
      p acc
    RUBY

    _(result).must_answer <<~'OUT'
      4
      3
      [[3, 10], [4, 11], [5, 12]]
      5
      [[3, 10], [4, 11], [5, 12], [5, 0], [4, 1], [3, 2]]
    OUT
  end

  it "a bignum negates and rounds at a negative precision, Float <=> NaN is nil, and arg answers by sign" do
    result = zr(<<~'RUBY')
      # Bignum -@ / round / ceil / floor (incl. negative precision); Float <=> NaN
      # is nil; Float arg/angle/phase (Integer 0 or Float PI by sign).
      b = 2 ** 100
      p(-b)
      p(-(-b))
      p b.round
      p b.round(-2)
      p b.floor(-2)
      p b.ceil(-2)
      p((0 - b).round(-2))
      p(Float::NAN <=> 1.0)
      p(1.0 <=> 2.0)
      p(2.0 <=> 2.0)
      p(Float::NAN <=> Float::NAN)
      p((-1.5).angle)
      p(1.5.arg)
      p(1.5.phase)
    RUBY

    _(result).must_answer <<~'OUT'
      -1267650600228229401496703205376
      1267650600228229401496703205376
      1267650600228229401496703205376
      1267650600228229401496703205400
      1267650600228229401496703205300
      1267650600228229401496703205400
      -1267650600228229401496703205400
      nil
      -1
      0
      nil
      3.141592653589793
      0
      0
    OUT
  end

  it "the bit slice, gcd, divmod, clamp and round(half:) edges raise or answer as CRuby does" do
    result = zr(<<~'RUBY')
      # Integer bit-slice n[range], gcd/lcm TypeError on Float, divmod/modulo
      # with Float divisors, clamp with Float-bounded ranges (both receivers),
      # round(half:), and FloatDomainError on Infinity/NaN roundings.
      p(5[1..3])
      p(0b1101[0..2])
      r = (begin; 5.gcd(2.0); rescue TypeError; "TypeError"; end); p r
      r2 = (begin; 10.divmod(2.5); rescue; "raised"; end); p r2
      p(10.divmod(3))
      p(7.clamp(1.0..3.5))
      p(2.5.clamp(1..3))
      p(10.round(half: :even))
      p(11.round(half: :up))
      inf = Float::INFINITY
      r3 = (begin; inf.floor; rescue FloatDomainError; "FDE"; end); p r3
      r4 = (begin; (1.0/0.0).round; rescue FloatDomainError; "FDE2"; end); p r4
      p(7.0.divmod(inf))
      p(0.5.clamp(1..3))
      p(7.0.divmod(-inf))
      p(25.round(-1, half: :down))
      p(15.round(-1, half: :even))
      p(25.round(-1, half: :even))
      p(25.round(-1, half: :up))
      r5 = (begin; inf.round(-1); rescue FloatDomainError => e; e.message; end); p r5
      p(inf.floor(1))
    RUBY

    _(result).must_answer <<~'OUT'
      2
      5
      "TypeError"
      [4, 0.0]
      [3, 1]
      3.5
      2.5
      10
      11
      "FDE"
      "FDE2"
      [0, 7.0]
      1
      [-1, -Infinity]
      20
      20
      20
      30
      "Infinity"
      Infinity
    OUT
  end

  it "rational complex wave9" do
    result = zr(<<~'RUBY')
      # Rational floor/ceil (0/1 arg), predicates, coerce, Rational ** Rational,
      # Complex(String), ** float/Complex, to_i/to_f/to_r, numerator/denominator,
      # fdiv, coerce. Float-exponent pow is approx-checked (libm last-digit).
      p(Rational(7,2).floor)
      p(Rational(7,2).ceil)
      p(Rational(-7,2).floor)
      p(Rational(-7,2).ceil)
      p(Rational(11,4).round)
      p(Rational(314,100).floor(1))
      p(Rational(314,100).ceil(1))
      p(Rational(0,1).zero?)
      p(Rational(1,2).positive?)
      p(Rational(-1,2).negative?)
      p(Rational(1,2).coerce(2))
      p(Rational(2,3) ** Rational(1,2))
      p(Complex("2+3i"))
      z = Complex(2,3) ** 2.0
      puts (z.real.to_f + 5.0).abs < 1e-9 && (z.imaginary.to_f - 12.0).abs < 1e-9 ? "pow_float ok" : "pow_float bad"
      p(Complex(2,3) ** Complex(1,0))
      p(Complex(1,1).arg)
      p(Complex(1,1).angle)
      p(Complex(2,3).polar)
      p(Complex(2,3).rect)
      p(Complex(2,3).rectangular)
      p(Complex.rect(2,3))
      p(Complex.rectangular(2,3))
      p(Complex(2,0).to_i)
      p(Complex(2,3).numerator)
      p(Complex(2,3).denominator)
      p(Complex(2,3).fdiv(2))
      p(Complex(2,3).coerce(2))
      p(Complex(2,0).to_f)
      p(Complex(2.5,0).to_r)
      r = (begin; Complex(2,3).to_i; rescue RangeError => e; "RangeError"; end); p r
    RUBY

    _(result).must_answer <<~'OUT'
      3
      4
      -4
      -3
      3
      (31/10)
      (16/5)
      true
      true
      true
      [(2/1), (1/2)]
      0.816496580927726
      (2+3i)
      pow_float ok
      (2+3i)
      0.7853981633974483
      0.7853981633974483
      [3.605551275463989, 0.982793723247329]
      [2, 3]
      [2, 3]
      (2+3i)
      (2+3i)
      2
      (2+3i)
      1
      (1.0+1.5i)
      [(2+0i), (2+3i)]
      2.0
      (5/2)
      "RangeError"
    OUT
  end
end
