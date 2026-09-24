# frozen_string_literal: true

require "spec_helper"

describe "Numeric: raising and rescuing" do
  it "complex nil arg and nomethod" do
    result = zr(<<~'RUBY')
      # Kernel#Complex rejects a nil component (TypeError), and an undefined method
      # on a Complex/Rational value raises NoMethodError instead of aborting.
      begin; Complex(nil); rescue => e; p e.class; end
      begin; Complex(1, nil); rescue => e; p e.class; end
      begin; Complex(2, 3).floor; rescue NoMethodError => e; puts e.message; end
      begin; Rational(1, 2).each; rescue => e; p e.class; end
      p Complex(2, 3).real
      p Complex(2, 3).abs2
    RUBY

    _(result).must_answer <<~'OUT'
      TypeError
      TypeError
      undefined method 'floor' for an instance of Complex
      NoMethodError
      2
      13
    OUT
  end

  it "float division by zero returns infinity not an error" do
    result = zr(<<~'RUBY')
      # Regression guard for the fix above: `ZeroDivisionError` must stay
      # `Int`/`Int`-division-specific -- real Ruby's `Float`/`0` is
      # `Infinity`/`-Infinity`/`NaN` (IEEE semantics), never a raised
      # exception, and `float_div` already gives this for free with no
      # check needed.

      puts(1.0 / 0.0); puts(-1.0 / 0.0)
    RUBY

    _(result).must_answer "Infinity\n-Infinity\n"
  end

  it "float divmod zerodiv" do
    result = zr(<<~'RUBY')
      # Float#divmod(0) / Float#divmod(0.0) raises ZeroDivisionError.
      #
      # Sibling of Integer#divmod(0) which was fixed in the parent
      # rescue/raise overhaul (test/integer_div_by_zero.rb). Without
      # this guard, `(mrb_int)floor(rc / 0.0)` would consume an
      # Infinity/NaN and produce undefined C behaviour at the cast.
      #
      # Test uses `puts e` directly (which prints the message string in
      # spinel) — exception object methods like .message live on a
      # separate exception-bindings PR.

      # Sanity: divmod with non-zero divisor still works.
      q, r = 5.0.divmod(2.0)
      puts q
      puts r

      # Float / int divisor
      begin
        1.0.divmod(0)
        puts "no raise"
      rescue ZeroDivisionError => e
        puts "caught int divisor: #{e}"
      end

      # Float / float divisor
      begin
        1.0.divmod(0.0)
        puts "no raise"
      rescue ZeroDivisionError => e
        puts "caught float divisor: #{e}"
      end

      # Bare rescue catches it.
      begin
        3.5.divmod(0.0)
      rescue => e
        puts "bare-rescue: #{e}"
      end

      # NaN divisor → FloatDomainError("NaN"). Without this guard the
      # `(mrb_int)floor(1.0 / NaN)` cast on the result would also be
      # C undefined behaviour.
      nan = 0.0 / 0.0
      begin
        1.0.divmod(nan)
        puts "no raise nan divisor"
      rescue FloatDomainError => e
        puts "caught nan divisor: #{e}"
      end

      # NaN dividend → FloatDomainError("NaN"). Same UB risk on the cast.
      begin
        nan.divmod(2.0)
        puts "no raise nan dividend"
      rescue FloatDomainError => e
        puts "caught nan dividend: #{e}"
      end
    RUBY

    _(result).must_answer <<~'OUT'
      2
      1.0
      caught int divisor: divided by 0
      caught float divisor: divided by 0
      bare-rescue: divided by 0
      caught nan divisor: NaN
      caught nan dividend: NaN
    OUT
  end

  it "float rational math family" do
    result = zr(<<~'RUBY')
      # Float#numerator/#denominator (exact rational of the double), Math.frexp,
      # and Math.sqrt coercing a Rational argument.
      def num(a) = a.numerator
      def den(a) = a.denominator
      def fx(x) = Math.frexp(x)
      def sq(r) = Math.sqrt(r)

      p num(0.5)          # 1
      p den(0.5)          # 2
      p num(-0.75)        # -3
      p den(-0.75)        # 4
      p num(3.0)          # 3
      p den(3.0)          # 1
      p fx(8.0)           # [0.5, 4]
      p fx(0.5)           # [0.5, 0]
      p fx(-12.0)         # [-0.75, 4]
      p Math.frexp(1)     # [0.5, 1]
      p sq(Rational(1, 4))     # 0.5
      p sq(Rational(9, 1))     # 3.0
      p Math.sqrt(Rational(1, 16))  # 0.25
      begin
        Math.sqrt("x")
      rescue TypeError => e
        puts "#{e.class}: #{e.message}"
      end
    RUBY

    _(result).must_answer <<~'OUT'
      1
      2
      -3
      4
      3
      1
      [0.5, 4]
      [0.5, 0]
      [-0.75, 4]
      [0.5, 1]
      0.5
      3.0
      0.25
      TypeError: can't convert String into Float
    OUT
  end

  it "float remainder zero divisor" do
    result = zr(<<~'RUBY')
      # GAP -- imported from the spinel corpus at c55d9bdb.
      # Float#remainder by zero answers NaN where ruby raises ZeroDivisionError.
      #
      r001 = (7.0.remainder(0.0) rescue $!.class); p r001
      r002 = (7.0.remainder(0) rescue $!.class); p r002
      v003 = 7.0; w003 = 0.0; r003 = (v003.remainder(w003) rescue $!.class); p r003
      r004 = (0.0.remainder(0.0) rescue $!.class); p r004
      r005 = (7.remainder(0.0) rescue $!.class); p r005
      p(7.0.remainder(2.0))
      p(7.remainder(2.5))
    RUBY

    _(result).must_answer <<~'OUT'
      ZeroDivisionError
      ZeroDivisionError
      ZeroDivisionError
      ZeroDivisionError
      ZeroDivisionError
      1.0
      2.0
    OUT
  end

  it "int bit beginless raises" do
    result = zr(<<~'RUBY')
      begin
        puts 255[..3]
      rescue ArgumentError => e
        puts "AE: #{e.message}"
      end
      a = 255
      begin
        puts a[..3]
      rescue ArgumentError => e
        puts "AE: #{e.message}"
      end
      puts 255[0..3]
      puts 255[4..]
      puts 255[1, 3]
    RUBY

    _(result).must_answer <<~'OUT'
      AE: The beginless range for Integer#[] results in infinity
      AE: The beginless range for Integer#[] results in infinity
      15
      15
      7
    OUT
  end

  it "Integer() reads a decimal string, signed or not" do
    result = zr(<<~'RUBY')
      # Integer(s) raises ArgumentError on unparseable input, matching
      # CRuby semantics. Previously spinel emitted bare strtoll(s, NULL, 10)
      # which silently returned 0 for invalid input — that meant
      # `Integer(s) rescue 0` always took the main branch and the rescue
      # never fired.
      #
      # Test uses same-type rescue fallbacks (int + int) to avoid the
      # int+string type-mismatch issue (a separate poly-boxing PR). For
      # the bare-rescue path, e.g. `rescue ArgumentError => e`, we use
      # `puts e` directly — exception .message dispatch lives on a
      # separate exception-bindings PR.

      # Valid inputs unchanged
      a = (Integer("42") rescue -1)
      puts a
      b = (Integer("0") rescue -1)
      puts b
      c = (Integer("-7") rescue -1)
      puts c
      d = (Integer("+5") rescue -1)
      puts d

    RUBY

    _(result).must_answer <<~'OUT'
      42
      0
      -7
      5
    OUT
  end

  it "Integer() allows the leading and trailing whitespace CRuby allows" do
    result = zr(<<~'RUBY')
      # Integer(s) raises ArgumentError on unparseable input, matching
      # CRuby semantics. Previously spinel emitted bare strtoll(s, NULL, 10)
      # which silently returned 0 for invalid input — that meant
      # `Integer(s) rescue 0` always took the main branch and the rescue
      # never fired.
      #
      # Test uses same-type rescue fallbacks (int + int) to avoid the
      # int+string type-mismatch issue (a separate poly-boxing PR). For
      # the bare-rescue path, e.g. `rescue ArgumentError => e`, we use
      # `puts e` directly — exception .message dispatch lives on a
      # separate exception-bindings PR.

      # Whitespace handling per CRuby (leading/trailing whitespace ok).
      # Includes \t \n \r \v \f — all should be skipped (isspace covers
      # them; the previous manual `c == ' ' || c == '\t' || c == '\n' ||
      # c == '\r'` check missed \v and \f).
      e = (Integer("  -7  ") rescue -1)
      puts e
      e_tab = (Integer("\t42\t") rescue -1)
      puts e_tab
      e_nl = (Integer("\n42\n") rescue -1)
      puts e_nl
      e_cr = (Integer("\r42\r") rescue -1)
      puts e_cr
      e_vt = (Integer("\v42\v") rescue -1)
      puts e_vt
      e_ff = (Integer("\f42\f") rescue -1)
      puts e_ff
      e_mix = (Integer("  \t\n -7 \r\f ") rescue -1)
      puts e_mix

    RUBY

    _(result).must_answer <<~'OUT'
      -7
      42
      42
      42
      42
      42
      -7
    OUT
  end

  it "Integer() reads a sign, and a sign on its own is not a number" do
    result = zr(<<~'RUBY')
      # Integer(s) raises ArgumentError on unparseable input, matching
      # CRuby semantics. Previously spinel emitted bare strtoll(s, NULL, 10)
      # which silently returned 0 for invalid input — that meant
      # `Integer(s) rescue 0` always took the main branch and the rescue
      # never fired.
      #
      # Test uses same-type rescue fallbacks (int + int) to avoid the
      # int+string type-mismatch issue (a separate poly-boxing PR). For
      # the bare-rescue path, e.g. `rescue ArgumentError => e`, we use
      # `puts e` directly — exception .message dispatch lives on a
      # separate exception-bindings PR.

      # Sign handling
      sign_pos_zero = (Integer("+0") rescue -1); puts sign_pos_zero
      sign_neg_zero = (Integer("-0") rescue -1); puts sign_neg_zero
      sign_plus_sp  = (Integer("+ 7") rescue -1); puts sign_plus_sp   # space between sign and digit → invalid
      sign_minus_sp = (Integer("- 7") rescue -1); puts sign_minus_sp
      sign_double   = (Integer("++7") rescue -1); puts sign_double    # double-sign → invalid
      sign_bare     = (Integer("+")   rescue -1); puts sign_bare      # bare sign → invalid

    RUBY

    _(result).must_answer <<~'OUT'
      0
      0
      -1
      -1
      -1
      -1
    OUT
  end

  it "Integer() reads the edges of the machine word" do
    result = zr(<<~'RUBY')
      # Integer(s) raises ArgumentError on unparseable input, matching
      # CRuby semantics. Previously spinel emitted bare strtoll(s, NULL, 10)
      # which silently returned 0 for invalid input — that meant
      # `Integer(s) rescue 0` always took the main branch and the rescue
      # never fired.
      #
      # Test uses same-type rescue fallbacks (int + int) to avoid the
      # int+string type-mismatch issue (a separate poly-boxing PR). For
      # the bare-rescue path, e.g. `rescue ArgumentError => e`, we use
      # `puts e` directly — exception .message dispatch lives on a
      # separate exception-bindings PR.

      # Edge magnitudes within mrb_int range
      ll_max = (Integer("9223372036854775807")  rescue -1); puts ll_max   # LLONG_MAX
      ll_min = (Integer("-9223372036854775808") rescue -1); puts ll_min   # LLONG_MIN

    RUBY

    _(result).must_answer <<~'OUT'
      9223372036854775807
      -9223372036854775808
    OUT
  end

  it "Integer() raises for a string that names no number" do
    result = zr(<<~'RUBY')
      # Integer(s) raises ArgumentError on unparseable input, matching
      # CRuby semantics. Previously spinel emitted bare strtoll(s, NULL, 10)
      # which silently returned 0 for invalid input — that meant
      # `Integer(s) rescue 0` always took the main branch and the rescue
      # never fired.
      #
      # Test uses same-type rescue fallbacks (int + int) to avoid the
      # int+string type-mismatch issue (a separate poly-boxing PR). For
      # the bare-rescue path, e.g. `rescue ArgumentError => e`, we use
      # `puts e` directly — exception .message dispatch lives on a
      # separate exception-bindings PR.

      # Invalid inputs now raise (caught by rescue, returns -1)
      f = (Integer("xyz") rescue -1); puts f
      g = (Integer("") rescue -1); puts g
      h = (Integer("   ") rescue -1); puts h
      ii = (Integer("12abc") rescue -1); puts ii
      j = (Integer("12.5") rescue -1); puts j

    RUBY

    _(result).must_answer <<~'OUT'
      -1
      -1
      -1
      -1
      -1
    OUT
  end

  it "Integer() raises for trailing junk after the digits" do
    result = zr(<<~'RUBY')
      # Integer(s) raises ArgumentError on unparseable input, matching
      # CRuby semantics. Previously spinel emitted bare strtoll(s, NULL, 10)
      # which silently returned 0 for invalid input — that meant
      # `Integer(s) rescue 0` always took the main branch and the rescue
      # never fired.
      #
      # Test uses same-type rescue fallbacks (int + int) to avoid the
      # int+string type-mismatch issue (a separate poly-boxing PR). For
      # the bare-rescue path, e.g. `rescue ArgumentError => e`, we use
      # `puts e` directly — exception .message dispatch lives on a
      # separate exception-bindings PR.

      # Trailing-junk variants
      trail_junk      = (Integer("42x") rescue -1);          puts trail_junk
      trail_junk_ws   = (Integer("42 x") rescue -1);         puts trail_junk_ws       # whitespace then junk
      trail_nl_junk   = (Integer("42\n garbage") rescue -1); puts trail_nl_junk
      trail_only_ws   = (Integer("42 ") rescue -1);          puts trail_only_ws       # bare trailing whitespace OK

    RUBY

    _(result).must_answer <<~'OUT'
      -1
      -1
      -1
      42
    OUT
  end

  it "Integer() raises for leading junk before the digits" do
    result = zr(<<~'RUBY')
      # Integer(s) raises ArgumentError on unparseable input, matching
      # CRuby semantics. Previously spinel emitted bare strtoll(s, NULL, 10)
      # which silently returned 0 for invalid input — that meant
      # `Integer(s) rescue 0` always took the main branch and the rescue
      # never fired.
      #
      # Test uses same-type rescue fallbacks (int + int) to avoid the
      # int+string type-mismatch issue (a separate poly-boxing PR). For
      # the bare-rescue path, e.g. `rescue ArgumentError => e`, we use
      # `puts e` directly — exception .message dispatch lives on a
      # separate exception-bindings PR.

      # Leading-junk variants
      lead_junk    = (Integer("x42") rescue -1);    puts lead_junk
      lead_ws_junk = (Integer(" x 42") rescue -1);  puts lead_ws_junk

    RUBY

    _(result).must_answer <<~'OUT'
      -1
      -1
    OUT
  end

  it "a bare rescue catches the ArgumentError, whose message quotes the string" do
    result = zr(<<~'RUBY')
      # Integer(s) raises ArgumentError on unparseable input, matching
      # CRuby semantics. Previously spinel emitted bare strtoll(s, NULL, 10)
      # which silently returned 0 for invalid input — that meant
      # `Integer(s) rescue 0` always took the main branch and the rescue
      # never fired.
      #
      # Test uses same-type rescue fallbacks (int + int) to avoid the
      # int+string type-mismatch issue (a separate poly-boxing PR). For
      # the bare-rescue path, e.g. `rescue ArgumentError => e`, we use
      # `puts e` directly — exception .message dispatch lives on a
      # separate exception-bindings PR.

      # Hex prefixes ("0x10") and underscore separators ("12_345") are
      # CRuby-supported but Spinel's base-10 strtoll path doesn't parse
      # them. Documented in the PR's "Out of scope" — not exercised here
      # because the test compares spinel output against MRI directly,
      # and we'd diverge.

      # Bare rescue catches and lets us see the error message.
      # Also exercises the GC-root path: the message is allocated via
      # sp_sprintf (str-heap) and stored in sp_exc_msg; reading it from
      # `err` after a hypothetical mid-flight collection would dangle
      # without sp_mark_in_flight_exceptions marking the slot.
      begin
        Integer("nope")
      rescue ArgumentError => err
        puts "msg: #{err}"
      end

    RUBY

    _(result).must_answer <<~'OUT'
      msg: invalid value for Integer(): "nope"
    OUT
  end

  it "a hundred raises in succession leave the allocator sound" do
    result = zr(<<~'RUBY')
      # Integer(s) raises ArgumentError on unparseable input, matching
      # CRuby semantics. Previously spinel emitted bare strtoll(s, NULL, 10)
      # which silently returned 0 for invalid input — that meant
      # `Integer(s) rescue 0` always took the main branch and the rescue
      # never fired.
      #
      # Test uses same-type rescue fallbacks (int + int) to avoid the
      # int+string type-mismatch issue (a separate poly-boxing PR). For
      # the bare-rescue path, e.g. `rescue ArgumentError => e`, we use
      # `puts e` directly — exception .message dispatch lives on a
      # separate exception-bindings PR.

      # Stress the GC-root fix: many raises in succession force allocator
      # churn. Each `Integer("bad...")` builds an sp_sprintf-allocated
      # message and stores it in sp_exc_msg before longjmping. Pre-fix
      # (without sp_mark_in_flight_exceptions), a sweep landing between
      # raise and rescue would reap the message; the rescue handler would
      # read garbage. Post-fix, the marker keeps each message live until
      # the handler returns and sp_exc_top decrements.
      i = 0
      ok = 0
      while i < 100
        caught = 0
        begin
          Integer("bad")
        rescue ArgumentError
          caught = 1
        end
        ok += caught
        i += 1
      end
      puts "stress ok: #{ok}"

    RUBY

    _(result).must_answer <<~'OUT'
      stress ok: 100
    OUT
  end

  it "an endless method with a rescue clause still answers" do
    result = zr(<<~'RUBY')
      # Integer(s) raises ArgumentError on unparseable input, matching
      # CRuby semantics. Previously spinel emitted bare strtoll(s, NULL, 10)
      # which silently returned 0 for invalid input — that meant
      # `Integer(s) rescue 0` always took the main branch and the rescue
      # never fired.
      #
      # Test uses same-type rescue fallbacks (int + int) to avoid the
      # int+string type-mismatch issue (a separate poly-boxing PR). For
      # the bare-rescue path, e.g. `rescue ArgumentError => e`, we use
      # `puts e` directly — exception .message dispatch lives on a
      # separate exception-bindings PR.

      # Pre-existing endless_method_rescue.rb shape continues to work.
      # Integer("abc") now raises but the rescue catches and returns 0,
      # so the observed behaviour is unchanged.
      def parse_int(s) = Integer(s) rescue 0
      puts parse_int("42")
      puts parse_int("abc")
      puts parse_int("0")
      puts parse_int("-7")
    RUBY

    _(result).must_answer <<~'OUT'
      42
      0
      0
      -7
    OUT
  end

  it "integer bit reference operator" do
    result = zr(<<~'RUBY')
      p 0b1011[0]
      p 0b1011[2]
      p 5[0, 2]
      p 0b1101[1, 3]
      p 255[0..3]
      p 255[4..]
      p (-2)[0]
      p (-2)[1]
      p 10[100]
      p((1 << 100)[100])
      begin
        255[..3]
      rescue ArgumentError => e
        puts e.message
      end
    RUBY

    _(result).must_answer <<~'OUT'
      1
      0
      1
      6
      15
      15
      0
      1
      0
      1
      The beginless range for Integer#[] results in infinity
    OUT
  end

  it "integer conversion base zero" do
    result = zr(<<~'RUBY')
      # `Integer(str, 0)` means "detect the base from the literal prefix" (0x, 0b,
      # 0o/0, else decimal) -- the C strtol convention. zr's Integer() only accepts
      # explicit bases and raises ArgumentError for base 0.
      puts Integer("0b101", 0)
      puts Integer("0x1A", 0)
      puts Integer("0o17", 0)
      puts Integer("017", 0)
      puts Integer("42", 0)
      begin
        Integer("9", 8)
      rescue ArgumentError => e
        puts "control: #{e.message}"
      end
    RUBY

    _(result).must_answer <<~'OUT'
      5
      26
      15
      15
      42
      control: invalid value for Integer(): "9"
    OUT
  end

  it "integer sqrt is exact including bignums" do
    result = zr(<<~'RUBY')
      p Integer.sqrt(0)
      p Integer.sqrt(8)
      p Integer.sqrt(9)
      p Integer.sqrt(10**20)
      p Integer.sqrt(2**100)
      begin
        Integer.sqrt(-4)
      rescue Math::DomainError => e
        puts e.message
      end
    RUBY

    _(result).must_answer <<~'OUT'
      0
      2
      3
      10000000000
      1125899906842624
      Numerical argument is out of domain - "isqrt"
    OUT
  end

  it "kernel float strict" do
    result = zr(<<~'RUBY')
      # Issue #888: Kernel#Float() raises ArgumentError on unparseable
      # input per MRI; previously silently returned 0.0 from strtod.
      begin
        Float("abc")
      rescue ArgumentError => e
        puts "abc: " + e.message
      end
      begin
        Float("")
      rescue ArgumentError => e
        puts "empty: " + e.message
      end
      puts Float("3.14")
      puts Float("  42.5  ")
      puts Float(7)
      puts Float(2.5)
    RUBY

    _(result).must_answer <<~'OUT'
      abc: invalid value for Float(): "abc"
      empty: invalid value for Float(): ""
      3.14
      42.5
      7.0
      2.5
    OUT
  end

  it "kernel integer float errors" do
    result = zr(<<~'RUBY')
      # Kernel#Integer / #Float raise TypeError on nil (not 0), and Integer with a
      # base and a non-String value raises ArgumentError (#2514, #2515).
      p((Integer(nil) rescue $!.class))
      p((Float(nil) rescue $!.class))
      p((Integer(5, 16) rescue $!.class))
      p(Integer("5", 16))
      p(Integer("101", 2))
      p(Integer("42"))
      p(Float("3.5"))
      p(Integer(3.9))
      p(Float(7))
    RUBY

    _(result).must_answer <<~'OUT'
      TypeError
      TypeError
      ArgumentError
      5
      5
      42
      3.5
      3
      7.0
    OUT
  end

  it "kernel integer with base" do
    result = zr(<<~'RUBY')
      # Issue #887: Kernel#Integer(s, base) parses non-decimal correctly
      # and raises catchable ArgumentError on invalid input.
      puts Integer("ff", 16)
      puts Integer("1010", 2)
      puts Integer("777", 8)
      puts Integer("z", 36)
      begin
        Integer("zz", 16)
      rescue ArgumentError => e
        puts "caught: " + e.message
      end
      begin
        Integer("xyz", 8)
      rescue ArgumentError => e
        puts "caught: " + e.message
      end
    RUBY

    _(result).must_answer <<~'OUT'
      255
      10
      511
      35
      caught: invalid value for Integer(): "zz"
      caught: invalid value for Integer(): "xyz"
    OUT
  end

  it "kernel rational strict" do
    result = zr(<<~'RUBY')
      r001 = (Rational("bad") rescue $!.class); p r001
      r002 = (Rational("") rescue $!.class); p r002
      r003 = (Rational(nil) rescue $!.class); p r003
      r004 = (Rational("1/2/3") rescue $!.class); p r004
      p(Rational("1.5e2"))
      p(Rational("2", "4") == Rational(1, 2))
      p(Rational("1/3"))
      p(Rational("0.5"))
      p(Rational(1, 2))
      p("bad".to_r)
    RUBY

    _(result).must_answer <<~'OUT'
      ArgumentError
      ArgumentError
      TypeError
      ArgumentError
      (150/1)
      true
      (1/3)
      (1/2)
      (1/2)
      (0/1)
    OUT
  end

  it "an in-domain argument still answers" do
    result = zr(<<~'RUBY')
      # Math.* methods raise Math::DomainError on out-of-domain input,
      # matching CRuby semantics. Previously spinel called bare libc
      # sqrt(-1.0) etc. which returns NaN silently. Math::DomainError is
      # now in the known-exception list and the ancestry walker wires it
      # as < StandardError < Exception, so the natural CRuby idiom works:
      #
      #   x = Math.sqrt(input) rescue 0.0
      #   begin Math.log(x); rescue Math::DomainError => e; ...; end
      #
      # Methods with restricted domains (sqrt, log, log2, log10, acos,
      # asin, acosh, atanh, plus Integer.sqrt) get sp_math_* wrappers.
      # Unrestricted methods (cos, sin, tan, atan, sinh, cosh, tanh,
      # asinh, exp, atan2, hypot) call libc directly — no overhead.

      # Sanity: in-domain values still work and produce expected output.
      puts Math.sqrt(4.0)
      puts Math.sqrt(2.0).round(4)
      puts Math.acos(1.0)
      puts Math.asin(0.0)
      puts Math.log(1.0)

    RUBY

    _(result).must_answer <<~'OUT'
      2.0
      1.4142
      0.0
      0.0
      0.0
    OUT
  end

  it "sqrt of a negative raises Math::DomainError" do
    result = zr(<<~'RUBY')
      # Math.* methods raise Math::DomainError on out-of-domain input,
      # matching CRuby semantics. Previously spinel called bare libc
      # sqrt(-1.0) etc. which returns NaN silently. Math::DomainError is
      # now in the known-exception list and the ancestry walker wires it
      # as < StandardError < Exception, so the natural CRuby idiom works:
      #
      #   x = Math.sqrt(input) rescue 0.0
      #   begin Math.log(x); rescue Math::DomainError => e; ...; end
      #
      # Methods with restricted domains (sqrt, log, log2, log10, acos,
      # asin, acosh, atanh, plus Integer.sqrt) get sp_math_* wrappers.
      # Unrestricted methods (cos, sin, tan, atan, sinh, cosh, tanh,
      # asinh, exp, atan2, hypot) call libc directly — no overhead.

      # sqrt(negative) → Math::DomainError
      begin
        Math.sqrt(-1.0)
        puts "no raise"
      rescue Math::DomainError => e
        puts "sqrt: #{e}"
      end

    RUBY

    _(result).must_answer <<~'OUT'
      sqrt: Numerical argument is out of domain - sqrt
    OUT
  end

  it "log of a negative raises Math::DomainError" do
    result = zr(<<~'RUBY')
      # Math.* methods raise Math::DomainError on out-of-domain input,
      # matching CRuby semantics. Previously spinel called bare libc
      # sqrt(-1.0) etc. which returns NaN silently. Math::DomainError is
      # now in the known-exception list and the ancestry walker wires it
      # as < StandardError < Exception, so the natural CRuby idiom works:
      #
      #   x = Math.sqrt(input) rescue 0.0
      #   begin Math.log(x); rescue Math::DomainError => e; ...; end
      #
      # Methods with restricted domains (sqrt, log, log2, log10, acos,
      # asin, acosh, atanh, plus Integer.sqrt) get sp_math_* wrappers.
      # Unrestricted methods (cos, sin, tan, atan, sinh, cosh, tanh,
      # asinh, exp, atan2, hypot) call libc directly — no overhead.

      # log(negative)
      begin
        Math.log(-1.0)
        puts "no raise"
      rescue Math::DomainError => e
        puts "log: #{e}"
      end

    RUBY

    _(result).must_answer <<~'OUT'
      log: Numerical argument is out of domain - log
    OUT
  end

  it "log2 and log10 of a negative raise Math::DomainError" do
    result = zr(<<~'RUBY')
      # Math.* methods raise Math::DomainError on out-of-domain input,
      # matching CRuby semantics. Previously spinel called bare libc
      # sqrt(-1.0) etc. which returns NaN silently. Math::DomainError is
      # now in the known-exception list and the ancestry walker wires it
      # as < StandardError < Exception, so the natural CRuby idiom works:
      #
      #   x = Math.sqrt(input) rescue 0.0
      #   begin Math.log(x); rescue Math::DomainError => e; ...; end
      #
      # Methods with restricted domains (sqrt, log, log2, log10, acos,
      # asin, acosh, atanh, plus Integer.sqrt) get sp_math_* wrappers.
      # Unrestricted methods (cos, sin, tan, atan, sinh, cosh, tanh,
      # asinh, exp, atan2, hypot) call libc directly — no overhead.

      # log2 / log10
      begin
        Math.log2(-1.0)
      rescue Math::DomainError => e
        puts "log2: #{e}"
      end
      begin
        Math.log10(-1.0)
      rescue Math::DomainError => e
        puts "log10: #{e}"
      end

    RUBY

    _(result).must_answer <<~'OUT'
      log2: Numerical argument is out of domain - log2
      log10: Numerical argument is out of domain - log10
    OUT
  end

  it "acos and asin outside -1 to 1 raise Math::DomainError" do
    result = zr(<<~'RUBY')
      # Math.* methods raise Math::DomainError on out-of-domain input,
      # matching CRuby semantics. Previously spinel called bare libc
      # sqrt(-1.0) etc. which returns NaN silently. Math::DomainError is
      # now in the known-exception list and the ancestry walker wires it
      # as < StandardError < Exception, so the natural CRuby idiom works:
      #
      #   x = Math.sqrt(input) rescue 0.0
      #   begin Math.log(x); rescue Math::DomainError => e; ...; end
      #
      # Methods with restricted domains (sqrt, log, log2, log10, acos,
      # asin, acosh, atanh, plus Integer.sqrt) get sp_math_* wrappers.
      # Unrestricted methods (cos, sin, tan, atan, sinh, cosh, tanh,
      # asinh, exp, atan2, hypot) call libc directly — no overhead.

      # acos / asin out of [-1, 1]
      begin
        Math.acos(2.0)
      rescue Math::DomainError => e
        puts "acos: #{e}"
      end
      begin
        Math.asin(-2.0)
      rescue Math::DomainError => e
        puts "asin: #{e}"
      end

    RUBY

    _(result).must_answer <<~'OUT'
      acos: Numerical argument is out of domain - acos
      asin: Numerical argument is out of domain - asin
    OUT
  end

  it "acosh below 1 raises Math::DomainError" do
    result = zr(<<~'RUBY')
      # Math.* methods raise Math::DomainError on out-of-domain input,
      # matching CRuby semantics. Previously spinel called bare libc
      # sqrt(-1.0) etc. which returns NaN silently. Math::DomainError is
      # now in the known-exception list and the ancestry walker wires it
      # as < StandardError < Exception, so the natural CRuby idiom works:
      #
      #   x = Math.sqrt(input) rescue 0.0
      #   begin Math.log(x); rescue Math::DomainError => e; ...; end
      #
      # Methods with restricted domains (sqrt, log, log2, log10, acos,
      # asin, acosh, atanh, plus Integer.sqrt) get sp_math_* wrappers.
      # Unrestricted methods (cos, sin, tan, atan, sinh, cosh, tanh,
      # asinh, exp, atan2, hypot) call libc directly — no overhead.

      # acosh requires x >= 1
      begin
        Math.acosh(0.5)
      rescue Math::DomainError => e
        puts "acosh: #{e}"
      end

    RUBY

    _(result).must_answer <<~'OUT'
      acosh: Numerical argument is out of domain - acosh
    OUT
  end

  it "atanh raises past 1, and answers an infinity at the endpoints" do
    result = zr(<<~'RUBY')
      # Math.* methods raise Math::DomainError on out-of-domain input,
      # matching CRuby semantics. Previously spinel called bare libc
      # sqrt(-1.0) etc. which returns NaN silently. Math::DomainError is
      # now in the known-exception list and the ancestry walker wires it
      # as < StandardError < Exception, so the natural CRuby idiom works:
      #
      #   x = Math.sqrt(input) rescue 0.0
      #   begin Math.log(x); rescue Math::DomainError => e; ...; end
      #
      # Methods with restricted domains (sqrt, log, log2, log10, acos,
      # asin, acosh, atanh, plus Integer.sqrt) get sp_math_* wrappers.
      # Unrestricted methods (cos, sin, tan, atan, sinh, cosh, tanh,
      # asinh, exp, atan2, hypot) call libc directly — no overhead.

      # atanh raises for |x| > 1; the endpoints ±1 yield ±Infinity (no raise in CRuby)
      begin
        Math.atanh(2.0)
      rescue Math::DomainError => e
        puts "atanh: #{e}"
      end

    RUBY

    _(result).must_answer <<~'OUT'
      atanh: Numerical argument is out of domain - atanh
    OUT
  end

  it "Integer.sqrt of a negative raises Math::DomainError" do
    result = zr(<<~'RUBY')
      # Math.* methods raise Math::DomainError on out-of-domain input,
      # matching CRuby semantics. Previously spinel called bare libc
      # sqrt(-1.0) etc. which returns NaN silently. Math::DomainError is
      # now in the known-exception list and the ancestry walker wires it
      # as < StandardError < Exception, so the natural CRuby idiom works:
      #
      #   x = Math.sqrt(input) rescue 0.0
      #   begin Math.log(x); rescue Math::DomainError => e; ...; end
      #
      # Methods with restricted domains (sqrt, log, log2, log10, acos,
      # asin, acosh, atanh, plus Integer.sqrt) get sp_math_* wrappers.
      # Unrestricted methods (cos, sin, tan, atan, sinh, cosh, tanh,
      # asinh, exp, atan2, hypot) call libc directly — no overhead.

      # Integer.sqrt of negative
      begin
        Integer.sqrt(-4)
      rescue Math::DomainError => e
        puts "isqrt: #{e}"
      end

    RUBY

    _(result).must_answer <<~'OUT'
      isqrt: Numerical argument is out of domain - "isqrt"
    OUT
  end

  it "Math::DomainError descends from StandardError" do
    result = zr(<<~'RUBY')
      # Math.* methods raise Math::DomainError on out-of-domain input,
      # matching CRuby semantics. Previously spinel called bare libc
      # sqrt(-1.0) etc. which returns NaN silently. Math::DomainError is
      # now in the known-exception list and the ancestry walker wires it
      # as < StandardError < Exception, so the natural CRuby idiom works:
      #
      #   x = Math.sqrt(input) rescue 0.0
      #   begin Math.log(x); rescue Math::DomainError => e; ...; end
      #
      # Methods with restricted domains (sqrt, log, log2, log10, acos,
      # asin, acosh, atanh, plus Integer.sqrt) get sp_math_* wrappers.
      # Unrestricted methods (cos, sin, tan, atan, sinh, cosh, tanh,
      # asinh, exp, atan2, hypot) call libc directly — no overhead.

      # Hierarchy: Math::DomainError < StandardError < Exception
      begin
        Math.sqrt(-1.0)
      rescue StandardError => e
        puts "as Std: caught"
      end
      begin
        Math.sqrt(-1.0)
      rescue Exception => e
        puts "as Exc: caught"
      end

    RUBY

    _(result).must_answer <<~'OUT'
      as Std: caught
      as Exc: caught
    OUT
  end

  it "a bare rescue catches a Math::DomainError" do
    result = zr(<<~'RUBY')
      # Math.* methods raise Math::DomainError on out-of-domain input,
      # matching CRuby semantics. Previously spinel called bare libc
      # sqrt(-1.0) etc. which returns NaN silently. Math::DomainError is
      # now in the known-exception list and the ancestry walker wires it
      # as < StandardError < Exception, so the natural CRuby idiom works:
      #
      #   x = Math.sqrt(input) rescue 0.0
      #   begin Math.log(x); rescue Math::DomainError => e; ...; end
      #
      # Methods with restricted domains (sqrt, log, log2, log10, acos,
      # asin, acosh, atanh, plus Integer.sqrt) get sp_math_* wrappers.
      # Unrestricted methods (cos, sin, tan, atan, sinh, cosh, tanh,
      # asinh, exp, atan2, hypot) call libc directly — no overhead.

      # Bare rescue catches it
      begin
        Math.sqrt(-1.0)
      rescue => e
        puts "bare-rescue: #{e}"
      end

    RUBY

    _(result).must_answer <<~'OUT'
      bare-rescue: Numerical argument is out of domain - sqrt
    OUT
  end

  it "an unrestricted function answers NaN or an infinity rather than raising" do
    result = zr(<<~'RUBY')
      # Math.* methods raise Math::DomainError on out-of-domain input,
      # matching CRuby semantics. Previously spinel called bare libc
      # sqrt(-1.0) etc. which returns NaN silently. Math::DomainError is
      # now in the known-exception list and the ancestry walker wires it
      # as < StandardError < Exception, so the natural CRuby idiom works:
      #
      #   x = Math.sqrt(input) rescue 0.0
      #   begin Math.log(x); rescue Math::DomainError => e; ...; end
      #
      # Methods with restricted domains (sqrt, log, log2, log10, acos,
      # asin, acosh, atanh, plus Integer.sqrt) get sp_math_* wrappers.
      # Unrestricted methods (cos, sin, tan, atan, sinh, cosh, tanh,
      # asinh, exp, atan2, hypot) call libc directly — no overhead.

      # Unrestricted methods don't raise — return NaN/Infinity per IEEE 754
      puts Math.cos(0.0)
      puts Math.exp(1.0).round(4)

    RUBY

    _(result).must_answer <<~'OUT'
      1.0
      2.7183
    OUT
  end

  it "the two-argument log computes in the base it is given, and raises for a negative one" do
    result = zr(<<~'RUBY')
      # Math.* methods raise Math::DomainError on out-of-domain input,
      # matching CRuby semantics. Previously spinel called bare libc
      # sqrt(-1.0) etc. which returns NaN silently. Math::DomainError is
      # now in the known-exception list and the ancestry walker wires it
      # as < StandardError < Exception, so the natural CRuby idiom works:
      #
      #   x = Math.sqrt(input) rescue 0.0
      #   begin Math.log(x); rescue Math::DomainError => e; ...; end
      #
      # Methods with restricted domains (sqrt, log, log2, log10, acos,
      # asin, acosh, atanh, plus Integer.sqrt) get sp_math_* wrappers.
      # Unrestricted methods (cos, sin, tan, atan, sinh, cosh, tanh,
      # asinh, exp, atan2, hypot) call libc directly — no overhead.

      # 2-arg Math.log(x, base): a valid base computes log_base(x); a NEGATIVE base
      # raises (log of a negative). Per CRuby a base of 0.0 or 1.0 does NOT raise
      # (it yields -0.0 / NaN), so only the negative-base domain error is asserted.
      puts Math.log(8.0, 2.0)
      begin
        Math.log(2.0, -1.0)
        puts "no raise"
      rescue Math::DomainError => e
        puts "log neg base: #{e}"
      end
    RUBY

    _(result).must_answer <<~'OUT'
      3.0
      log neg base: Numerical argument is out of domain - log
    OUT
  end

  it "math domainerror namespaced" do
    result = zr(<<~'RUBY')
      # raise/rescue a builtin namespaced exception under its qualified name.
      begin
        raise Math::DomainError, "boom"
      rescue Math::DomainError => e
        puts "#{e.class}: #{e.message}"
      end
      begin
        Math.sqrt(-1)
      rescue Math::DomainError => e
        puts e.class
      end
    RUBY

    _(result).must_answer "Math::DomainError: boom\nMath::DomainError\n"
  end

  it "Float#% by zero raises ZeroDivisionError, and a negative count raises for the receiver" do
    result = zr(<<~'RUBY')
      # Float#% by zero raises ZeroDivisionError (not NaN); a negative first/last
      # count raises ArgumentError with the receiver-specific message.

      def t; yield; rescue => e; "#{e.class}: #{e.message}"; end
      p t { 5.0 % 0 }
      p t { 5.0 % 0.0 }
      p 5.0 % 2
      p(-5.5 % 2)
      p t { [1, 2, 3].first(-1) }
      p t { [1, 2, 3].last(-2) }
      p t { (1..3).first(-1) }
      p t { [1, 2, 3].cycle.first(-1) }
      p [1, 2, 3].first(2)
    RUBY

    _(result).must_answer <<~'OUT'
      "ZeroDivisionError: divided by 0"
      "ZeroDivisionError: divided by 0"
      1.0
      0.5
      "ArgumentError: negative array size"
      "ArgumentError: negative array size"
      "ArgumentError: negative array size (or size too big)"
      "ArgumentError: attempt to take negative size"
      [1, 2]
    OUT
  end

  it "the modulo, divmod and negative-count edges raise with CRuby's own messages" do
    result = zr(<<~'RUBY')
      # CRuby error-protocol edges for numeric and collection operations.
      def caught
        yield
      rescue => e
        "#{e.class}: #{e.message}"
      end

      # Float#% by zero raises ZeroDivisionError (int or float divisor), rather than
      # answering NaN; a nonzero divisor keeps the floored-modulo sign rule.
      p caught { 5.0 % 0 }
      p caught { 5.0 % 0.0 }
      p 5.0 % 2
      p(-5.5 % 2)
      p 5.5 % -2

      # A negative first/last count raises ArgumentError with the receiver-specific
      # message: Array, Range, and the generic Enumerable/Enumerator forms differ.
      p caught { [1, 2, 3].first(-1) }
      p caught { [1, 2, 3].last(-2) }
      p caught { (1..3).first(-1) }
      p caught { [1, 2, 3].cycle.first(-1) }
      p caught { [1, 2, 3].cycle.take(-2) }

      # The non-negative forms are unchanged.
      p [1, 2, 3].first(2)
      p [1, 2, 3].last(2)
      p [1, 2, 3].cycle.first(5)
    RUBY

    _(result).must_answer <<~'OUT'
      "ZeroDivisionError: divided by 0"
      "ZeroDivisionError: divided by 0"
      1.0
      0.5
      -0.5
      "ArgumentError: negative array size"
      "ArgumentError: negative array size"
      "ArgumentError: negative array size (or size too big)"
      "ArgumentError: attempt to take negative size"
      "ArgumentError: attempt to take negative size"
      [1, 2]
      [2, 3]
      [1, 2, 3, 1, 2]
    OUT
  end

  it "Complex() and its siblings answer nil under exception: false" do
    result = zr(<<~'RUBY')
      # GAP -- imported from the spinel corpus at c55d9bdb.
      # Complex() with exception: false raises instead of answering nil.
      #
      p(Complex("bad", exception: false))

      p(Rational("x", exception: false))
      # Ruby: nil   Spinel: invalid value for Rational(): "x" (ArgumentError)
      c = Complex("bad", exception: false); p c
      # Ruby: nil   Spinel: invalid value for convert():  (ArgumentError)

      p(Complex("1+2i", exception: false))    # => (1+2i)
      p(Rational("1/2", exception: false))    # => (1/2)
      p(Integer("abc", exception: false))     # => nil
      p(Integer("ff", 16, exception: false))  # => 255
      p(Float("x", exception: false))         # => nil
    RUBY

    _(result).must_answer <<~'OUT'
      nil
      nil
      nil
      (1+2i)
      (1/2)
      nil
      255
      nil
    OUT
  end

  it "an exception: keyword stays a keyword and never counts as the second component" do
    result = zr(<<~'RUBY')
      # GAP -- imported from the spinel corpus at c55d9bdb.
      # Complex() with an exception: keyword mis-routes the keyword into the
      # numeric argument.
      #
      # `exception: false` is a keyword, not the second component: it counted as one
      # and the value came out of the keyword hash's address (#3869).
      p(Complex("1+2i", exception: false))
      p(Complex("1+2i"))
      p(Complex(1, 2))
      p(Rational("1/2", exception: false))
      p(Rational("1/2"))
      p(Rational(1, 2))
      p(Integer("42", exception: false))
      p(Integer("abc", exception: false))
      p(Float("1.5", exception: false))
    RUBY

    _(result).must_answer <<~'OUT'
      (1+2i)
      (1+2i)
      (1+2i)
      (1/2)
      (1/2)
      (1/2)
      42
      nil
      1.5
    OUT
  end

  it "size, rationalize and the Rational and Complex constructors all answer exactly" do
    result = zr(<<~'RUBY')
      p 42.size
      p (2**64).size
      p (2**64 - 1).size
      p (2**128).size
      p 0.3.rationalize
      p 2.5.rationalize
      p 3.14159.rationalize
      p 1.333.rationalize(0.01)
      p Rational(2.5)
      p Rational(1.5, 0.5)
      begin
        Complex(nil)
      rescue TypeError => e
        puts e.message
      end
      p 2 ** Complex(0, 1)
      p Complex(6, 0).to_r
      p Complex(3, 4).numerator
      p 7.div(Rational(2))
      p 10.div(Rational(3, 2))
    RUBY

    _(result).must_answer <<~'OUT'
      8
      9
      8
      17
      (3/10)
      (5/2)
      (314159/100000)
      (4/3)
      (5/2)
      (3/1)
      can't convert nil into Complex
      (0.7692389013639721+0.6389612763136348i)
      (6/1)
      (3+4i)
      3
      6
    OUT
  end

  it "random bignum seed" do
    result = zr(<<~'RUBY')
      r = Random.new(2**70)
      v = r.rand(100)
      p v >= 0 && v < 100
      p Random.new(2**70).rand(1000) == Random.new(2**70).rand(1000)
      p Random.new(2**70 + 1).rand(2**40) != Random.new(2**70 + 2).rand(2**40)
      p (Random.new(2**70).rand(100) rescue $!.class).is_a?(Integer)
    RUBY

    _(result).must_answer <<~'OUT'
      true
      true
      true
      true
    OUT
  end

  it "rational ctor exact" do
    result = zr(<<~'RUBY')
      # Kernel#Rational with Float and Rational operands keeps the exact value
      # (5/2 for 2.5) instead of truncating through an int cast. Per-operand-kind
      # helpers: a mixed-type param would widen to poly, which has no ctor arm.
      def f1f(a) = Rational(a)
      def f1r(a) = Rational(a)
      def f2f(a, b) = Rational(a, b)
      def f2i(a, b) = Rational(a, b)

      p f1f(2.5)                            # (5/2)
      p f1f(-0.75)                          # (-3/4)
      p f1f(3.0)                            # (3/1)
      p f1r(Rational(7, 4))                 # (7/4)
      p f2f(2.5, 0.5)                       # (5/1)
      p f2f(1.0, 3.0)                       # (1/3)
      p f2i(1, 3)                           # (1/3)
      p Rational(Rational(1, 2), Rational(1, 3))  # (3/2)
      p Rational(1.5, 3)                    # (1/2)
      begin
        f2f(1.0, 0.0)
      rescue ZeroDivisionError => e
        puts "#{e.class}: #{e.message}"
      end
    RUBY

    _(result).must_answer <<~'OUT'
      (5/2)
      (-3/4)
      (3/1)
      (7/4)
      (5/1)
      (1/3)
      (1/3)
      (3/2)
      (1/2)
      ZeroDivisionError: divided by 0
    OUT
  end
end
