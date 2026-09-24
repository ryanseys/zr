# frozen_string_literal: true

require "spec_helper"

describe "Regexp: pattern matching" do
  it "allocated regexp takes a pattern once" do
    result = zr(<<~'RUBY')
      # `Regexp.new` is `Class#new`: `allocate` makes the husk and
      # `initialize` seats the pattern in it. A subclass that builds its
      # source in its own initialize therefore keeps what it gave to `super`.
      class Wrapped < Regexp
        def initialize(source) = super("(#{source})")
      end

      r = Wrapped.new("a+")
      p r.class
      p r.source
      p r.options
      p r.match("xaaay")[1]

      # A husk answers no pattern until one is seated, and takes only one.
      bare = Regexp.allocate
      p bare.class
      begin
        bare.source
      rescue TypeError => e
        p [e.class, e.message]
      end
      bare.send(:initialize, "b+", Regexp::IGNORECASE)
      p bare.source
      p bare.options
      p bare.match?("ZBB")
      begin
        bare.send(:initialize, "c+")
      rescue TypeError => e
        p [e.class, e.message]
      end

      # The husk of a subclass is a regexp from the start, so one marshals and
      # converts like any other.
      p Wrapped.allocate.class
      p Marshal.load(Marshal.dump(r)).class
      p Marshal.load(Marshal.dump(r)).source
      p Regexp.new(r).source
      p Regexp.new("d+", nil).source

    RUBY

    _(result).must_answer <<~'OUT'
      Wrapped
      "(a+)"
      0
      "aaa"
      Regexp
      [TypeError, "uninitialized Regexp"]
      "b+"
      1
      true
      [TypeError, "already initialized regexp"]
      Wrapped
      Wrapped
      "(a+)"
      "(a+)"
      "d+"
    OUT
  end

  it "array pattern match basic" do
    result = zr(<<~'RUBY')
      # Issue #669: `case arr in [a, b, c]` pattern matching with
      # LocalVariableTargetNode bindings. Pre-fix, spinel_parse emitted
      # `UnsupportedNode { kind: "ArrayPatternNode" }` and the codegen
      # silently ran the body with lv_a / lv_b / lv_c never declared
      # (C compile failed with "undeclared identifier"). Fix wires the
      # pattern through spinel_parse + compile_array_pattern_arm so each
      # bound LV gets declared with the scrutinee's elem type and
      # initialised from the matching index.

      case [1, 2, 3]
      in [a, b, c]
        puts "matched: #{a}, #{b}, #{c}"
      end

      # String array
      case ["x", "y", "z"]
      in [p, q, r]
        puts "matched: #{p}, #{q}, #{r}"
      end

      # Non-match arm: fall through to else
      case [1, 2]
      in [a, b, c]
        puts "wrong"
      in [a, b]
        puts "two: #{a}, #{b}"
      end
    RUBY

    _(result).must_answer <<~'OUT'
      matched: 1, 2, 3
      matched: x, y, z
      two: 1, 2
    OUT
  end

  it "case in matchdata deconstruct" do
    result = zr(<<~'RUBY')
      # A hash pattern against a MatchData scrutinee matches via
      # MatchData#deconstruct_keys: the regex's named captures become a symbol-keyed
      # hash, so `case md in {name:}` binds the capture. Covers case/in (single,
      # multiple, class check, capture binding, no-match -> else), the rightward
      # `=>` form, and a nil (no-match) MatchData against `in nil`.

      m = "2026-06".match(/(?<yr>\d+)-(?<mo>\d+)/)

      case m
      in { mo: } then p mo
      end

      case m
      in { yr:, mo: } then p [yr, mo]
      end

      case m
      in { mo: String => s } then p s
      else p :no
      end

      case m
      in { yr: bound } then p bound
      end

      case m
      in { nope: } then p :yes
      else p :fellthrough
      end

      # rightward assignment form
      m => { yr:, mo: }
      p [yr, mo]

      # a no-match MatchData is nil; `in nil` matches it
      miss = "abc".match(/(?<d>\d+)/)
      case miss
      in { d: } then p d
      in nil then p :nilmatch
      end
    RUBY

    _(result).must_answer <<~'OUT'
      "06"
      ["2026", "06"]
      "06"
      "2026"
      :fellthrough
      ["2026", "06"]
      :nilmatch
    OUT
  end

  it "case in pattern matching dispatches via real regexp case eq" do
    result = zr(<<~'RUBY')
      class Checker
        def check(x)
          case x
          in /^\d+$/
            "number"
          in /^[a-z]+$/
            "lower"
          else
            "other"
          end
        end
      end
      c = Checker.new
      puts c.check("123")
      puts c.check("abc")
      puts c.check("ABC")
    RUBY

    _(result).must_answer <<~'OUT'
      number
      lower
      other
    OUT
  end

  it "find pattern match" do
    result = zr(<<~'RUBY')
      # Find patterns `case arr in [*head, m.., *tail]`: scan for the first window of
      # requireds, binding the leading splat (head), required targets, and trailing
      # splat (tail). Pre-fix the arm matched unconditionally with head/tail nil.

      def classify(a)
        case a
        in [*head, :a, :b, *tail]
          "ab head=#{head.inspect} tail=#{tail.inspect}"
        in [*pre, x, :stop, *post]
          "stop x=#{x} pre=#{pre.inspect} post=#{post.inspect}"
        else
          "none"
        end
      end

      puts classify([:x, :y, :a, :b, :z])
      puts classify([:a, :b])
      puts classify([:p, :q, :stop, :r])
      puts classify([:z])
      puts classify([])
    RUBY

    _(result).must_answer <<~'OUT'
      ab head=[:x, :y] tail=[:z]
      ab head=[] tail=[]
      stop x=q pre=[:p] post=[:r]
      none
      none
    OUT
  end

  it "matchdata array pattern" do
    result = zr(<<~'RUBY')
      # GAP -- imported from the spinel corpus at c55d9bdb.
      # MatchData does not deconstruct for an array pattern in case/in.
      #
      m001 = "ab".match(/(a)(b)/)
      p m001.deconstruct
      case m001
      in [x001, y001] then p [x001, y001]
      else p :none
      end
      case m001
      in {a: 1} then p :h
      else p :noh
      end
      r1 = (case m001; in [x, y] then [x, y]; end rescue $!.class); p r1
    RUBY

    _(result).must_answer <<~'OUT'
      ["a", "b"]
      ["a", "b"]
      :noh
      ["a", "b"]
    OUT
  end

  it "matchdata deconstruct" do
    result = zr(<<~'RUBY')
      # MatchData introspection: begin/end and bytebegin/byteend group positions,
      # match/match_length, inspect, and the pattern-matching deconstruct hooks
      # (deconstruct for arrays, deconstruct_keys for named captures).
      m = "hello world".match(/(\w+)(\s+)(\w+)/)
      puts m.begin(1)
      puts m.end(3)
      puts m.offset(1).inspect

      md = "a1b2".match(/(\d)(\w)/)
      puts md.bytebegin(1)
      puts md.byteend(2)

      full = "abc".match(/(a)(b)(c)/)
      puts full.inspect
      p full.deconstruct
      puts full.match(2)
      puts full.match_length(2)

      named = "2024-01".match(/(?<year>\d+)-(?<mon>\d+)/)
      p named.deconstruct_keys(nil)
      p named.deconstruct_keys([:year])
      p named.deconstruct_keys([:year, :mon, :extra])
      p named.named_captures(symbolize_names: true)
    RUBY

    _(result).must_answer <<~'OUT'
      0
      11
      [0, 5]
      1
      3
      #<MatchData "abc" 1:"a" 2:"b" 3:"c">
      ["a", "b", "c"]
      b
      1
      {year: "2024", mon: "01"}
      {year: "2024"}
      {}
      {year: "2024", mon: "01"}
    OUT
  end

  it "matchdata deconstruct keys type" do
    result = zr(<<~'RUBY')
      # GAP -- imported from the spinel corpus at c55d9bdb.
      # MatchData#deconstruct_keys with a bad argument type answers {} where ruby
      # raises TypeError.
      #
      m001 = "ab".match(/(?<a>a)/)
      r001 = (m001.deconstruct_keys(["a"]) rescue $!.class); p r001
      r002 = (m001.deconstruct_keys(1) rescue $!.class); p r002
      p m001.deconstruct_keys(nil)
      p m001.deconstruct_keys([:a])
      p m001.deconstruct_keys([:a, :b])
    RUBY

    _(result).must_answer <<~'OUT'
      TypeError
      TypeError
      {a: "a"}
      {a: "a"}
      {}
    OUT
  end

  it "pattern match splat rest" do
    result = zr(<<~'RUBY')
      # Issue #844: array pattern with `*rest` splat target. The rest LV
      # needs to be declared in the surrounding scope; pre-fix it was
      # only handled at codegen-emit, leaving lv_rest undeclared.
      case [1, 2, 3]
      in [first, *rest]
        puts "first=" + first.to_s
        puts "rest=" + rest.inspect
      end

      # `Array(...)` with capture constant + rest
      case [10, 20, 30]
      in Array(head, *tail)
        puts "head=" + head.to_s
        puts "tail=" + tail.inspect
      end
    RUBY

    _(result).must_answer <<~'OUT'
      first=1
      rest=[2, 3]
      head=10
      tail=[20, 30]
    OUT
  end

  it "pattern pin regexp" do
    result = zr(<<~'RUBY')
      # A pinned Regexp in a pattern matches via === (Regexp#===), not equality.
      r = /a/
      case 'abc'
      in ^r then puts "re ok"
      else puts "no"
      end
      x = 5
      case 5
      in ^x then puts "eq ok"
      end
      case 'zzz'
      in ^r then puts "wrong"
      else puts "no2"
      end
    RUBY

    _(result).must_answer <<~'OUT'
      re ok
      eq ok
      no2
    OUT
  end

  it "pattern timeout stops every kind of match" do
    result = zr(<<~'RUBY')
      # A timeout stops a match that backtracks without end (a backreference
      # keeps Onigmo's match cache out), whichever method started it; a
      # pattern the cache makes linear finishes inside the same limit.

      slow = Regexp.new('\A(a|aa)*\1\z', timeout: 0.05)
      text = "a" * 64 + "!"
      {
        "match" => -> { slow.match(text) },
        "match?" => -> { slow.match?(text) },
        "===" => -> { slow === text },
        "=~" => -> { slow =~ text },
        "scan" => -> { text.scan(slow) },
        "gsub" => -> { text.gsub(slow, "") },
        "split" => -> { text.split(slow) },
        "index" => -> { text.index(slow) },
      }.each do |name, run|
        run.call
        p [name, :finished]
      rescue Regexp::TimeoutError => e
        p [name, e.class, e.message]
      end

      fast = Regexp.new('\A(a+)+\z', timeout: 0.5)
      p fast.match?("a" * 5000 + "b")

    RUBY

    _(result).must_answer <<~'OUT'
      ["match", Regexp::TimeoutError, "regexp match timeout"]
      ["match?", Regexp::TimeoutError, "regexp match timeout"]
      ["===", Regexp::TimeoutError, "regexp match timeout"]
      ["=~", Regexp::TimeoutError, "regexp match timeout"]
      ["scan", Regexp::TimeoutError, "regexp match timeout"]
      ["gsub", Regexp::TimeoutError, "regexp match timeout"]
      ["split", Regexp::TimeoutError, "regexp match timeout"]
      ["index", Regexp::TimeoutError, "regexp match timeout"]
      false
    OUT
  end

  it "regex pattern through a name" do
    result = zr(<<~'RUBY')
      # A regex reached through a NAME is as statically visible as the literal
      # itself, and every resolver has to agree about that.
      #
      # re_lit_index followed a constant and a local; re_lit_src followed only a
      # constant; the analyze rule looked only at a direct literal node. So a
      # capturing pattern named by a constant made codegen emit the capturing scan
      # under a str_array type (a PolyArray walked as a StrArray -- a segfault),
      # while the same pattern named by a local silently dropped the capture groups.
      # One resolver now answers for all of them.

      PAT = /(\d)(\w)/
      NOCAP = /\d/
      FROZEN = /(\d)(\w)/.freeze

      lpat = /(\d)(\w)/
      lnocap = /\d/

      p "a1b2".scan(/(\d)(\w)/)
      p "a1b2".scan(PAT)
      p "a1b2".scan(lpat)
      p "a1b2".scan(FROZEN)
      p "a1b2".scan(/\d/)
      p "a1b2".scan(NOCAP)
      p "a1b2".scan(lnocap)

      # the block form destructures a capture row through a name too
      "a1b2".scan(PAT) { |a, b| p [a, b] }
      "a1b2".scan(lpat) { |a, b| p [a, b] }
      "a1b2".scan(NOCAP) { |m| p m }
      "a1b2".scan(lnocap) { |m| p m }

      # resolving a name must not change what the other regex methods see
      p "a1b2".sub(PAT, "-")
      p "a1b2".gsub(lnocap, "#")
      p "a1b2".match(PAT)[2]
      p("a1b2" =~ NOCAP)
    RUBY

    _(result).must_answer <<~'OUT'
      [["1", "b"]]
      [["1", "b"]]
      [["1", "b"]]
      [["1", "b"]]
      ["1", "2"]
      ["1", "2"]
      ["1", "2"]
      ["1", "b"]
      ["1", "b"]
      "1"
      "2"
      "1"
      "2"
      "a-2"
      "a#b#"
      "b"
      1
    OUT
  end

  it "string patterns to split and gsub now work" do
    result = zr(<<~'RUBY')
      # SEMANTICS FLIP: String patterns to split/gsub used to be
      # compile-time rejections ("pass a Regexp literal instead"); the String
      # table rows now implement them for real, so the static regexp path falls
      # through to dynamic dispatch instead. Oracle-verified.

      puts "a,b".split(",").inspect
      puts "a,b".gsub(",", ";")
    RUBY

    _(result).must_answer <<~'OUT'
      ["a", "b"]
      a;b
    OUT
  end
end
