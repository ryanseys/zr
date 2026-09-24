# frozen_string_literal: true

require "spec_helper"

describe "Numeric: conversion" do
  it "bignum downto upto to a" do
    result = zr(<<~'RUBY')
      # Bignum#downto / #upto materialized with .to_a (KieranP #2305)
      big = 2 ** 100
      p big.downto(big - 3).to_a
      p big.upto(big + 2).to_a
      p big.downto(big - 2).size
      p big.downto(big + 5).to_a           # descending past the limit -> empty
      p (2 ** 64).upto(2 ** 64 + 1).to_a
    RUBY

    _(result).must_answer <<~'OUT'
      [1267650600228229401496703205376, 1267650600228229401496703205375, 1267650600228229401496703205374, 1267650600228229401496703205373]
      [1267650600228229401496703205376, 1267650600228229401496703205377, 1267650600228229401496703205378]
      3
      []
      [18446744073709551616, 18446744073709551617]
    OUT
  end

  it "bignum query to i" do
    result = zr(<<~'RUBY')
      big = 2 ** 100
      p big.zero?
      p big.positive?
      p big.negative?
      p big.integer?
      p big.class
      p big.succ
      p big.pred
      p((10 ** 30).to_i)
      p((2 ** 100).to_i.class)
      n = 0 - (2 ** 80)
      p n.negative?
      p n.zero?
      p n.positive?
    RUBY

    _(result).must_answer <<~'OUT'
      false
      true
      false
      true
      Integer
      1267650600228229401496703205377
      1267650600228229401496703205375
      1000000000000000000000000000000
      Integer
      true
      false
      false
    OUT
  end

  it "bignum to f" do
    result = zr(<<~'RUBY')
      # Integer#to_f on a value beyond 63 bits. The conversion narrowed the bignum to
      # a low 64-bit limb before the Float cast, so anything past int64 read as 0.0 or
      # garbage. It now folds every limb into the double directly.
      def f(x); x.to_f; end
      p f(2 ** 64)
      p f(10 ** 20)
      p f(1 - 2 ** 70)
      p f(2 ** 100)

      # The receiver is a bignum literal (folds through the same to_f arm).
      p (2 ** 64).to_f
      p (2 ** 70).to_f

      # A bignum flowing through a poly slot (Array element) reaches the poly to_f
      # helper, which had the same narrow-then-widen bug.
      def g(a); a.map { |v| v.to_f }; end
      p g([2 ** 64, 3, 10 ** 25])
    RUBY

    _(result).must_answer <<~'OUT'
      1.8446744073709552e+19
      1.0e+20
      -1.1805916207174113e+21
      1.2676506002282294e+30
      1.8446744073709552e+19
      1.1805916207174113e+21
      [1.8446744073709552e+19, 3.0, 1.0e+25]
    OUT
  end

  it "coerce error value spelling" do
    result = zr(<<~'RUBY')
      # CRuby names the offending value in a coercion TypeError by its CLASS, except
      # nil / true / false, which it spells as themselves. spinel used the class name
      # for all of them, so `[[]].sum {}` reported "NilClass can't be coerced into
      # Integer" where CRuby says "nil can't be coerced into Integer".
      #
      # The two messages disagree about Symbol, and deliberately: "no implicit
      # conversion" names the CLASS, while "can't be coerced" spells the symbol.
      def add(a, b)
        a + b
      end

      [nil, true, false, "x", [1], :s, 1.5, {}].each do |v|
        begin
          add(1, v)
        rescue => e
          puts "#{e.class}: #{e.message}"
        end
      end

      [nil, true, :s].each do |v|
        begin
          add(1.5, v)
        rescue => e
          puts "#{e.class}: #{e.message}"
        end
      end

      # the String and Array receivers take the other message
      [nil, true, :s, 1, [1]].each do |v|
        begin
          add("x", v)
        rescue => e
          puts "#{e.class}: #{e.message}"
        end
      end

      [nil, true, :s, "q"].each do |v|
        begin
          add([1], v)
        rescue => e
          puts "#{e.class}: #{e.message}"
        end
      end

      # which is how a fold over nil block values reports itself
      begin
        p [[]].sum {}
      rescue TypeError => e
        puts e.message
      end
    RUBY

    _(result).must_answer <<~'OUT'
      TypeError: nil can't be coerced into Integer
      TypeError: true can't be coerced into Integer
      TypeError: false can't be coerced into Integer
      TypeError: String can't be coerced into Integer
      TypeError: Array can't be coerced into Integer
      TypeError: :s can't be coerced into Integer
      TypeError: Hash can't be coerced into Integer
      TypeError: nil can't be coerced into Float
      TypeError: true can't be coerced into Float
      TypeError: :s can't be coerced into Float
      TypeError: no implicit conversion of nil into String
      TypeError: no implicit conversion of true into String
      TypeError: no implicit conversion of Symbol into String
      TypeError: no implicit conversion of Integer into String
      TypeError: no implicit conversion of Array into String
      TypeError: no implicit conversion of nil into Array
      TypeError: no implicit conversion of true into Array
      TypeError: no implicit conversion of Symbol into Array
      TypeError: no implicit conversion of String into Array
      nil can't be coerced into Integer
    OUT
  end

  it "coerce factory and explicit call" do
    result = zr(<<~'RUBY')
      # The coerce route emits two calls that have no node of their own: the
      # operator, and #coerce itself. Nothing bound coerce's parameter, so it stayed
      # unknown until a late backstop -- too late to widen the factory it feeds, and
      # `Q.scalar(other)` took an sp_Q* that read a boxed Integer as a pointer
      # (#3497). Where an explicit `m.coerce(4)` did bind it, the two disagreed and
      # the build failed (#3499). Both shapes are here, each in its own class so the
      # other's call sites cannot mask it.
      class Fac
        attr_reader :v

        def initialize(v)
          @v = v
        end

        def self.scalar(v)
          new(v)
        end

        def coerce(other)
          [Fac.scalar(other), self]
        end

        def +(other)
          o = other.is_a?(Fac) ? other : Fac.scalar(other)
          Fac.new(@v + o.v)
        end

        def to_s
          "F(" + @v.to_s + ")"
        end
      end

      # coerce-only: no direct call site to bind anything
      puts (10 + Fac.new(Rational(3, 2))).to_s
      puts (2 + Fac.new(5)).to_s
      puts (1.5 + Fac.new(2.5)).to_s

      class Exp
        attr_reader :v

        def initialize(v)
          @v = v
        end

        def coerce(other)
          [Exp.new(other), self]
        end

        def *(other)
          o = other.is_a?(Exp) ? other : Exp.new(other)
          Exp.new(@v * o.v)
        end

        def to_s
          "E(" + @v.to_s + ")"
        end
      end

      # an explicit coerce call alongside an operator-routed one
      m = Exp.new(3)
      p m.coerce(4).map(&:to_s)
      puts (2 * m).to_s
      puts (m * 2).to_s
    RUBY

    _(result).must_answer <<~'OUT'
      F(23/2)
      F(7)
      F(4.0)
      ["E(4)", "E(3)"]
      E(6)
      E(6)
    OUT
  end

  it "coerce factory param types" do
    result = zr(<<~'RUBY')
      # A class whose #coerce is never reached through a numeric operator in this
      # program still has to type the chain the parameter feeds. `other` holds
      # whatever the numeric protocol hands it, so binding it only where a `3 * obj`
      # call site exists left the slot unknown for the whole fixpoint; a late backstop
      # lifted it to poly after the factory it feeds had already settled on the
      # concrete type, and the build aborted on the argument type.
      class U
        attr_reader :v
        def initialize(v); @v = v; end
        def self.scalar(v); new(v); end
        def coerce(other); [U.scalar(other), self]; end
      end

      u = U.new(Rational(3, 2))
      w = u.v
      p w
      p U.scalar(7).v
      p U.scalar(1.5).v
      p u.coerce(3)[0].v
      p u.coerce(2)[1].v
      p u.coerce("s")[0].v

      # the same with the factory taking the value straight to the constructor
      class V
        attr_reader :v
        def initialize(v); @v = v; end
        def coerce(other); [V.new(other), self]; end
      end

      p V.new(Complex(1, 2)).v
      p V.new(3).coerce(4)[0].v
    RUBY

    _(result).must_answer <<~'OUT'
      (3/2)
      7
      1.5
      3
      (3/2)
      "s"
      (1+2i)
      4
    OUT
  end

  it "coerce non numeric argument" do
    result = zr(<<~'RUBY')
      # `Integer#coerce` / `Float#coerce` raise `Float()`'s own errors.
      #
      # Ruby's `num_coerce` is literally `[Float(y), Float(x)]`, so a failure
      # names the VALUE and `Float` (`can't convert nil into Float`) rather than
      # reporting a coercion failure naming the class and the receiver's type.
      # An INTEGER pair stays integral, which is `rb_int_coerce`'s own rule.
      #
      # The fix closed one more divergence with it: `5.coerce(Rational(1,2))`
      # raised where ruby answers `[0.5, 5.0]`.
      #
      # The original header follows. It describes the PREDECESSOR project's
      # version of this test and its own fix.
      #
      # Integer#coerce / Float#coerce with a non-numeric argument. CRuby answers
      # `[Float(other), Float(self)]`, so the errors are Float()'s: a TypeError for
      # nil / true / an Array / a Symbol, and an ArgumentError for an unparseable
      # String. spinel put the argument straight into the Integer pair's slot, so a
      # String stopped the C BUILD and a nil answered a coerced 0 (#4011).

      [nil, true, false, "x", [1], { a: 1 }, :s].each do |v|
        begin
          p 5.coerce(v)
        rescue => e
          puts "#{v.inspect} => #{e.class}: #{e.message}"
        end
        begin
          p 1.5.coerce(v)
        rescue => e
          puts "1.5 #{v.inspect} => #{e.class}: #{e.message}"
        end
      end

      # the same, written as literals at the call
      begin; p 5.coerce("x"); rescue => e; puts "#{e.class}: #{e.message}"; end
      begin; p 5.coerce([1]); rescue => e; puts "#{e.class}: #{e.message}"; end
      begin; p 5.coerce(nil); rescue => e; puts "#{e.class}: #{e.message}"; end
      begin; p 1.5.coerce(nil); rescue => e; puts "#{e.class}: #{e.message}"; end

      # a parseable String is still a number
      p 5.coerce("2.5")

      # and the numeric pairs are unchanged
      p 5.coerce(2)
      p 5.coerce(2.5)
      p 5.coerce(2**70)
      p 1.5.coerce(3)
      v = [1, 2][1]
      p 5.coerce(v)
    RUBY

    _(result).must_answer <<~'OUT'
      nil => TypeError: can't convert nil into Float
      1.5 nil => TypeError: can't convert nil into Float
      true => TypeError: can't convert true into Float
      1.5 true => TypeError: can't convert true into Float
      false => TypeError: can't convert false into Float
      1.5 false => TypeError: can't convert false into Float
      "x" => ArgumentError: invalid value for Float(): "x"
      1.5 "x" => ArgumentError: invalid value for Float(): "x"
      [1] => TypeError: can't convert Array into Float
      1.5 [1] => TypeError: can't convert Array into Float
      {a: 1} => TypeError: can't convert Hash into Float
      1.5 {a: 1} => TypeError: can't convert Hash into Float
      :s => TypeError: can't convert Symbol into Float
      1.5 :s => TypeError: can't convert Symbol into Float
      ArgumentError: invalid value for Float(): "x"
      TypeError: can't convert Array into Float
      TypeError: can't convert nil into Float
      TypeError: can't convert nil into Float
      [2.5, 5.0]
      [2, 5]
      [2.5, 5.0]
      [1180591620717411303424, 5]
      [3.0, 1.5]
      [2, 5]
    OUT
  end

  it "coerce operator param" do
    result = zr(<<~'RUBY')
      # `3 + q` reaches the user operator through #coerce: Ruby asks q.coerce(3),
      # which answers [Q(3), q], and calls `+` on the first with the SECOND as its
      # argument -- the user object itself. Only the direct call site has a call
      # node, so the parameter settled on Integer and the coerce path read a Q
      # pointer out of the pair as a raw integer: a pointer-sized number that
      # changed between runs (#3491).
      class Q
        attr_reader :value, :units

        def initialize(value, units = {})
          @value = value
          @units = units
        end

        def self.scalar(v)
          new(v, {})
        end

        def coerce(other)
          [Q.scalar(other), self]
        end

        def +(other)
          o = other.is_a?(Q) ? other : Q.scalar(other)
          Q.new(@value + o.value, @units)
        end

        def *(other)
          o = other.is_a?(Q) ? other : Q.scalar(other)
          Q.new(@value * o.value, @units)
        end

        def to_s
          @value.to_s
        end
      end

      def q(value, units = {})
        Q.new(value, units)
      end

      # the direct form and the coerce form, both present
      puts(q(4) + 3)
      puts(3 + q(4))
      puts(q(4) * 3)
      puts(3 * q(4))

      # an instance on both sides still works
      puts(q(4) + q(5))

      # a Float on the left takes the same route
      puts(1.5 + q(4))
    RUBY

    _(result).must_answer <<~'OUT'
      7
      7
      12
      12
      9
      5.5
    OUT
  end

  it "coerce poly operand" do
    result = zr(<<~'RUBY')
      # `5 + obj` runs the numeric coerce protocol from the argument side. The static
      # path takes it when the object's class is known at the call site; an operand
      # that only reads poly (here from a factory whose ternary widens) reached the
      # poly operator and raised "can't be coerced" (#3960).
      class F
        attr_reader :n
        def self.from(value)
          value.is_a?(F) ? value : new(value)
        end
        def initialize(n) = @n = n
        def +(other) = F.new(@n + F.from(other).n)
        def -(other) = F.new(@n - F.from(other).n)
        def *(other) = F.new(@n * F.from(other).n)
        def /(other) = F.new(@n / F.from(other).n)
        def coerce(other) = [F.from(other), self]
        def to_s = @n.to_s
      end

      puts 5 + F.from(3)
      puts 5 - F.from(3)
      puts 5 * F.from(3)
      puts 12 / F.from(3)
      puts 2.5 + F.from(3)
      puts F.from(5) + 3

      # the object on the left keeps its own operator
      puts F.from(5) * F.from(3)

      # a class with no coerce still raises
      class G
        def initialize(n) = @n = n
      end
      begin
        p(1 + G.new(2))
      rescue TypeError => e
        puts e.message
      end
    RUBY

    _(result).must_answer <<~'OUT'
      8
      2
      15
      4
      5.5
      8
      15
      G can't be coerced into Integer
    OUT
  end

  it "coerce result reader local" do
    result = zr(<<~'RUBY')
      # Reading an ivar off a coerce-only operator result and assigning it to a local
      # aborted the C build: the reader was typed from the ivar slot as the analysis
      # had it partway through, while the slot itself finished poly, so the emitted
      # assignment put an sp_RbVal into an sp_Rational local. Rational and Complex are
      # by-value structs, which is why an Integer or Float ivar survived the same
      # shape. The local has to follow the slot it is read out of (#3500).
      class Q
        attr_reader :v
        def initialize(v); @v = v; end
        def self.scalar(v); new(v); end
        def coerce(other); [Q.scalar(other), self]; end
        def *(other); Q.new(@v * other.v); end
      end

      v1 = (2 * Q.new(Rational(3, 2))).v
      p v1
      p v1.class

      # the neighbouring forms that already worked stay working
      p((2 * Q.new(Rational(3, 2))).v)
      q1 = (2 * Q.new(Rational(3, 2)))
      p q1.v
      t = Q.new(Rational(5, 4))
      p t.v
      p (Q.new(Rational(1, 2)) * Q.new(Rational(2, 3))).v

      class C
        attr_reader :v
        def initialize(v); @v = v; end
        def self.scalar(v); new(v); end
        def coerce(other); [C.scalar(other), self]; end
        def *(other); C.new(@v * other.v); end
      end

      v2 = (2 * C.new(Complex(1, 2))).v
      p v2
      p v2.class
      p((2 * C.new(Complex(1, 2))).v)

      # a scalar ivar takes the same route
      class I
        attr_reader :v
        def initialize(v); @v = v; end
        def self.scalar(v); new(v); end
        def coerce(other); [I.scalar(other), self]; end
        def *(other); I.new(@v * other.v); end
      end

      p (2 * I.new(4)).v
      p (2.0 * I.new(2.5)).v

      # and using the widened local afterwards. The read's own node was repointed to
      # poly, but what CONSUMED it still carried the type it was inferred with, so an
      # operator on it lowered to sp_poly_<op> -- whose value is boxed -- while its
      # consumer still expected the exact struct, and the two met at the call.
      w = (2 * Q.new(Rational(3, 2))).v
      p w + 1
      p w - 1
      p w * 2
      p w + Rational(1, 2)
      p w - Rational(1, 2)
      p w * Rational(1, 3)
      p w + 1.5
      p w * 0.5
      p w.class
      p (w + Rational(1, 2)).class
      p (w + 1.5).class

      c = (2 * C.new(Complex(1, 2))).v
      p c + 1
      p c * 2
      p c.class
      p (c + 1).class
    RUBY

    _(result).must_answer <<~'OUT'
      (3/1)
      Rational
      (3/1)
      (3/1)
      (5/4)
      (1/3)
      (2+4i)
      Complex
      (2+4i)
      8
      5.0
      (4/1)
      (2/1)
      (6/1)
      (7/2)
      (5/2)
      (1/1)
      4.5
      1.5
      Rational
      Rational
      Float
      (3+4i)
      (4+8i)
      Complex
      Complex
    OUT
  end

  it "data with poly member coerce" do
    result = zr(<<~'RUBY')
      # A poly (sp_RbVal) value assigned to a CONCRETE record member via Data#with was
      # passed straight into the generated constructor's typed slot (const char* /
      # mrb_int / mrb_float / ...) with no coercion -- a C type error at compile time --
      # even though the regular `.new` call path (emit_arg_or_default) already coerces
      # such an argument. Data#with now applies the same poly->concrete coercion.
      M = Data.define(:entry, :xs)
      m = M.new(entry: "", xs: [])
      msg = [:entry, "hi"]              # a heterogeneous [Symbol, String] array
      p m.with(entry: msg[1]).entry     # msg[1] is the array's union (poly) element

      N = Data.define(:n, :f, :x)
      nn = N.new(n: 0, f: 0.0, x: 0)
      ints = [10, 20]
      flts = [1.5, 2.5]
      p nn.with(n: ints[0]).n           # poly -> Int member
      p nn.with(f: flts[1]).f           # poly -> Float member

      B = Data.define(:flag)
      bb = B.new(flag: false)
      mix = [true, 1]                   # heterogeneous [Bool, Int] -> poly element
      p bb.with(flag: mix[0]).flag      # poly -> Bool member (coerced via sp_poly_truthy)
    RUBY

    _(result).must_answer <<~'OUT'
      "hi"
      10
      2.5
      true
    OUT
  end

  it "float clamp" do
    result = zr(<<~'RUBY')
      def norm(a) = a.to_f.clamp(0.0, 1.0)

      # receiver routed through a method param to exercise the runtime path, not a fold
      def clamp_between(x, lo, hi) = x.clamp(lo, hi)

      puts norm(2.5)
      puts norm(-1.0)
      puts norm(0.5)
      puts norm(1.0)
      puts norm(0.0)
      puts clamp_between(7.25, 1.5, 3.5)
      puts clamp_between(0.25, 1.5, 3.5)
      puts clamp_between(2.5, 1.5, 3.5)
    RUBY

    _(result).must_answer <<~'OUT'
      1.0
      0.0
      0.5
      1.0
      0.0
      3.5
      1.5
      2.5
    OUT
  end

  it "float coerce typeerror" do
    result = zr(<<~'RUBY')
      # Float arithmetic coerces its operand, and a value with no coercion is a
      # TypeError -- the rule Integer already enforced. The Float side had no guard
      # at all: `1.5 + nil` evaluated to nil and `1.5 + "s"` emitted double + char *.
      p((1.5 + nil rescue $!.message))
      p((1.5 + "s" rescue $!.message))
      p((1.5 + :a rescue $!.message))
      p((1.5 + true rescue $!.message))
      p((1.5 + [1] rescue $!.message))
      p((1.5 - nil rescue $!.class))
      p((1.5 * nil rescue $!.class))
      p((1.5 / nil rescue $!.class))
      p(1.5 + 1)
      p(1.5 + 2.5)
      p((1 + nil rescue $!.message))
    RUBY

    _(result).must_answer <<~'OUT'
      "nil can't be coerced into Float"
      "String can't be coerced into Float"
      ":a can't be coerced into Float"
      "true can't be coerced into Float"
      "Array can't be coerced into Float"
      TypeError
      TypeError
      TypeError
      2.5
      4.0
      "nil can't be coerced into Integer"
    OUT
  end

  it "float step to a" do
    result = zr(<<~'RUBY')
      # Float#step without a block materialises into an array.
      # Previously SEGV'd because the call fell through to the
      # unresolved-call int path (emitting 0), then `.to_a` was
      # dispatched on int 0 as if it were a pointer.
      puts 1.0.step(3.0, 0.5).to_a.inspect
      puts 1.0.step(2.0).to_a.inspect

      # Integer#step with int args returns an IntArray.
      puts 1.step(5).to_a.inspect
      puts 1.step(10, 2).to_a.inspect

      # Integer#step with a float step promotes to FloatArray.
      puts 1.step(5, 0.5).to_a.inspect

      # Empty: limit below start with positive step.
      puts 5.0.step(1.0, 1.0).to_a.inspect
      puts 5.step(1).to_a.inspect

      # Block form is unchanged.
      1.0.step(2.0, 0.5) { |x| puts x }
    RUBY

    _(result).must_answer <<~'OUT'
      [1.0, 1.5, 2.0, 2.5, 3.0]
      [1.0, 2.0]
      [1, 2, 3, 4, 5]
      [1, 3, 5, 7, 9]
      [1.0, 1.5, 2.0, 2.5, 3.0, 3.5, 4.0, 4.5, 5.0]
      []
      []
      1.0
      1.5
      2.0
    OUT
  end

  it "float to r" do
    result = zr(<<~'RUBY')
      # Float#to_r (exact) and Float#rationalize(eps) / rationalize.
      # Route the receiver through a param to exercise the runtime path, not a fold.
      def id(x) = x

      # --- to_r: exact rational value of the double ---
      p id(1.5).to_r            # (3/2)
      p id(0.75).to_r           # (3/4)
      p id(2.0).to_r            # (2/1)
      p id(-1.5).to_r           # (-3/2)
      p id(0.0).to_r            # (0/1)
      p id(0.25).to_r           # (1/4)
      p id(-0.125).to_r         # (-1/8)

      # --- rationalize(eps): simplest fraction within eps ---
      p id(0.3).rationalize(0.01)     # (3/10)
      p id(2.5).rationalize(0.1)      # (5/2)
      p id(0.333333).rationalize(0.001) # (1/3)
      p id(-0.3).rationalize(0.01)    # (-3/10)
      p id(3.14159).rationalize(0.001) # simplest within 0.001

      # --- rationalize (no arg): simplest fraction that round-trips ---
      p id(1.5).rationalize     # (3/2)
      p id(0.3).rationalize     # (3/10)

      # --- the result is a Rational and composes with Rational arithmetic ---
      p (id(1.5).to_r + id(0.5).to_r)   # (2/1)
      p id(1.5).to_r.numerator          # 3
      p id(1.5).to_r.denominator        # 2
      p id(0.3).rationalize(0.01).to_f  # 0.3

      # --- literal receivers fold but must agree too ---
      p 1.5.to_r
      p 0.3.rationalize(0.01)
    RUBY

    _(result).must_answer <<~'OUT'
      (3/2)
      (3/4)
      (2/1)
      (-3/2)
      (0/1)
      (1/4)
      (-1/8)
      (3/10)
      (5/2)
      (1/3)
      (-3/10)
      (201/64)
      (3/2)
      (3/10)
      (2/1)
      3
      2
      0.3
      (3/2)
      (3/10)
    OUT
  end

  it "int to enum times" do
    result = zr(<<~'RUBY')
      # Integer#to_enum(:times) / #enum_for(:times) (and String#to_enum(:each_byte))
      # retarget to the blockless builtin form, so .to_a / .map materialize.
      p 3.to_enum(:times).to_a
      p 3.enum_for(:times).to_a
      p 4.to_enum(:times).map { |i| i * 2 }
      p "abc".to_enum(:each_byte).to_a
    RUBY

    _(result).must_answer <<~'OUT'
      [0, 1, 2]
      [0, 1, 2]
      [0, 2, 4, 6]
      [97, 98, 99]
    OUT
  end

  it "integer 0d prefix" do
    result = zr(<<~'RUBY')
      # `0d19` is CRuby's explicit decimal prefix; the parser knew 0x, 0b and 0o but
      # not this one, and rejected the string.
      r001 = (Integer("0d19") rescue $!.class)
      p r001
      r002 = (Integer("0D19") rescue $!.class); p r002
      r003 = (Integer("0d19", 10) rescue $!.class); p r003
      p(Integer("0x1f"))
      p(Integer("0b101"))
      p(Integer("0o17"))
      p(Integer("017"))
      p("0d19".to_i(10))
      p(Integer("0d0"))
      p(Integer(" 0d19 "))
    RUBY

    _(result).must_answer <<~'OUT'
      19
      19
      19
      31
      5
      15
      15
      19
      0
      19
    OUT
  end

  it "integer conversion ducks through to i" do
    result = zr(<<~'RUBY')
      p Integer(Time.at(5))
      p format("%011o", Time.at(0))
      p format("%d", Time.at(42))

      class OnlyToI
        def to_i = 9
      end
      p Integer(OnlyToI.new)
      p format("%d", OnlyToI.new)

      class OnlyToInt
        def to_int = 7
      end
      p format("%d", OnlyToInt.new)

      begin
        Integer(nil)
      rescue TypeError => e
        puts e.message
      end
      begin
        format("%d", Object.new)
      rescue TypeError => e
        puts e.message
      end
      begin
        Integer(false)
      rescue TypeError => e
        puts e.message
      end
    RUBY

    _(result).must_answer <<~'OUT'
      5
      "00000000000"
      "42"
      9
      "9"
      "7"
      can't convert nil into Integer
      can't convert Object into Integer
      can't convert false into Integer
    OUT
  end

  it "integer shift float and coerce" do
    result = zr(<<~'RUBY')
      # Integer#<< / #>> accept a Float count (truncated via to_int); the bitwise
      # &/|/^ and the arithmetic ops with a non-coercible argument raise TypeError.
      p(5 << 2.0)
      p(5 << 2.9)
      p(100 >> 1.9)
      p(10 << 3)
      begin; 5 & 2.0; rescue => e; p e.class; end
      begin; 5 % "x"; rescue => e; p [e.class, e.message]; end
      begin; 5 + "x"; rescue => e; p e.class; end
      begin; 5 * :sym; rescue => e; p e.class; end
      begin; 5 % [1]; rescue => e; p e.class; end
      p(5 % 3)
      p(7 + 2.0)
    RUBY

    _(result).must_answer <<~'OUT'
      20
      20
      50
      80
      TypeError
      [TypeError, "String can't be coerced into Integer"]
      TypeError
      TypeError
      TypeError
      2
      9.0
    OUT
  end

  it "kernel integer float strict nil" do
    result = zr(<<~'RUBY')
      # Kernel#Integer / Kernel#Float are STRICT: nil or a non-numeric object raises
      # TypeError, an unparseable String raises ArgumentError. They must not coerce
      # nil to 0 the way the lenient nil.to_i / nil.to_f do.
      def i(x); Integer(x); end
      def fl(x); Float(x); end

      [nil, :sym, true, [1]].each do |v|
        begin; i(v); rescue => e; puts "#{e.class}: #{e.message}"; end
      end
      begin; i("12abc"); rescue => e; puts "#{e.class}: #{e.message}"; end

      # valid inputs unchanged
      p i(3.9)      # 3 (truncates)
      p i("42")     # 42
      p i(7)        # 7

      [nil, :sym].each do |v|
        begin; fl(v); rescue => e; puts "#{e.class}: #{e.message}"; end
      end
      begin; fl("x"); rescue => e; puts "#{e.class}: #{e.message}"; end

      p fl(5)       # 5.0
      p fl("3.5")   # 3.5

      # lenient nil.to_i / nil.to_f are unaffected (still 0 / 0.0)
      p nil.to_i    # 0
      p nil.to_f    # 0.0
    RUBY

    _(result).must_answer <<~'OUT'
      TypeError: can't convert nil into Integer
      TypeError: can't convert Symbol into Integer
      TypeError: can't convert true into Integer
      TypeError: can't convert Array into Integer
      ArgumentError: invalid value for Integer(): "12abc"
      3
      42
      7
      TypeError: can't convert nil into Float
      TypeError: can't convert Symbol into Float
      ArgumentError: invalid value for Float(): "x"
      5.0
      3.5
      0
      0.0
    OUT
  end

  it "math fn nil typeerror" do
    result = zr(<<~'RUBY')
      # Math.<fn> accepts only a real Numeric: nil, a String, a Symbol, or any other
      # non-numeric argument raises TypeError (Math does not parse strings). Spinel
      # previously coerced nil to 0.0 and a String cast was a C compile error.
      def ms(x); Math.sqrt(x); end

      [nil, :sym, "2", [1]].each do |v|
        begin; ms(v); rescue => e; puts "#{e.class}: #{e.message}"; end
      end

      # valid numeric inputs (Integer and Float) still work across the fn family.
      p Math.sqrt(9)          # 3.0
      p Math.sqrt(2.0)        # 1.4142135623730951
      p Math.log(1.0)         # 0.0
      p Math.hypot(3, 4)      # 5.0
      p Math.log2(8)          # 3.0

      def ml(x); Math.log(x); end
      begin; ml(nil); rescue => e; puts "#{e.class}: #{e.message}"; end
    RUBY

    _(result).must_answer <<~'OUT'
      TypeError: can't convert nil into Float
      TypeError: can't convert Symbol into Float
      TypeError: can't convert String into Float
      TypeError: can't convert Array into Float
      3.0
      1.4142135623730951
      0.0
      5.0
      3.0
      TypeError: can't convert nil into Float
    OUT
  end

  it "a built-in number asks a user object to coerce when the object is the right operand" do
    result = zr(<<~'RUBY')
      # The coerce protocol lets a user numeric type take part in arithmetic even
      # when it is the RIGHT operand of a built-in number. When `5 + obj` finds that
      # `obj` isn't a built-in number, it asks `obj.coerce(5)` for a `[a, b]` pair in
      # the object's own domain, then evaluates `a + b`.
      class Money
        attr_reader :cents
        def initialize(cents)
          @cents = cents
        end

        def coerce(other)
          # Interpret a bare number as whole dollars.
          [Money.new(other * 100), self]
        end

        def +(other)
          Money.new(@cents + other.cents)
        end

        def to_s
          format("$%.2f", @cents / 100.0)
        end
      end

      wallet = Money.new(250)
      puts(wallet + Money.new(100))     # $3.50  -- ordinary dispatch
      puts(5 + wallet)                  # $7.50  -- 5 coerces to $5.00, then + $2.50

      # It works from the Float lane too, and for any operator.
      class Scaled
        attr_reader :value
        def initialize(value)
          @value = value
        end
        def coerce(n)
          [Scaled.new(n), self]
        end
        def *(other)
          Scaled.new(@value * other.value)
        end
        def to_s
          "Scaled(#{@value})"
        end
      end
      puts(3 * Scaled.new(4))           # Scaled(12)
      puts(2.0 * Scaled.new(5.0))       # Scaled(10.0)

      # A non-numeric operand that can't coerce still raises the ordinary TypeError.
      begin
        1 + "nope"
      rescue TypeError => e
        puts e.message                  # String can't be coerced into Integer
      end
    RUBY

    _(result).must_answer <<~'OUT'
      $3.50
      $7.50
      Scaled(12)
      Scaled(10.0)
      String can't be coerced into Integer
    OUT
  end

  it "coerce, ceildiv, i, finite? and div each answer on Integer and on Float" do
    result = zr(<<~'RUBY')
      p 7.coerce(2)
      p 7.coerce(2.0)
      p 7.ceildiv(2)
      p((-7).ceildiv(2))
      p 5.i
      p 10.finite?
      p 10.infinite?
      p 2.0.coerce(3)
      p 7.0.div(2)
      p 5.0.i
      p 1.0.next_float > 1.0
    RUBY

    _(result).must_answer <<~'OUT'
      [2, 7]
      [2.0, 7.0]
      4
      -3
      (0+5i)
      true
      nil
      [3.0, 2.0]
      3
      (0+5.0i)
      true
    OUT
  end

  it "a class that writes coerce and + takes part in 5 + obj" do
    result = zr(<<~'RUBY')
      class Money
        attr_reader :cents
        def initialize(c); @cents = c; end
        def coerce(o); [Money.new(o * 100), self]; end
        def +(o); Money.new(@cents + o.cents); end
        def cents_s; @cents.to_s; end
      end
      puts((5 + Money.new(250)).cents_s)
      puts((2 + 3))
      begin; 1 + "x"; rescue TypeError => e; puts e.message; end
      class Bad; def coerce(o); 42; end; end
      begin; 1 + Bad.new; rescue TypeError; puts "bad"; end
    RUBY

    _(result).must_answer <<~'OUT'
      750
      5
      String can't be coerced into Integer
      bad
    OUT
  end

  it "the Rational and Complex leaf rows and the rect and polar family all answer" do
    result = zr(<<~'RUBY')
      # Rational and Complex leaf methods, plus the Numeric rect/polar family.

      # Rational predicates, coercion, floored division, imaginary lift.
      r = Rational(3, 2)
      puts r.finite?
      p r.infinite?
      p r.coerce(2)
      p r.coerce(2.0)
      p r.div(1)
      p Rational(7, 2).div(2)
      p r.i

      # Complex finiteness, coercion, and the real-projection conversions.
      c = Complex(6, 0)
      puts c.finite?
      p c.infinite?
      p c.to_f
      p c.to_i
      p c.to_r
      p c.coerce(3)
      p Complex(3, 4).finite?
      begin
        Complex(3, 4).to_f
      rescue RangeError => e
        puts e.message
      end

      # numerator/denominator scale both components to a shared denominator.
      p Complex(3, 4).numerator
      p Complex(3, 4).denominator
      p Complex(Rational(2, 3), Rational(3, 4)).numerator
      p Complex(Rational(2, 3), Rational(3, 4)).denominator

      # rect / rectangular / polar are shared by every real Numeric.
      p 5.rect
      p 5.polar
      p((-5).polar)
      p 2.5.polar
      p 5.rationalize
      p Rational(3, 2).polar

      # nil never matches a pattern.
      p(nil =~ /x/)
    RUBY

    _(result).must_answer <<~'OUT'
      true
      nil
      [(2/1), (3/2)]
      [2.0, 1.5]
      1
      1
      (0+(3/2)*i)
      true
      nil
      6.0
      6
      (6/1)
      [(3+0i), (6+0i)]
      true
      can't convert 3+4i into Float
      (3+4i)
      1
      (8+9i)
      12
      [5, 0]
      [5, 0]
      [5, 3.141592653589793]
      [2.5, 0]
      (5/1)
      [(3/2), 0]
      nil
    OUT
  end

  it "a class that writes abs takes over that name's poly dispatch, and an Integer still finds its arm" do
    result = zr(<<~'RUBY')
      # A class defining `abs` (or `round`, `succ`) takes over that name's poly
      # dispatch. An Integer arriving there had no arm, so a boxed ivar holding one
      # raised "undefined method 'abs' for an instance of Integer" -- and where the
      # result was consumed as the user method's type, the builtin arm's boxed answer
      # was read as that object and the program crashed (#4012).
      class Fixed
        attr_reader :units

        def initialize(units) = @units = units
        def abs = Fixed.new(@units.abs)
        def round = Fixed.new(@units.round)
        def succ = Fixed.new(@units.succ)
        def coerce(other) = [Fixed.new(other), self]

        def probe
          p @units.abs
          p @units.round
          p @units.succ
          p @units.ceil
          p @units.floor
          p @units.truncate
        end
      end

      Fixed.new(-1999).probe
      p Fixed.new(-7).abs.units
      p Fixed.new(3).succ.units

      # the user method still wins for its own instances
      f = [Fixed.new(-2)][0]
      p f.abs.units
    RUBY

    _(result).must_answer <<~'OUT'
      1999
      -1999
      -1998
      -1999
      -1999
      -1999
      7
      4
      2
    OUT
  end

  it "step with a zero stride raises, and every non-zero stride walks to its limit" do
    result = zr(<<~'RUBY')
      r001 = (1.step(10, 0) { |i001| break } rescue $!.class); p r001
      r002 = (1.0.step(2.0, 0.0) { |i002| break } rescue $!.class); p r002
      v003 = 1; w003 = 0; r003 = (v003.step(10, w003) { |i003| break } rescue $!.class); p r003
      r004 = (1.step(by: 0, to: 10) { |i004| break } rescue $!.class); p r004
      r005 = (1.step(nil, 0) { |i| break } rescue $!.class); p r005
      p(1.step(10, 3).to_a)
      p(10.step(1, -3).to_a)
      p(1.step(2, 0.25).to_a)
      p(1.step(by: 0.5, to: 3).to_a)
      p((1.step(10, 0).to_a.size rescue $!.class))
      p((1.0.step(2.0, 0.0).to_a.size rescue $!.class))
    RUBY

    _(result).must_answer <<~'OUT'
      ArgumentError
      ArgumentError
      ArgumentError
      ArgumentError
      ArgumentError
      [1, 4, 7, 10]
      [10, 7, 4, 1]
      [1.0, 1.25, 1.5, 1.75, 2.0]
      [1.0, 1.5, 2.0, 2.5, 3.0]
      ArgumentError
      ArgumentError
    OUT
  end

  it "promote xorshift mask" do
    result = zr(<<~'RUBY')
      # The masked-xorshift idiom under --int-overflow=promote: a value past 2^63
      # stays a positive bignum, so `.to_f / 2**64` lands in [0,1) and `>>` shifts a
      # non-negative value -- the stream matches CRuby draw for draw. (#3371)
      #
      # The state array is seeded with a bignum so it is not an INT array: a promoted
      # value stored into an int-typed array is still truncated back to int64, which
      # is a documented promote-mode gap (see docs/limitations.md).
      def xorshift_uniform!(state)
        x = state[0]
        x = x ^ (x << 13)
        x = x & 0xFFFFFFFFFFFFFFFF
        x = x ^ (x >> 7)
        x = x ^ (x << 17)
        x = x & 0xFFFFFFFFFFFFFFFF
        state[0] = x
        (x.to_f / 18446744073709551616.0) + 1.0e-300
      end
      st = [104729, 0xFFFFFFFFFFFFFFFF]
      6.times { puts xorshift_uniform!(st) }
      p st[0]

      # the pieces, on their own: a bignum keeps its width through ^ | & and >>
      x = 17376399848315274067
      p x >> 7
      p x ^ (x >> 7)
      p x | 1
      p x & 0xFFFFFFFF
      p (921264593961460563 << 17)
    RUBY

    _(result).must_answer <<~'OUT'
      6.111756714894084e-06
      0.9619175892199281
      0.853688394252864
      0.8765764863265179
      0.9934991040712747
      0.3127630596712962
      5769460117466749671
      135753123814963078
      17349859343022437589
      17376399848315274067
      301712211
      120751992859716558913536
    OUT
  end

  it "rational coerce user object" do
    result = zr(<<~'RUBY')
      # `Rational(3, 2) * money`, where money defines #coerce, refused to compile at
      # all -- an "unsupported arithmetic" abort that took the whole program down
      # even when the expression sat behind a rescue. The coerce protocol was wired
      # for an Integer or Float on the left only, so Rational and Bignum fell off
      # the end of it (#3489).
      class Money
        attr_reader :cents

        def initialize(cents)
          @cents = cents
        end

        def coerce(other)
          [Money.new(other), self]
        end

        def *(other)
          other = Money.new(other) unless other.is_a?(Money)
          Money.new(@cents * other.cents)
        end

        def +(other)
          other = Money.new(other) unless other.is_a?(Money)
          Money.new(@cents + other.cents)
        end

        def to_s
          "M(#{@cents})"
        end
      end

      m = Money.new(6)
      puts(m * 3)
      puts(3 * m)
      puts(1.5 * m)
      puts(Rational(3, 2) * m)
      puts(Rational(1, 2) + m)
      puts(m + 4)
      puts(4 + m)
    RUBY

    _(result).must_answer <<~'OUT'
      M(18)
      M(18)
      M(9.0)
      M(9/1)
      M(13/2)
      M(10)
      M(10)
    OUT
  end

  it "rational complex numeric leaf methods" do
    result = zr(<<~'RUBY')
      r = Rational(3, 2)
      p r.finite?
      p r.infinite?
      p r.coerce(2)
      p r.coerce(2.0)
      p r.div(1)
      p Rational(7, 2).div(2)
      p r.i
      c = Complex(6, 0)
      p c.finite?
      p c.infinite?
      p c.to_f
      p c.to_i
      p c.to_r
      p c.coerce(3)
      p Complex(3, 4).finite?
      p Complex(3, 4).numerator
      p Complex(3, 4).denominator
      p Complex(Rational(2, 3), Rational(3, 4)).numerator
      p Complex(Rational(2, 3), Rational(3, 4)).denominator
      begin
        Complex(3, 4).to_f
      rescue RangeError => e
        puts e.message
      end
    RUBY

    _(result).must_answer <<~'OUT'
      true
      nil
      [(2/1), (3/2)]
      [2.0, 1.5]
      1
      1
      (0+(3/2)*i)
      true
      nil
      6.0
      6
      (6/1)
      [(3+0i), (6+0i)]
      true
      (3+4i)
      1
      (8+9i)
      12
      can't convert 3+4i into Float
    OUT
  end

  it "rational from sum rounding" do
    result = zr(<<~'RUBY')
      # A Rational that arrives boxed -- the result of Array#sum or reduce(:+) over
      # Rational elements -- answers the rounding surface and converts back through
      # Kernel#Rational like a statically typed one.
      r = [Rational(1, 2), Rational(1, 4)].sum
      p r
      p r.round
      p r.floor
      p r.ceil
      p r.truncate
      p r.round(2)
      p r.to_f
      p r.numerator
      p r.denominator

      p Rational(r, 2)
      p Rational(r)
      p Rational(r, r)

      q = [Rational(3, 2), Rational(1, 2)].reduce(:+)
      p q
      p q.round
      p q.floor

      neg = [Rational(-3, 4), Rational(0, 1)].sum
      p neg.round
      p neg.floor
      p neg.ceil
      p neg.truncate

      vals = [Rational(1, 2), 3, 2.5]
      vals.each { |v| p Rational(v, 2) }
    RUBY

    _(result).must_answer <<~'OUT'
      (3/4)
      1
      0
      1
      0
      (3/4)
      0.75
      3
      4
      (3/8)
      (3/4)
      (1/1)
      (2/1)
      2
      2
      -1
      -1
      0
      0
      (1/4)
      (3/2)
      (5/4)
    OUT
  end

  it "rational to i from sum" do
    result = zr(<<~'RUBY')
      # to_i on a Rational that arrives boxed (from sum / inject) truncates toward
      # zero like the statically typed one.
      r = [Rational(7, 2)].sum
      p r
      p r.to_i
      p r.truncate
      p r.floor
      p r.to_f
      q = [Rational(1, 2), Rational(1, 4)].inject(:+)
      p q
      p q.to_i
      p Rational(-7, 2).to_i
      n = [Rational(-7, 2)].sum
      p n.to_i
    RUBY

    _(result).must_answer <<~'OUT'
      (7/2)
      3
      3
      3
      3.5
      (3/4)
      0
      -3
      -3
    OUT
  end

  it "rationals are exact and oracle faithful" do
    result = zr(<<~'RUBY')
      # Rational: literals, reduction, exact arithmetic across the Int lane,
      # `2 ** -2`, `quo`, Float promotion, rounding family, and the
      # ZeroDivisionError channel.

      r = 3r
      puts r.class
      p r
      puts r
      p 1.5r
      p Rational(4, 8)
      p Rational(1, 2) + Rational(1, 3)
      p Rational(1, 2) * 3
      p Rational(1, 2) / Rational(3, 4)
      p Rational(3, 4) ** 2
      p 2 ** -2
      p 1.quo(3)
      p Rational(1, 2) + 0.5
      puts Rational(1, 2) < Rational(2, 3)
      puts Rational(1, 2) == 0.5
      puts Rational(1, 3).to_f
      puts Rational(7, 2).to_i
      p Rational(-7, 2).floor
      p Rational(-7, 2).ceil
      p Rational(7, 2).round
      p Rational(3, 4).numerator
      p Rational(3, 4).denominator
      begin
        Rational(1, 0)
      rescue ZeroDivisionError => e
        puts "ZeroDivisionError: #{e.message}"
      end
    RUBY

    _(result).must_answer <<~'OUT'
      Rational
      (3/1)
      3/1
      (3/2)
      (1/2)
      (5/6)
      (3/2)
      (2/3)
      (9/16)
      (1/4)
      (1/3)
      1.0
      true
      true
      0.3333333333333333
      3
      -4
      -3
      4
      3
      4
      ZeroDivisionError: divided by 0
    OUT
  end

  it "splat coerces via to a" do
    result = zr(<<~'RUBY')
      # A call-site/yield splat coerces its operand the way ruby does -- `to_a`
      # when it responds (rspec splats its own Set into `register_listener`),
      # wrap otherwise, nil to nothing -- never a bare Array unwrap.
      class MySet
        include Enumerable
        def initialize(items) = @items = items
        def each(&b) = @items.each(&b)
        def to_a = @items.dup
      end
      def takes(*xs) = xs.inspect
      puts takes(*MySet.new([1, 2]))
      puts takes(*3)
      puts takes(*nil)
      def yields
        yield(*MySet.new([4, 5]))
      end
      yields { |a, b| puts "#{a}/#{b}" }
    RUBY

    _(result).must_answer <<~'OUT'
      [1, 2]
      [3]
      []
      4/5
    OUT
  end

  it "user coerce op ivar" do
    result = zr(<<~'RUBY')
      class Vec
        attr_reader :x
        def initialize(x); @x = x; end
        def +(o); Vec.new(x + o.x); end
        def bump(v); @x += v; self; end
        def coerce(n); [Vec.new(n), self]; end
      end
      p((Vec.new(1) + Vec.new(2)).x)
      p(Vec.new(1).bump(5).x)

      class Vec3
        attr_reader :x
        def initialize(x); @x = x; end
        def +(o); Vec3.new(x + o.x); end
        def *(n); Vec3.new(x * n); end
        def <<(v); @x += v; self; end
        def to_proc; ->(n) { n * @x }; end
      end
      p((Vec3.new(1) + Vec3.new(2)).x)
      p((Vec3.new(1) << 2).x)

      class Holder
        def initialize; @v = nil; end
        def set(o); @v = o; self; end
        def add(o); @v += o; self; end
        def v; @v; end
      end
      class Money
        attr_reader :c
        def initialize(c); @c = c; end
        def +(o); Money.new(c + o.c); end
        def to_s; "$#{@c}"; end
      end
      p Holder.new.set(2).add(3).v
      p Holder.new.set(Money.new(2)).add(Money.new(3)).v.to_s
    RUBY

    _(result).must_answer <<~'OUT'
      3
      6
      3
      3
      5
      "$5"
    OUT
  end
end
