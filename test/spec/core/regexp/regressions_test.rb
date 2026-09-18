# frozen_string_literal: true

require "spec_helper"

describe "Regexp: regressions" do
  it "regexp" do
    result = ze0(<<~'RUBY')
      # Test Regexp support

      # match operator
      if "hello 123 world" =~ /\d+/
        puts "matched"
      end

      # match with capture
      str = "2024-03-17"
      if str =~ /(\d{4})-(\d{2})-(\d{2})/
        puts $1  # 2024
        puts $2  # 03
        puts $3  # 17
      end

      # String#match?
      puts "hello".match?(/ell/)    # true
      puts "hello".match?(/xyz/)    # false

      # String#gsub with regexp
      puts "hello world".gsub(/o/, "0")   # hell0 w0rld

      # String#sub with regexp
      puts "hello world".sub(/o/, "0")    # hell0 world

      # String#scan
      "one 1 two 2 three 3".scan(/\d+/) do |m|
        puts m
      end
      # 1, 2, 3

      # String#split with regexp
      parts = "a, b,  c".split(/,\s*/)
      puts parts.length  # 3
    RUBY

    _(result).must_answer <<~'OUT'
      matched
      2024
      03
      17
      true
      false
      hell0 w0rld
      hell0 world
      1
      2
      3
      3
    OUT
  end

  it "regexp backspace in class" do
    result = ze0(<<~'RUBY')
      # `\b` inside a `[...]` character class means U+0008 (backspace),
      # not the letter `b`. Outside `[...]`, `\b` is a word-boundary
      # anchor — the regex compiler's outer loop consumes that case
      # before reaching parse_escape, so adding the 0x08 mapping in
      # parse_escape only fires for the inside-class meaning. Pre-fix
      # spinel treated `[\b]` as `[b]`, stripping the letter b from any
      # `gsub(/[\b]/, ...)`. Issue #632.

      puts "Ruby".gsub(/[\b]/, "X")
      puts "a\bc".gsub(/[\b]/, "X")
      puts "no backspace here".gsub(/[\b]/, "X")
      puts "back\bspace".gsub(/[\b]/, "X")

      # `\b` outside a character class stays a word boundary.
      puts "hello world".gsub(/\bworld\b/, "earth")
      puts "hello worldwide".gsub(/\bworld\b/, "earth")

      # Combined char class with `\b` plus other escapes.
      puts "a\tb\nc\bd".gsub(/[\t\n\b]/, "_")
    RUBY

    _(result).must_answer <<~'OUT'
      Ruby
      aXc
      no backspace here
      backXspace
      hello earth
      hello worldwide
      a_b_c_d
    OUT
  end

  it "regexp inline flag group no hang" do
    result = ze0(<<~'RUBY')
      # `(?xim:...)` inline-flag groups previously parsed into an infinite
      # loop in re_compile: the `?` after `(` didn't match any recognized
      # directive (`:`, `=`, `!`, `<...`) and didn't advance c->p, so
      # compile_seq's outer loop spun forever on the unconsumed `?`.
      # Sam Ruby's #600 puzzle 3 (`p(/(?x:foo)/.to_s)`) hung at runtime
      # during the sp_re_init's static-regex compilation.
      #
      # Fix: when the `(?` lookahead matches a recognized flag char
      # (x / i / m / s / u / a), consume to `:` (non-capturing body)
      # or `)` (whole-group flag application -- spinel doesn't track
      # scoped flag state, so the directive is consumed without
      # emitting). Unrecognized `(?<X>` now raises a clean
      # `unrecognized (? construct` compile_error instead of hanging.
      #
      # Semantically /x's whitespace-stripping IS NOT applied inside
      # the sub-pattern -- spinel's compile-time flag handling only
      # does top-level stripping. Patterns whose `/x` flag is decorative
      # (whitespace inside `(?x:body)` for layout only) match the same
      # as the spinel literal would; patterns relying on the strip
      # would behave differently, but no longer hang.

      # `(?x:...)` with no whitespace in body. /foo/ matches "foo".
      puts (/(?x:foo)/ =~ "foobar").to_s     # 0
      puts (/(?x:foo)/ =~ "barbaz").nil?     # true

      # `(?:...)` non-capturing still works.
      puts (/(?:hello) (?:world)/ =~ "hello world").to_s  # 0

      # `(?i:...)` consumes the flag; spinel doesn't honor case-insensitivity
      # inside the group, but the parse no longer hangs.
      puts (/(?i:abc)/ =~ "abc").to_s       # 0

      # `(?m:...)` similar.
      puts (/(?m:foo)/ =~ "foo").to_s       # 0
    RUBY

    _(result).must_answer <<~'OUT'
      0
      true
      0
      0
      0
    OUT
  end

  it "issue 2896" do
    result = ze0(<<~'RUBY')
      ["12-a", "xx", "999-z"].each do |s|
        m = s.match(/^(\d+)-/)
        if m && m[1].to_i < 999
          puts "yes #{m[1]}"
        else
          puts "no"
        end
      end
    RUBY

    _(result).must_answer <<~'OUT'
      yes 12
      no
      no
    OUT
  end

  it "issue 3014" do
    result = ze0(<<~'RUBY')
      m1 = "abc".match(/b/)
      m2 = "xbz".match(/b/)
      m3 = "abc".match(/b/)
      p(m1.hash == m2.hash)
      p(m1.hash == m3.hash)
      p(m1.hash.is_a?(Integer))
    RUBY

    _(result).must_answer <<~'OUT'
      false
      true
      true
    OUT
  end

  it "issue 3015" do
    result = ze0(<<~'RUBY')
      m = "abc".match(/(?<x>b)(?<y>c)/)
      p m.deconstruct_keys([:x])
      p m.deconstruct_keys([:y, :x])
      p m.deconstruct_keys([:x, :nope])
      p m.deconstruct_keys([])
      p m.deconstruct_keys(nil)
      p m.deconstruct_keys([:x, :y, :z])
      case "2024-01".match(/(?<year>\d+)-(?<mon>\d+)/)
      in { year:, mon: }
        puts "#{year}/#{mon}"
      end
    RUBY

    _(result).must_answer <<~'OUT'
      {x: "b"}
      {y: "c", x: "b"}
      {x: "b"}
      {}
      {x: "b", y: "c"}
      {}
      2024/01
    OUT
  end

  it "issue 3019" do
    result = ze0(<<~'RUBY')
      class Pat
        def initialize(s); @s = s; end
        def =~(str); str.include?(@s) ? 0 : nil; end
      end
      p Pat.new("x") !~ "xyz"
      p Pat.new("q") !~ "xyz"
      p("abc" !~ /b/)
      p("abc" !~ /z/)
      r = /d/
      p("abc" !~ r)
      s = "abc"
      p(s !~ /a/)
    RUBY

    _(result).must_answer <<~'OUT'
      false
      true
      false
      true
      true
      false
    OUT
  end

  it "issue 3055" do
    result = ze0(<<~'RUBY')
      puts Regexp.new("a", Regexp::EXTENDED).options
      puts Regexp.new("a", Regexp::MULTILINE).options
      puts Regexp.new("a", Regexp::IGNORECASE).options
      puts Regexp.new("a", Regexp::IGNORECASE | Regexp::EXTENDED).options
      puts Regexp.new("a", 0).options
      puts Regexp.new("a").options
      puts(Regexp.new("A", Regexp::IGNORECASE) =~ "xxaXX" ? "i-matches" : "no")
      puts(Regexp.new("a b", Regexp::EXTENDED) =~ "xab" ? "x-matches" : "no")
      puts(Regexp.new("a.b", Regexp::MULTILINE) =~ "a\nb" ? "m-matches" : "no")
    RUBY

    _(result).must_answer <<~'OUT'
      2
      4
      1
      3
      0
      0
      i-matches
      x-matches
      m-matches
    OUT
  end

  it "issue 3056" do
    result = ze0(<<~'RUBY')
      p("あいうえお" =~ /う/)
      p "あいうえお".index(/う/)
      p "abcdef".index(/d/)
      p("hello" =~ /l/)
      p("あいうえお" =~ /x/)
      s = "日本語テスト"
      p(s =~ /テ/)
      p "café x".index(/x/)
    RUBY

    _(result).must_answer <<~'OUT'
      2
      2
      3
      2
      nil
      3
      5
    OUT
  end

  it "issue 3187" do
    result = ze0(<<~'RUBY')
      def tok(expr)
        tokens = []
        expr.scan(/\s*(\d+\.\d+|\d+|[+\-*\/()]|[a-z]+)/) { |m| tokens << m[0] }
        tokens
      end
      ["3 + 4 * 2", "(x + 12) / y", "3.14 * r", "1+2"].each do |e|
        toks = tok(e)
        kinds = toks.map do |t|
          if t =~ /\A\d/ then "NUM"
          elsif t =~ /\A[a-z]/ then "ID"
          else "OP" end
        end
        puts kinds.join(",")
      end
    RUBY

    _(result).must_answer <<~'OUT'
      NUM,OP,NUM,OP,NUM
      OP,ID,OP,NUM,OP,OP,ID
      NUM,OP,ID
      NUM,OP,NUM
    OUT
  end

  it "issue 3219" do
    result = ze0(<<~'RUBY')
      class Crash
        attr_reader :text
        def initialize(text) = @text = text
        def value = @value ||= /<(.*)>/.match(text)[1].to_sym
      end
      def fn(flag) = flag ? "<foo>" : nil
      raise unless Crash.new(fn(true)).value == :foo
      puts "ok"
    RUBY

    _(result).must_answer "ok\n"
  end

  it "issue 3301 case regex last match" do
    result = ze0(<<~'RUBY')
      # A `case`/`when <regex>` arm does not set `Regexp.last_match` (`$~`), so every
      # `last_match` read after a matched arm answers nil. ruby's `Regexp#===` sets
      # the match globals exactly as `=~` does.
      case "hello world"
      when /(h\w+) (w\w+)/
        p Regexp.last_match(1)
        p Regexp.last_match(2)
        p $1
        p $~.nil?
      end

      case "abc"
      when /x/
        puts "no"
      when /(b)(c)/
        p Regexp.last_match(1)
        p $2
      end

      x = ["str", 42]
      x.each do |v|
        case v
        when /(t)r/
          p $1
        else
          p v
        end
      end

      case "zzz"
      when /(q)/
        puts "no"
      else
        p $~.nil?
      end
      puts "done"

      p(/(y)m/ === :sym)
      p $1
      case :abc
      when /(b)/
        p $1
      end
      puts "end"
    RUBY

    _(result).must_answer <<~'OUT'
      "hello"
      "world"
      "hello"
      false
      "b"
      "c"
      "t"
      42
      true
      done
      true
      "y"
      "b"
      end
    OUT
  end

  it "issue 3322 regex escaped quote scan" do
    result = ze0(<<~'RUBY')
      module YarnLockParser
        class Parser
          TOKEN_TYPES = {
            boolean: "BOOLEAN",
          }.freeze
          class << self
            def parse(file_path)
              until input.empty?
                if input[0] == "\n" || input[0] == "\r"
                  while token.type == TOKEN_TYPES[:comma]
                  end
                  if valid_prop_value_token?(token)
                    keys.each do |k|
                    end
                  end
                end
              end
              between_quotes = /\"(.*?)\"/
              lines.each do |line|
              end
            end
          end
        end
      end
      puts YarnLockParser::Parser::TOKEN_TYPES.keys.sort.map(&:to_s).inspect
      x = 10 / 2
      p x
      r = /\"(.*?)\"/
      p "say \"hi\" now"[r, 1]
      p [:b, :a].sort.map(&:to_s)
    RUBY

    _(result).must_answer <<~'OUT'
      ["boolean"]
      5
      "hi"
      ["a", "b"]
    OUT
  end
end
