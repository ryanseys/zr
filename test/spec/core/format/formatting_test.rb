# frozen_string_literal: true

require "spec_helper"

describe "Format: formatting and inspection" do
  it "a format argument that is itself a call is rooted where it stands" do
    result = zr(<<~'RUBY')
      # A format() argument that is itself a call rooting its own operands used to
      # leak that rooting decl into the PolyArray_push argument position
      # (`sp_PolyArray_push(_t, sp_RbVal _t2 = ...;` -- illegal C, #1508/#1498).
      def f(v) = v * 1000.0
      puts format("L: %.3f; A: %.3f; X: %.3f", f(0.001), f(0.0025), f(0.5))
      puts format("%d/%s", f(2).to_i, "ok")
    RUBY

    _(result).must_answer "L: 1.000; A: 2.500; X: 500.000\n2000/ok\n"
  end

  it "the full C directive set answers, plus ruby's named and positional references" do
    result = zr(<<~'RUBY')
      # `format` (aka `sprintf`, and `String#%`) supports the full C-style directive
      # set, plus Ruby's named and positional references.

      # Named references pull from a Hash / keyword arguments.
      puts format("%<name>s is %<age>d", name: "Ada", age: 36)   # Ada is 36
      puts format("%{greeting}, world!", greeting: "Hello")      # Hello, world!

      # Binary (%b / %B) and the `#` alternate form add a radix prefix.
      puts format("%b", 10)                                      # 1010
      puts format("%#b", 10)                                     # 0b1010
      puts format("%#x / %#o", 255, 8)                           # 0xff / 010
      puts format("%08b", 10)                                    # 00001010

      # `*` reads the width (or precision) from an argument; a negative width
      # left-justifies.
      puts format("%*d|", 5, 42)                                 #    42|
      puts format("%-*d|", 5, 42)                                # 42   |
      puts format("%.*f", 2, 3.14159)                            # 3.14

      # Positional (`N$`) references reuse and reorder arguments.
      puts format("%2$s %1$s", "world", "hello")                 # hello world

      # Uppercase variants and hex float.
      puts format("%X", 255)                                     # FF
      puts format("%a", 0.5)                                     # 0x1p-1

      # All of this works through String#% too.
      puts("%<x>05.2f" % { x: 3.14159 })                         # 03.14
    RUBY

    _(result).must_answer <<~'OUT'
      Ada is 36
      Hello, world!
      1010
      0b1010
      0xff / 010
      00001010
         42|
      42   |
      3.14
      hello world
      FF
      0x1p-1
      03.14
    OUT
  end

  it "the named, positional, star-width and alternate forms each answer through format and String#%" do
    result = zr(<<~'RUBY')
      puts format("%<name>s is %<age>d", name: "Ada", age: 36)
      puts format("%#b / %#x", 10, 255)
      puts format("%*d|", 5, 42)
      puts format("%2$s %1$s", "world", "hello")
      puts format("%a", 0.5)
      puts("%<x>05.2f" % { x: 3.14159 })
    RUBY

    _(result).must_answer "Ada is 36\n0b1010 / 0xff\n   42|\nhello world\n0x1p-1\n03.14\n"
  end

  it "a star width or precision takes the next argument, and a missing name raises KeyError" do
    result = zr(<<~'RUBY')
      # format/sprintf: dynamic width/precision (%*d, %.*f) consume the next
      # positional argument; %<name>conv and %{name} reference a hash argument by
      # key (missing keys raise KeyError). Unknown specs used to echo verbatim.
      puts format("%*d", 5, 3)
      puts format("%-*d|", 5, 3)
      puts format("%*d", -5, 3) + "|"
      puts format("%.*f", 2, 3.14159)
      puts format("%08.*f", 3, 3.14159)
      puts format("%<val>d", val: 42)
      puts format("%<val>05d", val: 42)
      puts format("%{val}", val: 42)
      puts format("%{a}-%{b}", a: "x", b: 9)
      puts sprintf("%<f>.2f", f: 1.2345)
      begin
        format("%<nope>d", val: 1)
      rescue KeyError => e
        puts "KeyError"
      end
    RUBY

    _(result).must_answer <<~'OUT'
          3
      3    |
      3    |
      3.14
      0003.142
      42
      00042
      42
      x-9
      1.23
      KeyError
    OUT
  end

  it "%.Nf rounds the way ruby rounds, and a precision past the shortest digits expands exactly" do
    result = zr(<<~'RUBY')
      puts format("%.2f", 2.675)
      puts format("%.1f", 0.15)
      vals = [2.675, 1.005, 8.835, 0.145, 1.115, 2.345, 3.045, 1.255, 0.615, 4.985]
      puts vals.map { |v| format("%.2f", v) }.join(" ")
      puts [0.15, 0.25, 0.35, 0.45, 0.55, 0.65, 0.75, 0.85].map { |v| format("%.1f", v) }.join(" ")
      puts [-2.675, -2.345, -0.15].map { |v| format("%.2f", v) }.join(" ")

      # a precision past the shortest digits keeps the exact expansion
      puts format("%.20f", 0.1)
      puts format("%.17f", 2.675)

      # the field machinery is unchanged
      puts format("%08.2f", -2.675)
      puts format("%+.2f", 2.675)
      puts format("%10.2f|", 2.675)
      puts format("%-10.2f|", 2.675)
      puts format("%.0f %.0f %.0f", 2.5, 3.5, 0.5)
      puts format("%f", 1.0 / 3)
      puts format("%.2f", 0.005)
      puts format("%.2e %.3g", 2.675, 2.675)

      printf("%.2f %.2f\n", 2.675, 2.345)
      puts "%.2f" % 2.675
    RUBY

    _(result).must_answer <<~'OUT'
      2.68
      0.2
      2.68 1.00 8.84 0.14 1.12 2.34 3.04 1.26 0.62 4.98
      0.2 0.2 0.4 0.4 0.6 0.6 0.8 0.8
      -2.68 -2.34 -0.15
      0.10000000000000000555
      2.67499999999999982
      -0002.68
      +2.68
            2.68|
      2.68      |
      2 4 0
      0.333333
      0.01
      2.68e+00 2.68
      2.68 2.34
      2.68
    OUT
  end

  it "the + and space flags reach the non-decimal conversions, and %u is %d" do
    result = zr(<<~'RUBY')

      # The non-decimal conversions honour '+' and ' ': C's printf drops both on
      # them, so every signed form was missing its sign
      p(format("%+x", 255))
      p(format("% x", 255))
      p(format("%+X", 255))
      p(format("%+o", 8))
      p(format("% o", 8))
      p(format("%+b", 5))
      p(format("% b", 5))
      p(format("%+5x", 255))
      p(format("%+05x", 255))
      p(format("%-+6x", 255) + "|")
      p(format("% #x", 255))
      p(format("%+#o", 8))
      p(format("%+8b", 5))

      # %u is %d, not a C-style unsigned conversion (it was rejected outright)
      p(format("%u", 42))
      p(format("%+u", 42))
      p(format("%u", -42))

      # the unsigned forms that already worked keep working, negatives included
      p(format("%x", 255))
      p(format("%+d", 42))
      p(format("% d", 42))
      p(format("%x", -255))
      p(format("%o", -8))
      p(format("%b", -5))
      p(format("%#x", -255))
      p(format(".8x: %.8x", -255))
      p(format("%08x", -255))
      p(format("%#o", -1))
      p(format("%#.0o", 0))
      p(format("%#b", 5))
      p(format("%#X", 255))
      p("%05.2f %x %s" % [1.5, 255, "s"])

      # a later include wins, and its super reaches the earlier one
      module A; def who; "A"; end; end
      module B; def who; "B>" + super; end; end
      module C; def who; "C>" + super; end; end
      class K1; include A; include B; end
      class K2; include A; include B; include C; end
      class K3; include A; include B; def who; "K3>" + super; end; end
      class K4; include A; include C; end
      p K1.new.who
      p K2.new.who
      p K3.new.who
      p K4.new.who
      p K2.ancestors

      # $! is the exception being handled: it goes back to nil when the handler
      # exits, including when the handler exits by raising out of a modifier rescue
      def m; raise "a"; rescue; raise; end
      r = (m rescue 1)
      p r
      p $!
      begin; raise "b"; rescue; p $!.message; end
      p $!
      def n; raise "c"; rescue; $!.message; end
      p n
      p $!
    RUBY

    _(result).must_answer <<~'OUT'
      "+ff"
      " ff"
      "+FF"
      "+10"
      " 10"
      "+101"
      " 101"
      "  +ff"
      "+00ff"
      "+ff   |"
      " 0xff"
      "+010"
      "    +101"
      "42"
      "+42"
      "-42"
      "ff"
      "+42"
      " 42"
      "..f01"
      "..70"
      "..1011"
      "0x..f01"
      ".8x: ..ffff01"
      "..ffff01"
      "..7"
      "0"
      "0b101"
      "0XFF"
      "01.50 ff s"
      "B>A"
      "C>B>A"
      "K3>B>A"
      "C>A"
      [K2, C, B, A, Object, Kernel, BasicObject]
      1
      nil
      "b"
      nil
      "c"
      nil
    OUT
  end

  it "%g shows a fixed count of significant digits, and %#g keeps the trailing zeros" do
    result = zr(<<~'RUBY')
      # `%g` picks between `%e` and `%f` and shows a fixed number of SIGNIFICANT
      # digits -- six by default, `%.Ng` for N, and `%#g` keeps the trailing zeros
      # that plain `%g` strips. zr ignores the precision entirely and prints the
      # shortest representation that round-trips:
      #
      #     format("%g", 123456789.0)     ruby "1.23457e+08"   zr "1.23456789e+08"
      #     format("%.3g", 123456789.0)   ruby "1.23e+08"      zr "1.23456789e+08"
      #     format("%.10g", 123456789.0)  ruby "123456789"     zr "1.23456789e+08"
      #     format("%#g", 1.5)            ruby "1.50000"       zr "1.5"
      #
      # `%g` is the directive for "show me this number readably", so it is what a
      # report, a table or a log line uses -- and a shortest-round-trip answer defeats
      # the point of asking for a fixed width. The choice of `%e` vs `%f` also
      # depends on the precision (ruby switches when the exponent is < -4 or >= the
      # precision), which is why `%.10g` above comes out positional in ruby and
      # scientific in zr.
      #
      # `%e` and `%f` already honour their precision, so only `%g`/`%G` diverge.

      p [123456789.0, 1234.5678, 0.000012345678, 1.0, 100.0, 0.0].map { format("%g", _1) }
      p [format("%.3g", 123456789.0), format("%.10g", 123456789.0), format("%.1g", 1234.0)]
      p format("%G", 123456789.0)
      p [format("%g", 1.500), format("%#g", 1.5)]

      # These already agree.
      p [format("%e", 123456789.0), format("%.2e", 1234.5), format("%f", 1.5), format("%.2f", 1.5)]
    RUBY

    _(result).must_answer <<~'OUT'
      ["1.23457e+08", "1234.57", "1.23457e-05", "1", "100", "0"]
      ["1.23e+08", "123456789", "1e+03"]
      "1.23457E+08"
      ["1.5", "1.50000"]
      ["1.234568e+08", "1.23e+03", "1.500000", "1.50"]
    OUT
  end

  it "%a and %A render a float in hexadecimal" do
    result = zr(<<~'RUBY')
      # %a/%A hex-float directives render through C's own %a (C99, portable),
      # via String#%, format, and sprintf.
      p("%a" % 1.0)
      p(format("%a", 0.5))
      p(sprintf("%A", 2.0))
      p("%a" % 255.5)
    RUBY

    _(result).must_answer <<~'OUT'
      "0x1p+0"
      "0x1p-1"
      "0X1P+1"
      "0x1.ffp+7"
    OUT
  end

  it "a malformed directive and a mixed reference style each raise ArgumentError" do
    result = zr(<<~'RUBY')
      p(format("%.*f", -2, 3.14159))
      r001 = (format("%") rescue $!.class); p r001
      r002 = (format("%1$s %s", "a", "b") rescue $!.class); p r002
      r003 = (format("%d %<a>d", 1, { a: 2 }) rescue $!.class); p r003
      p(format("%*d", -6, 42))
      r004 = (format("%z", 1) rescue $!.class); p r004
      r005 = (format("%s") rescue $!.class); p r005
      p(format("%.2f", 3.14159))
      p(format("%1$s %1$s", "a"))
      p(format("%<a>d", { a: 2 }))
    RUBY

    _(result).must_answer <<~'OUT'
      "3.141590"
      ArgumentError
      ArgumentError
      ArgumentError
      "42    "
      ArgumentError
      ArgumentError
      "3.14"
      "a a"
      "2"
    OUT
  end

  it "a missing name raises KeyError worded for the spelling, and unparseable text raises" do
    result = zr(<<~'RUBY')
      # GAP -- imported from the spinel corpus at c55d9bdb.
      # The missing-key KeyError message brackets the key with <> where ruby uses
      # {}.
      #
      # A missing key in a `%{name}` / `%<name>s` format is CRuby's KeyError, not a
      # nil that rendered as the empty string, and a String argument to an integer
      # conversion goes through Integer()'s parse, so unparseable text raises rather
      # than reading as zero.
      p(("%d" % "x" rescue $!.class))
      p(("%{z}" % { a: 1 } rescue $!.class))
      p(("%<z>d" % { a: 1 } rescue $!.class))
      r = (format("%{z}", a: 1) rescue $!.class); p r
      p("%d" % "12")
      p("%{a}" % { a: 1 })
      p(("%x" % "zz" rescue $!.class))
      p("%x" % "255")
      p("%<a>d" % { a: 5 })
      p("%{a}-%{b}" % { a: 1, b: 2 })
      p(("%{zz}" % { a: 1 } rescue $!.message))
      p(("%<zz>d" % { a: 1 } rescue $!.message))
    RUBY

    _(result).must_answer <<~'OUT'
      ArgumentError
      KeyError
      KeyError
      KeyError
      "12"
      "1"
      ArgumentError
      "ff"
      "5"
      "1-2"
      "key{zz} not found"
      "key<zz> not found"
    OUT
  end

  it "a named reference reads a symbol-keyed hash, held in a local or returned by a method" do
    result = zr(<<~'RUBY')
      # Named references in String#% (and the `%{name}` shorthand) read from a
      # symbol-keyed hash argument. Previously rejected at compile time.
      #   %<name>spec  -> the value formatted with `spec`
      #   %{name}      -> the value's to_s
      def s(x); x; end

      p("%<n>d" % {n: 9})                      # "9"
      p("%<x>05.2f" % {x: 3.14159})            # "03.14"
      p("%<a>s-%<b>s" % {a: "hi", b: "yo"})    # "hi-yo"
      p("%{n}" % {n: 5})                       # "5"
      p("%{greeting}, world" % {greeting: "Hello"})  # "Hello, world"

      # Named and brace forms mixed, with literal text and a literal percent.
      p("[%<k>d] %{v}!" % {k: 3, v: "x"})      # "[3] x!"
      p("100%% as %<n>d" % {n: 7})             # "100% as 7"

      # Routed through a method (defeats constant-folding).
      p("%<n>d" % s({n: 42}))                  # "42"

      # A hash held in a local works too.
      h = {label: "qty", amount: 12}
      p("%<label>s=%<amount>d" % h)            # "qty=12"
    RUBY

    _(result).must_answer <<~'OUT'
      "9"
      "03.14"
      "hi-yo"
      "5"
      "Hello, world"
      "[3] x!"
      "100% as 7"
      "42"
      "qty=12"
    OUT
  end

  it "a name scanned out of the format still matches the hash's key byte for byte" do
    result = zr(<<~'RUBY')
      # A format's `%<name>` / `%{name}` is scanned into a C stack buffer and then
      # compared against the hash's keys. The comparison read a marker byte in FRONT
      # of both operands to recover a length that can carry an embedded NUL -- and a
      # stack buffer has no marker, so it read whatever preceded it on the stack.
      # When that byte happened to look like a marker it read a bogus header and
      # answered a garbage length, and the lookup missed:
      #
      #   key<n> not found (KeyError)
      #
      # Nondeterministic by construction, which is what made this test flaky.
      printf("%<n>04d\n", n: 7)
      printf("%{k}\n", k: 3)
      printf("%<x>s|%{y}\n", x: "a", y: "b")
      p(format("%<v>d", v: 42))
      p(format("%{one}-%{two}", one: "a", two: "b"))
      p(format("%<a>s%<b>s%<c>s", a: 1, b: 2, c: 3))

      # a name that is not there is CRuby's KeyError, worded for the spelling used
      # -- and raising out of the lookup must not leak the caller's format buffer
      begin
        format("%<missing>d", other: 1)
      rescue KeyError => e
        p [e.class, e.message]
      end
      begin
        format("%{missing}", other: 1)
      rescue KeyError => e
        p e.message
      end
      50.times do
        begin
          format("%{gone}", other: 1)
        rescue KeyError
        end
      end
      puts "no leak"

      # repeated in a loop, where the stack under the buffer keeps changing
      20.times { |i| print format("%<i>02d,", i: i) }
      puts
    RUBY

    _(result).must_answer <<~'OUT'
      0007
      3
      a|b
      "42"
      "a-b"
      "123"
      [KeyError, "key<missing> not found"]
      "key{missing} not found"
      no leak
      00,01,02,03,04,05,06,07,08,09,10,11,12,13,14,15,16,17,18,19,
    OUT
  end

  it "a numeric conversion refuses what is not a number, and takes a bignum whole" do
    result = zr(<<~'RUBY')
      # A numeric conversion in format/sprintf answered 0 for an argument that is not
      # a number at all -- nil, a Symbol, an Array -- where CRuby refuses (#4010).
      # %s accepts anything and is unaffected.
      [nil, true, false, :s, [1], { a: 1 }].each do |v|
        ["%d", "%f", "%x"].each do |spec|
          begin
            p format(spec, v)
          rescue TypeError => e
            puts "#{spec} #{v.inspect} => #{e.class}: #{e.message}"
          end
        end
        p format("%s", v)
      end

      # found while fixing it: a BIGNUM does not fit the long long the conversions
      # format, and truncating printed 0 for every value past 64 bits
      p format("%d", 2**70)
      p format("%x", 2**70)
      p format("%o", 2**70)
      p format("%b", 2**70)
      p format("%d", -(2**70))
      p format("%f", 2**70)
      p format("%+d", 2**70)
      p format("%#x", 2**70)
      p format("%30d|", 2**70)
      p format("%-30d|", 2**70)

      # and a String argument reached the float conversions as a zero
      p format("%f", "7")
      p format("%e", "7")

      # the ordinary conversions keep working
      p format("%d", 5)
      p format("%d", 2.5)
      p format("%d", "7")
      p format("%05.2f", 2.5)
      p format("%x", 255)
      p sprintf("%s-%d", "a", 1)
    RUBY

    _(result).must_answer <<~'OUT'
      %d nil => TypeError: can't convert nil into Integer
      %f nil => TypeError: can't convert nil into Float
      %x nil => TypeError: can't convert nil into Integer
      ""
      %d true => TypeError: can't convert true into Integer
      %f true => TypeError: can't convert true into Float
      %x true => TypeError: can't convert true into Integer
      "true"
      %d false => TypeError: can't convert false into Integer
      %f false => TypeError: can't convert false into Float
      %x false => TypeError: can't convert false into Integer
      "false"
      %d :s => TypeError: can't convert Symbol into Integer
      %f :s => TypeError: can't convert Symbol into Float
      %x :s => TypeError: can't convert Symbol into Integer
      "s"
      %d [1] => TypeError: can't convert Array into Integer
      %f [1] => TypeError: can't convert Array into Float
      %x [1] => TypeError: can't convert Array into Integer
      "[1]"
      %d {a: 1} => TypeError: can't convert Hash into Integer
      %f {a: 1} => TypeError: can't convert Hash into Float
      %x {a: 1} => TypeError: can't convert Hash into Integer
      "{a: 1}"
      "1180591620717411303424"
      "400000000000000000"
      "200000000000000000000000"
      "10000000000000000000000000000000000000000000000000000000000000000000000"
      "-1180591620717411303424"
      "1180591620717411303424.000000"
      "+1180591620717411303424"
      "0x400000000000000000"
      "        1180591620717411303424|"
      "1180591620717411303424        |"
      "7.000000"
      "7.000000e+00"
      "5"
      "2"
      "7"
      "02.50"
      "ff"
      "a-1"
    OUT
  end

  it "too few arguments and a bad directive raise, beside a block pattern and $!" do
    result = zr(<<~'RUBY')
      # gsub/sub with a String pattern and a block; format/% raising on too-few
      # arguments and malformed directives; $! visible inside rescue modifiers;
      # a Symbol variable as a block argument (&op) and via to_proc.
      p "hello".gsub("l") { |m| m.upcase }
      p "hello".sub("l") { |m| m.upcase }
      p "hello".gsub("l", &:upcase)
      r1 = (format("%d %d %d", 1, 2) rescue "too few")
      p r1
      begin
        "%,d" % 5
      rescue ArgumentError => e
        p e.message
      end
      begin
        "%z" % 1
      rescue ArgumentError => e
        p e.message
      end
      p format("%05.2f|%x|%c|%%", 3.14159, 255, 65)
      p format("%2$s %1$s", "world", "hello")
      r = (raise "boom" rescue $!.message)
      p r
      r2 = ("%z" % 1 rescue $!.message)
      p r2
      raise "st" rescue puts $!.message
      p $!.nil?
      op = :upcase
      p ["a", "b"].map(&op)
      op2 = :+
      p [1, 2, 3, 4].reduce(&op2)
      a = :upcase
      up = a.to_proc
      p up.call("hi")
      flag = [true, false].first
      sel = flag ? :upcase : :downcase
      p ["ab"].map(&sel)
    RUBY

    _(result).must_answer <<~'OUT'
      "heLLo"
      "heLlo"
      "heLLo"
      "too few"
      "malformed format string - %,"
      "malformed format string - %z"
      "03.14|ff|A|%"
      "hello world"
      "boom"
      "malformed format string - %z"
      st
      true
      ["A", "B"]
      10
      "HI"
      ["AB"]
    OUT
  end

  it "%s calls to_s on every argument kind, and %f spells Inf, -Inf and NaN ruby's way" do
    result = zr(<<~'RUBY')
      # %s calls to_s on every argument kind (it printed empty for symbols,
      # collections, booleans, and user objects); %f prints non-finite floats
      # with Ruby's casing (Inf/-Inf/NaN, where C printf lowercases).
      puts format("%s", :sym)
      puts format("%s", [1, 2])
      puts format("%s", true)
      puts format("%s|", nil)
      puts format("%5s|", :ab)
      class FmtC
        def to_s = "X"
      end
      puts format("%s", FmtC.new)
      puts format("%.3f", Float::INFINITY)
      puts format("%f", -Float::INFINITY)
      puts format("%.2f", Float::NAN)
      puts format("%s", 42)
    RUBY

    _(result).must_answer "sym\n[1, 2]\ntrue\n|\n   ab|\nX\nInf\n-Inf\nNaN\n42\n"
  end

  it "a splatted array variable contributes its elements as separate arguments" do
    result = zr(<<~'RUBY')
      # A splatted Array variable contributes its ELEMENTS to format/sprintf/printf:
      # it used to be pushed as one boxed array, so the conversions went unfed and the
      # call raised "too few arguments" (#3957).
      args = ["a", "b"]
      p format("%s%s", *args)
      p sprintf("%s/%s", *args)
      p format("%s%s%s", "x", *args)

      nums = [1, 2, 3]
      p format("%d%d%d", *nums)

      mixed = ["ab", 42, 3.5]
      p format("%s%d%.1f", *mixed)

      fmt = "%s-%s"
      p format(fmt, *args)

      printf("%s|%s\n", *args)
      $stdout.printf("%s;%s\n", *args)

      path = "/tmp/spinel_format_splat_test.txt"
      File.open(path, "w") { |f| f.printf("%s=%s\n", *args) }
      p File.read(path)
      File.delete(path)

      # an empty splat leaves a format with no conversions alone
      none = []
      p format("plain", *none)
    RUBY

    _(result).must_answer <<~'OUT'
      "ab"
      "a/b"
      "xab"
      "123"
      "ab423.5"
      "a-b"
      a|b
      a;b
      "a=b\n"
      "plain"
    OUT
  end

  it "kernel array format negx wave10" do
    result = zr(<<~'RUBY')
      # Kernel#Array enumerates Ranges and Hashes; format %x/%X/%o of a negative
      # renders Ruby's infinite-two's-complement ..-notation (sign flags switch
      # to signed magnitude). Complex(String) and the Rational division family.
      p(Complex("2+3i"))
      p(Rational(7,2) % Rational(1,3))
      p(Rational(7,2).divmod(Rational(1,3)))
      p(Rational(7,2).div(Rational(1,3)))
      p(Rational(7,2).fdiv(Rational(1,3)))
      p(Rational(7,2).quo(Rational(1,3)))
      p(Rational(7,2).remainder(Rational(1,3)))
      p(Array(1..3))
      p(Array({a: 1}))
      p(Array(nil))
      p(format("%x", -1))
      p(format("%o", -8))
      p(format("%x", 255))
      p(format("%+x", -1))
      p(format("%X", -1))
      p(format("%x", -256))
      p(format("%o", 64))
    RUBY

    _(result).must_answer <<~'OUT'
      (2+3i)
      (1/6)
      [10, (1/6)]
      10
      10.5
      (21/2)
      (1/6)
      [1, 2, 3]
      [[:a, 1]]
      []
      "..f"
      "..70"
      "ff"
      "-1"
      "..F"
      "..f00"
      "100"
    OUT
  end

  it "printf percent b" do
    result = zr(<<~'RUBY')
      # printf with a %b/%B binary conversion routes through the Ruby formatter
      # (the String#% / format engine): C printf has no portable %b -- glibc
      # 2.35+ renders it natively (which masked this on Linux), macOS prints a
      # literal b. Mixed directives and width/flag forms included.
      printf("%b\n", 10)
      printf("%08b|\n", 5)
      printf("%#b %B\n", 5, 5)
      printf("x=%d b=%b s=%s\n", 7, 7, "ok")
      p format("%b", 255)
      p sprintf("%09b", 6)
    RUBY

    _(result).must_answer <<~'OUT'
      1010
      00000101|
      0b101 101
      x=7 b=111 s=ok
      "11111111"
      "000000110"
    OUT
  end

  it "prints nonfinite floats with ruby casing" do
    result = zr(<<~'RUBY')
      # %f/%e/%g print Inf/-Inf/NaN (Ruby's casing), not C's lowercase inf.

      puts format("%.3f", Float::INFINITY)
      puts format("%f", -Float::INFINITY)
      puts format("%.2f", Float::NAN)
      puts format("%e", Float::INFINITY)
    RUBY

    _(result).must_answer <<~'OUT'
      Inf
      -Inf
      NaN
      Inf
    OUT
  end

  it "sprintf long interp" do
    result = zr(<<~'RUBY')
      # sp_sprintf truncated string-interpolation results to 4095 bytes.
      #
      # Every Ruby string interpolation ("...#{x}...") compiles to
      # sp_sprintf (see compile_interpolated in spinel_codegen.rb), which
      # formatted into a fixed `char _sp_tmp[4096]` stack buffer and then
      # clamped the result length to sizeof(buf)-1 -- silently dropping
      # everything past 4095 bytes. vsnprintf already returns the would-be
      # length, so the fix re-renders into a correctly-sized heap buffer for
      # the overflow case (the common <4096 path keeps the stack temp +
      # memcpy fast path).
      #
      # Surfaced in roundhouse view emit: a lowering that coalesces
      # `io << a; io << b; io << c` append runs into a single
      # `io << "...#{}..."` produced interpolations larger than 4096 bytes,
      # which truncated rendered HTML pages mid-content.

      big = "A" * 5000
      out = "[#{big}]"
      # Full length must survive, and both ends must be intact (a mid-string
      # clamp would keep the head but drop the closing bracket).
      puts out.length
      puts out[0, 1]
      puts out[out.length - 1, 1]
    RUBY

    _(result).must_answer <<~'OUT'
      5002
      [
      ]
    OUT
  end

  it "sprintf positional" do
    result = zr(<<~'RUBY')
      puts "%1$s%2$s%1$s%2$s" % ["ab", "cd"]
      puts "%2$s %1$s" % ["world", "hello"]
      puts "%2$05d|%1$s|%2$d|%3$.2f" % [7, 42, 3.14159]
      puts "%1$s-%1$s-%1$s" % ["x"]
      puts "%s-%d" % ["x", 9]
    RUBY

    _(result).must_answer <<~'OUT'
      abcdabcd
      hello world
      00042|7|42|3.14
      x-x-x
      x-9
    OUT
  end

  it "string format poly array rhs" do
    result = zr(<<~'RUBY')
      # String#% with a right-hand side whose static type is poly (a scalar at one
      # call site, an Array at another) must spread an Array value across the format
      # directives at runtime. Spinel previously wrapped a poly RHS in a one-element
      # array unconditionally, so an Array read zeros.
      def fmt(f, v); f % v; end

      # v unifies to poly: it receives an Integer, an Array, a Float, and a String.
      p fmt("%d", 5)               # "5"       (scalar stays a one-element list)
      p fmt("%d-%d", [1, 2])       # "1-2"     (Array spread across directives)
      p fmt("%03d/%02d", [7, 3])   # "007/03"
      p fmt("%.1f", 2.5)           # "2.5"
      p fmt("%s!", "hi")           # "hi!"
      p fmt("%s=%s", ["k", "v"])   # "k=v"     (string array spread)
      p fmt("%d %s", [1, "x"])     # "1 x"     (mixed-type array spread)

      # A single-element array still fills one directive.
      p fmt("[%d]", [9])           # "[9]"
    RUBY

    _(result).must_answer <<~'OUT'
      "5"
      "1-2"
      "007/03"
      "2.5"
      "hi!"
      "k=v"
      "1 x"
      "[9]"
    OUT
  end

  it "string format polyarr" do
    result = zr(<<~'RUBY')
      # String#% with a poly_array (mixed-type) argument.
      puts "%s is %d" % ["age", 25]
      puts "%s: %.2f" % ["pi", 3.14159]
      puts "[%5d] %-10s" % [42, "hi"]
      puts "%x" % [255]
      puts "%-3s %s" % ["a", "b"]
    RUBY

    _(result).must_answer "age is 25\npi: 3.14\n[   42] hi        \nff\na   b\n"
  end

  it "string format scalar operands" do
    result = zr(<<~'RUBY')
      # String#% with a bare nil / true / Rational operand: scalars box into
      # the one-element format path, and the float directives coerce a boxed
      # Rational (%.2f % (1r/3) => "0.33").
      p("x=%s" % nil)
      p("%.2f" % (1r/3))
      p("%s!" % true)
      p("%d" % 5)
    RUBY

    _(result).must_answer <<~'OUT'
      "x="
      "0.33"
      "true!"
      "5"
    OUT
  end
end
