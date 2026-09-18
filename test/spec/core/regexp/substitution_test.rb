# frozen_string_literal: true

require "spec_helper"

describe "Regexp: substitution" do
  it "gsub and sub block forms" do
    result = ze0(<<~'RUBY')
      # The block body is a literal replacement (not `m.upcase`) since a
      # block parameter's static type is always `Poly` (this codebase's own
      # established rule -- params are never inferred from call sites), and
      # `String#upcase` itself isn't implemented as a builtin method yet, a
      # separate, pre-existing, unrelated gap this test isn't about.

      puts "hello".gsub(/l/) { |m| "L" }
      puts "hello".sub(/l/) { "L" }
    RUBY

    _(result).must_answer <<~'OUT'
      heLLo
      heLlo
    OUT
  end

  it "gsub and sub with a string replacement including numbered backreferences" do
    result = ze0(<<~'RUBY')
      puts "hello world".gsub(/o/, "0")
      puts "hello world".sub(/o/, "0")
      puts "John Smith".gsub(/(\w+) (\w+)/, '\2 \1')
    RUBY

    _(result).must_answer <<~'OUT'
      hell0 w0rld
      hell0 world
      Smith John
    OUT
  end

  it "gsub sub block" do
    result = ze0(<<~'RUBY')
      # Block-form String#gsub / #sub: the block receives each match and
      # returns its replacement. The result used to be padded with trailing
      # NUL bytes (the working buffer was returned with its allocation size
      # as the byte length, not the content length).
      p "abc".gsub(/[ac]/) { |m| m.upcase }
      p "hello world".gsub(/o/) { |m| "0" }
      p "aaa".gsub(/a/) { |m| m + m }
      p "abc".sub(/b/) { |m| m.upcase }
      p "x y z".gsub(/\s/) { |m| "_" }
      p "no match here".gsub(/z+/) { |m| "!" }

      # Replacement much larger than input forces the buffer to grow
      # (realloc must operate on a plain malloc'd buffer, not a string alloc).
      p ("a" * 100).gsub(/a/) { |m| "XYZ" }
    RUBY

    _(result).must_answer <<~'OUT'
      "AbC"
      "hell0 w0rld"
      "aaaaaa"
      "aBc"
      "x_y_z"
      "no match here"
      "XYZXYZXYZXYZXYZXYZXYZXYZXYZXYZXYZXYZXYZXYZXYZXYZXYZXYZXYZXYZXYZXYZXYZXYZXYZXYZXYZXYZXYZXYZXYZXYZXYZXYZXYZXYZXYZXYZXYZXYZXYZXYZXYZXYZXYZXYZXYZXYZXYZXYZXYZXYZXYZXYZXYZXYZXYZXYZXYZXYZXYZXYZXYZXYZXYZXYZXYZXYZXYZXYZXYZXYZXYZXYZXYZXYZXYZXYZXYZXYZXYZXYZXYZXYZXYZXYZXYZXYZXYZXYZXYZXYZXYZXYZXYZXYZXYZXYZXYZXYZ"
    OUT
  end

  it "gsub with hash replacement" do
    result = ze0(<<~'RUBY')
      # #485. `String#gsub(regex, hash)` — the per-match hash-lookup form
      # Ruby uses for HTML/JSON escape. Pre-fix codegen passed the hash
      # pointer through to sp_re_gsub's `const char *rep` parameter; the
      # binary read garbage from the pointer's memory in place of the
      # replacement string. Fix: detect a str_str_hash second arg and
      # route to a parallel runtime helper that does the per-match
      # lookup.

      ESCAPES = {
        "&" => "&amp;",
        "<" => "&lt;",
        ">" => "&gt;",
      }.freeze

      PATTERN = /[&<>]/.freeze

      puts "a&b<c".gsub(PATTERN, ESCAPES)
      puts "<p>x & y</p>".gsub(PATTERN, ESCAPES)
      puts "no specials here".gsub(PATTERN, ESCAPES)
    RUBY

    _(result).must_answer <<~'OUT'
      a&amp;b&lt;c
      &lt;p&gt;x &amp; y&lt;/p&gt;
      no specials here
    OUT
  end

  it "matchdata gsub named backref" do
    result = ze0(<<~'RUBY')
      # String#gsub / #sub expand `\k<name>` in the replacement to the named capture
      # group (empty when the group did not participate). An unknown or empty name
      # raises IndexError, mirroring md[:name]. `\k'name'` is regex-only and stays
      # literal. The subject string is routed through a method param so the
      # substitution runs at runtime rather than being constant-folded.
      def s(x); x; end

      # single named backref
      puts s("foobar").gsub(/(?<x>o+)/, "[\\k<x>]")
      # two named groups, swapped
      puts s("abcd").gsub(/(?<a>a)(?<b>b)/, "\\k<b>\\k<a>")
      # \k<name> mixed with \& (whole match)
      puts s("ab").gsub(/(?<a>a)b/, "\\k<a>-\\&")
      # optional group that participated
      p s("xyz").gsub(/(?<a>x)(?<b>y)?/, "[\\k<b>]")
      # optional group that did NOT participate -> empty expansion
      p s("xz").gsub(/(?<a>x)(?<b>y)?/, "[\\k<b>]")
      # single sub
      puts s("foobar").sub(/(?<x>o+)/, "[\\k<x>]")
      # \k'name' is regex-only syntax: left literal in a replacement
      puts s("ab").gsub(/(?<g>a)b/, "\\k'g'")

      # unknown name raises IndexError with the exact CRuby message
      begin
        s("abc").gsub(/(?<x>a)/, "\\k<y>")
      rescue IndexError => e
        puts "#{e.class}: #{e.message}"
      end
      # empty name likewise raises IndexError
      begin
        s("abc").gsub(/(?<x>a)/, "\\k<>")
      rescue IndexError => e
        puts "#{e.class}: #{e.message}"
      end
    RUBY

    _(result).must_answer <<~'OUT'
      f[oo]bar
      bacd
      a-ab
      "[y]z"
      "[]z"
      f[oo]bar
      \k'g'
      IndexError: undefined group name reference: y
      IndexError: undefined group name reference: 
    OUT
  end

  it "poly gsub block" do
    result = ze0(<<~'RUBY')
      # A class defining a nil-returning `#to_s` anywhere in the program used to
      # make `gsub`/`sub` WITH A BLOCK on a widened (poly) receiver infer as
      # returning void: the poly-dispatch inference had a rule for the two-argument
      # blockless form but none for the block form, so the call fell through
      # unresolved -- either a bad C build, or (when the value reached a String
      # consumer instead) a runtime NoMethodError claiming a String had no #gsub.

      class Poison
        def to_s
          @never_set
        end
      end

      def escape(text)
        text.to_s.gsub(/[&<>]/) { |c| c == "<" ? "&lt;" : "&gt;" }
      end

      def first_vowel(text)
        text.to_s.sub(/[aeiou]/) { |c| c.upcase }
      end

      puts escape("a<b")        # a&lt;b
      puts escape(123)          # 123
      puts first_vowel("hello") # hEllo
      puts first_vowel(42)      # 42

      # The blockless, two-argument form already worked before this fix; keep it
      # exercised here so a future change can't silently narrow the new rule.
      h = { stream: "abc/def", count: 5 }
      puts h[:stream].gsub(/[^a-z]/, "_") # abc_def

      # The receiver can be poly WITHOUT a `.to_s` in front of it, and then the block
      # parameter widens to poly too. gsub/sub always yield the matched substring, a
      # String whatever the receiver's static type is, so the parameter is typed that
      # way for a boxed receiver as well -- otherwise the slot is declared sp_RbVal
      # while the emitter assigns it the raw substring.
      def upcase_a(x)
        x.gsub(/a/) { |c| c.upcase }
      end

      def bracket_vowel(x)
        x.sub(/[aeiou]/) { |c| "[#{c}]" }
      end

      p upcase_a(true ? "banana" : [1, 2])
      p bracket_vowel(true ? "banana" : 5)
    RUBY

    _(result).must_answer <<~'OUT'
      a&lt;b
      123
      hEllo
      42
      abc_def
      "bAnAnA"
      "b[a]nana"
    OUT
  end

  it "poly gsub str arm" do
    result = ze0(<<~'RUBY')
      # `v.gsub(/regex/, "repl")` where v is poly-typed (sp_RbVal, e.g.
      # from a poly-valued hash lookup) used to emit an empty SP_TAG_OBJ
      # dispatch shell — the per-tag arm was missing — leaving the result
      # temp at its default mrb_int 0 and the downstream const char *
      # assignment failing C compile.
      #
      # compile_poly_method_call now emits a SP_TAG_STR arm for gsub /
      # sub at the same level as the existing SP_TAG_INT `[]` bit-extract.
      # poly_dispatch_return_type was also extended to report "string"
      # for these methods so the result temp is correctly typed (and the
      # arm's assignment doesn't try to store const char * into a
      # mrb_int slot).

      def normalize(entry)
        v = entry[:stream]
        v.gsub(/[^a-z]/, "_")
      end

      # Force the hash to be poly-valued by mixing value types — the
      # `:stream` value is String, but `:count` is Int, so the analyzer
      # widens the hash to sym_poly_hash and `entry[:stream]` returns
      # sp_RbVal rather than const char *.
      h = { stream: "abc/def", count: 5 }
      puts normalize(h)
    RUBY

    _(result).must_answer "abc_def\n"
  end

  it "poly gsub str str hash" do
    result = ze0(<<~'RUBY')
      # #503. `s.gsub(regex, hash)` on a poly-typed receiver still
      # called `sp_re_gsub` (the const-char-* replacement helper) and
      # passed the hash pointer where `rep` was expected. C compile
      # warned -Wincompatible-pointer-types; binary ran but produced
      # runtime garbage (the hash pointer's memory was interpreted as
      # a replacement string).
      #
      # The typed-receiver path (s is concretely `const char *`)
      # already routes str_str_hash replacements through
      # `sp_re_gsub_str_str_hash` via #485. This test exercises the
      # poly path (sp_RbVal lv_s) by passing a poly value into a
      # function whose param widens to poly.

      class A
        attr_accessor :body
        def initialize; @body = "a&b<c>"; end
      end
      class B
        attr_accessor :body
        def initialize; @body = 42; end
      end

      def pick(n)
        n > 0 ? A.new : B.new
      end

      ESCAPES = { "&" => "&amp;", "<" => "&lt;", ">" => "&gt;" }.freeze
      PATTERN = /[&<>]/.freeze

      # `s` here is sp_RbVal because the caller passes
      # `src.body` which is poly (A#body is String, B#body is Int).
      def html_escape(s)
        s.gsub(PATTERN, ESCAPES)
      end

      src = pick(1)
      puts html_escape(src.body)
    RUBY

    _(result).must_answer "a&amp;b&lt;c&gt;\n"
  end

  it "regex const freeze" do
    result = ze0(<<~'RUBY')
      # Issue #394: a top-level `PATTERN = /regex/.freeze` constant
      # was not recognised as a regex source. `gsub(PATTERN, ...)` then
      # fell through to `sp_str_gsub(... cst_PATTERN ...)` (mrb_int -> char *
      # C-compile error). The non-`.freeze` form already worked because
      # find_regexp_index recursed through @const_expr_ids; .freeze
      # wraps the literal in a CallNode so the recursion missed.
      #
      # Fix: find_regexp_index now peels the `.freeze` CallNode wrapper
      # before checking for RegularExpressionNode.

      PATTERN1 = /abc/
      PATTERN2 = /xy[0-9]+/.freeze
      PATTERN3 = /^foo/.freeze

      puts "xabcyz".gsub(PATTERN1, "Q")        # "xQyz"
      puts "xy42 xy7".gsub(PATTERN2, "M")      # "M M"
      puts "foobar foobaz".gsub(PATTERN3, "Y") # "Ybar foobaz"
    RUBY

    _(result).must_answer <<~'OUT'
      xQyz
      M M
      Ybar foobaz
    OUT
  end

  it "regex local gsub split" do
    result = ze0(<<~'RUBY')
      # A regex held in a local (notably an interpolated /.../ built at runtime)
      # must dispatch gsub/sub/split to the compiled-pattern overloads, not the
      # string-pattern ones.
      re = /#{"(.)" * 3}/
      p "ABCabc".gsub(re, '\1')
      p "ABCabc".sub(re, '<\1>')
      comma = /#{","}/
      p "a,b,c".split(comma)
      p "a,b,c,d".split(comma, 2)
      ws = /\s+/
      p "x  y   z".split(ws)
      vowel = /[aeiou]/
      p "hello world".gsub(vowel, "*")
    RUBY

    _(result).must_answer <<~'OUT'
      "Aa"
      "<A>abc"
      ["a", "b", "c"]
      ["a", "b,c,d"]
      ["x", "y", "z"]
      "h*ll* w*rld"
    OUT
  end

  it "regex sub backref" do
    result = ze0(<<~'RUBY')
      # Issue #855: sub / gsub expand `\1`..`\9` and `\&` backreferences
      # in the replacement string.
      puts "hello world".sub(/(\w+)/, '\1_up')
      puts "hello world".gsub(/(\w+)/, '\1!')
      puts "abc".sub(/b/, '[\&]')
      # Swap two captured groups via \2\1.
      puts "foo:bar".sub(/(\w+):(\w+)/, '\2:\1')
      # `\\` is a literal backslash, not a backref.
      puts "x".sub(/x/, '\\')
      # Numeric backref beyond captured groups stays empty.
      puts "ab".sub(/(a)(b)/, '\1-\2-\3')
    RUBY

    _(result).must_answer <<~'OUT'
      hello_up world
      hello! world!
      a[b]c
      bar:foo
      \
      a-b-
    OUT
  end

  it "regexp gsub zero width" do
    result = ze0(<<~'RUBY')
      # gsub with a zero-width match (anchors, empty pattern, word boundary,
      # zero-repeat quantifier) must insert the replacement at each match
      # position, keep the source character there, and advance by one -- not
      # drop the character, spin forever, or run the tail copy with an
      # underflowed length (which previously corrupted the heap / crashed).
      p "abc".gsub(/$/, "!")
      p "x\ny".gsub(/$/, "!")
      p "x\ny\nz".gsub(/$/, "!")
      p "a\nb".gsub(/^/, ">")
      p "hello".gsub(//, "-")
      p "abc".gsub(/b*/, "X")
      p "hello world".gsub(/\b/, "|")
      p "abc".sub(/$/, "!")

      # The each_line + $-anchored capture build, which surfaced the bug.
      table = {}
      "Name Ada\nLang Ruby\nYear 1995".each_line do |line|
        if (m = line.match(/^(\w+) (.+)$/))
          table[m[1]] = m[2]
        end
      end
      p table.keys
      p table["Lang"]

      # Lengths are correct (metadata, not just strlen).
      p "x\ny".gsub(/$/, "!").length
      p "hello".gsub(//, "-").length
    RUBY

    _(result).must_answer <<~'OUT'
      "abc!"
      "x!\ny!"
      "x!\ny!\nz!"
      ">a\n>b"
      "-h-e-l-l-o-"
      "XaXXcX"
      "|hello| |world|"
      "abc!"
      ["Name", "Lang", "Year"]
      "Ruby"
      5
      11
    OUT
  end

  it "regexp ruby escape e lowers to x1b" do
    result = ze0(<<~'RUBY')
      # Ruby's `\e` (ESC) is not an escape every regex engine knows; it must be
      # translated to `\x1b`, and `#source` still shows the original `\e`.

      re = /\e\[[0-9;]*m/
      puts "\e[31mRED\e[0m".gsub(re, "")
      puts re.source
    RUBY

    _(result).must_answer <<~'OUT'
      RED
      \e\[[0-9;]*m
    OUT
  end

  it "regexp sub gsub length" do
    result = ze0(<<~'RUBY')
      # Regex String#sub / #gsub build into an over-allocated buffer; the
      # result's stored byte length must reflect the bytes actually written,
      # not the buffer's slack. Without the fix, #length returned the padded
      # capacity and inspect/p showed trailing NUL bytes. Exercise the paths
      # that read the metadata length (p / #length), which strlen-based
      # operations like puts would otherwise hide.
      p "hello".gsub(/l/, "L")
      p "hello".gsub(/l/, "L").length
      p "hello world".gsub(/o/, "0")
      p "hello world".gsub(/o/, "0").length
      p "hello".sub(/l/, "L")
      p "hello".sub(/l/, "L").length
      p "aaa".gsub(/a/, "bb")
      p "aaa".gsub(/a/, "bb").length
      # Backreference expansion still lands at the right length.
      p "FontName Times".gsub(/(\w+) (\w+)/, '\2 \1')
      p "abcabc".gsub(/b/, "").length
    RUBY

    _(result).must_answer <<~'OUT'
      "heLLo"
      5
      "hell0 w0rld"
      11
      "heLlo"
      5
      "bbbbbb"
      6
      "Times FontName"
      4
    OUT
  end

  it "regexp sub gsub realloc" do
    result = ze0(<<~'RUBY')
      # When a regex sub / gsub / scrub result grows past the initial buffer
      # capacity, the buffer must be grown on a real malloc base. Previously
      # these built into a sp_str_alloc'd buffer and grew it with realloc on a
      # pointer offset past the string header -- undefined behaviour that
      # corrupted the heap once the output exceeded the initial slack. Each
      # input below produces output larger than its starting capacity.

      # gsub: 50 'a' -> 50 * "zzzz" = 200 bytes (cap starts ~180).
      g = ("a" * 50).gsub(/a/, "zzzz")
      p g.length
      p g[0, 8]

      # sub with a backreference that repeats the whole match: 100 -> 200.
      s = ("x" * 100).sub(/x+/, '\0\0')
      p s.length

      # gsub(regex, hash) with replacement longer than the match.
      h = { "a" => "zzzzz" }
      gh = ("a" * 40).gsub(/a/, h)
      p gh.length

      # scrub: 100 invalid bytes, each replaced by a 5-char string -> 500.
      sc = ("\xFF" * 100).scrub("XXXXX")
      p sc.length
      p sc == "X" * 500
    RUBY

    _(result).must_answer <<~'OUT'
      200
      "zzzzzzzz"
      200
      200
      500
      true
    OUT
  end

  it "string gsub block" do
    result = ze0(<<~'RUBY')
      # Issue #849: gsub / sub with a block — block receives the
      # matched substring and its return value is the replacement.
      puts "hello".gsub(/./) { |c| c.upcase }
      puts "hello world".gsub(/\w+/) { |w| w.length.to_s }
      puts "abc".sub(/b/) { |c| c.upcase }
      # Block return is concatenated verbatim — backref expansion
      # does not run on block returns (Ruby semantics).
      puts "ab".gsub(/(a)(b)/) { |m| "[" + m + "]" }
    RUBY

    _(result).must_answer <<~'OUT'
      HELLO
      5 5
      aBc
      [ab]
    OUT
  end

  it "string sub hash replacement" do
    result = ze0(<<~'RUBY')
      # Issue #910: sub / gsub with a hash replacement argument.
      # The hash's matched-substring value is the replacement; missing
      # keys substitute with the empty string (CRuby semantics).
      puts "hello".sub(/l/, "l" => "X")
      puts "foo bar baz".sub(/\w+/, "foo" => "XXX")
      puts "hello".sub("l", "l" => "X")
      # gsub form (previously worked).
      puts "hello".gsub(/l/, "l" => "X")
    RUBY

    _(result).must_answer <<~'OUT'
      heXlo
      XXX bar baz
      heXlo
      heXXo
    OUT
  end

  it "sub hash default" do
    result = ze0(<<~'RUBY')
      # GAP -- imported from the spinel corpus at c55d9bdb.
      # String#sub with a Hash replacement drops a key that misses, where ruby
      # substitutes the hash's default.
      #
      # A Hash replacement in #sub/#gsub answers its default for a key it does not
      # have; the empty string was hard-coded (#3824).
      h = Hash.new("?")
      h["e"] = "3"
      p "hello".sub(/l/, h)
      p "hello".sub(/e/, h)
      p "hello".gsub(/l/, h)
      g = { "e" => "3" }
      p "hello".sub(/l/, g)
      p "hello".sub(/e/, g)
    RUBY

    _(result).must_answer <<~'OUT'
      "he?lo"
      "h3llo"
      "he??o"
      "helo"
      "h3llo"
    OUT
  end

  it "sub prematch backref" do
    result = ze0(<<~'RUBY')
      # The replacement backreferences for the text around the match: \` is what
      # came before it and \' what comes after. Neither was expanded, so both were
      # copied through as the literal two characters.
      p "hello".sub(/l/, '\`')
      p "hello".sub(/l/, "\\'")
      p "hello".gsub(/l/, '\`')
      p "hello".sub(/l/, '[\`|\0|\']')
      p "hello".sub(/l/, '\0')
      p "hello".sub(/(l)(o)/, '\2\1')
    RUBY

    _(result).must_answer <<~'OUT'
      "hehelo"
      "helolo"
      "hehehelo"
      "he[he|l|']lo"
      "hello"
      "helol"
    OUT
  end
end
