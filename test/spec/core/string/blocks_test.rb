# frozen_string_literal: true

require "spec_helper"

describe "String: blocks and yields" do
  it "hash default proc symbol" do
    result = ze0(<<~'RUBY')
      h = {}
      p h.public_send(:default_proc=, :a).class
      p h.default_proc.class
    RUBY

    _(result).must_answer <<~'OUT'
      Proc
      Proc
    OUT
  end

  it "kernel rational string zerodenom" do
    result = ze0(<<~'RUBY')
      # Kernel#Rational parses a String argument ("n", "n/d", "n.d", with optional
      # whitespace and sign) instead of reading the string pointer as an integer, and
      # raises ZeroDivisionError for a zero denominator instead of building (n/0).
      def r1(s); Rational(s); end
      p r1("3/4")                    # (3/4)
      p r1("  -5/2 ")                # (-5/2)
      p r1("6")                      # (6/1)
      p r1("2.5")                    # (5/2)

      def r2(a, b); Rational(a, b); end
      p r2(6, 4)                     # (3/2)  (still reduces)
      p r2(-1, 3)                    # (-1/3)

      def check
        yield
      rescue ZeroDivisionError => e
        puts "ZeroDivisionError: #{e.message}"
      end
      check { r2(1, 0) }             # ZeroDivisionError: divided by 0
      check { r2(0, 0) }             # ZeroDivisionError: divided by 0

      # The single-argument integer form is unchanged.
      p Rational(3)                  # (3/1)
    RUBY

    _(result).must_answer <<~'OUT'
      (3/4)
      (-5/2)
      (6/1)
      (5/2)
      (3/2)
      (-1/3)
      ZeroDivisionError: divided by 0
      ZeroDivisionError: divided by 0
      (3/1)
    OUT
  end

  it "lambda arrow string return" do
    result = ze0(<<~'RUBY')
      # An arrow lambda (`-> {}`, the sp_Val / sp_lam_* ABI, distinct from the
      # `lambda {}` proc-call ABI) returning a string literal round-trips its
      # value instead of the old hardcoded sp_lam_int(0) stub.
      f = -> { "arrow" }
      puts f.call

      g = -> { 7 }
      puts g.call
    RUBY

    _(result).must_answer <<~'OUT'
      arrow
      7
    OUT
  end

  it "map block string new join" do
    result = ze0(<<~'RUBY')
      # #526. Sibling to #522. #522 fixed `.map { String.new }` block-return
      # inference so the result is correctly typed as
      # `mutable_str_ptr_array` (a sp_PtrArray of sp_String*). But the
      # is_ptr_array_type recv block in codegen had no `join` arm for this
      # variant — `xs.map { String.new }.join(",")` fell through to the
      # unresolved-call warning and emitted 0 at the call site (compile-time
      # warning, runtime no-op producing empty output between separators in
      # the composite JSON-fragment use case in action_view/view_helpers).
      #
      # Fix: add the `join` arm in the ptr_array recv block (gated on
      # elem_type == "mutable_str") that emits sp_PtrArray_str_join, and the
      # matching runtime helper that reads each element's bytes via the
      # sp_String data/len pair.

      def make_str(x)
        s = String.new
        s << x.to_s
        s
      end

      xs = [1, 2, 3]

      # The repro case from the issue: block returns String.new directly.
      puts xs.map { |x| String.new }.join(",")

      # Block body is a method call returning a mutable_str — mirrors the
      # real-world action_view/view_helpers pattern where the map block calls
      # something like `Views::Articles.article_json(article)` and the result
      # is joined with "," to form a JSON fragment.
      puts xs.map { |x| make_str(x) }.join("-")

      # Single-element (no separator emitted in output).
      puts [1].map { |x| make_str(x) }.join(",")
    RUBY

    _(result).must_answer <<~'OUT'
      ,,
      1-2-3
      1
    OUT
  end

  it "min by string key" do
    result = ze0(<<~'RUBY')
      # min_by/max_by with a String or Symbol block key orders lexicographically
      # (String#<=>), not just for Integer/Float keys.
      p ["banana", "apple", "cherry"].min_by { |s| s }
      p ["banana", "apple", "cherry"].max_by { |s| s }
      p ["banana", "apple", "cherry"].max_by { |s| s.length }
      p [:foo, :bar, :baz].min_by { |s| s }
      def first_alpha(a); a.min_by { |s| s }; end
      p first_alpha(["c", "a", "b"])
    RUBY

    _(result).must_answer <<~'OUT'
      "apple"
      "cherry"
      "banana"
      :bar
      "a"
    OUT
  end

  it "proc reads attr reader" do
    result = ze0(<<~'RUBY')
      class Scale
        attr_reader :factor
        def initialize(f); @factor = f; end
        def make; ->(n) { n * factor }; end
      end
      p Scale.new(3).make.call(2)
      class S2
        attr_accessor :k
        def initialize(k); @k = k; end
        def pr; proc { |n| n + k }; end
        def lm; lambda { |n| n * k }; end
      end
      p S2.new(4).pr.call(1)
      p S2.new(4).lm.call(2)
    RUBY

    _(result).must_answer <<~'OUT'
      6
      5
      8
    OUT
  end

  it "proc source location is a string integer pair" do
    result = ze0(<<~'RUBY')
      loc = ->(x) { x }.source_location
      p loc.class
      p loc.length
      p loc[0].class
      p loc[1].class
    RUBY

    _(result).must_answer <<~'OUT'
      Array
      2
      String
      Integer
    OUT
  end

  it "rational and complex parse string arguments" do
    result = ze0(<<~'RUBY')
      p Rational("3/4")
      p Rational("  -5/2 ")
      p Rational("6")
      p Rational("2.5")
      p Rational(3)
      p Complex("2+3i")
      p Complex("1+2i")
      p Complex("3")
      p Complex("-i")
      p Complex("4i")
      def t; yield; rescue => e; "#{e.class}"; end
      p t { Rational("abc") }
      p t { Complex("xyz") }
      p t { Rational(1, 0) }
    RUBY

    _(result).must_answer <<~'OUT'
      (3/4)
      (-5/2)
      (6/1)
      (5/2)
      (3/1)
      (2+3i)
      (1+2i)
      (3+0i)
      (0-1i)
      (0+4i)
      "ArgumentError"
      "ArgumentError"
      "ZeroDivisionError"
    OUT
  end

  it "rational complex string args" do
    result = ze0(<<~'RUBY')
      # Kernel#Rational and Kernel#Complex parse a String argument as a numeric
      # literal, rather than reading the string's pointer as an integer.

      # Rational("n/d" | "n.d" | "n"): the DECIMAL value, so "2.5" is exactly 5/2
      # (not the Float value). Whitespace and a sign are allowed; a zero denominator
      # raises ZeroDivisionError, an unparseable string ArgumentError.
      p Rational("3/4")
      p Rational("  -5/2 ")
      p Rational("6")
      p Rational("2.5")
      p Rational(3)          # the numeric form is unchanged

      # Complex("a+bi"): each component is an Integer without a decimal point, else a
      # Float; a bare "±i" is the unit, a pure real or pure imaginary is supported.
      p Complex("2+3i")
      p Complex("1+2i")
      p Complex("3")
      p Complex("-i")
      p Complex("4i")
      p Complex("1.5-2.5i")

      def caught
        yield
      rescue => e
        "#{e.class}: #{e.message}"
      end
      p caught { Rational("abc") }
      p caught { Complex("xyz") }
      p caught { Rational(1, 0) }
    RUBY

    _(result).must_answer <<~'OUT'
      (3/4)
      (-5/2)
      (6/1)
      (5/2)
      (3/1)
      (2+3i)
      (1+2i)
      (3+0i)
      (0-1i)
      (0+4i)
      (1.5-2.5i)
      "ArgumentError: invalid value for convert(): \"abc\""
      "ArgumentError: invalid value for convert(): \"xyz\""
      "ZeroDivisionError: divided by 0"
    OUT
  end

  it "string array hash symbol proc leaf methods" do
    result = ze0(<<~'RUBY')
      p "hello".codepoints
      s = "hi\n"; p s.chomp!; p s.chomp!
      p "hello".partition("l")
      p "hello".rpartition("l")
      p "a.b.c".partition(/\./)
      p "TestName".delete_prefix("Test")
      p "file.rb".delete_suffix(".rb")
      c = +"x"; c.clear; p c
      p((+"y").frozen?)
      p [1, 2].repeated_permutation(2).to_a
      p [1, 2].repeated_combination(2).to_a
      p [1, 2, 3].intersect?([3, 4])
      p [1, 2].chain([3], [4]).to_a
      p({ a: 1, b: 2, c: 3 }.slice(:a, :c))
      p({ a: 1, b: 2 }.except(:a))
      p({ a: 1, b: 2 }.fetch_values(:a, :b))
      p({ a: 1, b: [2, 3] }.flatten)
      p :hello[1, 3]
      p :Hello.casecmp?(:hELLO)
      f = ->(x) { x + 1 }
      g = ->(x) { x * 2 }
      p((f >> g).call(3))
      p((f << g).call(3))
    RUBY

    _(result).must_answer <<~'OUT'
      [104, 101, 108, 108, 111]
      "hi"
      nil
      ["he", "l", "lo"]
      ["hel", "l", "o"]
      ["a", ".", "b.c"]
      "Name"
      "file"
      ""
      false
      [[1, 1], [1, 2], [2, 1], [2, 2]]
      [[1, 1], [1, 2], [2, 2]]
      true
      [1, 2, 3, 4]
      {a: 1, c: 3}
      {b: 2}
      [1, 2]
      [:a, 1, :b, [2, 3]]
      "ell"
      true
      8
      7
    OUT
  end

  it "string enum block returns self" do
    result = ze0(<<~'RUBY')
      # String#chars/#bytes/#codepoints/#lines with a block yield each element
      # and return the receiver (self), not the element array. The no-block
      # form still returns the array.
      s = "abc"

      r1 = s.chars { |c| print c }
      puts ""
      puts r1

      sum = 0
      r2 = s.bytes { |b| sum = sum + b }
      puts sum
      puts r2

      cps = 0
      r3 = "ab".codepoints { |cp| cps = cps + cp }
      puts cps
      puts r3

      n = 0
      r4 = "x\ny\n".lines { |l| n = n + 1 }
      puts n
      puts r4

      # No-block forms still return arrays.
      p "abc".chars
      p "abc".bytes
    RUBY

    _(result).must_answer <<~'OUT'
      abc
      abc
      294
      abc
      195
      ab
      2
      x
      y
      ["a", "b", "c"]
      [97, 98, 99]
    OUT
  end

  it "string to c lenient" do
    result = ze0(<<~'RUBY')
      # String#to_c raised where CRuby answers (0+0i). One parser was serving two
      # contracts: Kernel#Complex(str) must consume the whole string or raise, while
      # String#to_c reads a LEADING complex and ignores the rest. String#to_r has had
      # that pair (sp_str_to_r / sp_str_to_r_strict) all along; to_c had only the
      # strict half and #to_c was pointed at it.
      #
      # And sp_poly_to_r_m had no String arm, though sp_poly_to_c_m has carried one
      # all along -- so a String that widened to poly answered NoMethodError, which
      # is what `v&.to_r` is.

      # String#to_c: a leading complex, the rest ignored, (0+0i) when there is none
      p "abc".to_c
      p "".to_c
      p "5x".to_c
      p "1+2i".to_c
      p "3".to_c
      p "2.5".to_c
      p "  7  ".to_c

      # String#to_r, the sibling that was already right
      p "abc".to_r
      p "3/4".to_r
      p "1.5".to_r
      p "12".to_r
      p "5x".to_r
      p "".to_r

      # Kernel#Complex / #Rational keep the strict contract
      def try
        yield
      rescue ArgumentError
        "ArgumentError"
      end

      p try { Complex("abc") }
      p try { Complex("1+") }
      p try { Complex("5x") }
      p try { Complex("2+3i") }
      p try { Rational("abc") }
      p try { Rational("3/4") }
      p Complex("abc", exception: false)
      p Rational("abc", exception: false)

      # through a poly receiver, which is where the missing String arm showed
      def as_r(v) = v&.to_r
      def as_c(v) = v&.to_c

      p as_r("3/4")
      p as_r("abc")
      p as_r(nil)
      p as_r(5)
      p as_r(1.5)
      p as_c("1+2i")
      p as_c("abc")
      p as_c(nil)
      p as_c(5)
    RUBY

    _(result).must_answer <<~'OUT'
      (0+0i)
      (0+0i)
      (5+0i)
      (1+2i)
      (3+0i)
      (2.5+0i)
      (7+0i)
      (0/1)
      (3/4)
      (3/2)
      (12/1)
      (5/1)
      (0/1)
      "ArgumentError"
      "ArgumentError"
      "ArgumentError"
      (2+3i)
      "ArgumentError"
      (3/4)
      nil
      nil
      (3/4)
      (0/1)
      nil
      (5/1)
      (3/2)
      (1+2i)
      (0+0i)
      nil
      (5+0i)
    OUT
  end

  it "symbol proc absent method" do
    result = ze0(<<~'RUBY')
      # max_by / min_by / sort_by with a symbol-proc naming a method the element does
      # not have compiles and raises NoMethodError, as map with the same proc does.
      a = ([1, 2].max_by(&:foo) rescue $!.class); p a
      b = ([1, 2].min_by(&:foo) rescue $!.class); p b
      c = ([1, 2].sort_by(&:foo) rescue $!.class); p c
      d = ([1, 2].map(&:foo) rescue $!.class); p d
      e = (["a", "b"].max_by(&:nope) rescue $!.class); p e
      p [1, 2].max_by(&:abs)
      p [3, 1, 2].sort_by { |x| -x }
      p [1, 2, 3].min_by(&:abs)
    RUBY

    _(result).must_answer <<~'OUT'
      NoMethodError
      NoMethodError
      NoMethodError
      NoMethodError
      NoMethodError
      2
      [3, 2, 1]
      1
    OUT
  end

  it "symbol to proc after positional" do
    result = ze0(<<~'RUBY')
      # &:symbol block-pass after a positional argument must parse as a
      # symbol-to-proc block, not a hash literal -- in both parenthesized
      # and command (paren-less) calls. Front-door blocker for bundler
      # (File.open(f, "r:UTF-8", &:read)) and minitest
      # (define_method :mu_pp, &:pretty_inspect).
      class Widget
        define_method(:as_str, &:to_s)   # parenthesized, after a positional
      end

      class Gadget
        define_method :label, &:to_s     # command (paren-less), after a positional
      end

      puts Widget.new.as_str(7)
      puts Gadget.new.label(8)
      p [1, 2, 3].map(&:to_s)            # sole arg in parens (regression guard)
      p [1, 2, 3].map &:to_s            # command-position sole arg
      p [10, 20, 30].inject(0, &:+)     # operator symbol after a positional (native)
    RUBY

    _(result).must_answer <<~'OUT'
      7
      8
      ["1", "2", "3"]
      ["1", "2", "3"]
      60
    OUT
  end

  it "yield autosplat kernel string" do
    result = ze0(<<~'RUBY')
      # CRuby auto-splat of a single yielded Array across multiple block params,
      # and Kernel#String on containers/ranges (returns the object's to_s).
      def pairs124; yield [1, 2]; end
      pairs124 { |a, b| p(a + b) }
      def trip; yield [3, 4, 5]; end
      trip { |a, b, c| p [a, b, c] }
      trip { |a, b| p [a, b] }
      def strs; yield ["x", "y"]; end
      strs { |a, b| p(a + b) }
      def one; yield [7]; end
      one { |a, b| p [a, b] }
      def three; yield [1, 2, 3]; end
      three { |a, *r| p [a, r] }
      three { |*r| p r }
      def two_args; yield 1, 2; end
      two_args { |a, b| p [a, b] }
      def poly_arr; yield [1, "x"]; end
      poly_arr { |a, b| p [a, b] }
      p(String([1, 2]))
      p(String(123))
      p(String(:sym))
      p(String(1.5))
      p(String(nil))
      p(String("s"))
      p(String({ a: 1 }))
      p(String(1..3))
    RUBY

    _(result).must_answer <<~'OUT'
      3
      [3, 4, 5]
      [3, 4]
      "xy"
      [7, nil]
      [1, [2, 3]]
      [[1, 2, 3]]
      [1, 2]
      [1, "x"]
      "[1, 2]"
      "123"
      "sym"
      "1.5"
      ""
      "s"
      "{a: 1}"
      "1..3"
    OUT
  end
end
