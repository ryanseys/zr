# frozen_string_literal: true

require "spec_helper"

describe "String: case mapping" do
  it "capitalize titlecases the digraphs" do
    result = ze0(<<~'RUBY')
      # `String#capitalize` maps the Unicode digraphs to their TITLECASE forms
      # (U+01F3 dz -> U+01F2 Dz, and the Lj/Nj/Dz families), and #swapcase of a
      # titlecase char lowercases per-half ("Dz" -> "dZ"). zeo maps both
      # through the full-uppercase table. #upcase and #downcase already match;
      # only the titlecase third of the case-mapping triple is missing. (Found
      # by the 2026-08-24 probe sweep.)
      p "ǳ".capitalize
      p ["ǉx".capitalize, "ǌx".capitalize, "ǆx".capitalize]
      p "ǲ".swapcase
      p "ǳ".upcase
      p "ǲ".downcase
    RUBY

    _(result).must_answer <<~'OUT'
      "ǲ"
      ["ǈx", "ǋx", "ǅx"]
      "dZ"
      "Ǳ"
      "ǳ"
    OUT
  end

  it "casecmp folds ascii and casecmp p folds unicode" do
    result = ze0(<<~'RUBY')
      # casecmp folds ASCII alone and casecmp? folds all of Unicode, as
      # CRuby's str_casecmp and str_casecmp_p do. An operand the receiver has
      # no encoding in common with answers nil.
      def t = yield rescue [$!.class, $!.message]

      p t { "Ä".casecmp("ä") }, t { "Ä".casecmp?("ä") }, t { "ß".casecmp?("ss") }, t { "ﬃ".casecmp?("ffi") }
      p t { "abc".casecmp("ABD") }, t { "b".casecmp("A") }, t { "a".casecmp(1) }, t { "a".casecmp?(1) }
      p t { "İstanbul".downcase(:turkic) }, t { "Iı".swapcase(:turkic) }, t { "ΣΑΣ".downcase(:fold) }
      p t { "é".casecmp("É".b) }, t { "a".casecmp("A".b) }, t { "é".casecmp?("É") }

    RUBY

    _(result).must_answer <<~'OUT'
      -1
      true
      true
      true
      -1
      1
      nil
      nil
      "istanbul"
      "ıI"
      "σασ"
      nil
      0
      true
    OUT
  end

  it "reader named after string method" do
    result = ze0(<<~'RUBY')
      # A reader whose name is also a String method, read through a poly receiver.
      # The poly shortcuts stringified the receiver and applied the String method, so
      # a Struct member called `upcase` answered the UPCASED #inspect of the object
      # holding it. Declining to the general dispatch is not enough on its own: that
      # dispatch only covers SP_TAG_OBJ, so a genuine String receiver in the same
      # program then fell through to the slot's seed -- nil, or 0 for #bytes.
      E = Struct.new(:ip, :upcase, :downcase, :capitalize, :swapcase,
                     :strip, :reverse, :chomp, :chop, :succ, :chr, :bytes, :chars)
      e = E.new("a", 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12)

      # the member wins, inside a block and through &:sym
      [e].each { |x| p [x.upcase, x.downcase, x.capitalize, x.swapcase] }
      [e].each { |x| p [x.strip, x.reverse, x.chomp, x.chop] }
      [e].each { |x| p [x.succ, x.chr, x.bytes, x.chars] }
      p [e].map(&:upcase)
      p [e].map(&:bytes)

      D = Data.define(:upcase, :bytes)
      p [D.new(upcase: 7, bytes: 8)].map { |d| [d.upcase, d.bytes] }

      class C
        attr_accessor :upcase, :reverse, :chars
        def initialize; @upcase = 1; @reverse = 2; @chars = 3; end
      end
      p [C.new].map { |o| [o.upcase, o.reverse, o.chars] }

      # ... and a real String receiver still answers String, in the same program.
      # A mixed array makes the element genuinely poly, which is the case that broke.
      mixed = ["  Ab  ", 65]
      p mixed[0].upcase
      p mixed[0].downcase
      p mixed[0].capitalize
      p mixed[0].swapcase
      p mixed[0].strip
      p mixed[0].reverse
      p mixed[0].bytes
      p mixed[0].chars
      p mixed[1].chr
      p ["x\n", 1][0].chomp
      p ["xy", 1][0].chop
      p ["az", 1][0].succ
    RUBY

    _(result).must_answer <<~'OUT'
      [1, 2, 3, 4]
      [5, 6, 7, 8]
      [9, 10, 11, 12]
      [1]
      [11]
      [[7, 8]]
      [[1, 2, 3]]
      "  AB  "
      "  ab  "
      "  ab  "
      "  aB  "
      "Ab"
      "  bA  "
      [32, 32, 65, 98, 32, 32]
      [" ", " ", "A", "b", " ", " "]
      "A"
      "x"
      "x"
      "ba"
    OUT
  end

  it "gsub with a Hash, split(\"\"), a capture index, casecmp?, oct and slice! each answer" do
    result = ze0(<<~'RUBY')
      puts "hello world".gsub(/[aeiou]/, "a" => "1", "e" => "2", "o" => "3")
      p "hello".split("")
      p "hello world"[/(\w+) (\w+)/, 2]
      p "Hello".casecmp?("HELLO")
      p "0x1f".oct
      s = "hello"; s.slice!(1, 2); p s
      p({ b: 2, a: 1 }.sort)
    RUBY

    _(result).must_answer <<~'OUT'
      h2ll3 w3rld
      ["h", "e", "l", "l", "o"]
      "world"
      true
      31
      "hlo"
      [[:a, 1], [:b, 2]]
    OUT
  end

  it "a Hash replacement maps every match, and a key that is missing gives the empty string" do
    result = ze0(<<~'RUBY')
      # A grab-bag of String / Hash leaf methods.

      # `gsub` with a Hash maps each match to its replacement (missing keys -> "").
      puts "hello world".gsub(/[aeiou]/, "a" => "1", "e" => "2", "o" => "3")   # h2ll1 w3rld

      # `split` with an empty separator yields characters; a single space splits on
      # whitespace runs; a limit caps the field count.
      p "hello".split("")                    # ["h", "e", "l", "l", "o"]
      p "a b  c   d".split(" ")              # ["a", "b", "c", "d"]
      p "a,b,c,d".split(",", 2)              # ["a", "b,c,d"]

      # Regexp indexing pulls out the whole match or a capture group.
      p "hello world foo"[/\w+/]             # "hello"
      p "hello world"[/(\w+) (\w+)/, 2]      # "world"

      # Case-insensitive comparison and radix parsing.
      p "Hello".casecmp("hello")             # 0
      p "Hello".casecmp?("HELLO")            # true
      p "0x1f".oct                           # 31
      p "777".oct                            # 511
      p "ff".hex                             # 255

      # `slice!` removes a span in place and returns it.
      s = "hello"
      p s.slice!(1, 2)                       # "el"
      p s                                    # "hlo"

      # `Hash#sort` orders the [key, value] pairs.
      p({ b: 2, a: 1, c: 3 }.sort)           # [[:a, 1], [:b, 2], [:c, 3]]

      # Numeric stepping, integer and float lanes.
      p 1.step(10, 3).to_a                   # [1, 4, 7, 10]
      p 1.0.step(2.0, 0.5).to_a              # [1.0, 1.5, 2.0]
    RUBY

    _(result).must_answer <<~'OUT'
      h2ll3 w3rld
      ["h", "e", "l", "l", "o"]
      ["a", "b", "c", "d"]
      ["a", "b,c,d"]
      "hello"
      "world"
      0
      true
      31
      511
      255
      "el"
      "hlo"
      [[:a, 1], [:b, 2], [:c, 3]]
      [1, 4, 7, 10]
      [1.0, 1.5, 2.0]
    OUT
  end

  it "the case, strip, split, chomp, index, sub, tr and % families all match the oracle" do
    result = ze0(<<~'RUBY')
      # The String Tier A surface: case/strip families, split shapes, chomp,
      # indexing forms, sub/gsub (String + block), tr/delete/squeeze/count,
      # lenient conversions, succ carry, padding, and `%` formatting.

      p "hello world".capitalize
      p "HeLLo".swapcase
      p "hello".upcase
      p "HELLO".downcase
      p "  hi  ".strip
      p "  hi".lstrip
      p "hi  ".rstrip
      p "hello".chars
      p "a,b,,c".split(",")
      p "a b  c".split
      p "hello".split("l")
      p "hello".chomp("lo")
      p "hello".chop
      p "abc" * 3
      p "abc".reverse
      p "hello".index("l")
      p "hello".rindex("l")
      p "hello".index("x")
      p "hello"[1]
      p "hello"[1, 3]
      p "hello"[1..3]
      p "hello".sub("l", "L")
      p "hello".gsub("l", "L")
      p "hello".gsub("l") { |m| m.upcase }
      p "hello".start_with?("he")
      p "hello".end_with?("lo", "x")
      p "hello".tr("el", "ip")
      p "hello".tr("a-y", "b-z")
      p "42abc".to_i
      p "abc".to_i
      p "ff".to_i(16)
      p "42.5xyz".to_f
      p "hello".to_sym
      p "az".succ
      p "zz".succ
      p "a\nb\nc".lines
      p "Hello %s, you are %d" % ["Bob", 42]
      p "%05.1f|%x|%o|%b|%e|%g|%%" % [3.14159, 255, 8, 5, 12345.678, 0.00001]
      p "hi".center(7, "*")
      p "hi".ljust(5, ".")
      p "hi".rjust(5, ".")
      p "hello".delete("l")
      p "aabbcc".squeeze
      p "aabbcc".squeeze("a")
      p "hello world".count("lo")
      s = "orig"
      s.replace("xyz")
      p s
      s << "!"
      p s
      s.prepend("ab")
      p s
    RUBY

    _(result).must_answer <<~'OUT'
      "Hello world"
      "hEllO"
      "HELLO"
      "hello"
      "hi"
      "hi"
      "hi"
      ["h", "e", "l", "l", "o"]
      ["a", "b", "", "c"]
      ["a", "b", "c"]
      ["he", "", "o"]
      "hel"
      "hell"
      "abcabcabc"
      "cba"
      2
      3
      nil
      "e"
      "ell"
      "ell"
      "heLlo"
      "heLLo"
      "heLLo"
      true
      true
      "hippo"
      "ifmmp"
      42
      0
      255
      42.5
      :hello
      "ba"
      "aaa"
      ["a\n", "b\n", "c"]
      "Hello Bob, you are 42"
      "003.1|ff|10|101|1.234568e+04|1e-05|%"
      "**hi***"
      "hi..."
      "...hi"
      "heo"
      "abc"
      "abbcc"
      5
      "xyz"
      "xyz!"
      "abxyz!"
    OUT
  end

  it "casecmp answers -1, 0 or 1, and casecmp? answers true or false" do
    result = ze0(<<~'RUBY')
      # String#casecmp returns -1 / 0 / 1 for case-insensitive lex compare.
      # String#casecmp? returns true / false.
      puts "ABC".casecmp("abc")
      puts "ABC".casecmp("abd")
      puts "abc".casecmp("ABB")
      puts "ABC".casecmp?("abc")
      puts "ABC".casecmp?("abd")
      puts "".casecmp("")
      puts "a".casecmp("aa")
    RUBY

    _(result).must_answer <<~'OUT'
      0
      -1
      1
      true
      false
      0
      -1
    OUT
  end

  it "an embedded NUL is a byte of the string, and no operation truncates at it" do
    result = ze0(<<~'RUBY')
      # An embedded NUL is a byte of the string: the representation has always
      # carried it (the header records the true byte length), but an operation that
      # reached for strlen or strstr stopped at it and silently truncated. The policy
      # is opportunistic -- fix what is met -- and this is what a sweep of the common
      # String surface met.
      s = "a\0b"
      p s.bytesize
      p s.size
      p s == "a\0b"
      p s == "a"
      p s.bytes

      p s.upcase.bytesize
      p s.downcase.bytes
      p s.reverse.bytes

      p s.sub("\0", "-")
      p s.sub("a", "X")
      p s.gsub("\0", "-")
      p s.gsub("a", "X")
      p "abcabc".gsub("b", "-")
      p "abc".gsub("", "-")

      p s.split("\0").map(&:bytesize)
      p s.split("").map(&:bytesize)
      p "a\0b\0c".split("\0").size
      p "a,b,c".split(",")

      p [s].join.bytesize
      p [s, s].join("\0").bytesize
      p [1, 2].join("\0").bytesize
      p ["x", "y"].join("-")

      p s.tr("\0", "-")
      p s.delete("\0").bytesize
      p s.count("\0")
      p "a\0\0b".squeeze("\0").bytesize
      p "aabb".squeeze
      p "abc".tr("b", "-")

      p s.chomp.bytesize
      p s.chop.bytesize
      p s.swapcase.bytesize
      p s.capitalize.bytesize
      p s.succ.bytesize
      p "az".succ
      p "zz".succ
      p "abc\n".chomp

      p s.partition("\0").map(&:bytesize)
      p s.rpartition("\0").map(&:bytesize)
      p "a-b-c".partition("-")
      p "a-b-c".rpartition("-")

      p s.dump
      p s.dump.undump.bytesize
      p("\0" "1").bytesize
      p("x" "\0" "y").bytesize

      # and the operations that already carried it
      p s.b.bytesize
      p s.dup.bytesize
      p (+s).bytesize
      p ("a\0b" + "c\0d").bytesize
      p (s * 2).bytesize
      p s.include?("\0")
      p s.index("b")
      p s.start_with?("a\0")
      p s.end_with?("\0b")
      p s.hash == "a\0b".hash
      p({ s => 1 }[s])
      p s.inspect
    RUBY

    _(result).must_answer <<~'OUT'
      3
      3
      true
      false
      [97, 0, 98]
      3
      [97, 0, 98]
      [98, 0, 97]
      "a-b"
      "X\u0000b"
      "a-b"
      "X\u0000b"
      "a-ca-c"
      "-a-b-c-"
      [1, 1]
      [1, 1, 1]
      3
      ["a", "b", "c"]
      3
      7
      3
      "x-y"
      "a-b"
      2
      1
      3
      "ab"
      "a-c"
      3
      2
      3
      3
      3
      "ba"
      "aaa"
      "abc"
      [1, 1, 1]
      [1, 1, 1]
      ["a", "-", "b-c"]
      ["a-b", "-", "c"]
      "\"a\\x00b\""
      3
      "\u00001"
      "x\u0000y"
      3
      3
      3
      6
      6
      true
      2
      true
      true
      true
      1
      "\"a\\u0000b\""
    OUT
  end

  it "upcase, reverse, +, *, capitalize and include? each answer" do
    result = ze0(<<~'RUBY')
      puts "abc".upcase
      puts "ABC".downcase
      puts "abc".length
      puts "abc".reverse
      puts "a" + "b"
      puts "ab" * 3
      s = "hello"
      puts s.capitalize
      puts s.include?("ell")
      puts s.index("l")
      p "x".succ
    RUBY

    _(result).must_answer <<~'OUT'
      ABC
      abc
      3
      cba
      ab
      ababab
      Hello
      true
      2
      "y"
    OUT
  end

  it "a parameter with no concrete-typed caller takes its type from the calls in the body" do
    result = ze0(<<~'RUBY')
      # #450 cascade 2: a method like
      #
      #   def match_pattern(pattern, path)
      #     pp = pattern.split("/")
      #     p2 = path.split("/")
      #     ...
      #   end
      #
      # with no concrete-typed caller (or callers passing a still-int default
      # from a deeper chain) used to leave `pattern` / `path` typed mrb_int.
      # `.split("/")` on a mrb_int then failed C compile. Now the analyze
      # pass infers "string" for params that have String-specific methods
      # called on them in the body.

      module Router
        def self.match_pattern(pattern, path)
          pp = pattern.split("/")
          p2 = path.split("/")
          return nil if pp.length != p2.length
          pp[0] + ":" + p2[0]
        end
      end

      puts Router.match_pattern("a/b/c", "x/y/z")

      # Top-level def variant.
      def normalize(s)
        s.strip.downcase
      end

      puts normalize("  HELLO  ")

      # Param widened only when the called method is String-only. `length`
      # alone (a container builtin) stays int — only flagging "definitive
      # String evidence" methods keeps the inference conservative.
      def show_len(arr)
        arr.length
      end

      puts show_len([1, 2, 3])
    RUBY

    _(result).must_answer <<~'OUT'
      a:x
      hello
      3
    OUT
  end

  it "symbol casecmp" do
    result = ze0(<<~'RUBY')
      # Symbol#casecmp and Symbol#casecmp? compare two symbols' names case-folded.
      # casecmp returns -1/0/1 (like <=>); casecmp? returns a boolean.
      # (String#casecmp/casecmp? already work; a couple are kept here as a guard.)
      def sy(x); x; end   # symbol receiver
      def st(x); x; end   # string receiver

      # casecmp orders case-insensitively
      p sy(:Foo).casecmp(:foo)      # 0
      p sy(:abc).casecmp(:abd)      # -1
      p sy(:b).casecmp(:A)          # 1  (case-folded: 'b' > 'a')
      p sy(:Foo).casecmp(:foobar)   # -1 (prefix is shorter)

      # casecmp? is the boolean case-insensitive equality
      p sy(:Foo).casecmp?(:foo)     # true
      p sy(:Foo).casecmp?(:FOO)     # true
      p sy(:Foo).casecmp?(:bar)     # false

      # literal-receiver forms
      p :HELLO.casecmp(:hello)      # 0
      p :HELLO.casecmp?(:world)     # false

      # usable directly in a condition
      puts(sy(:Yes).casecmp?(:yes) ? "match" : "no")   # match

      # String#casecmp / casecmp? remain correct
      p st("Foo").casecmp("FOO")    # 0
      p st("Foo").casecmp?("foo")   # true
    RUBY

    _(result).must_answer <<~'OUT'
      0
      -1
      1
      -1
      true
      true
      false
      0
      false
      match
      0
      true
    OUT
  end

  it "symbol upcase interpolation" do
    result = ze0(<<~'RUBY')
      # Symbol#upcase / #downcase on a method-returned (branch-poly) symbol
      # inside string interpolation lowers through sp_sym_intern. The runtime
      # helper is gated on @needs_sym_intern, which analyze set as a memoized
      # side effect and missed for this shape -> link failure on the call.
      # Found via the spinelgems harness (nagiosplugin).
      class P
        def status(n)
          return :critical if n > 2
          return :warning if n > 1
          :ok
        end
        def output(n)
          "X #{status(n).upcase}"
        end
        def lower(n)
          "y #{status(n).downcase}"
        end
      end

      puts P.new.output(3)
      puts P.new.output(2)
      puts P.new.output(1)
      puts P.new.lower(3)
      puts "hi".to_sym.inspect
    RUBY

    _(result).must_answer <<~'OUT'
      X CRITICAL
      X WARNING
      X OK
      y critical
      :hi
    OUT
  end
end
