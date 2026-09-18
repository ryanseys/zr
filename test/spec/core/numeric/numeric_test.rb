# frozen_string_literal: true

require "spec_helper"

describe "Numeric programs" do
  it "bignum integers promote demote and interoperate" do
    result = ze0(<<~'RUBY')
      # Bignum end-to-end: overflow promotion + demotion round trips, big
      # literals (decimal/hex/binary/underscored), interpolation, hash keys,
      # Enumerable, is_a?, and the i64::MIN / -1 overflow edge.

      r = 1
      i = 2
      while i <= 25
        r = r * i
        i += 1
      end
      puts r
      puts 2 ** 100
      puts 100000000000000000000 + 1
      puts 0xff
      puts 0b1010
      puts 1_000_000
      big = 9_223_372_036_854_775_807
      puts big + 1
      puts big + 1 - 1
      puts (big + 1) > big
      puts (big + 1).class
      puts "v=#{2 ** 70}"
      h = { 2 ** 70 => :big }
      puts h[2 ** 70]
      puts [2 ** 70, 1, 2 ** 65].min
      puts (2 ** 70).is_a?(Numeric)
      puts 2 ** 70 == 2 ** 70
      puts(-9223372036854775808 / -1)
    RUBY

    _(result).must_answer <<~'OUT'
      15511210043330985984000000
      1267650600228229401496703205376
      100000000000000000001
      255
      10
      1000000
      9223372036854775808
      9223372036854775807
      true
      Integer
      v=1180591620717411303424
      big
      1
      true
      true
      9223372036854775808
    OUT
  end

  it "bignum receiver bitwise" do
    result = ze0(<<~'RUBY')
      # Bitwise ops with a bignum receiver (a value > Integer 63-bit) -- the 64-bit
      # unsigned masking idiom used by PRNGs/hashes. The receiver, the mask, and the
      # result can all exceed int64, so they must use arbitrary-precision bitwise,
      # not an int64 round-trip. (#1516)
      MASK64 = (1 << 64) - 1
      puts(1 << 64)                                  # 18446744073709551616
      puts(MASK64)                                   # 18446744073709551615
      a = 0x9e3779b97f4a7c16                         # > int63, a bignum
      puts(a & MASK64)                               # 11400714819323198486
      puts(a & 0xFFFFFFFFFFFFFFFF)                   # same, hex mask
      puts(a | 0xFF)                                 # 11400714819323198719
      puts(a ^ 0xFFFFFFFFFFFFFFFF)                   # 7046029254386353129
      puts(a >> 4)                                   # 712544676207699905
      puts(a << 4 & MASK64)                          # 2545957259850036576

      # SplitMix64: every step is `(x + K) & MASK64`, computed in 64-bit unsigned.
      sm = 0
      out = []
      5.times do
        sm = (sm + 0x9e3779b97f4a7c15) & MASK64
        z = sm
        z = ((z ^ (z >> 30)) * 0xbf58476d1ce4e5b9) & MASK64
        z = ((z ^ (z >> 27)) * 0x94d049bb133111eb) & MASK64
        out << (z ^ (z >> 31))
      end
      puts out.join(",")
    RUBY

    _(result).must_answer <<~'OUT'
      18446744073709551616
      18446744073709551615
      11400714819323198486
      11400714819323198486
      11400714819323198719
      7046029254386353129
      712544676207699905
      16390740445785211232
      16294208416658607535,7960286522194355700,487617019471545679,17909611376780542444,1961750202426094747
    OUT
  end

  it "bitwise operators on integers" do
    result = ze0(<<~'RUBY')
      a = 12
      b = 10
      puts a & b
      puts a | b
      puts a ^ b
      puts a << 2
      puts a >> 2
      puts ~a
    RUBY

    _(result).must_answer <<~'OUT'
      8
      14
      6
      48
      3
      -13
    OUT
  end

  it "case in range pattern covers float poly and open bounds" do
    result = ze0(<<~'RUBY')
      # A range pattern is Range#=== (rb_case_eq/range_covers), so a Float or
      # Poly scrutinee, an exclusive bound, and a beginless/endless range all
      # work -- an as_int_unchecked path would panic on non-Int scrutinees.

      def classify(x)
        case x
        in 0.0...0.5 then "low"
        in 0.5..1.0 then "high"
        in ..0.0 then "neg"
        else "other"
        end
      end
      puts classify(0.2)
      puts classify(0.9)
      puts classify(-1.0)
      puts classify(5.0)
      arr = [3, "x"]
      case arr[0]
      in 0..3 then puts "small"
      else puts "big"
      end
      case arr[1]
      in 0..3 then puts "small"
      else puts "not-int"
      end
    RUBY

    _(result).must_answer <<~'OUT'
      low
      high
      neg
      other
      small
      not-int
    OUT
  end

  it "complex polar constructor" do
    result = ze0(<<~'RUBY')
      p Complex.polar(2, 0)
    RUBY

    _(result).must_answer "(2+0.0i)\n"
  end

  it "complex rational class" do
    result = ze0(<<~'RUBY')
      # .class on Complex/Rational values (variables and literal calls).
      a = Complex(2, 3)
      p a.class
      r = Rational(1, 2)
      p r.class
      p Complex(1,1).class
    RUBY

    _(result).must_answer <<~'OUT'
      Complex
      Rational
      Complex
    OUT
  end

  it "complex rect arg polar" do
    result = ze0(<<~'RUBY')
      # Complex.rect / .rectangular constructors, instance #arg (#angle/#phase),
      # instance #polar and #rect component pairs.
      def a1(c) = c.arg
      def an(c) = c.angle
      def ph(c) = c.phase
      def po(c) = c.polar
      def rc(c) = c.rect

      p Complex.rect(3, 4)          # (3+4i)
      p Complex.rectangular(3, 4)   # (3+4i)
      p Complex.rect(5)             # (5+0i)
      p Complex.rect(1.5, -2.5)     # (1.5-2.5i)
      p a1(Complex(0, 1))           # 1.5707963267948966
      p a1(Complex(1, 0))           # 0.0
      p an(Complex(-1, 0))          # 3.141592653589793
      p ph(Complex(0, -1))          # -1.5707963267948966
      p po(Complex(3, 4))           # [5.0, 0.9272952180016122]
      p po(Complex(0, 2))           # [2, 1.5707963267948966]
      p rc(Complex(1.25, -2.5))     # [1.25, -2.5]
      p rc(Complex(1.25, -2))       # [1.25, -2]
    RUBY

    _(result).must_answer <<~'OUT'
      (3+4i)
      (3+4i)
      (5+0i)
      (1.5-2.5i)
      1.5707963267948966
      0.0
      3.141592653589793
      -1.5707963267948966
      [5.0, 0.9272952180016122]
      [2, 1.5707963267948966]
      [1.25, -2.5]
      [1.25, -2]
    OUT
  end

  it "dir and file mutation round trips" do
    result = ze0(<<~'RUBY')
      # `Dir.mkdir`/`rmdir` round-trip, and `File.rename`/`delete`.

      dir = File.join(ENV.fetch("TMPDIR", "/tmp"), "zeo_e2e_mut_#{Process.pid}")
      Dir.mkdir(dir)
      begin
        fresh = File.join(dir, "fresh")
        Dir.mkdir(fresh)
        p Dir.exist?(fresh)
        Dir.rmdir(fresh)
        p Dir.exist?(fresh)

        a = File.join(dir, "a.txt")
        b = File.join(dir, "b.txt")
        File.write(a, "x")
        File.rename(a, b)
        p [File.exist?(a), File.exist?(b)]
        p File.delete(b)
        p File.exist?(b)
      ensure
        Dir.rmdir(dir)
      end
    RUBY

    _(result).must_answer <<~'OUT'
      true
      false
      [false, true]
      1
      false
    OUT
  end

  it "eval dynamic arithmetic honours precedence" do
    result = ze0(<<~'RUBY')
      code = "1 + 2 * 3"; puts eval(code)
    RUBY

    _(result).must_answer "7\n"
  end

  it "eval value is usable in the surrounding expression" do
    result = ze0(<<~'RUBY')
      a = "6"; b = "7"; puts(eval(a) * eval(b))
    RUBY

    _(result).must_answer "42\n"
  end

  it "float adjacent representable values" do
    result = ze0(<<~'RUBY')
      p 1.0.next_float > 1.0
      p 1.0.prev_float < 1.0
      p 1.0.next_float.prev_float == 1.0
      p 3.14.next_float.class
    RUBY

    _(result).must_answer <<~'OUT'
      true
      true
      true
      Float
    OUT
  end

  it "float limit constants" do
    result = ze0(<<~'RUBY')
      # Issue #1253: Float::MAX / MIN / EPSILON compiled to undeclared C
      # identifiers (Float_MAX) instead of the <float.h> DBL_* macros.
      # Issue #1252: Integer has no public constants in CRuby (it is
      # arbitrary precision), so Integer::MAX must raise NameError, not emit
      # a bare Integer_MAX identifier.
      puts Float::MAX
      puts Float::MIN
      puts Float::EPSILON
      puts(Float::MAX > Float::MIN)
      puts((1.0 + Float::EPSILON) > 1.0)
      imax = Integer::MAX rescue "NameError"
      puts imax
      imin = Integer::MIN rescue "NameError"
      puts imin
    RUBY

    _(result).must_answer <<~'OUT'
      1.7976931348623157e+308
      2.2250738585072014e-308
      2.220446049250313e-16
      true
      true
      NameError
      NameError
    OUT
  end

  it "float numerator denominator on non finite" do
    result = ze0(<<~'RUBY')
      # Infinity/NaN have no rational form, so `numerator` returns the float
      # itself and `denominator` returns 1 -- CRuby never raises here.

      p Float::INFINITY.numerator
      p Float::INFINITY.denominator
      p Float::NAN.numerator
      p((-Float::INFINITY).numerator)
      p 0.5.numerator, 0.5.denominator
    RUBY

    _(result).must_answer <<~'OUT'
      Infinity
      1
      NaN
      -Infinity
      1
      2
    OUT
  end

  it "immediate and numeric subclass" do
    result = ze0(<<~'RUBY')
      # Subclassing immediates and the abstract Numeric (D3).
      #
      # An immediate subclass (Integer/Float/Symbol/NilClass/TrueClass/FalseClass) is
      # a valid DEFINITION but has no instances -- CRuby raises NoMethodError at .new.
      # A Numeric subclass is an ordinary object (user <=>/state, Comparable inherited).

      class MyInt < Integer
      end

      puts MyInt.superclass
      puts MyInt.ancestors.include?(Integer)
      puts MyInt.ancestors.include?(Numeric)
      begin
        MyInt.new
      rescue => e
        puts "#{e.class}: #{e.message}"
      end

      class Money < Numeric
        def initialize(cents)
          @cents = cents
        end

        def cents
          @cents
        end

        def <=>(other)
          cents <=> other.cents
        end
      end

      a = Money.new(500)
      b = Money.new(300)
      puts a.cents
      puts(a > b)
      puts(a < b)
      puts(a == Money.new(500))
      puts a.is_a?(Numeric)
      puts a.is_a?(Comparable)
      puts a.class
      puts [a, b].min.cents
      puts [a, b].max.cents
    RUBY

    _(result).must_answer <<~'OUT'
      Integer
      true
      true
      NoMethodError: undefined method 'new' for class MyInt
      500
      true
      false
      true
      true
      true
      Money
      300
      500
    OUT
  end

  it "implicit self call between sibling class methods dispatches correctly" do
    result = ze0(<<~'RUBY')
      # Found while testing `class << self`: `current_class` is
      # `None` inside a class method's own `Ctx` (no concrete `self` receiver
      # exists there), so a no-receiver call to a SIBLING class method
      # (`def self.a; b; end` calling `def self.b`) always panicked --
      # the compiler's implicit-self call lowering only ever consulted
      # `current_class`. Fixed by also checking `defining_class` against
      # `Compiler::class_method_in_chain`, dispatching as a direct
      # associated-function call, same as `ClassName.foo(...)`.

      class Widget
        def self.create
          helper
        end
        def self.helper
          "made"
        end
      end
      puts Widget.create

      class MathUtils
        class << self
          def sum_of_squares(a, b)
            square(a) + square(b)
          end
          def square(x)
            x * x
          end
        end
      end
      puts MathUtils.sum_of_squares(3, 4)
    RUBY

    _(result).must_answer <<~'OUT'
      made
      25
    OUT
  end

  it "include math bare names" do
    result = ze0(<<~'RUBY')
      # include Math exposes bare functions and PI/E constants.
      include Math
      p sqrt(16)
      p hypot(3, 4)
      p (PI > 3.14 && PI < 3.15)
      p (E > 2.71 && E < 2.72)
    RUBY

    _(result).must_answer <<~'OUT'
      4.0
      5.0
      true
      true
    OUT
  end

  it "int bits bignum mask" do
    result = ze0(<<~'RUBY')
      # Integer#allbits?/#anybits?/#nobits? with a Bignum mask: an int receiver
      # cannot cover a mask that exceeds int64 (allbits? is false); anybits?/nobits?
      # test the mask's low 64 bits.
      a = 14; b = 2 ** 100
      p(a.allbits?(b))
      p(a.anybits?(b))
      p(a.nobits?(b))
      p(a.allbits?(6))
      p(a.anybits?(1))
      p(a.nobits?(1))
      p(255.anybits?(2 ** 64))
      p(255.anybits?(2 ** 64 + 1))
    RUBY

    _(result).must_answer <<~'OUT'
      false
      false
      true
      true
      false
      true
      false
      true
    OUT
  end

  it "int sentinel class nilclass" do
    result = ze0(<<~'RUBY')
      # .class on an int/float slot holding the nil sentinel (a nil-returning
      # <=>, Complex#infinite? on a finite value) reports NilClass, matching
      # how p prints it -- not the slot's static Integer/Float.
      z = Complex(2, 3).infinite?
      p z
      p z.class
    RUBY

    _(result).must_answer <<~'OUT'
      nil
      NilClass
    OUT
  end

  it "integer bit predicates float argument" do
    result = ze0(<<~'RUBY')
      p 42.allbits?(1.5)
      p 42.anybits?(1.5)
      p 42.nobits?(1.5)
    RUBY

    _(result).must_answer <<~'OUT'
      false
      false
      true
    OUT
  end

  it "integer chr" do
    result = ze0(<<~'RUBY')
      # Integer#chr: no argument yields a single byte; an Encoding encodes the
      # codepoint into that encoding.

      # No argument: US-ASCII for 0..127, BINARY for 128..255.
      p 65.chr
      p 65.chr.encoding
      p 0.chr.bytes
      p 200.chr.bytes
      p 200.chr.encoding

      # With an Encoding: UTF-8 encodes multibyte, byte encodings stay one byte.
      p 233.chr(Encoding::UTF_8)
      p 233.chr(Encoding::UTF_8).encoding
      p 0x3042.chr(Encoding::UTF_8)
      p 233.chr(Encoding::ISO_8859_1).bytes
      p 200.chr(Encoding::ASCII_8BIT).bytes

      # Out-of-range codepoints raise RangeError.
      begin; 256.chr; rescue RangeError => e; puts e.message; end
      begin; (-1).chr; rescue RangeError => e; puts e.message; end
      begin; 0x110000.chr(Encoding::UTF_8); rescue RangeError => e; puts e.message; end
      begin; 300.chr(Encoding::ISO_8859_1); rescue RangeError => e; puts e.message; end
    RUBY

    _(result).must_answer <<~'OUT'
      "A"
      #<Encoding:US-ASCII>
      [0]
      [200]
      #<Encoding:BINARY (ASCII-8BIT)>
      "é"
      #<Encoding:UTF-8>
      "あ"
      [233]
      [200]
      256 out of char range
      -1 out of char range
      1114112 out of char range
      300 out of char range
    OUT
  end

  it "integer chr char table" do
    result = ze0(<<~'RUBY')
      # `Integer#chr` allocated a 1-byte string per call -- 64% of a chr loop was
      # malloc, free and the GC sweep walking what they left. The static table that
      # now serves 1-byte slices serves this too, so nothing is allocated.
      #
      # It stays on the PLAIN table, not the BINARY one. spinel does not let a
      # program name an encoding, so nothing but pack and String#b asks for BYTES,
      # and a chr result is not one of those. Tagging it BINARY would have matched
      # CRuby on two more surfaces (255.chr.encoding, 1.chr.inspect) and diverged on
      # two others; leaving it plain changes nothing observable at all.
      #
      # The table entry has a real header, so byte 0 is a 1-byte string here where
      # strlen made it the empty one.

      p 0.chr.length
      p 0.chr.bytesize
      p 0.chr.ord
      p 0.chr.bytes
      p 65.chr
      p 65.chr.length
      p 65.chr.bytes
      p 65.chr.ord
      p 255.chr.bytes
      p 255.chr.bytesize
      p 255.chr.ord
      p 127.chr.ord

      # building with chr
      p 65.chr + 66.chr
      p (65.chr + 66.chr).length
      p [72, 105].map { |c| c.chr }.join
      s = String.new("x")
      s << 65.chr
      p s
      p s.length
      p 65.chr == "A"
      p "abc".include?(97.chr)
      p "abc".index(98.chr)
      p 65.chr.to_sym == :A

      # a chr result is mutable, and mutating a copy must not poison the entry
      p 65.chr.frozen?
      t = 65.chr.dup
      t << "z"
      p t
      p 65.chr
      w = 65.chr.dup
      w.setbyte(0, 66)
      p w
      p 65.chr

      # embedded NUL through concat, the shape #593 is about
      b = 0.chr + 0xc8.chr
      p b.length
      p b.bytesize
      p b[0].ord
      p b[1].ord

      # as Hash keys, and against a literal
      h = {}
      h[65.chr] = 1
      h["A"] = 2
      p h.size
      p [65.chr, "A"].uniq.length

      # the entries are static: a collection must not reach them
      kept = []
      2000.times do |i|
        kept.push((i % 256).chr) if (i % 97).zero?
        raise "bad" unless (i % 256).chr.bytesize == 1
      end
      p kept.length
      p kept.map { |c| c.bytes[0] }.uniq.length
      p 65.chr.bytes
    RUBY

    _(result).must_answer <<~'OUT'
      1
      1
      0
      [0]
      "A"
      1
      [65]
      65
      [255]
      1
      255
      127
      "AB"
      2
      "Hi"
      "xA"
      2
      true
      true
      1
      true
      false
      "Az"
      "A"
      "B"
      "A"
      2
      2
      0
      200
      1
      1
      21
      21
      [65]
    OUT
  end

  it "integer numeric projection" do
    result = ze0(<<~'RUBY')
      p 3.9.to_int
      p((-3.9).to_int)
      p 5.abs2
      p 5.i
      p 5.real
      p 5.imaginary
      p 5.imag
      p 5.rect
      p 5.rectangular
      p 5.polar
      p((-5).polar)
      p 5.arg
      p((-5).arg)
      p 5.angle
      p 5.phase
      p 5.conj
      p 5.conjugate
      p 5.finite?
      p 5.infinite?
      p 5.real?
      p 7.quo(2.0)
      p 10.quo(4.0)
    RUBY

    _(result).must_answer <<~'OUT'
      3
      -3
      25
      (0+5i)
      5
      0
      0
      [5, 0]
      [5, 0]
      [5, 0]
      [5, 3.141592653589793]
      0
      3.141592653589793
      0
      0
      5
      5
      true
      nil
      true
      3.5
      2.5
    OUT
  end

  it "integer rational complex ops" do
    result = ze0(<<~'RUBY')
      # Integer ** Complex (and a complex exponent) evaluate to Complex; Integer#fdiv
      # and #div with a Rational argument are exact. (** with a Rational exponent is
      # a Float by design -- see docs/limitations.md.)
      p(3 ** Complex(0, 1))
      p(2 ** Complex(1, 1))
      p(7.fdiv(2r))
      p(4.fdiv(Rational(1, 2)))
      p(10.div(3r))
    RUBY

    _(result).must_answer <<~'OUT'
      (0.4548324228266097+0.8905770416677471i)
      (1.5384778027279442+1.2779225526272695i)
      3.5
      8.0
      3
    OUT
  end

  it "integer times as expr" do
    result = ze0(<<~'RUBY')
      # Issue #877: Integer#times / #upto / #downto in expression
      # position return self (per MRI). Pre-fix, the expression form
      # emitted 0; the statement form already iterated correctly.
      x = 5.times { }
      puts x
      y = 1.upto(5) { }
      puts y
      z = 5.downto(1) { }
      puts z
    RUBY

    _(result).must_answer <<~'OUT'
      5
      1
      5
    OUT
  end

  it "interp call arg root" do
    result = ze0(<<~'RUBY')
      # Regression for #1498: a module_function whose String return is inferred
      # nilable, called with a string-literal arg from inside a string interpolation
      # that is passed to Regexp.new/compile. The embedded call roots its own arg, and
      # that rooting decl must land as a whole statement before the pattern temp's
      # declaration -- not nested inside its initializer (which emitted illegal C:
      # `const char *_t3 = const char *_t5 = ...`).
      module StringGlob
        module_function
        def regexp_string(s)
          return nil if s.empty?
          s.gsub("*", ".*")
        end
      end

      re1 = Regexp.new("\\A#{StringGlob.regexp_string('*.rb')}\\z")
      puts re1 === 'hello.rb'
      puts re1 === 'hello.txt'

      re2 = Regexp.compile("\\A#{StringGlob.regexp_string('*.txt')}\\z")
      puts re2 === 'notes.txt'
    RUBY

    _(result).must_answer <<~'OUT'
      true
      false
      true
    OUT
  end

  it "interp diverging part" do
    result = ze0(<<~'RUBY')
      # An uninitialized constant inside interpolation compiles to the NameError raise
      # spinel's warning promises -- but the raise closes its expression with a dead
      # placeholder of the node's type, and the arm the interpolation picks comes from
      # the node's INFERRED type. Those disagreed: `(sp_raise_cls(...), (sp_Class){-1})`
      # was handed to sp_poly_to_s (#4092).
      #
      # Anything that diverges is discarded and answers the empty string instead. The
      # raise means nothing reads it.

      module Engine
      end

      def cost
        "cost #{Engine::DEFAULT_COST}"
      end

      def try
        yield
      rescue NameError => e
        e.class
      end

      p try { cost }

      # a reachable interpolation still works, and is not disturbed by the probe that
      # looks for the raise (it emits the value once and hands the text on)
      X = 3
      def fine = "n=#{X} s=#{X.to_s} f=#{1.5} a=#{[1, 2]}"
      p fine

      i = 0
      def bump(n) = n + 1
      s = "#{bump(i)}#{bump(i)}"
      p s
      p i
    RUBY

    _(result).must_answer <<~'OUT'
      NameError
      "n=3 s=3 f=1.5 a=[1, 2]"
      "11"
      0
    OUT
  end

  it "interp method widening" do
    result = ze0(<<~'RUBY')
      # Method called only inside string interpolation should still anchor its
      # parameter type. Pre-fix: scan_features didn't visit EmbeddedStatementsNode
      # bodies, so `cap(name)` inside `"#{...}"` was the only call site for `cap`,
      # its `s` param defaulted to int, and codegen produced a C compile error.

      def cap(s)
        s + "_cap"
      end

      name = "frob"
      puts "lv_#{cap(name)}"

      # Same shape with two args, one of which is also a method call
      def join_with(a, b)
        a + "_" + b
      end

      x = "hello"
      y = "world"
      puts "wrapped(#{join_with(x, y)})"

      # Nested interpolation containing a method call whose param widens to int
      def inc(n)
        n + 1
      end

      puts "next=#{inc(10)}"

      # Method whose param widens to bool via interpolated boolean call
      def bang(p)
        if p
          "YES"
        else
          "no"
        end
      end

      flag = true
      puts "answer: #{bang(flag)}"
    RUBY

    _(result).must_answer <<~'OUT'
      lv_frob_cap
      wrapped(hello_world)
      next=11
      answer: YES
    OUT
  end

  it "interp mixin method" do
    result = ze0(<<~'RUBY')
      # Interpolating a method whose type is known only through the including module:
      # the module method is analyzed with an unknown self, so the call types as
      # unknown; codegen re-resolves it against the class being emitted.
      module Greeting
        def greet; "hi #{name}, you are #{age}"; end   # name -> String, age -> Integer
      end

      class Person
        include Greeting
        def initialize(n, a); @n = n; @a = a; end
        def name; @n; end
        def age; @a; end
      end

      puts Person.new("bob", 42).greet
      puts Person.new("amy", 7).greet
    RUBY

    _(result).must_answer <<~'OUT'
      hi bob, you are 42
      hi amy, you are 7
    OUT
  end

  it "interp single buffer" do
    result = ze0(<<~'RUBY')
      x = 42
      y = -7
      name = "matz"
      p "#{x}-#{y}"
      p "hello #{name}!"
      p "#{x}"
      p "a" "b"
      f = 3.14
      p "f=#{f}"
      b = true
      p "b=#{b} nb=#{false}"
      s = nil
      p "nil=[#{s}]"
      sym = :ok
      p "sym=#{sym}"
      arr = [1, "two"]
      p "arr=#{arr}"
      big = -9223372036854775807
      p "big=#{big}"
      p "multi #{x} and #{name} and #{f} end"
      p "tab\t nl\n q\" bs\\ pct% #{x}"
      h = { a: 1 }
      p "h=#{h}"
      p "#{ z = x + 1; z }"
      vals = [0.0, -0.0, 1.0, -1.0, 2.5, -2.5, 0.1, 1.0/3.0, 999999999999999.0,
              1e15, -1e15, 1e16, 123456789.0, 3.14159, 1e-5, 0.0001, 1.5e20,
              -999999999999999.0, 42.0, 100.0]
      vals.each { |v| puts v.to_s; puts "i=#{v}" }
      puts (0.1 + 0.2).to_s
    RUBY

    _(result).must_answer <<~'OUT'
      "42--7"
      "hello matz!"
      "42"
      "ab"
      "f=3.14"
      "b=true nb=false"
      "nil=[]"
      "sym=ok"
      "arr=[1, \"two\"]"
      "big=-9223372036854775807"
      "multi 42 and matz and 3.14 end"
      "tab\t nl\n q\" bs\\ pct% 42"
      "h={a: 1}"
      "43"
      0.0
      i=0.0
      -0.0
      i=-0.0
      1.0
      i=1.0
      -1.0
      i=-1.0
      2.5
      i=2.5
      -2.5
      i=-2.5
      0.1
      i=0.1
      0.3333333333333333
      i=0.3333333333333333
      999999999999999.0
      i=999999999999999.0
      1.0e+15
      i=1.0e+15
      -1.0e+15
      i=-1.0e+15
      1.0e+16
      i=1.0e+16
      123456789.0
      i=123456789.0
      3.14159
      i=3.14159
      1.0e-05
      i=1.0e-05
      0.0001
      i=0.0001
      1.5e+20
      i=1.5e+20
      -999999999999999.0
      i=-999999999999999.0
      42.0
      i=42.0
      100.0
      i=100.0
      0.30000000000000004
    OUT
  end

  it "introspection constant path" do
    result = ze0(<<~'RUBY')
      # `is_a?` / `kind_of?` / `instance_of?` with a qualified-constant
      # argument (ConstantPathNode like `Mod::Klass`). The dynamic-arg
      # branch in compile_introspection_expr previously excluded only the
      # bare ConstantReadNode shape; a qualified constant fell through and
      # emitted compile_expr(arg) as a bare C identifier with no declaration,
      # producing "use of undeclared identifier" at C compile time. The
      # is_a? branch also didn't route kind_of? or instance_of? through
      # the same static collapse, so those names silently fell through to
      # warn_unresolved_call. Fix: resolve the constant name via the path
      # walker, and dispatch the whole introspection family uniformly.
      #
      # Coverage:
      # - Same-class match (is_a?/kind_of?/instance_of? all true)
      # - Unrelated-sibling mismatch (all false)
      # - Ancestor case (is_a?/kind_of? true; instance_of? false, exact only)
      # - Deeper constant path (Mod::Sub::Deep — three-level path walk)
      #
      # Out of scope for this PR:
      # - Class-as-local (`k = Mod::Klass; obj.is_a?(k)`) emits the const
      #   name as a bare C identifier — a separate ConstantPathNode-to-local
      #   assignment bug, distinct from the introspection-arg fix here.
      # - Built-in ancestor (`obj.is_a?(Object)`) returns false in spinel
      #   today; spinel's class registry doesn't materialize Object as an
      #   ancestor of user classes. Separate gap.

      module Mod
        class Base
          def base_name; "base"; end
        end
        class Klass < Base
          def initialize(v); @v = v; end
          def get; @v; end
        end
        class Other
          def initialize(v); @v = v; end
        end
        module Sub
          class Deep
            def initialize(v); @v = v; end
            def get; @v; end
          end
        end
      end

      k = Mod::Klass.new(7)
      puts k.is_a?(Mod::Klass)
      puts k.kind_of?(Mod::Klass)
      puts k.instance_of?(Mod::Klass)
      puts k.is_a?(Mod::Other)
      puts k.instance_of?(Mod::Other)
      puts k.is_a?(Mod::Base)
      puts k.kind_of?(Mod::Base)
      puts k.instance_of?(Mod::Base)
      puts k.get

      d = Mod::Sub::Deep.new(42)
      puts d.is_a?(Mod::Sub::Deep)
      puts d.kind_of?(Mod::Sub::Deep)
      puts d.instance_of?(Mod::Sub::Deep)
      puts d.get
    RUBY

    _(result).must_answer <<~'OUT'
      true
      true
      true
      false
      false
      true
      true
      false
      7
      true
      true
      true
      42
    OUT
  end

  it "kernel complex" do
    result = ze0(<<~'RUBY')
      # Kernel#Complex(re, im) builds a Complex value (imaginary part defaults
      # to 0). Previously the no-receiver Complex() call fell through to the
      # integer 0 fallback.
      p Complex(2, 3)
      p Complex(1)
      p Complex(2.5, -1.5)
      p Complex(0, 1)
      p(Complex(1, 2) + Complex(3, 4))
      p(Complex(2, 3) * Complex(1, 1))
    RUBY

    _(result).must_answer <<~'OUT'
      (2+3i)
      (1+0i)
      (2.5-1.5i)
      (0+1i)
      (4+6i)
      (-1+5i)
    OUT
  end

  it "kernel integer float convert" do
    result = ze0(<<~'RUBY')
      # GAP -- imported from the spinel corpus at c55d9bdb.
      # Integer() with a Hash argument raises instead of answering nil under
      # exception: false.
      #
      # Kernel#Integer / #Float: `exception: false` asks for nil rather than a raise,
      # and the keyword hash is not one of the value arguments (passed through as one
      # it landed in the base slot as a pointer). A value with no integer conversion
      # is a TypeError, not the value reinterpreted.
      p(Integer("abc", exception: false))
      p(Integer("12", exception: false))
      p(Integer("ff", 16, exception: false))
      p(Integer("zz", 16, exception: false))
      p(Float("abc", exception: false))
      p(Float("1.5", exception: false))
      p((Integer([1]) rescue $!.class))
      p((Integer({ a: 1 }) rescue $!.class))
      p((Integer(:s) rescue $!.class))
      p((Integer(nil) rescue $!.class))

      # the strict forms keep their behaviour
      p(Integer("0x1f", 16))
      p(Integer(" 42 "))
      p((Integer("abc") rescue $!.class))
      p(Float("1.5"))
      p((Float("x") rescue $!.class))
      p(Integer(3.9))
    RUBY

    _(result).must_answer <<~'OUT'
      nil
      12
      255
      nil
      nil
      1.5
      TypeError
      TypeError
      TypeError
      TypeError
      31
      42
      ArgumentError
      1.5
      ArgumentError
      3
    OUT
  end

  it "math constants and kernel conversions" do
    result = ze0(<<~'RUBY')
      # Math module functions + Math::DomainError + the Float constants, and
      # the Kernel conversion functions with CRuby's exact failure shapes.

      puts Math::PI
      puts Math::E
      puts Math.sqrt(16)
      puts Math.sqrt(2)
      puts Math.cbrt(27)
      puts Math.log2(8)
      puts Math.log(Math::E)
      puts Math.log(8, 2)
      puts Math.hypot(3, 4)
      puts Math.atan2(1, 1)
      begin
        Math.sqrt(-1)
      rescue Math::DomainError => e
        puts "Math::DomainError: #{e.message}"
      end
      puts Float::INFINITY
      puts Float::EPSILON
      puts Float::MAX
      puts Float::DIG
      puts Float::RADIX
      puts Integer("42")
      puts Integer("ff", 16)
      puts Integer("0x1A")
      puts Integer(" -4_2 ")
      puts Integer(3.9)
      puts Float("1.5e3")
      puts Float(2)
      puts String(42)
      puts Array(nil).inspect
      puts Array(1..3).inspect
      puts Array(5).inspect
      puts Hash(nil).inspect
      p Rational(3, 4)
      p Complex(1, 2)
      begin
        Integer("nope")
      rescue ArgumentError => e
        puts "ArgumentError: #{e.message}"
      end
      begin
        Integer(nil)
      rescue TypeError => e
        puts "TypeError: #{e.message}"
      end
      begin
        Float("x")
      rescue ArgumentError => e
        puts "ArgumentError: #{e.message}"
      end
    RUBY

    _(result).must_answer <<~'OUT'
      3.141592653589793
      2.718281828459045
      4.0
      1.4142135623730951
      3.0
      3.0
      1.0
      3.0
      5.0
      0.7853981633974483
      Math::DomainError: Numerical argument is out of domain - sqrt
      Infinity
      2.220446049250313e-16
      1.7976931348623157e+308
      15
      2
      42
      255
      26
      -42
      3
      1500.0
      2.0
      42
      []
      [1, 2, 3]
      [5]
      {}
      (3/4)
      (1+2i)
      ArgumentError: invalid value for Integer(): "nope"
      TypeError: can't convert nil into Integer
      ArgumentError: invalid value for Float(): "x"
    OUT
  end

  it "negative zero phase" do
    result = ze0(<<~'RUBY')
      p (-0.0).angle
      p (-0.0).arg
      p (-0.0).phase
      p (-0.0).polar
      p (0.0).phase
    RUBY

    _(result).must_answer <<~'OUT'
      3.141592653589793
      3.141592653589793
      3.141592653589793
      [0.0, 3.141592653589793]
      0
    OUT
  end

  it "nil rationalize variable" do
    result = ze0(<<~'RUBY')
      # NilClass#rationalize (and #to_r) return (0/1), including when the nil is
      # held in a variable (a nil-only local widens to a boxed poly value).
      r = nil
      p(r.rationalize)
      p(r.to_r)
      p(nil.rationalize)
    RUBY

    _(result).must_answer <<~'OUT'
      (0/1)
      (0/1)
      (0/1)
    OUT
  end

  it "nil to r rational" do
    result = ze0(<<~'RUBY')
      # NilClass#to_r returns Rational(0, 1), not float zero.
      p nil.to_r                       # (0/1)
      p nil.to_r == Rational(0, 1)     # true
      p nil.to_r + Rational(1, 2)      # (1/2)
    RUBY

    _(result).must_answer <<~'OUT'
      (0/1)
      true
      (1/2)
    OUT
  end

  it "numeric exactness" do
    result = ze0(<<~'RUBY')
      # Numeric-tower exactness: Integer#size, Float#rationalize, Rational/Complex.

      # Integer#size: 8 bytes up to a machine word, then the magnitude byte-width.
      p 42.size
      p (2**64).size
      p (2**64 - 1).size
      p (2**128).size

      # Float#rationalize finds the simplest rational rounding back to the double.
      p 0.3.rationalize
      p 0.1.rationalize
      p 2.5.rationalize
      p 3.14159.rationalize
      p(-0.75.rationalize)
      p 1.333.rationalize(0.01)

      # Rational(Float) keeps the exact dyadic value.
      p Rational(2.5)
      p Rational(0.3)
      p Rational(1.5, 0.5)

      # Complex construction, projection, and general exponentiation.
      begin
        Complex(nil)
      rescue TypeError => e
        puts e.message
      end
      p 2 ** Complex(0, 1)
      p Complex(2, 0) ** Complex(1, 1)
      p Complex(6, 0).to_r
      p Complex(3, 4).numerator

      # Integer#div with a Rational divisor stays exact (floored).
      p 7.div(Rational(2))
      p 10.div(Rational(3, 2))
    RUBY

    _(result).must_answer <<~'OUT'
      8
      9
      8
      17
      (3/10)
      (1/10)
      (5/2)
      (314159/100000)
      (-3/4)
      (4/3)
      (5/2)
      (5404319552844595/18014398509481984)
      (3/1)
      can't convert nil into Complex
      (0.7692389013639721+0.6389612763136348i)
      (1.5384778027279442+1.2779225526272695i)
      (6/1)
      (3+4i)
      3
      6
    OUT
  end

  it "numeric ranges bignum hexfloat" do
    result = ze0(<<~'RUBY')
      # Range, Integer iteration, and Float() long-tail behaviors.

      # A Symbol range iterates by name succession, yielding Symbols.
      p (:a..:e).to_a
      p (:a...:d).to_a
      p (:aa..:ac).to_a

      # A Float range has O(1) min/max endpoints (it can't be iterated), a
      # drift-free step (1.0 lands exactly), and a float bsearch that converges on a
      # representable boundary. Iterating one (each/to_a) raises, naming the element
      # type; an exclusive float max has no maximum element.
      r = (1.0..3.0)
      p r.min
      p r.max
      p r.step(0.5).to_a
      p (0.0..1.0).step(0.1).to_a
      p (0.0..10.0).bsearch { |x| x >= 3.5 }
      p(begin; r.to_a; rescue => e; "#{e.class}: #{e.message}"; end)
      p(begin; (1.0...3.0).max; rescue => e; "#{e.class}: #{e.message}"; end)

      # Range#step with a negative step walks a descending range.
      p (10..2).step(-2).to_a
      p (10...1).step(-1).to_a

      # Integer#downto / #upto iterate as BigInt when the values exceed i64 (the span
      # is small), and the enumerator's size is exact. A Float limit yields integers.
      big = 2 ** 100
      p big.downto(big - 3).to_a
      p big.upto(big + 2).to_a
      p big.downto(big - 2).size
      p 5.downto(2.0).to_a

      # Float() parses C99 hex-float strings (the binary exponent is optional).
      p Float("0x1p4")
      p Float("0x1.8p1")
      p Float("0xa")
      p Float("-0x1p4")
    RUBY

    _(result).must_answer <<~'OUT'
      [:a, :b, :c, :d, :e]
      [:a, :b, :c]
      [:aa, :ab, :ac]
      1.0
      3.0
      [1.0, 1.5, 2.0, 2.5, 3.0]
      [0.0, 0.1, 0.2, 0.30000000000000004, 0.4, 0.5, 0.6000000000000001, 0.7000000000000001, 0.8, 0.9, 1.0]
      3.5
      "TypeError: can't iterate from Float"
      "TypeError: cannot exclude non Integer end value"
      [10, 8, 6, 4, 2]
      [10, 9, 8, 7, 6, 5, 4, 3, 2]
      [1267650600228229401496703205376, 1267650600228229401496703205375, 1267650600228229401496703205374, 1267650600228229401496703205373]
      [1267650600228229401496703205376, 1267650600228229401496703205377, 1267650600228229401496703205378]
      3
      [5, 4, 3, 2]
      16.0
      3.0
      10.0
      -16.0
    OUT
  end

  it "numeric step accepts by and to keywords" do
    result = ze0(<<~'RUBY')
      1.step(by: 2, to: 10) { |i| print i, " " }
      puts
      1.step(10, 2) { |i| print i, " " }
      puts
      1.step(to: 5) { |i| print i, " " }
      puts
      10.step(by: -3, to: 1) { |i| print i, " " }
      puts
    RUBY

    _(result).must_answer "1 3 5 7 9 \n1 3 5 7 9 \n1 2 3 4 5 \n10 7 4 1 \n"
  end

  it "numeric step keywords" do
    result = ze0(<<~'RUBY')
      # Numeric#step accepts positional (limit, step) and/or keyword (by:, to:) forms.
      1.step(by: 2, to: 9) { |i| print i, " " }
      puts

      1.step(9, 2) { |i| print i, " " }
      puts

      1.step(to: 5) { |i| print i, " " }
      puts

      10.step(by: -3, to: 1) { |i| print i, " " }
      puts

      # Float step moves the whole iteration into the Float domain.
      1.step(2.0, 0.5) { |i| print i, " " }
      puts

      # Positional limit with a keyword step.
      0.step(10, by: 5) { |i| print i, " " }
      puts
    RUBY

    _(result).must_answer "1 3 5 7 9 \n1 3 5 7 9 \n1 2 3 4 5 \n10 7 4 1 \n1.0 1.5 2.0 \n0 5 10 \n"
  end

  it "numeric subclass defaults" do
    result = ze0(<<~'RUBY')
      # `Numeric`'s generic implementations -- the ones a user subclass inherits.
      # They know nothing but `<=>`, `-`, `/`, `*`, `to_f`, `to_i`, `to_r` and
      # `coerce`, so a class that defines only those gets the rest for free. Every
      # concrete numeric class carries its own faster row for each, which the
      # ancestor walk finds first, so none of this changes what `Integer` answers.

      class Deg < Numeric
        attr_reader :v

        def initialize(v) = @v = v
        def <=>(o) = v <=> (o.is_a?(Deg) ? o.v : o)
        def +(o) = Deg.new(v + (o.is_a?(Deg) ? o.v : o))
        def -(o) = Deg.new(v - (o.is_a?(Deg) ? o.v : o))
        def *(o) = Deg.new(v * (o.is_a?(Deg) ? o.v : o))
        def /(o) = Deg.new(v / (o.is_a?(Deg) ? o.v : o))
        def to_f = v.to_f
        def to_i = v.to_i
        def to_r = Rational(v)
        def coerce(o) = [Deg.new(o), self]
        def inspect = "Deg(#{v})"
      end

      puts "-- sign, through <=> and coerce"
      p Deg.new(-7).abs
      p Deg.new(-7).magnitude
      p Deg.new(7).abs
      p(+Deg.new(-7))
      p(-Deg.new(-7))
      p(-Deg.new(7))

      puts "-- floored division and its remainder"
      p Deg.new(7).div(Deg.new(2))
      p Deg.new(7).modulo(Deg.new(2))
      p Deg.new(7) % Deg.new(2)

      puts "-- the rounding family, all via Float(self)"
      p Deg.new(7.6).round
      p Deg.new(7.6).round(1)
      p Deg.new(7.6).ceil
      p Deg.new(7.6).floor
      p Deg.new(7.6).truncate
      p Deg.new(-7.6).truncate

      puts "-- conversions"
      p Deg.new(7).to_int
      p Deg.new(7).numerator
      p Deg.new(7).denominator
      p Deg.new(7).finite?
      p Deg.new(7).infinite?

      puts "-- the fallback coerce, for a subclass that defines none"
      class Plain < Numeric
        def initialize(v) = @v = v
        def to_f = @v.to_f
        def inspect = "Plain"
      end
      p Plain.new(1).coerce(Plain.new(2))
      p Plain.new(1).coerce(3)

      puts "-- Kernel#Float goes through to_f for any object that has one"
      class Convertible
        def to_f = 1.5
      end
      p Float(Convertible.new)
      p Plain.new(2).floor
      begin
        Float(Object.new)
      rescue TypeError => e
        p e.message
      end

      puts "-- Numeric refuses a singleton class"
      p Numeric.method_defined?(:singleton_method_added)

      puts "-- Complex undefines every one that needs an ordering"
      c = Complex(1, 2)
      %i[% < <= > >= between? ceil clamp div divmod floor i modulo
         negative? positive? remainder round step truncate].each do |m|
        print c.respond_to?(m) ? "#{m}! " : ""
      end
      puts "(none)"
      p(begin
        c.positive?
      rescue NoMethodError
        :no_method_error
      end)

      puts "-- and the concrete classes still answer for themselves"
      p 5.coerce(2.0)
      p(-5.abs)
      p 7.div(2)
      p 7.modulo(2)
      p 2.5.round
      p 5.numerator, 5.denominator
      p Rational(1, 2).positive?
      p 5.finite?, (1.0 / 0).infinite?
    RUBY

    _(result).must_answer <<~'OUT'
      -- sign, through <=> and coerce
      Deg(7)
      Deg(7)
      Deg(7)
      Deg(-7)
      Deg(7)
      Deg(-7)
      -- floored division and its remainder
      3
      Deg(1)
      Deg(1)
      -- the rounding family, all via Float(self)
      8
      7.6
      8
      7
      7
      -7
      -- conversions
      7
      7
      1
      true
      nil
      -- the fallback coerce, for a subclass that defines none
      [Plain, Plain]
      [3.0, 1.0]
      -- Kernel#Float goes through to_f for any object that has one
      1.5
      2
      "can't convert Object into Float"
      -- Numeric refuses a singleton class
      true
      -- Complex undefines every one that needs an ordering
      (none)
      :no_method_error
      -- and the concrete classes still answer for themselves
      [2.0, 5.0]
      5
      3
      1
      3
      5
      1
      true
      true
      1
    OUT
  end

  it "numeric subclass is a plain comparable object" do
    result = ze0(<<~'RUBY')
      # A `Numeric` subclass (D3) is an ordinary ivar-carrying object: it defines its
      # own `<=>`/state, and `Comparable` (inherited through `Numeric`) drives
      # `<`/`>`/`min` off that `<=>`.

      class Money < Numeric
        def initialize(cents); @cents = cents; end
        def cents; @cents; end
        def <=>(o); cents <=> o.cents; end
      end
      m = Money.new(500)
      n = Money.new(300)
      puts m.cents
      puts(m > n)
      puts(m == Money.new(500))
      puts m.is_a?(Numeric)
      puts m.is_a?(Comparable)
      puts m.class
      puts [m, n].min.cents
    RUBY

    _(result).must_answer <<~'OUT'
      500
      true
      true
      true
      true
      Money
      300
    OUT
  end

  it "numeric subclass limits" do
    result = ze0(<<~'RUBY')
      # WAITING ON `builtin_frames_in_a_backtrace`. Complex now holds a user
      # `Numeric` subclass and dispatches every component operation, so this file
      # raises ruby's ArgumentError from ruby's line with ruby's message -- what is
      # left is the three C frames under it. zeo's native rows push no frame, so
      # `Comparable#<`, `Complex#inspect` and `Kernel#p` are all missing from the
      # trace. Promote this the moment that gap closes; nothing here needs Complex
      # work any more.
      #
      # The original cause: `Numeric#i` builds `Complex(0, self)`, and zeo's Complex
      # held only its own numeric lanes, so a user subclass got a TypeError where
      # ruby builds `(0+Deg(7)*i)`.
      #
      # This file used to record a second, unrelated limit -- that nothing called
      # `Numeric#singleton_method_added`, so `def n.foo` on a number succeeded where
      # ruby refuses. The definition hooks now fire; see
      # `tests/definition_hooks_at_runtime.rb`.

      class Deg < Numeric
        def initialize(v) = @v = v
        def to_f = @v.to_f
        def inspect = "Deg"
      end

      n = Deg.new(7)

      begin
        p n.i
      rescue TypeError => e
        puts "i: #{e.message}"
      end
    RUBY

    _(result).must_answer "", stderr: "core/numeric/numeric_test.rb:27:in 'Comparable#<': comparison of Deg with 0 failed (ArgumentError)\n\n  p n.i\n    ^^^\n\tfrom core/numeric/numeric_test.rb:27:in 'Complex#inspect'\n\tfrom core/numeric/numeric_test.rb:27:in 'Kernel#p'\n\tfrom core/numeric/numeric_test.rb:27:in '<main>'\n", status: 1
  end

  it "polyarray insert delete at" do
    result = ze0(<<~'RUBY')
      # Array#insert / #delete_at on a poly array (heterogeneous elements): insert
      # shifts boxed slots and boxes the inserted value; delete_at returns the
      # removed element.
      arr = [1, "two"]
      arr.insert(1, :mid)
      p arr.size
      p arr[1]
      removed = arr.delete_at(0)
      p removed
      p arr.size
      arr.insert(-1, 9.5)
      p arr[arr.size - 1]
      # boxed (TY_POLY) index: a poly-array element read must unbox to mrb_int, not
      # pass an sp_RbVal into the mrb_int slot.
      idxs = [0, "x"]
      arr.insert(idxs[0], :head)
      p arr[0]
    RUBY

    _(result).must_answer <<~'OUT'
      3
      :mid
      1
      2
      9.5
      :head
    OUT
  end

  it "rational i to complex" do
    result = ze0(<<~'RUBY')
      # Rational#i -> Complex(0, self). spinel's Complex is float-backed, so the
      # imaginary part renders as a Float where CRuby keeps the exact Rational
      # (docs/limitations.md "Rational precision and Complex components").
      p(Rational(3, 4).i)      # (0+0.75i)   CRuby: (0+(3/4)*i)
      p(Rational(-1, 2).i)     # (0-0.5i)    CRuby: (0-(1/2)*i)
      p(Rational(2, 1).i)      # (0+2.0i)    CRuby: (0+(2/1)*i)

      r = Rational(3, 4)
      c = r.i
      p c.class                # Complex
      p c.real                 # 0   -- the real part is exact
      p c.imaginary            # 0.75  CRuby: (3/4)
      # the VALUE is right even though the component class is not
      p c.imaginary == 0.75
      p c.abs2 == 0.5625
    RUBY

    _(result).must_answer <<~'OUT'
      (0+(3/4)*i)
      (0-(1/2)*i)
      (0+(2/1)*i)
      Complex
      0
      (3/4)
      true
      true
    OUT
  end

  it "reduce numeric promotion" do
    result = ze0(<<~'RUBY')
      # A fold accumulator seeded with an int but reassigned to a float each
      # iteration must accumulate float, not truncate. The seed type alone used to
      # fix both the reduce return type and the C accumulator type, so an int seed
      # folded over floats silently truncated (`[1.5,2.5].reduce(0)` -> 3, not 4.0).

      # int seed, float elements -> float fold
      p [1.5, 2.5].reduce(0) { |a, x| a + x }
      # 4.0

      p [1.5, 2.5, 3.0].inject(0) { |a, x| a + x }
      # 7.0

      # float seed, int elements -> float fold
      p [1, 2, 3].reduce(0.0) { |a, x| a + x }
      # 6.0

      # int seed, int elements -> stays int (no spurious promotion)
      p [1, 2, 3].reduce(0) { |a, x| a + x }
      # 6

      p [1, 2, 3].reduce(10) { |a, x| a * x }
      # 60

      # int seed, string elements, int body (x.length) -> stays int
      p ["a", "bb", "ccc"].reduce(0) { |a, x| a + x.length }
      # 6

      # int seed promoted to float via an explicit conversion in the body
      p [1, 2, 3].reduce(0) { |a, x| a + x.to_f }
      # 6.0

      # the chained-map fold from the sibling-collision report
      puts([1, 2, 3].map { |x| x + 0.5 }.map { |x| x.floor }.reduce(0) { |a, x| a + x })
      # 6
    RUBY

    _(result).must_answer <<~'OUT'
      4.0
      7.0
      6.0
      6
      60
      6
      6.0
      6
    OUT
  end

  it "sort by rational key" do
    result = ze0(<<~'RUBY')
      # sort_by / min_by / max_by list the key types they can order. A Rational and a
      # Bignum are comparable numbers carried as pointers, and the keys are boxed and
      # compared with the poly ordering anyway -- which already orders both, since
      # Array#sort and #max on Rationals work. Refusing them here only dropped the
      # call to the unresolved-call raise, so the program got "undefined method
      # 'sort_by' for an instance of Array" (#4061).
      p [3, 1, 2].sort_by { |n| Rational(n, 2) }
      p [3, 1, 2].min_by { |n| Rational(n, 2) }
      p [3, 1, 2].max_by { |n| Rational(n, 2) }

      # a descending key, so the answer is not the identity either way
      p [3, 1, 2].sort_by { |n| Rational(10 - n, 3) }
      p [3, 1, 2].min_by { |n| Rational(10 - n, 3) }

      # a Bignum key
      p [3, 1, 2].sort_by { |n| 10**20 * n }
      p [3, 1, 2].max_by { |n| 10**20 * n }

      # the count forms and a hash receiver take the same route
      p [3, 1, 2].min_by(2) { |n| Rational(n, 2) }
      p({ "a" => 3, "b" => 1 }.sort_by { |k, v| Rational(v, 2) })
      p [1.5, 0.5].sort_by { |f| f.to_r }

      # the count form boxes its keys the same way, so a String or Symbol key works
      # there too -- it used to reject every key that needed boxing
      p %w[pear fig apple].min_by(2) { |w| w }
      p [:c, :a, :b].max_by(2) { |s| s }
      p [[2, 9], [1, 0]].min_by(1) { |a| a }
    RUBY

    _(result).must_answer <<~'OUT'
      [1, 2, 3]
      1
      3
      [3, 2, 1]
      3
      [1, 2, 3]
      3
      [1, 2]
      [["b", 1], ["a", 3]]
      [0.5, 1.5]
      ["apple", "fig"]
      [:c, :b]
      [[1, 0]]
    OUT
  end

  it "value obj boxing clamp" do
    result = ze0(<<~'RUBY')
      class Ver139
        include Comparable
        attr_reader :n
        def initialize(n); @n = n; end
        def <=>(o); n <=> o.n; end
      end
      lo = Ver139.new(1); hi = Ver139.new(9)
      p(Ver139.new(5).clamp(lo..hi).n)
      p(Ver139.new(0).clamp(lo..hi).n)
      p(Ver139.new(12).clamp(lo, hi).n)
      # value obj crossing into a poly slot and back out via GC pressure
      class Tag139
        attr_reader :label, :num
        def initialize(label, num); @label = label; @num = num; end
      end
      box = []
      10.times { |i| box << Tag139.new("t#{i}", i) }
      20000.times { |i| "waste#{i}" * 3 }
      GC.start if defined?(GC)
      p box.map { |t| t.label }.join(",")
      p box.last.num
    RUBY

    _(result).must_answer <<~'OUT'
      5
      1
      9
      "t0,t1,t2,t3,t4,t5,t6,t7,t8,t9"
      9
    OUT
  end
end
