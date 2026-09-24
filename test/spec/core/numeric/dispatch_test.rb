# frozen_string_literal: true

require "spec_helper"

describe "Numeric: dispatch" do
  it "case in matches float and builtin classes on poly values" do
    result = zr(<<~'RUBY')
      def describe(val)
        case val
        in Integer then "int"
        in Float then "float"
        in String then "str"
        else "other"
        end
      end
      puts describe(1)
      puts describe(2.5)
      puts describe("s")
      puts describe(:sym)
    RUBY

    _(result).must_answer <<~'OUT'
      int
      float
      str
      other
    OUT
  end

  it "complex poly arith" do
    result = zr(<<~'RUBY')
      # Arithmetic and abs/abs2/magnitude on a Complex read out of a poly container
      # (the poly `+`/`-`/`*`/`/` and sp_poly_abs dispatch the Complex tag). Complex
      # division with integer components follows spinel's float-backed Complex
      # (a documented divergence from CRuby's rational components), so the divisor
      # here is chosen to divide cleanly.
      xs = [Complex(1, 2), Complex(3, -4)]
      c = xs.first
      p (c + Complex(5, 5))
      p (c - Complex(1, 1))
      p (c * 2)
      p (c * Complex(2, 1))
      p (Complex(4, 2) == xs.first * Complex(2, 0) + Complex(2, 2))
      p (c + 3)
      p c.abs
      p c.abs2
      p c.magnitude
      p xs.reduce(Complex(0, 0)) { |a, z| a + z }
      p xs.map { |z| z.abs }
    RUBY

    _(result).must_answer <<~'OUT'
      (6+7i)
      (0+1i)
      (2+4i)
      (0+5i)
      false
      (4+2i)
      2.23606797749979
      5
      2.23606797749979
      (4-2i)
      [2.23606797749979, 5.0]
    OUT
  end

  it "int nil boxing at poly boundary" do
    result = zr(<<~'RUBY')
      # A missed element read from an int container boxes as nil, not as an Integer.
      def klass(v) = v.class.name
      def isnil(v) = v.nil?

      a = [1, 2]
      h = { "a" => 1 }
      ih = { 1 => 2 }
      fa = [1.5]

      p klass(a[5]), klass(a[0])
      p klass(h["zz"]), klass(h["a"])
      p klass(ih[3]), klass(ih[1])
      p klass([].max), klass([].min), klass(a.max)
      p klass(a.find { false }), klass(a.detect { |v| v == 2 })
      p klass([].first), klass([].last), klass(a.first)
      p klass(a.at(9)), klass([[1]].dig(0, 5))
      p klass(fa[3]), klass(fa[0])
      p klass(Integer("x", exception: false)), klass(Integer("7", exception: false))
      p klass(Float("x", exception: false)), klass(Float("1.5", exception: false))
      p isnil(a[5]), isnil(a[0]), isnil("s")

      x = h["zz"]
      y = a[1]
      p isnil(x), isnil(y), klass(x), klass(y)

      def pick(arr, i) = arr[i]
      p klass(pick(a, 7)), klass(pick(a, 0))

      out = []
      out << a[5] << a[0] << h["q"]
      p out
      p [a[9], h["zz"], a[0]]
    RUBY

    _(result).must_answer <<~'OUT'
      "NilClass"
      "Integer"
      "NilClass"
      "Integer"
      "NilClass"
      "Integer"
      "NilClass"
      "NilClass"
      "Integer"
      "NilClass"
      "Integer"
      "NilClass"
      "NilClass"
      "Integer"
      "NilClass"
      "NilClass"
      "NilClass"
      "Float"
      "NilClass"
      "Integer"
      "NilClass"
      "Float"
      true
      false
      false
      true
      false
      "NilClass"
      "Integer"
      "NilClass"
      "Integer"
      [nil, 1, nil]
      [nil, nil, 1]
    OUT
  end

  it "integer poly arg methods" do
    result = zr(<<~'RUBY')
      # Integer methods whose argument the runtime takes as an mrb_int must unbox a
      # polymorphic argument (here an element of a mixed array, poly-typed but an
      # integer at runtime) rather than emitting it as a raw boxed value.
      mix = [6, "x"]
      b = mix.first

      p 255.allbits?(b)
      p 255.anybits?(b)
      p 256.nobits?(b)
      p 100.ceildiv(b)
      p 2.pow(b)
      p 2.pow(b, 100)
      p 255.to_s(b)
      p 12.gcd(b)
      p 4.lcm(b)
      p 17.remainder(b)

      # remainder by zero raises ZeroDivisionError (not a SIGFPE crash)
      z = [0, "x"].first
      begin
        p 17.remainder(z)
      rescue ZeroDivisionError => e
        puts "ZeroDivisionError: #{e.message}"
      end

      # allbits? evaluates its argument exactly once (the side effect prints once)
      def bit
        puts "bit evaluated"
        6
      end
      p 255.allbits?(bit)
    RUBY

    _(result).must_answer <<~'OUT'
      true
      true
      true
      17
      64
      64
      "1103"
      6
      12
      5
      ZeroDivisionError: divided by 0
      bit evaluated
      true
    OUT
  end

  it "math poly arg unbox" do
    result = zr(<<~'RUBY')
      # Math.* with a poly-typed argument (a value that unifies to Integer|Float)
      # must unbox at the call boundary via sp_poly_to_f. Previously only a plain
      # TY_INT arg got a (double) cast; a poly arg passed straight through as an
      # sp_RbVal into the mrb_float parameter -- invalid C. Shape from the Doom
      # gem's distance helpers (player_physics.rb, sector_actions.rb):
      #   Math.sqrt(dx * dx + dy * dy)  # dx, dy flow both Integer and Float

      def dist(dx, dy)
        Math.sqrt(dx * dx + dy * dy)
      end

      puts dist(3, 4)
      puts dist(1.5, 2.0)

      def pick(int_side)
        int_side ? 2 : 2.0
      end

      x = pick(true)   # poly: Integer|Float
      y = pick(false)

      puts Math.sqrt(x).round(4)
      puts Math.sin(y).round(4)
      puts Math.log(x).round(4)
      puts Math.log(8, x)
      puts Math.log2(x)
      puts Math.log10(y).round(4)
      puts Math.atan2(x, y).round(4)
      puts Math.hypot(x, y).round(4)
      puts Math.ldexp(y, 3)
      lg = Math.lgamma(x)
      lg0 = lg[0]
      puts lg0
    RUBY

    _(result).must_answer <<~'OUT'
      5.0
      2.5
      1.4142
      0.9093
      0.6931
      3.0
      1.0
      0.301
      0.7854
      2.8284
      16.0
      0.0
    OUT
  end

  it "poly" do
    result = zr(<<~'RUBY')
      # Test polymorphic variables (sp_RbValue)

      # Variable holding different types
      x = 1
      puts x      # 1
      x = "hello"
      puts x      # hello

      # Polymorphic method parameter
      def show(val)
        puts val
      end
      show(42)
      show("world")
      show(true)
      show(3.14)

      # Nilable
      y = "found"
      puts y      # found
      y = nil
      puts y.nil? # true — but this needs nil tracking

      puts "done"
    RUBY

    _(result).must_answer <<~'OUT'
      1
      hello
      42
      world
      true
      3.14
      found
      true
      done
    OUT
  end

  it "poly arithmetic invalid raises" do
    result = zr(<<~'RUBY')
      # Invalid operations reached through boxed values must raise instead of
      # silently producing Integer zero.
      receivers = [nil, true, :token, {"a" => 1}]

      receivers.each do |value|
        begin
          value + 1
        rescue StandardError => error
          p error.class
        end
        begin
          value - 1
        rescue StandardError => error
          p error.class
        end
        begin
          value * 1
        rescue StandardError => error
          p error.class
        end
      end

      # Arithmetic-capable receivers reject incompatible operands with TypeError.
      [1, 1.5].each do |value|
        begin
          value + "x"
        rescue StandardError => error
          p error.class
        end
      end

      # This is the minimized differential-fuzzer case: the fresh block-local starts
      # as nil, so subtraction raises and the surrounding rescue assigns -1.
      begin
        [0, 0, 0].each do |element|
          if element > 0
            accumulator = accumulator + element
          else
            accumulator = accumulator - 0
          end
        end
      rescue StandardError
        accumulator = -1
      end
      p accumulator
    RUBY

    _(result).must_answer <<~'OUT'
      NoMethodError
      NoMethodError
      NoMethodError
      NoMethodError
      NoMethodError
      NoMethodError
      NoMethodError
      NoMethodError
      NoMethodError
      NoMethodError
      NoMethodError
      NoMethodError
      TypeError
      TypeError
      -1
    OUT
  end

  it "poly exact numeric ops" do
    result = zr(<<~'RUBY')
      # An exact receiver reaching an operator or a numeric method through a block
      # parameter is boxed, and the poly path answered it in floats or not at all.
      # `**` evaluated in doubles (a different answer as well as a different class),
      # `%` truncated to Integer, and divmod / modulo / quo / abs had no arm at all
      # so they raised NoMethodError on methods Rational answers (#3510, #3512).
      p([Rational(3, 2)].map { |a| a**2 })
      p([Rational(7, 2)].map { |a| a % 2 })
      p([Rational(-7, 2)].map { |a| a**3 })
      p([Complex(1, 2)].map { |a| a**2 })
      p([Complex(1, 2)].map { |a| a**3 })

      p([Rational(7, 2)].map { |a| a.divmod(2) })
      p([Rational(7, 2)].map { |a| a.modulo(2) })
      p([Rational(7, 2)].map { |a| a.quo(2) })
      p([Rational(-7, 2)].map { |a| a.abs })
      p([Rational(7, 2)].map { |a| a.abs })

      # the neighbours that were already right stay right
      p([Rational(7, 2)].map { |a| a.floor })
      p([Rational(7, 2)].map { |a| a.round })
      p([Rational(7, 2)].map { |a| a.truncate })
      p([Rational(7, 2)].map { |a| a.to_i })
      p([Rational(3, 2)].map { |a| a + 1 })
      p([Rational(3, 2)].map { |a| a * 2 })
      p([Rational(3, 2)].map { |a| a / 2 })
      p([Rational(3, 2)].map { |a| a - 1 })

      # and the same operators on the kinds that share the path
      p([2].map { |a| a**3 })
      p([7].map { |a| a % 2 })
      p([7].map { |a| a.divmod(2) })
      p([7].map { |a| a.quo(2) })
      p([-7].map { |a| a.abs })
      p([2.5].map { |a| a**2 })
      p([7.5].map { |a| a % 2 })
      p([7.5].map { |a| a.divmod(2) })
      p([-7.5].map { |a| a.abs })

      # a monomorphic receiver was always exact; it has to stay that way
      r = Rational(3, 2)
      p r**2
      p r % 1
      p r.divmod(1)
      p r.quo(2)
      p r.abs
    RUBY

    _(result).must_answer <<~'OUT'
      [(9/4)]
      [(3/2)]
      [(-343/8)]
      [(-3+4i)]
      [(-11-2i)]
      [[1, (3/2)]]
      [(3/2)]
      [(7/4)]
      [(7/2)]
      [(7/2)]
      [3]
      [4]
      [3]
      [3]
      [(5/2)]
      [(3/1)]
      [(3/4)]
      [(1/2)]
      [8]
      [1]
      [[3, 1]]
      [(7/2)]
      [7]
      [6.25]
      [1.5]
      [[3, 1.5]]
      [7.5]
      (9/4)
      (1/2)
      [1, (1/2)]
      (3/4)
      (3/2)
    OUT
  end

  it "poly numeric div remainder" do
    result = zr(<<~'RUBY')
      # A Float that reaches a method through a boxed slot answers the whole
      # Numeric surface, not only the operators (#3800).
      rings = [[[[-63.1269583, 46.2338358], [-63.1260111, 46.234436]]]]
      array = rings.flat_map { |ring| ring.first.map(&:first) }
      p array.sum
      p array.sum.div(array.size)

      xs = [7.0, 3, -7.0]
      a = xs[0]
      b = xs[1]
      c = xs[2]
      p a.div(3)
      p c.div(3)
      p b.div(3)
      p a.divmod(3)
      p c.divmod(3)
      p b.divmod(3)
      p a.remainder(3)
      p c.remainder(3)
      p b.remainder(3)
      p a.modulo(3)
      p a.quo(3)
      p a.fdiv(3)
      p a.to_r
      p a.coerce(3)
      p b.coerce(2.5)
      begin
        p a.div(0)
      rescue ZeroDivisionError => e
        p e.class
      end
      begin
        p a.remainder(0)
      rescue ZeroDivisionError => e
        p e.class
      end
    RUBY

    _(result).must_answer <<~'OUT'
      -126.2529694
      -64
      2
      -3
      1
      [2, 1.0]
      [-3, 2.0]
      [1, 0]
      1.0
      -1.0
      0
      1.0
      2.3333333333333335
      2.3333333333333335
      (7/1)
      [3.0, 7.0]
      [2.5, 3.0]
      ZeroDivisionError
      ZeroDivisionError
    OUT
  end

  it "poly numeric query methods" do
    result = zr(<<~'RUBY')
      # Numeric / byte query methods on a poly value (a boxed element of a
      # heterogeneous array): nan? / finite? / infinite? / abs / floor / ceil /
      # round / truncate / zero? / positive? / negative? / bytesize / ord /
      # bit_length / getbyte dispatch on the runtime tag like CRuby dispatches on
      # the class. Previously only to_i / to_f (and a few string transforms) were
      # in the poly table, so `v.nan?` raised "undefined method 'nan?' for poly"
      # at runtime and `v.floor` failed to compile.
      #
      # NOTE: no class in this file may define a colliding method/reader name --
      # a user definition shadows the builtin poly path program-wide (that
      # shadowing is covered by poly_attr_reader_shadows_builtin.rb).

      # Float carried in a poly slot
      v = [1.5, "x"][0]
      puts v.to_i        # 1 (already worked)
      puts v.nan?        # false
      puts v.abs         # 1.5
      puts v.floor       # 1
      puts v.ceil        # 2
      puts v.round       # 2
      puts v.truncate    # 1
      puts v.zero?       # false
      puts v.positive?   # true
      puts v.negative?   # false
      puts v.finite?     # true
      p v.infinite?      # nil

      # Negative float: round is half-away-from-zero, truncate goes toward zero
      w = [-2.5, "x"][0]
      puts w.abs         # 2.5
      puts w.floor       # -3
      puts w.ceil        # -2
      puts w.round       # -3
      puts w.truncate    # -2
      puts w.negative?   # true

      # Integer carried in a poly slot: floor/ceil/round return self
      n = [-3, "x"][0]
      puts n.abs         # 3
      puts n.floor       # -3
      puts n.round       # -3
      puts n.zero?       # false
      puts n.positive?   # false
      puts n.finite?     # true
      p n.infinite?      # nil

      z = [0, "x"][0]
      puts z.zero?       # true
      puts z.positive?   # false
      puts z.negative?   # false
      puts z.bit_length  # 0
      puts n.bit_length  # 2

      # String carried in a poly slot: byte/codepoint queries
      s = ["ab", 1][0]
      puts s.getbyte(0)  # 97
      puts s.getbyte(1)  # 98
      puts s.getbyte(-1) # 98
      p s.getbyte(5)     # nil (out of range)
      puts s.bytesize    # 2
      puts s.ord         # 97

      # Non-finite floats: rounding raises FloatDomainError (not C UB), abs works
      nan = [0.0 / 0.0, "x"][0]
      inf = [-1.0 / 0.0, "x"][0]
      begin
        nan.floor
      rescue FloatDomainError => ex
        puts "#{ex.class}: #{ex.message}"   # FloatDomainError: NaN
      end
      begin
        inf.round
      rescue FloatDomainError => ex
        puts "#{ex.class}: #{ex.message}"   # FloatDomainError: -Infinity
      end
      puts nan.abs.nan?  # true
      puts inf.finite?   # false
      p inf.infinite?    # -1

      # Empty string: bytesize 0; ord raises CRuby's ArgumentError
      es = ["", 1][0]
      puts es.bytesize   # 0
      begin
        es.ord
      rescue ArgumentError => ex
        puts "#{ex.class}: #{ex.message}"   # ArgumentError: empty string
      end
    RUBY

    _(result).must_answer <<~'OUT'
      1
      false
      1.5
      1
      2
      2
      1
      false
      true
      false
      true
      nil
      2.5
      -3
      -2
      -3
      -2
      true
      3
      -3
      -3
      false
      false
      true
      nil
      true
      false
      false
      0
      2
      97
      98
      98
      nil
      2
      97
      FloatDomainError: NaN
      FloatDomainError: -Infinity
      true
      false
      -1
      0
      ArgumentError: empty string
    OUT
  end

  it "poly rational arithmetic" do
    result = zr(<<~'RUBY')
      # A polymorphic method whose numeric params unify to poly (called with Integer
      # then Rational) does Rational arithmetic when a Rational operand is present,
      # instead of truncating it through integer division.
      def dv(a, b); a / b; end
      def ad(a, b); a + b; end
      def ml(a, b); a * b; end
      def sb(a, b); a - b; end
      p dv(5, 2); p dv(5, 2r); p dv(6, 2r)
      p ad(1, 2); p ad(1, 2r)
      p ml(3, 4); p ml(3, Rational(1, 2))
      p sb(10, 3); p sb(10, Rational(1, 3))

      # A Rational operand mixed with a Float unifies to Float, matching CRuby --
      # each param also sees a Float call site, so both are boxed poly at runtime.
      ad(2, 1.0); sb(2, 1.0); ml(2, 1.0); dv(2, 1.0)
      p ad(2r, 3.0); p ad(3.0, 2r)
      p sb(2r, 3.0); p ml(2r, 3.0)
      p dv(2r, 3.0); p dv(3.0, 2r)
    RUBY

    _(result).must_answer <<~'OUT'
      2
      (5/2)
      (3/1)
      3
      (3/1)
      12
      (3/2)
      7
      (29/3)
      5.0
      5.0
      -1.0
      6.0
      0.6666666666666666
      1.5
    OUT
  end

  it "poly sign predicate float" do
    result = zr(<<~'RUBY')
      # zero?/positive?/negative? on a POLY receiver must test the number itself, not
      # its integer truncation. A parameter widened to poly by one call site reading an
      # element off a heterogeneous array answered as though every value with |v| < 1
      # were zero: 0.004.zero? came back true and 0.004.positive? false. That poisoned
      # EVERY call site of the widened method, including ones passing a float literal.

      def sign(v) = "#{v.zero?} #{v.positive?} #{v.negative?}"

      # Widens `sign`'s parameter to poly: [Symbol, Float] has a union element type.
      def sign_via(pair) = sign(pair[1])

      puts sign(0.004) # the monomorphic call site is poisoned too
      puts sign_via([:t, 0.004])
      puts sign_via([:t, -0.004])
      puts sign_via([:t, 0.0])
      puts sign_via([:t, 2.5])
      puts sign_via([:t, 7])
      puts sign_via([:t, -7])
      puts sign_via([:t, 0])

      # A bigint reports its own sign rather than a wrapped int64's.
      puts sign_via([:t, 10**30])
      puts sign_via([:t, -(10**30)])

      # A Rational answers from its numerator, exactly: a ratio too small to survive
      # a double would otherwise round to zero and lose its sign.
      puts sign_via([:t, Rational(1, 2)])
      puts sign_via([:t, Rational(0, 5)])
      puts sign_via([:t, Rational(-3, 4)])

      # even?/odd? stay integer predicates - a Float does not answer them in Ruby - so
      # truncation cannot lose a value that legally reaches them.
      def parity(n) = "#{n.even?} #{n.odd?}"
      def parity_via(pair) = parity(pair[1])

      puts parity_via([:n, 4])
      puts parity_via([:n, 7])
    RUBY

    _(result).must_answer <<~'OUT'
      false true false
      false true false
      false false true
      true false false
      false true false
      false true false
      false false true
      true false false
      false true false
      false false true
      false true false
      true false false
      false false true
      true false
      false true
    OUT
  end

  it "poly to c flags" do
    result = zr(<<~'RUBY')
      x = nil
      p(x.to_c)
      p(nil.to_c)
      y = 5
      p(y.to_c)
      z = 1.5
      p(z.to_c)
    RUBY

    _(result).must_answer <<~'OUT'
      (0+0i)
      (0+0i)
      (5+0i)
      (1.5+0i)
    OUT
  end

  it "promote poly overflow" do
    result = zr(<<~'RUBY')
      # A poly-typed integer (a heterogeneous-array element) whose arithmetic
      # overflows int64 auto-promotes to bigint under --int-overflow=promote.
      arr = [4000000000000000000, "x"]
      x = arr[0]
      puts(x * 3)
      puts(x + x + x)
      y = arr[0]
      puts(y * y)
    RUBY

    _(result).must_answer <<~'OUT'
      12000000000000000000
      12000000000000000000
      16000000000000000000000000000000000000
    OUT
  end
end
