# frozen_string_literal: true

require "spec_helper"

describe "Regexp programs" do
  it "awk split limits and gsub block backref" do
    result = zr(<<~'RUBY')
      # awk-mode split honors limit (1 = whole, cap = verbatim remainder, nonzero
      # keeps a trailing empty); $1 is live inside a gsub/sub block.

      s = " one two  three "
      sep = " "
      p s.split(sep, 1)
      p s.split(sep, 2)
      p s.split(sep, -1)
      p "   ".split(sep, -1)
      p "trail   ".split(sep, 3)
      p "a1b2c3".gsub(/(\d)/) { ($1.to_i * 2).to_s }
      p "x9".sub(/(\d)/) { ($1.to_i + 1).to_s }
    RUBY

    _(result).must_answer <<~'OUT'
      [" one two  three "]
      ["one", "two  three "]
      ["one", "two", "three", ""]
      [""]
      ["trail", ""]
      "a2b4c6"
      "x10"
    OUT
  end

  it "binary regexp holds a high byte" do
    result = zr(<<~'RUBY')
      def t(l); r=(begin; yield.inspect; rescue Exception=>e; "#{e.class}: #{e.message}"; end); puts format("%-24s %s", l, r); end
      t("M-a in binary")     { Regexp.new("\\M-a".b) =~ "\xE1".b }
      t("M-a binary enc")    { Regexp.new("\\M-a".b).encoding.to_s }
      t("M-a binary source") { Regexp.new("\\M-a".b).source.bytes }
      t("a raw high byte")   { Regexp.new("\xE1".b) =~ "\xE1".b }
      t("raw byte enc")      { Regexp.new("\xE1".b).encoding.to_s }
      t("n flag")            { //n.encoding.to_s }
    RUBY

    _(result).must_answer <<~'OUT'
      M-a in binary            0
      M-a binary enc           "ASCII-8BIT"
      M-a binary source        [92, 77, 45, 97]
      a raw high byte          0
      raw byte enc             "ASCII-8BIT"
      n flag                   "US-ASCII"
    OUT
  end

  it "case in no match error" do
    result = zr(<<~'RUBY')
      begin
        case 5
        in 3
          puts "three"
        in 4
          puts "four"
        end
      rescue NoMatchingPatternError => e
        puts "caught int miss"
      end

      # Match still works
      case 5
      in 3
        puts "three"
      in 5
        puts "matched five"
      end

      # With else: no raise
      case 99
      in 1
        puts "one"
      else
        puts "else clause"
      end

      # String scrutinee
      begin
        case "x"
        in "y"
        end
      rescue NoMatchingPatternError => e
        puts "caught str miss"
      end

      # Symbol scrutinee
      begin
        case :foo
        in :bar
        end
      rescue NoMatchingPatternError => e
        puts "caught sym miss"
      end

      # StandardError parent catches NoMatchingPatternError
      begin
        case 7
        in 1
        in 2
        end
      rescue StandardError => e
        puts "caught via parent"
      end
    RUBY

    _(result).must_answer <<~'OUT'
      caught int miss
      matched five
      else clause
      caught str miss
      caught sym miss
      caught via parent
    OUT
  end

  it "case when dispatches via real regexp case eq" do
    result = zr(<<~'RUBY')
      # Method wrapped in a class, not a top-level `def` -- calling a
      # top-level-defined method is a separate, pre-existing, unrelated gap
      # (confirmed via a plain, regex-free repro), out of scope here.

      class Checker
        def check(x)
          case x
          when /^\d+$/
            "number"
          when /^[a-z]+$/
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

  it "const init block param scan" do
    result = zr(<<~'RUBY')
      # A constant initializer's RHS can introduce block params (here
      # `n`) whose declarations need to land at main()'s frame. The
      # top-level-stmt scan in `emit_main` previously skipped const-init
      # expressions, so iterations whose body assigns `lv_n` without a
      # preceding `mrb_int lv_n;` (e.g. the `Array#sum { |n| ... }`
      # emit path uses `emit_iter_open`, which does plain `elem_var =
      # idx_var;`) failed C compilation with "undeclared identifier".

      TOTAL = [1, 2, 3].sum { |n| n * 2 }
      puts TOTAL                         # 12

      DOUBLED = [4, 5, 6].sum { |m| m * 3 }
      puts DOUBLED                       # 45
    RUBY

    _(result).must_answer "12\n45\n"
  end

  it "const nil and poly scan" do
    result = zr(<<~'RUBY')
      # A constant assigned nil still needs a slot, and String#scan reaches a value
      # read out of a `{}`-then-filled Hash.
      EPSILON = nil
      p EPSILON
      p EPSILON.nil?
      p EPSILON.inspect
      OTHER = 5
      p OTHER

      h = {}
      h["A1"] = "a1b2"
      p h["A1"].scan(/\d+/)
      p h["A1"].scan(/(\w)(\d)/)
      p h["A1"].scan("b")
      p h["A1"].split("b")
      p h["A1"].length

      # a statically-typed String still takes the direct path
      s = "a1b2"
      p s.scan(/\d+/)
    RUBY

    _(result).must_answer <<~'OUT'
      nil
      true
      "nil"
      5
      ["1", "2"]
      [["a", "1"], ["b", "2"]]
      ["b"]
      ["a1", "2"]
      4
      ["1", "2"]
    OUT
  end

  it "exception value flow match" do
    result = zr(<<~'RUBY')
      # Exception values flowing through begin/rescue expressions, case/when and
      # Module#=== matching, and runtime-recovered NameError#name.
      e = (begin; raise "z"; rescue => x; x; end)
      p e.message
      c = (begin; begin; raise "inner"; rescue; raise "outer"; end; rescue => e2; e2.cause; end)
      p c.message
      def classify(ex)
        case ex
        when KeyError then "key"
        when IndexError then "index"
        when StandardError then "std"
        else "other"
        end
      end
      begin; raise KeyError, "k"; rescue => r1; p classify(r1); end
      begin; raise StopIteration; rescue => r2; p classify(r2); end
      begin; raise "r"; rescue => r3; p classify(r3); end
      begin
        raise ArgumentError, "a"
      rescue => ex
        p StandardError === ex
        p TypeError === ex
        k = StandardError
        p k === ex
      end
      begin; nil.foo(1); rescue NoMethodError => n1; p n1.name; end
      n2 = NoMethodError.new("m", :bar)
      p n2.name
      begin; raise NameError, "custom message"; rescue NameError => n3; p n3.name; end
    RUBY

    _(result).must_answer <<~'OUT'
      "z"
      "inner"
      "key"
      "index"
      "std"
      true
      false
      true
      :foo
      :bar
      nil
    OUT
  end

  it "gc grandparent ivar scan" do
    result = zr(<<~'RUBY')
      # Grandparent ivar must survive GC even when a passthrough middle
      # class introduces no ivars of its own. The leaf's scan function has
      # to walk the full ancestor chain, not just the immediate parent.
      class A
        def payload=(v); @payload = v; end
        def payload; @payload; end
      end
      class B < A          # passthrough: no ivars of its own
      end
      class C < B          # leaf with its own ivar
        def own=(v); @own = v; end
        def own; @own; end
      end

      def churn(n)
        s = ""; i = 0
        while i < n; s = s + i.to_s + ","; i += 1; end
        s.length
      end

      obj = C.new
      obj.payload = "secret_" + 42.to_s
      obj.own     = "kept_" + 7.to_s
      GC.start
      churn(8000)
      GC.start
      puts "own=" + obj.own
      puts "payload=" + obj.payload
    RUBY

    _(result).must_answer "own=kept_7\npayload=secret_42\n"
  end

  it "hash default proc gc scan" do
    result = zr(<<~'RUBY')
      # A StrPolyHash must keep the Proc stored in dproc_self alive. The hash is the
      # only owner after the local Proc is cleared; a forced collection must not turn
      # a later default lookup into a call through freed memory.
      suffix = "!"
      h = { "seed" => 1, "text" => "v" }
      h.default_proc = proc { |hh, key| key + suffix }
      GC.start
      p h["missing"]
    RUBY

    _(result).must_answer "\"missing!\"\n"
  end

  it "interpolated regexp literal shares the enclosing scope" do
    result = zr(<<~'RUBY')
      word = "wor"
      r = /#{word}ld/
      puts r.match?("world")
      puts r.source
    RUBY

    _(result).must_answer "true\nworld\n"
  end

  it "invalid interpolated pattern raises a catchable regexp error" do
    result = zr(<<~'RUBY')
      # A STATIC (non-interpolated) invalid pattern is a real, uncatchable
      # `SyntaxError` at parse time in real Ruby -- zr defers that
      # check to construction time uniformly (a documented, narrower-timing
      # approximation, see `hir::HirNode::RegexpLit`'s docs), so only the
      # INTERPOLATED case (genuinely runtime-only in real Ruby too) is
      # oracle-verified here as a rescuable exception.

      bad = "("
      begin
        r = /#{bad}/
        puts "no error"
      rescue RegexpError => e
        puts "regexp error"
      end
    RUBY

    _(result).must_answer "regexp error\n"
  end

  it "matchdata constant" do
    result = zr(<<~'RUBY')
      # `MatchData` names a class every match already answers to #class, but the
      # constant itself was not registered and reading it raised NameError.
      p MatchData
      p MatchData.name
      p "ab".match(/a/).class
      p("ab".match(/a/).is_a?(MatchData))
      p MatchData.to_s
    RUBY

    _(result).must_answer <<~'OUT'
      MatchData
      "MatchData"
      MatchData
      true
      "MatchData"
    OUT
  end

  it "matchdata frozen query" do
    result = zr(<<~'RUBY')
      m001 = "hello".match(/l+/)
      p m001.frozen?
      p m001.to_a.frozen?
      p m001.string.frozen?
    RUBY

    _(result).must_answer <<~'OUT'
      false
      false
      true
    OUT
  end

  it "matchdata values at range" do
    result = zr(<<~'RUBY')
      # MatchData#values_at takes a Range, selecting a run of groups the way
      # Array#values_at does. The Range went into the group-index slot as a struct,
      # so the C did not compile.
      m = "hello".match(/(l)(l)(o)/)
      p m.values_at(1..2)
      p m.values_at(0)
      p m.values_at(1,3)
      p m.values_at(1...3)
      p m.values_at(1..9)
    RUBY

    _(result).must_answer <<~'OUT'
      ["l", "l"]
      ["llo"]
      ["l", "o"]
      ["l", "l"]
      ["l", "l", "o", nil, nil, nil, nil, nil, nil]
    OUT
  end

  it "method missing receiver descriptions match cruby" do
    result = zr(<<~'RUBY')
      # One raiser builds every NoMethodError message, so the four receiver
      # shapes stay in step: an instance, nil (rendered bare, no "an instance
      # of" prefix), a module, and a class. Critically the receiver is described
      # by CLASS NAME and never by calling `inspect` on it -- CRuby's formats
      # carry no receiver-inspect directive, which is what lets an object with
      # no `inspect` still raise an error about itself.

      def msg
        yield
      rescue NoMethodError => e
        puts e.message
      end
      module Helper; end
      msg { Object.new.nope }
      msg { nil.nope }
      msg { Helper.nope }
      msg { String.nope }
      msg { 5.nope }
    RUBY

    _(result).must_answer <<~'OUT'
      undefined method 'nope' for an instance of Object
      undefined method 'nope' for nil
      undefined method 'nope' for module Helper
      undefined method 'nope' for class String
      undefined method 'nope' for an instance of Integer
    OUT
  end

  it "optional param default expr referencing an ivar is scanned" do
    result = zr(<<~'RUBY')
      # Before this fix, `analyze::collect_ivars`/`locals::track_extra`/
      # `hoisting`'s per-method scans never walked into a `Params::optional`/
      # `keywords` default expression -- an ivar referenced ONLY there (never
      # in the method's own body) would be missing from the generated
      # struct's fields entirely, a "no such field" codegen error. Also
      # exercises the keyword-optional case (`y:`) in the same call.

      class Greeter
        def initialize
          @default_name = "World"
        end
        def greet(x = @default_name, y: @default_name)
          "hi #{x} and #{y}"
        end
      end

      puts Greeter.new.greet
    RUBY

    _(result).must_answer "hi World and World\n"
  end

  it "poly recv runtime regex scan" do
    result = zr(<<~'RUBY')
      # A poly receiver scanning against a pattern the compiler cannot resolve to a
      # literal.
      #
      # The poly-receiver arm gated on the pattern being statically visible, so an
      # inline Regexp.new, a local holding one, or an interpolated literal fell past
      # the handler to the unresolved-call gate and raised NoMethodError on a String
      # that plainly answers #scan. The String-receiver arm has taken those shapes
      # since #3389; the gate itself still earns its keep, so it stays -- a non-String
      # receiver must raise rather than be stringified into an empty scan.

      PAT = /(\d)(\w)/
      mixed = ["a1b2", 7]
      poly = mixed[0]

      p poly.scan(/\d/)
      p poly.scan(PAT)

      lpat = /(\d)(\w)/
      p poly.scan(lpat)

      p poly.scan(Regexp.new("\\d"))
      rt = Regexp.new("(\\d)(\\w)")
      p poly.scan(rt)
      d = "\\d"
      p poly.scan(/#{d}/)
      p poly.scan("1")

      n = mixed[1]
      begin
        n.scan(/\d/)
        p "no raise"
      rescue NoMethodError
        p "NoMethodError"
      end

      begin
        n.scan(Regexp.new("\\d"))
        p "no raise"
      rescue NoMethodError
        p "NoMethodError"
      end
    RUBY

    _(result).must_answer <<~'OUT'
      ["1", "2"]
      [["1", "b"]]
      [["1", "b"]]
      ["1", "2"]
      [["1", "b"]]
      ["1", "2"]
      ["1"]
      "NoMethodError"
      "NoMethodError"
    OUT
  end

  it "poly string scan block" do
    result = zr(<<~'RUBY')
      # `str.scan(pat) { }` where the receiver is only known to be a String at run
      # time, and the pattern is a Regexp read out of a table (so it arrives boxed).
      # The poly path had no scan arm at all and raised NoMethodError.

      PATTERNS = { "num" => /\d+/, "word" => /[a-z]+/ }

      def pick(f, s)
        f ? s : 7
      end

      log = pick(true, "abc 123 def 45")
      counts = Hash.new(0)
      PATTERNS.each do |name, regex|
        log.scan(regex) { counts[name] += 1 }
      end
      p counts["num"]
      p counts["word"]

      seen = []
      log.scan(/\d+/) { |m| seen << m }
      p seen

      # the same, with the receiver statically a String and only the pattern boxed
      class L
        def initialize
          @log = "abc 123 def 45"
        end

        def run
          counts = Hash.new(0)
          PATTERNS.each do |name, regex|
            @log.scan(regex) { counts[name] += 1 }
          end
          counts.values.sum
        end
      end

      p L.new.run

      # the blockless form with the same boxed pattern
      PATTERNS.each do |name, regex|
        p [name, log.scan(regex).size]
      end
    RUBY

    _(result).must_answer <<~'OUT'
      2
      2
      ["123", "45"]
      4
      ["num", 2]
      ["word", 2]
    OUT
  end

  it "posix bracket validation and regexp error messages" do
    result = zr(<<~'RUBY')
      # An unknown POSIX class name is a RegexpError (invalid POSIX bracket type),
      # while valid ones compile; an unterminated char class reports onig's own
      # wording -- "premature end of char-class", not the engine's raw multiline
      # parse error and not a paraphrase of it.

      p "Hi 12".scan(/[[:alpha:]]+/)
      r = (begin; Regexp.new("[[:bogus:]]"); "ok"; rescue RegexpError => e; e.message; end); p r
      r2 = (begin; Regexp.new("[invalid"); "ok"; rescue RegexpError => e; e.message; end); p r2
      p Regexp.new("hello").match?("say hello")
    RUBY

    _(result).must_answer <<~'OUT'
      ["Hi"]
      "invalid POSIX bracket type: /[[:bogus:]]/"
      "premature end of char-class: /[invalid/"
      true
    OUT
  end

  it "Stage 1: UTF-8 source byte-length" do
    result = zr(<<~'RUBY')
      # Regex coverage — issue #61's five stages plus literal-form
      # tests. Was six tests; class names didn't collide and the only
      # top-level `def` (regex_local_var's `find`) is unique within this
      # file. Local-name collisions (`re`, `re2` reused across files for
      # different regex literals) are dodged with per-section prefixes
      # so spinel's local-type inference doesn't unify them across the
      # script and widen to poly.


      # A regex source containing multi-byte UTF-8 chars must reach the
      # runtime with the correct byte length. This section just verifies
      # the binary runs past regex init.
      re_s1a = /[₀₁₂₃₄₅₆₇₈₉]+/
      re_s1b = /\A→\z/
      re_s1c = /[αβγ]/
      puts "ok"
    RUBY

    _(result).must_answer "ok\n"
  end

  it "Stage 2: UTF-8 character class" do
    result = zr(<<~'RUBY')
      # Regex coverage — issue #61's five stages plus literal-form
      # tests. Was six tests; class names didn't collide and the only
      # top-level `def` (regex_local_var's `find`) is unique within this
      # file. Local-name collisions (`re`, `re2` reused across files for
      # different regex literals) are dodged with per-section prefixes
      # so spinel's local-type inference doesn't unify them across the
      # script and widen to poly.


      puts(("₁" =~ /[₀-₉]/) ? "ok1" : "fail1")
      puts(("α" =~ /[α-ω]/) ? "ok2" : "fail2")
      puts(("abc₁def" =~ /[₀₁₂₃₄₅₆₇₈₉]+/) ? "ok3" : "fail3")
      puts(("a"  =~ /[^₀-₉]/) ? "ok4" : "fail4")
      puts(("₁" =~ /[^₀-₉]/) ? "fail5" : "ok5")
      puts(("z"  =~ /[a-z₀-₉]/) ? "ok6" : "fail6")
      puts(("₅" =~ /[a-z₀-₉]/) ? "ok7" : "fail7")
      puts(("₁" =~ /[α-ω]/) ? "fail8" : "ok8")
      puts(("a"  =~ /[α-ω]/) ? "fail9" : "ok9")
      m_s2 = "abc₁₂₃def" =~ /[₀-₉]+/
      puts(m_s2 ? "ok10" : "fail10")
      m_s2_index = "abc" =~ /b/
      puts m_s2_index + 10
      if ("abc" =~ /z/) && true
        puts "fail11"
      else
        puts "ok11"
      end
    RUBY

    _(result).must_answer <<~'OUT'
      ok1
      ok2
      ok3
      ok4
      ok5
      ok6
      ok7
      ok8
      ok9
      ok10
      11
      ok11
    OUT
  end

  it "Stage 3: regex via constant" do
    result = zr(<<~'RUBY')
      # Regex coverage — issue #61's five stages plus literal-form
      # tests. Was six tests; class names didn't collide and the only
      # top-level `def` (regex_local_var's `find`) is unique within this
      # file. Local-name collisions (`re`, `re2` reused across files for
      # different regex literals) are dodged with per-section prefixes
      # so spinel's local-type inference doesn't unify them across the
      # script and widen to poly.


      RX = /[₀₁₂₃₄₅₆₇₈₉ₐₑₒₓₔ]+/
      puts RX.match?("₁₂")
      puts RX.match?("abc")
      if "₁₂" =~ RX
        puts "lhs match"
      else
        puts "lhs miss"
      end
      if RX =~ "₁₂"
        puts "rhs match"
      else
        puts "rhs miss"
      end
      m_s3 = RX.match("₁₂")
      puts m_s3 ? "match ok" : "match fail"
    RUBY

    _(result).must_answer <<~'OUT'
      true
      false
      lhs match
      rhs match
      match ok
    OUT
  end

  it "Stage 4: regex via local variable" do
    result = zr(<<~'RUBY')
      # Regex coverage — issue #61's five stages plus literal-form
      # tests. Was six tests; class names didn't collide and the only
      # top-level `def` (regex_local_var's `find`) is unique within this
      # file. Local-name collisions (`re`, `re2` reused across files for
      # different regex literals) are dodged with per-section prefixes
      # so spinel's local-type inference doesn't unify them across the
      # script and widen to poly.


      re_lv = /[₀₁₂₃₄₅₆₇₈₉]+/
      puts re_lv.match?("₁₂")
      puts re_lv.match?("abc")
      if "abc₁def" =~ re_lv
        puts "lhs match"
      else
        puts "lhs miss"
      end
      if re_lv =~ "abc₁def"
        puts "rhs match"
      else
        puts "rhs miss"
      end

      # Inside a method body — fresh scope, fresh local.
      def find(s)
        rx = /[a-z]+/
        rx.match?(s)
      end
      puts find("hello")
      puts find("123")

      # Multi-write disqualifies dispatch; the fall-through still compiles.
      re2_lv = /a/
      re2_lv = "not a regex"
      puts re2_lv
    RUBY

    _(result).must_answer <<~'OUT'
      true
      false
      lhs match
      rhs match
      true
      false
      not a regex
    OUT
  end

  it "Stage 5: UTF-8 quantifier" do
    result = zr(<<~'RUBY')
      # Regex coverage — issue #61's five stages plus literal-form
      # tests. Was six tests; class names didn't collide and the only
      # top-level `def` (regex_local_var's `find`) is unique within this
      # file. Local-name collisions (`re`, `re2` reused across files for
      # different regex literals) are dodged with per-section prefixes
      # so spinel's local-type inference doesn't unify them across the
      # script and widen to poly.


      puts "abc₁₂def".gsub(/[₀-₉]+/, "N")
      puts "abc₁₂₃def".gsub(/[₀-₉]+/, "N")
      puts "₁abc₂₃def₄₅₆".scan(/[₀-₉]+/).length
      puts "₀₁".match?(/[₀-₉]{2}/) ? "ok2" : "fail2"
      puts "₀".match?(/[₀-₉]{2}/) ? "fail3" : "ok3"
      puts "a₁b₂c".scan(/[a-z₀-₉]+/).length
      puts "₁₂₃".scan(/[₀-₉]/).length
      puts "αβ".match?(/[α-ω]+/) ? "ok7" : "fail7"
    RUBY

    _(result).must_answer <<~'OUT'
      abcNdef
      abcNdef
      3
      ok2
      ok3
      1
      3
      ok7
    OUT
  end

  it "Multi-line / escape patterns" do
    result = zr(<<~'RUBY')
      # Regex coverage — issue #61's five stages plus literal-form
      # tests. Was six tests; class names didn't collide and the only
      # top-level `def` (regex_local_var's `find`) is unique within this
      # file. Local-name collisions (`re`, `re2` reused across files for
      # different regex literals) are dodged with per-section prefixes
      # so spinel's local-type inference doesn't unify them across the
      # script and widen to poly.


      re_ml1 = /
        bar
      /x
      if re_ml1 =~ "barbar"
        puts "ok1"
      else
        puts "no1"
      end

      re_ml_t = /a\tb/
      if re_ml_t =~ "a\tb"
        puts "ok2"
      else
        puts "no2"
      end

      re_ml_n = /a\nb/
      if re_ml_n =~ "a\nb"
        puts "ok3"
      else
        puts "no3"
      end

      re_ml_r = /a\rb/
      if re_ml_r =~ "a\rb"
        puts "ok4"
      else
        puts "no4"
      end

      # InterpolatedRegularExpressionNode (/foo_#{x}/). Pattern is only known
      # at execution time; each AST site gets a `sp_re_dyn_<idx>(const char *)`
      # helper with a function-scope cache so heap is bounded to one engine
      # pattern per source location. Match-site dispatch goes through the
      # regex_pat_c_expr helper so =~, match?, match, gsub, sub, scan, and
      # split all accept either form.

      # match? predicate (boolean -- safe across CRuby/Spinel int/value
      # differences in =~ which returns a position vs a count).
      ir_x = "bar"
      puts "foo_bar".match?(/foo_#{ir_x}/)   #=> true
      puts "foo_baz".match?(/foo_#{ir_x}/)   #=> false

      # Captures populate $1
      if "foo_bar_42" =~ /foo_#{ir_x}_(\d+)/
        puts $1   #=> 42
      end

      # gsub with interpolated pattern
      ir_who = "world"
      puts "hello world".gsub(/#{ir_who}/, "Ruby")   #=> hello Ruby

      # sub
      puts "abc 123 def".sub(/(\d+)/, "X")           #=> abc X def

      # Interpolation that varies per-iteration (proves no stale cache and
      # that runtime compilation actually re-fires per evaluation).
      ir_i = 0
      while ir_i < 3
        ir_seed = ir_i.to_s
        puts ("v_" + ir_seed).match?(/v_#{ir_seed}/)
        ir_i = ir_i + 1
      end
      #=> true
      #=> true
      #=> true
    RUBY

    _(result).must_answer <<~'OUT'
      ok1
      ok2
      ok3
      ok4
      true
      false
      42
      hello Ruby
      abc X def
      true
      true
      true
    OUT
  end

  it "regex hex shorthand" do
    result = zr(<<~'RUBY')
      # Regex hex-digit shorthands \h ([0-9a-fA-F]) and \H (its negation).
      p("deadbeef" =~ /\A\h+\z/)
      p("ab"       =~ /\H/)
      p("xyz"      =~ /\h/)
      p("12ab"     =~ /\H/)
      p("g"        =~ /\h/)
      p("g"        =~ /\H/)
      p("a1F"      =~ /\h+/)
      p("z" =~ /[\h]/)
      p("a" =~ /[\h]/)
      p("a" =~ /[\H]/)
      p("z" =~ /[\H]/)
      p("X9k" =~ /[^\h]/)
    RUBY

    _(result).must_answer <<~'OUT'
      0
      nil
      nil
      nil
      nil
      0
      0
      nil
      0
      nil
      0
      0
    OUT
  end

  it "=~ answers the index it matched at, and match? answers whether it matched" do
    result = zr(<<~'RUBY', path: "regexp.rb")
      puts "hello world" =~ /world/
      puts "hello world" =~ /xyz/
      puts "hello".match?(/l+/)
      puts(/l+/.match?("hello"))
      puts("hello" !~ /xyz/)

    RUBY

    _(result).must_answer <<~'OUT'
      6

      true
      true
      true
    OUT
  end

  it "match answers a MatchData whose [] reads the whole match and each group" do
    result = zr(<<~'RUBY', path: "regexp.rb")

      m = "hello world".match(/(\w+) (\w+)/)
      puts m[0]
      puts m[1]
      puts m[2]
      puts m.pre_match
      puts m.post_match
      puts m.to_a
      puts m.captures

    RUBY

    _(result).must_answer <<~'OUT'
      hello world
      hello
      world


      hello world
      hello
      world
      hello
      world
    OUT
  end

  it "a named capture reads by name, as a Symbol or a String" do
    result = zr(<<~'RUBY', path: "regexp.rb")

      m = "hello world".match(/(\w+) (\w+)/)

      named = "John Smith".match(/(?<first>\w+) (?<last>\w+)/)
      puts named[:first]
      puts named["last"]
      h = named.named_captures
      puts h["first"]
      puts h["last"]

    RUBY

    _(result).must_answer <<~'OUT'
      John
      Smith
      John
      Smith
    OUT
  end

  it "the /i flag matches without regard to case" do
    result = zr(<<~'RUBY', path: "regexp.rb")

      m = "hello world".match(/(\w+) (\w+)/)

      named = "John Smith".match(/(?<first>\w+) (?<last>\w+)/)
      h = named.named_captures

      puts "HELLO".match?(/hello/i)
      puts "HELLO".match?(/hello/)

    RUBY

    _(result).must_answer <<~'OUT'
      true
      false
    OUT
  end

  it "the /m and ^ anchors read a multiline subject" do
    result = zr(<<~'RUBY', path: "regexp.rb")

      m = "hello world".match(/(\w+) (\w+)/)

      named = "John Smith".match(/(?<first>\w+) (?<last>\w+)/)
      h = named.named_captures


      puts("line1\nline2" =~ /^line2/)
      multiline_str = "abc\ndef"
      puts(multiline_str =~ /c.d/)
      puts(multiline_str =~ /c.d/m)

    RUBY

    _(result).must_answer <<~'OUT'
      6

      2
    OUT
  end

  it "to_s carries the flags inline, and inspect carries them after the slashes" do
    result = zr(<<~'RUBY', path: "regexp.rb")

      m = "hello world".match(/(\w+) (\w+)/)

      named = "John Smith".match(/(?<first>\w+) (?<last>\w+)/)
      h = named.named_captures


      multiline_str = "abc\ndef"

      r = /abc/x
      puts r.to_s
      puts(/abc/mi.inspect)

    RUBY

    _(result).must_answer <<~'OUT'
      (?x-mi:abc)
      /abc/mi
    OUT
  end

  it "scan answers every match, and each group when the pattern has them" do
    result = zr(<<~'RUBY', path: "regexp.rb")

      m = "hello world".match(/(\w+) (\w+)/)

      named = "John Smith".match(/(?<first>\w+) (?<last>\w+)/)
      h = named.named_captures


      multiline_str = "abc\ndef"

      r = /abc/x

      puts "one two three".scan(/\w+/)
      puts "a1b2c3".scan(/([a-z])(\d)/)

    RUBY

    _(result).must_answer <<~'OUT'
      one
      two
      three
      a
      1
      b
      2
      c
      3
    OUT
  end

  it "split cuts on the pattern and keeps an empty field between two separators" do
    result = zr(<<~'RUBY', path: "regexp.rb")

      m = "hello world".match(/(\w+) (\w+)/)

      named = "John Smith".match(/(?<first>\w+) (?<last>\w+)/)
      h = named.named_captures


      multiline_str = "abc\ndef"

      r = /abc/x


      puts "a,b,,c".split(/,/)
      puts ",a,b".split(/,/)

    RUBY

    _(result).must_answer <<~'OUT'
      a
      b

      c

      a
      b
    OUT
  end

  it "gsub and sub replace by pattern, by group reference and with a block" do
    result = zr(<<~'RUBY', path: "regexp.rb")

      m = "hello world".match(/(\w+) (\w+)/)

      named = "John Smith".match(/(?<first>\w+) (?<last>\w+)/)
      h = named.named_captures


      multiline_str = "abc\ndef"

      r = /abc/x



      puts "hello world".gsub(/o/, "0")
      puts "hello world".sub(/o/, "0")
      puts "John Smith".gsub(/(\w+) (\w+)/, '\2 \1')
      puts "hello".gsub(/l/) { |match| "[#{match}]" }

    RUBY

    _(result).must_answer <<~'OUT'
      hell0 w0rld
      hell0 world
      Smith John
      he[l][l]o
    OUT
  end

  it "a block given to scan runs once per match" do
    result = zr(<<~'RUBY', path: "regexp.rb")

      m = "hello world".match(/(\w+) (\w+)/)

      named = "John Smith".match(/(?<first>\w+) (?<last>\w+)/)
      h = named.named_captures


      multiline_str = "abc\ndef"

      r = /abc/x




      count = 0
      "one two three".gsub(/\w+/) { |w| count += 1; w }
      puts count

    RUBY

    _(result).must_answer <<~'OUT'
      3
    OUT
  end

  it "=== matches, which is what case/when asks" do
    result = zr(<<~'RUBY', path: "regexp.rb")

      m = "hello world".match(/(\w+) (\w+)/)

      named = "John Smith".match(/(?<first>\w+) (?<last>\w+)/)
      h = named.named_captures


      multiline_str = "abc\ndef"

      r = /abc/x




      count = 0
      "one two three".gsub(/\w+/) { |w| count += 1; w }

      puts(/foo/ === "foobar")
      puts(/foo/ === "baz")

    RUBY

    _(result).must_answer <<~'OUT'
      true
      false
    OUT
  end

  it "a case over several patterns picks the first that matches" do
    result = zr(<<~'RUBY', path: "regexp.rb")

      m = "hello world".match(/(\w+) (\w+)/)

      named = "John Smith".match(/(?<first>\w+) (?<last>\w+)/)
      h = named.named_captures


      multiline_str = "abc\ndef"

      r = /abc/x




      count = 0
      "one two three".gsub(/\w+/) { |w| count += 1; w }


      class Classifier
        def classify(x)
          case x
          when /^\d+$/
            "number"
          when /^[a-z]+$/
            "lower"
          else
            "other"
          end
        end

        def classify_in(x)
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
      classifier = Classifier.new
      puts classifier.classify("123")
      puts classifier.classify("abc")
      puts classifier.classify("ABC")
      puts classifier.classify_in("123")
      puts classifier.classify_in("abc")

    RUBY

    _(result).must_answer <<~'OUT'
      number
      lower
      other
      number
      lower
    OUT
  end

  it "an interpolated pattern matches what its parts spell" do
    result = zr(<<~'RUBY', path: "regexp.rb")

      m = "hello world".match(/(\w+) (\w+)/)

      named = "John Smith".match(/(?<first>\w+) (?<last>\w+)/)
      h = named.named_captures


      multiline_str = "abc\ndef"

      r = /abc/x




      count = 0
      "one two three".gsub(/\w+/) { |w| count += 1; w }


      class Classifier
        def classify(x)
          case x
          when /^\d+$/
            "number"
          when /^[a-z]+$/
            "lower"
          else
            "other"
          end
        end

        def classify_in(x)
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
      classifier = Classifier.new

      word = "wor"
      interpolated = /#{word}ld/
      puts interpolated.match?("world")
      puts interpolated.source

    RUBY

    _(result).must_answer <<~'OUT'
      true
      world
    OUT
  end

  it "the %r spelling matches the same as the slash one" do
    result = zr(<<~'RUBY', path: "regexp.rb")

      m = "hello world".match(/(\w+) (\w+)/)

      named = "John Smith".match(/(?<first>\w+) (?<last>\w+)/)
      h = named.named_captures


      multiline_str = "abc\ndef"

      r = /abc/x




      count = 0
      "one two three".gsub(/\w+/) { |w| count += 1; w }


      class Classifier
        def classify(x)
          case x
          when /^\d+$/
            "number"
          when /^[a-z]+$/
            "lower"
          else
            "other"
          end
        end

        def classify_in(x)
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
      classifier = Classifier.new

      word = "wor"
      interpolated = /#{word}ld/

      percent = %r{foo/bar}
      puts percent.match?("xxfoo/barxx")

    RUBY

    _(result).must_answer <<~'OUT'
      true
    OUT
  end

  it "Regexp.new and Regexp.union each answer a Regexp" do
    result = zr(<<~'RUBY', path: "regexp.rb")

      m = "hello world".match(/(\w+) (\w+)/)

      named = "John Smith".match(/(?<first>\w+) (?<last>\w+)/)
      h = named.named_captures


      multiline_str = "abc\ndef"

      r = /abc/x




      count = 0
      "one two three".gsub(/\w+/) { |w| count += 1; w }


      class Classifier
        def classify(x)
          case x
          when /^\d+$/
            "number"
          when /^[a-z]+$/
            "lower"
          else
            "other"
          end
        end

        def classify_in(x)
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
      classifier = Classifier.new

      word = "wor"
      interpolated = /#{word}ld/

      percent = %r{foo/bar}

      r2 = /abc/
      puts r2.is_a?(Regexp)
      puts r2.is_a?(Object)
      puts m.is_a?(MatchData)

    RUBY

    _(result).must_answer <<~'OUT'
      true
      true
      true
    OUT
  end

  it "a pattern that will not compile raises RegexpError" do
    result = zr(<<~'RUBY', path: "regexp.rb")

      m = "hello world".match(/(\w+) (\w+)/)

      named = "John Smith".match(/(?<first>\w+) (?<last>\w+)/)
      h = named.named_captures


      multiline_str = "abc\ndef"

      r = /abc/x




      count = 0
      "one two three".gsub(/\w+/) { |w| count += 1; w }


      class Classifier
        def classify(x)
          case x
          when /^\d+$/
            "number"
          when /^[a-z]+$/
            "lower"
          else
            "other"
          end
        end

        def classify_in(x)
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
      classifier = Classifier.new

      word = "wor"
      interpolated = /#{word}ld/

      percent = %r{foo/bar}

      r2 = /abc/

      bad = "("
      begin
        invalid = /#{bad}/
        puts "no error"
      rescue RegexpError => _e
        puts "regexp error"
      end
    RUBY

    _(result).must_answer <<~'OUT'
      regexp error
    OUT
  end

  it "deep backtracking runs off the heap, and atomic groups and backrefs answer with it" do
    result = zr(<<~'RUBY')
      [100, 5000, 9500, 10000, 12000, 20000].each do |n|
        s = "a" * n + "b" + "a" * n
        p [n, !!(s =~ /\A(a+)b\1\z/)]
      end

      p(/(a*)*\1/.match("aa").to_a)
      p(/(a*)+\1/.match("aa").to_a)
      p(/(a*)*\1/.match("").to_a)
      p(/((a)*)\2/.match("aa").to_a)
      p(/(?:(a)|(b))+\1/.match("ab").to_a)

      p(/(?>a?)*/.match("b").to_a)
      p(/(?>a*)*/.match("aab").to_a)
      p(/(a?)\1*/.match("").to_a)

      [200, 1000, 5000].each do |n|
        p [n, !!(("a" * n) =~ /\A(?>a)*\z/), !!(("a" * n) =~ /\A(?:(?=a)a)*\z/)]
      end
      [1, 50, 300].each do |d|
        p [d, !!("a" =~ Regexp.new("(?>" * d + "a" + ")" * d)),
              !!("a" =~ Regexp.new("(?=" * d + "a" + ")" * d + "a"))]
      end

      p(!!(("a" * 40 + "!") =~ /(a+)+$/))
      p(!!(("a" * 40 + "!") =~ /(a*)*b\1/))

      p(/(a)\1/.match("aa").to_a)
      p(/(?>ab|a)*c/.match("abac").to_a)
      p(/(a)(?=\1)/.match("aa").to_a)
      p(/(a)(?!\1)/.match("ab").to_a)
      p("aaa".scan(/(?>a)?/).size)
    RUBY

    _(result).must_answer <<~'OUT'
      [100, true]
      [5000, true]
      [9500, true]
      [10000, true]
      [12000, true]
      [20000, true]
      ["aa", ""]
      ["aa", ""]
      ["", ""]
      ["aa", "a", "a"]
      []
      [""]
      ["aa"]
      ["", ""]
      [200, true, true]
      [1000, true, true]
      [5000, true, true]
      [1, true, true]
      [50, true, true]
      [300, true, true]
      false
      false
      ["aa", "a"]
      ["abac"]
      ["a", "a"]
      ["a", "a"]
      4
    OUT
  end

  it "a capture used as an ivar hash key is kept as a String, so a String literal finds it" do
    result = zr(<<~'RUBY')
      # A regex match-capture used as the key of an instance-variable hash,
      # inside a loop, must store the capture as a boxed String key, so keys
      # come back as Strings and lookups by a String literal find them --
      # not stored unboxed as a raw integer/pointer. The "parse lines ->
      # build a lookup table in an ivar" shape (afm, i18n-country-translations).
      class Font
        def initialize(text)
          @table = {}
          text.each_line do |line|
            if (m = line.match(/^(\w+) (.+)/))
              @table[m[1]] = m[2]
            end
          end
        end

        def keys
          @table.keys
        end

        def [](name)
          @table[name]
        end
      end

      f = Font.new("FontName Times\nWeight Bold\nItalicAngle zero")
      p f.keys
      p f["FontName"]
      p f["Weight"]
      p f["ItalicAngle"]
      p f["Missing"]

      # Value derived from the same capture (downcase): still a String hash.
      class Index
        def initialize(text)
          @h = {}
          text.each_line do |line|
            if (m = line.match(/^(\w+)/))
              @h[m[1]] = m[1].downcase
            end
          end
        end
        def lookup(k); @h[k]; end
        def size; @h.keys.length; end
      end

      i = Index.new("Alpha\nBeta\nGamma")
      p i.lookup("Beta")
      p i.size
    RUBY

    _(result).must_answer <<~'OUT'
      ["FontName", "Weight", "ItalicAngle"]
      "Times"
      "Bold"
      "zero"
      nil
      "beta"
      3
    OUT
  end

  it "named and numbered captures reach scan, a replacement backref and a gsub block" do
    result = zr(<<~'RUBY')
      # Regexp capture plumbing: named-group scan, block-form scan destructuring,
      # the \+ replacement backref, non-string gsub block values, and blockless
      # each_line(chomp:).

      def scn(s)
        s.scan(/(?<a>\w)(?<b>\w)/)
      end
      p scn("abcd")
      p scn("x")

      # lookbehinds are not capture groups: whole matches come back
      def slb(s)
        s.scan(/(?<=a)\d/)
      end
      p slb("a1 b2 a3")

      # numbered groups through the block form: params destructure the row
      def scb(s)
        out = []
        s.scan(/(\d)(\d)/) { |a, b| out << [a, b] }
        out
      end
      p scb("12 34")

      # an optional group that does not participate binds nil
      def sco(s)
        out = []
        s.scan(/(a)(x)?/) { |a, b| out << [a, b] }
        out
      end
      p sco("ab")

      # a single param binds the whole group row
      def scr(s)
        rows = []
        s.scan(/(\d)(\w)/) { |row| rows << row }
        rows
      end
      p scr("1a 2b")

      # \+ expands to the highest-numbered participating group
      def bp(s, r)
        s.sub(/(a)(b)?/, r)
      end
      p bp("ab", '\+')
      p bp("a.", '\+')
      p bp("xy", '\+')

      def bg(s)
        s.gsub(/(\d)([a-z])?/, '<\+>')
      end
      p bg("1a 2. 3c")

      # gsub block values stringify like CRuby (Integer, nil, Float)
      def gi(s)
        s.gsub(/(\d)/) { $1.to_i * 2 }
      end
      p gi("a1b2")

      def gn(s)
        s.gsub(/x/) { nil }
      end
      p gn("axbxc")

      def gf(s)
        s.gsub(/\d+/) { |m| m.to_f / 2 }
      end
      p gf("10 33")

      # blockless each_line with the chomp keyword materializes an Enumerator
      def elc(s)
        s.each_line(chomp: true).to_a
      end
      p elc("a\nb\nc")
      p elc("one\n\ntwo\n")

      def elk(s)
        s.each_line(chomp: false).to_a
      end
      p elk("a\nb")

      def elm(s)
        s.each_line(chomp: true).map { |ln| ln.upcase }
      end
      p elm("x\ny\n")
    RUBY

    _(result).must_answer <<~'OUT'
      [["a", "b"], ["c", "d"]]
      []
      ["1", "3"]
      [["1", "2"], ["3", "4"]]
      [["a", nil]]
      [["1", "a"], ["2", "b"]]
      "b"
      "a."
      "xy"
      "<a> <2>. <c>"
      "a2b4"
      "abc"
      "5.0 16.5"
      ["a", "b", "c"]
      ["one", "", "two"]
      ["a\n", "b"]
      ["X", "Y"]
    OUT
  end

  it "#source is the pattern text and #=== answers whether the string matches" do
    result = zr(<<~'RUBY')
      puts(/abc/ =~ "xxabcxx")
      r = /foo/
      puts r.source
      puts(r === "foobar")
      puts(r === "baz")
    RUBY

    _(result).must_answer <<~'OUT'
      2
      foo
      true
      false
    OUT
  end

  it "(?a), (?u) and (?d) set which character-range mode a pattern reads" do
    result = zr(<<~'RUBY')
      # Ruby reads a pattern in one of three character-range modes. In the default
      # mode `\w`, `\d` and `\s` are ASCII-only while `\b`, `\B` and the POSIX
      # brackets are Unicode; `(?a)` moves everything to ASCII, `(?u)` everything to
      # Unicode, and `(?d)` is the default again. A bare option holds to the end of
      # its enclosing group; `(?a:...)` scopes to the group. `\h` is always ASCII
      # and `\p{...}` is always Unicode.
      #
      # Under `/i` a bare `\p{...}` case-folds, its negation folds as a negated
      # class, and a ctype-derived ASCII member never folds outside ASCII (`ſ` and
      # the Kelvin sign fold to `s` and `k`; `\w` does not reach them, `[a-z]` does).

      def t(l) = puts("#{l.ljust(28)} #{begin; yield.inspect; rescue Exception => e; "#{e.class}: #{e.message}"; end}")
      t("w cjk") { "日本語" =~ /\w/ }
      t("W cjk") { "日本語" =~ /\W/ }
      t("b cjk") { "λx" =~ /\b/ }
      t("word cjk") { "日本語" =~ /[[:word:]]/ }
      t("u w") { "日" =~ /(?u)\w/ }
      t("u: w") { "日" =~ /(?u:\w)x/ }
      t("a b") { "λx" =~ /(?a)\b/ }
      t("a B") { "λx" =~ /(?a)\B/ }
      t("a word") { "日" =~ /(?a)[[:word:]]/ }
      t("a ^alpha") { "日" =~ /(?a)[[:^alpha:]]/ }
      t("a pWord") { "日" =~ /(?a)\p{Word}/ }
      t("s nbsp") { "\u00a0" =~ /\s/ }
      t("space em") { "\u2003" =~ /[[:space:]]/ }
      t("d w") { "日" =~ /(?d)\w/ }
      t("digits") { "1２" =~ /\d+/ }
      t("[^W]") { "x" =~ /[^\W]/ }
      t("[W] cjk") { "日" =~ /[\W]/ }
      t("[^w] cjk") { "日" =~ /[^\w]/ }
      t("pUpper/i") { "é" =~ /\p{Upper}/i }
      t("pLu/i") { "é" =~ /\p{Lu}/i }
      t("pLower/i") { "É" =~ /\p{Lower}/i }
      t("p^Lower/i") { "É" =~ /\p{^Lower}/i }
      t("PLower/i") { "é" =~ /\P{Lower}/i }
      t("pLt/i") { "ǆ" =~ /\p{Lt}/i }
      t("(?i)pLower") { "É" =~ /(?i)\p{Lower}/ }
      t("(?i)(?-i:pLower)") { "É" =~ /(?i)(?-i:\p{Lower})/ }
      t("u w d w") { "日x" =~ /(?u)\w(?d)\w/ }
      t("w/i long s") { "ſ" =~ /\w/i }
      t("W/i long s") { "ſ" =~ /\W/i }
      t("[a-z]/i long s") { "ſ" =~ /[a-z]/i }
      t("k/i kelvin") { "\u212a" =~ /k/i }
      t("h fullwidth") { "Ａ" =~ /\h/ }
      t("xdigit fullwidth") { "Ａ" =~ /[[:xdigit:]]/ }
      t("h/i long s") { "ſ" =~ /\h/i }
      t("a h") { "日" =~ /(?a)\h/ }
      t("(?a) alone") { "" =~ /(?a)/ }
      t("-u") { Regexp.new("(?-u)\\w") }
      t("x comment") { "a1" =~ /a # \w [ (
       \d/x }
      t("names") { /(?<x>\w)(?a)(?<y>\d)/.names }
      t("source") { /(?a)\w\b/.source }
      t("inspect") { /(?u)\w/i.inspect }
      t("p+quant") { "abc".scan(/\p{L}+/) }
      t("pL/i neg class") { "É".scan(/[^\p{Lower}]/i) }
      t("w in lookbehind") { "a1" =~ /(?<=\w)\d/ }
      t("scan w cjk") { "日本 abc".scan(/\w+/) }
      t("gsub W") { "日本 abc".gsub(/\W/, "_") }
      t("split s") { "a b\u3000c".split(/\s/) }
      t("b unicode gsub") { "日本語 です".gsub(/\b/, "|") }
      t("union") { Regexp.union(/\w/, /(?a)\b/).source }
      t("bare option then group") { "aXb" =~ /a(?i)x(?-i)b/ }
      t("nested option") { "aXB" =~ /a(?i:x(?-i:B))/ }
    RUBY

    _(result).must_answer <<~'OUT'
      w cjk                        nil
      W cjk                        0
      b cjk                        0
      word cjk                     0
      u w                          0
      u: w                         nil
      a b                          1
      a B                          0
      a word                       nil
      a ^alpha                     0
      a pWord                      0
      s nbsp                       nil
      space em                     0
      d w                          nil
      digits                       0
      [^W]                         0
      [W] cjk                      0
      [^w] cjk                     0
      pUpper/i                     0
      pLu/i                        0
      pLower/i                     0
      p^Lower/i                    nil
      PLower/i                     nil
      pLt/i                        0
      (?i)pLower                   0
      (?i)(?-i:pLower)             nil
      u w d w                      0
      w/i long s                   nil
      W/i long s                   0
      [a-z]/i long s               0
      k/i kelvin                   0
      h fullwidth                  nil
      xdigit fullwidth             nil
      h/i long s                   nil
      a h                          nil
      (?a) alone                   0
      -u                           RegexpError: undefined group option: /(?-u)\w/
      x comment                    0
      names                        ["x", "y"]
      source                       "(?a)\\w\\b"
      inspect                      "/(?u)\\w/i"
      p+quant                      ["abc"]
      pL/i neg class               []
      w in lookbehind              1
      scan w cjk                   ["abc"]
      gsub W                       "___abc"
      split s                      ["a", "b　c"]
      b unicode gsub               "|日本語| |です|"
      union                        "(?-mix:\\w)|(?-mix:(?a)\\b)"
      bare option then group       0
      nested option                0
    OUT
  end

  it "RegexpError repeats onig's wording, and a subject with bytes invalid in its encoding is refused" do
    result = zr(<<~'RUBY')
      # `RegexpError` messages, which CRuby words after onig's own reasons and
      # echoes the pattern into. The engine underneath zr words several of them
      # differently, so `regexp::cruby_regex_error` maps them; `a{2,1}` it accepts
      # outright, so that one is checked before the build.
      ["[invalid", "(a", "a)", "a{2,1}", "[z-a]", "*a", "(?"].each do |src|
        begin
          Regexp.new(src)
          p [src, :ok]
        rescue RegexpError => e
          p [src, e.message]
        end
      end

      # Matching READS characters, so a subject whose bytes are not valid in its
      # own encoding is refused rather than matched against replacement characters.
      s = "\xff".force_encoding("UTF-8")
      p s.valid_encoding?
      [
        -> { s =~ /a/ }, -> { s.match(/a/) }, -> { s.match?(/a/) },
        -> { s.scan(/a/) }, -> { s.gsub(/a/, "b") }, -> { s.split(/a/) },
        -> { /a/ =~ s }, -> { /a/.match(s) }, -> { s.index(/a/) },
      ].each do |probe|
        begin
          probe.call
          p :no_raise
        rescue => e
          p [e.class, e.message]
        end
      end
      # A BINARY string has no invalid bytes, so it matches.
      p(("\xff".force_encoding("ASCII-8BIT") =~ /a/))
      # ...and a plain substring search moves by bytes, so it takes no guard.
      p s.index("a")
    RUBY

    _(result).must_answer <<~'OUT'
      ["[invalid", "premature end of char-class: /[invalid/"]
      ["(a", "end pattern with unmatched parenthesis: /(a/"]
      ["a)", "unmatched close parenthesis: /a)/"]
      ["a{2,1}", "upper is smaller than lower in repeat range: /a{2,1}/"]
      ["[z-a]", "empty range in char class: /[z-a]/"]
      ["*a", "target of repeat operator is not specified: /*a/"]
      ["(?", "end pattern in group: /(?/"]
      false
      [ArgumentError, "invalid byte sequence in UTF-8"]
      [ArgumentError, "invalid byte sequence in UTF-8"]
      [ArgumentError, "invalid byte sequence in UTF-8"]
      [ArgumentError, "invalid byte sequence in UTF-8"]
      [ArgumentError, "invalid byte sequence in UTF-8"]
      [ArgumentError, "invalid byte sequence in UTF-8"]
      [ArgumentError, "invalid byte sequence in UTF-8"]
      [ArgumentError, "invalid byte sequence in UTF-8"]
      [ArgumentError, "invalid byte sequence in UTF-8"]
      nil
      nil
    OUT
  end

  it "Regexp.compile and Regexp.new take a Regexp and copy its source and options" do
    result = zr(<<~'RUBY')
      p(Regexp.compile(/ab/i).source)
      p(Regexp.compile(/ab/i).options)
      p(Regexp.compile("cd").source)
      p(Regexp.new(/ab/i).source)
      p(Regexp.compile(/ab/i) =~ "AB")
    RUBY

    _(result).must_answer <<~'OUT'
      "ab"
      1
      "cd"
      "ab"
      0
    OUT
  end

  it "Regexp.escape, Regexp#options, Complex.rect and Range#bsearch each answer" do
    result = zr(<<~'RUBY')
      p Regexp.escape("a.b*c")
      p Regexp.quote("1+1")
      p(/abc/i.options)
      p(/abc/m.options)
      p(/abc/.options)
      p Complex.rect(3, 4)
      p Complex.rectangular(3)
      p((1..10).bsearch { |x| x >= 4 })
      p((1..100).bsearch { |x| x >= 40 })
      p((1..10).bsearch { |x| x >= 40 })
    RUBY

    _(result).must_answer <<~'OUT'
      "a\\.b\\*c"
      "1\\+1"
      1
      4
      0
      (3+4i)
      (3+0i)
      4
      40
      nil
    OUT
  end

  it "a quantified empty group matches empty, while a quantifier with no atom raises" do
    result = zr(<<~'RUBY')
      # Repeating an empty group answers the same empty match however many times it
      # runs, so the quantifier applies to an atom that emits no code. The engine
      # refused it as "target of repeat operator is not specified", which is the
      # error for a quantifier with NO atom -- a distinction the source position
      # makes, since the empty group does consume its own bytes.
      p("" =~ /(?:)*/)
      p("ab" =~ /(?:)+/)
      p("ab" =~ /(?:)?/)
      p("ab" =~ /a(?:)*b/)
      p("ab" =~ /(?:)*?/)
      p("ab" =~ /(?:){2}/)
      p("ab" =~ /a(?:){0,3}b/)
      p "ab".sub(/(?:)*/, "-")
      p "abc".scan(/(?:)*/).size

      # a quantifier with no atom at all still raises, and so does one after a
      # comment group, which consumes source without being an atom
      begin
        Regexp.new("*a")
      rescue => e
        p e.class
      end
      begin
        Regexp.new("(?#c)*")
      rescue => e
        p e.class
      end
    RUBY

    _(result).must_answer <<~'OUT'
      0
      0
      0
      0
      0
      0
      0
      "-ab"
      4
      RegexpError
      RegexpError
    OUT
  end

  it "a pattern is never equal to a String, a number or nil" do
    result = zr(<<~'RUBY')
      a001 = /ab/
      p(a001 == "ab")
      p(a001 == 5)
      p(a001.eql?("ab"))
      p(a001.eql?(nil))
      p(a001 != "ab")
      p(a001 == nil)
      p(a001 == /ab/)
    RUBY

    _(result).must_answer <<~'OUT'
      false
      false
      false
      false
      true
      false
      true
    OUT
  end

  it "Regexp.new and an equal literal are eql? and share a hash" do
    result = zr(<<~'RUBY')
      a001 = Regexp.new("ab")
      p(a001 == /ab/)
      p(a001.eql?(/ab/))
      p(a001.hash == /ab/.hash)
      h001 = { /ab/ => 1 }
      p h001[a001]
    RUBY

    _(result).must_answer <<~'OUT'
      true
      true
      true
      1
    OUT
  end

  it "equality covers the flags, so /ab/ and /ab/i are two patterns" do
    result = zr(<<~'RUBY')
      # Regexp equality is source AND options: /ab/ and /ab/i are different patterns.
      # Only the source was compared, so every flag variant of a pattern was equal to
      # it. #eql? is value equality too (only #equal? is identity), and it was
      # answering from a pointer comparison.
      p(/ab/ == /ab/i)
      p(/ab/ == /ab/m)
      a = /ab/
      b = /ab/x
      p(a == b)
      p(/ab/.eql?(/ab/i))
      p(/ab/ == /ab/)
      p(/ab/.eql?(/ab/))
      p(/ab/i == /ab/i)
      p(/ab/i.eql?(/ab/i))
      p(/ab/ != /ab/i)
      p(/ab/ != /ab/)
      p(/ab/ == /cd/)
      p(/ab/im == /ab/mi)
    RUBY

    _(result).must_answer <<~'OUT'
      false
      false
      false
      false
      true
      true
      true
      true
      true
      false
      false
      true
    OUT
  end

  it "Regexp.new raises a catchable RegexpError and the program runs on" do
    result = zr(<<~'RUBY')
      # Issue #846: a bad `Regexp.new("...")` raises a catchable
      # RegexpError. Pre-fix the static-table compile error fired
      # before main()'s setjmp scope and terminated the process.
      begin
        r = Regexp.new("[invalid")
        puts "no error raised"
      rescue => e
        puts "caught: " + e.class.to_s + ": " + e.message
      end
      puts "after rescue"

      # Valid pattern still compiles.
      r2 = Regexp.new("hello")
      puts "world hello".match?(r2)
    RUBY

    _(result).must_answer <<~'OUT'
      caught: RegexpError: premature end of char-class: /[invalid/
      after rescue
      true
    OUT
  end

  it "a RegexpError message echoes the pattern with its flag suffix" do
    result = zr(<<~'RUBY')
      def show(src, flags)
        Regexp.new(src, flags)
        puts "compiled"
      rescue RegexpError => e
        puts e.message
      end

      show('[z-a]', 0)
      show('[z-a]', Regexp::IGNORECASE)
      show('[z-a]', Regexp::EXTENDED)
      show('[z-a]', Regexp::MULTILINE)
      show('[z-a]', Regexp::IGNORECASE | Regexp::EXTENDED)
      show('[z-a]', Regexp::IGNORECASE | Regexp::MULTILINE)
      show('[z-a]', Regexp::EXTENDED | Regexp::MULTILINE)
      show('[z-a]', Regexp::IGNORECASE | Regexp::EXTENDED | Regexp::MULTILINE)

      show('(?i)[z-a]', 0)
      show('(?-i)[z-a]', Regexp::IGNORECASE)
      show('(?m)[z-a]', 0)
      show('(?-m)[z-a]', Regexp::MULTILINE)

      p Regexp.new('a', Regexp::IGNORECASE | Regexp::EXTENDED | Regexp::MULTILINE).inspect
      p Regexp.new('a', Regexp::MULTILINE).inspect
      p Regexp.new('a', 0).inspect

      show('(?<1>a)', Regexp::MULTILINE)
      show('[a-\d]', Regexp::IGNORECASE)
      show('\R', Regexp::EXTENDED)
    RUBY

    _(result).must_answer <<~'OUT'
      empty range in char class: /[z-a]/
      empty range in char class: /[z-a]/i
      empty range in char class: /[z-a]/x
      empty range in char class: /[z-a]/m
      empty range in char class: /[z-a]/ix
      empty range in char class: /[z-a]/mi
      empty range in char class: /[z-a]/mx
      empty range in char class: /[z-a]/mix
      empty range in char class: /(?i)[z-a]/
      empty range in char class: /(?-i)[z-a]/i
      empty range in char class: /(?m)[z-a]/
      empty range in char class: /(?-m)[z-a]/m
      "/a/mix"
      "/a/m"
      "/a/"
      invalid group name <1>: /(?<1>a)/m
      char-class value at end of range: /[a-\d]/i
      compiled
    OUT
  end

  it "Regexp.escape writes a control character as its letter form" do
    result = zr(<<~'RUBY')
      # Regexp.escape renders a control character as its LETTER form -- a backslash
      # and an 'n' -- where a backslash followed by the real newline came out.
      p(Regexp.escape("a\nb"))
      p(Regexp.escape("a\tb"))
      p(Regexp.quote("a\rb"))
      p(Regexp.escape("a b"))
      p(Regexp.escape("a.b"))
      p(Regexp.escape("a\fb"))
      p(Regexp.escape("a\vb"))
      p(Regexp.escape("a*b+c"))
      p("x" =~ Regexp.new(Regexp.escape("x")))
    RUBY

    _(result).must_answer <<~'OUT'
      "a\\nb"
      "a\\tb"
      "a\\rb"
      "a\\ b"
      "a\\.b"
      "a\\fb"
      "a\\vb"
      "a\\*b\\+c"
      0
    OUT
  end

  it "/ab/ and /ab/i hash apart, so they take two slots in a Hash" do
    result = zr(<<~'RUBY')
      # Regexp#hash covers the flags: /ab/ and /ab/i are not eql?, so they must not
      # collide as Hash keys (#3816).
      p(/ab/.hash == /ab/i.hash)
      p(/ab/.hash == /ab/.hash)
      p(/ab/.eql?(/ab/i))
      p(/ab/.eql?(/ab/))
      h = { /ab/ => 1 }
      h[/ab/i] = 2
      p h.size
      p h[/ab/]
      p h[/ab/i]
    RUBY

    _(result).must_answer <<~'OUT'
      false
      true
      false
      true
      2
      1
      2
    OUT
  end

  it "a pattern key is found by its source and flags, never by object identity" do
    result = zr(<<~'RUBY')
      # A Regexp is keyed by its SOURCE and flags, which is ruby's own
      # `Regexp#eql?`/`#hash` rule: `/a/` written twice is one Hash key, `/a/` and
      # `/a/i` are two. The key projection used to fall through to the object
      # pointer, so a Regexp key never matched and `#hash` disagreed between two
      # equal literals.

      h = { /re/ => "y", /re/i => "i", /re/m => "m", /other/ => "o" }
      p h[/re/], h[/re/i], h[/re/m], h[/other/], h[/nope/]
      p h.size
      p(/a/.hash == /a/.hash)
      p(/a/.hash == /a/i.hash)
      p(/a/.eql?(/a/))
      p Regexp.new("a").hash == /a/.hash
      p({ /x/ => 1 } == { /x/ => 1 })
      p [/a/, /a/, /b/].uniq
      p({ /a/ => 1 }.key?(/a/))
    RUBY

    _(result).must_answer <<~'OUT'
      "y"
      "i"
      "m"
      "o"
      nil
      4
      true
      false
      true
      true
      true
      [/a/, /b/]
      true
    OUT
  end

  it "Regexp.last_match(1) and (2) give the groups of the last =~" do
    result = zr(<<~'RUBY')
      "abc123" =~ /([a-z]+)(\d+)/
      p Regexp.last_match(1)
      p Regexp.last_match(2)
    RUBY

    _(result).must_answer <<~'OUT'
      "abc"
      "123"
    OUT
  end

  it "Regexp.last_match takes a variable index, and answers nil past the last group" do
    result = zr(<<~'RUBY')
      # Regexp.last_match(n) returns the n-th capture group of the most
      # recent match (n==0 is the whole match), or nil when the group is
      # out of range / didn't participate. Before, the call resolved to the
      # NoMethodError gate and emitted 0.

      "johndoe@example.com".match(/(\w+)@(\w+)/)
      puts Regexp.last_match(0)   # whole match
      puts Regexp.last_match(1)   # first group
      puts Regexp.last_match(2)   # second group

      # Variable index
      i = 1
      puts Regexp.last_match(i)

      # Out-of-range group -> nil
      p Regexp.last_match(7)

      # A group that didn't participate -> nil
      "abc".match(/(x)|(abc)/)
      p Regexp.last_match(1)
      puts Regexp.last_match(2)
    RUBY

    _(result).must_answer <<~'OUT'
      johndoe@example
      johndoe
      example
      johndoe
      nil
      nil
      abc
    OUT
  end

  it "a static literal compiles once per site, and an interpolated one is rebuilt every time" do
    result = zr(<<~'RUBY')
      # A static regexp literal is compiled once per SITE, not once per evaluation
      # and not once per pattern text.

      ids = []
      3.times { ids << /a+b/.object_id }
      p ids.uniq.size

      # Two literals written in two places are two objects, however identical.
      a = /a+b/
      b = /a+b/
      p a.equal?(b)
      p a == b
      p a.frozen?

      def in_a_method
        /same/
      end
      p in_a_method.equal?(in_a_method)

      # The cached object is the one that matches, and it keeps matching.
      r = nil
      2.times { r = /(\d+)-(\d+)/ }
      m = r.match("10-20")
      p [m[1], m[2]]
      p r.source
      p r.options

      # Flags ride with the site.
      p /x/i.match?("X")
      p /a b/x.match?("ab")
      p(/a.b/m.match?("a\nb"))
      p(/x/i.options)

      # An interpolated literal is rebuilt every time -- a fresh object, and it
      # tracks the interpolated value.
      outs = []
      %w[cat dog].each { |w| outs << /#{w}/.source }
      p outs
      x = "q"
      p(/#{x}/.equal?(/#{x}/))

      # A literal inside a block that closes over nothing still caches per site.
      seen = []
      2.times { seen << /loop/.object_id }
      p seen.uniq.size

      # Freezing is observable and cannot be undone.
      p(/frz/.frozen?)
      begin
        /frz/.instance_variable_set(:@x, 1)
      rescue FrozenError => e
        p e.class
      end
    RUBY

    _(result).must_answer <<~'OUT'
      1
      false
      true
      true
      true
      ["10", "20"]
      "(\\d+)-(\\d+)"
      0
      true
      true
      true
      1
      ["cat", "dog"]
      false
      1
      true
      FrozenError
    OUT
  end

  it "an if/else whose arms both build a pattern unifies to one the match can read" do
    result = zr(<<~'RUBY')
      # An if/else expression whose branches both build a Regexp now
      # unifies to the new `regexp` type (mrb_regexp_pattern *) instead
      # of collapsing to int. Before this fix Regexp.new(...) was
      # untyped (default int fallback), the if/else result was int, and
      # the resulting `pattern.match?(...)` call had no statically
      # resolvable pattern to thread through — the codegen warned
      # "cannot resolve call to 'match?' on int (emitting 0)" and the
      # binary always reported no match. Issue #609.

      def check(use_a)
        pattern = if use_a
                    Regexp.new("aaa")
                  else
                    Regexp.new("bbb")
                  end
        puts pattern.match?("xaaay") ? "match" : "no match"
      end

      check(true)    # match    (uses /aaa/)
      check(false)   # no match (uses /bbb/, body has no "bbb")

      # Dynamic-source arm: each Regexp.new(<expr>) goes through the
      # per-call-site sp_re_dyn_<i> cache, but the regexp-typed local
      # still holds the resulting pointer.
      def check_dyn(prefix, body)
        pattern = if prefix == "x"
                    Regexp.new(prefix + "aaa")
                  else
                    Regexp.new(prefix + "bbb")
                  end
        puts pattern.match?(body) ? "dyn-match" : "dyn-no-match"
      end

      check_dyn("x", "xaaa-yes")     # dyn-match
      check_dyn("y", "ybbb-yes")     # dyn-match
      check_dyn("x", "nope")         # dyn-no-match
    RUBY

    _(result).must_answer <<~'OUT'
      match
      no match
      dyn-match
      dyn-match
      dyn-no-match
    OUT
  end

  it "#=== reads a String subclass by its own characters, never through to_s" do
    result = zr(<<~'RUBY')
      # `Regexp#===` against an instance of a String SUBCLASS.
      #
      # CRuby's `rb_reg_eqq` takes any String, and a subclass instance is one. zr
      # matched on the String representation alone, so a subclass reached the
      # "not a string" arm and answered false -- while `match?`, `=~` and `String#=~`
      # on the very same object all answered true.
      #
      # bcrypt is where it showed: `BCrypt::Password` is a String subclass, and its
      # `valid_hash?` is a bare `/.../ === h`, so every hash the gem had just
      # produced was rejected as invalid.

      class Tag < String; end
      class Quiet < String
        def to_s = "not this"
      end

      tag = Tag.new("abc-123")
      re = /\A[a-z]+-\d+\z/

      puts "is_a String        : #{tag.is_a?(String)}"
      puts "regexp ===         : #{(re === tag).inspect}"
      puts "regexp === to_s    : #{(re === tag.to_s).inspect}"
      puts "regexp match?      : #{re.match?(tag).inspect}"
      puts "regexp =~          : #{(re =~ tag).inspect}"
      puts "string =~          : #{(tag =~ re).inspect}"
      puts "no match           : #{(/\Azzz/ === tag).inspect}"

      # `===` reads the string itself, never `to_s` -- a subclass that overrides
      # `to_s` still matches on its own characters.
      quiet = Quiet.new("abc-123")
      puts "ignores to_s       : #{(re === quiet).inspect}"

      # `case` takes the same path.
      answer = case tag
               when /\A\d/ then "digits"
               when re then "tag"
               else "none"
               end
      puts "case when          : #{answer}"

      # A match sets `$~` for a subclass the way it does for a String.
      re === tag
      puts "last match         : #{Regexp.last_match(0).inspect}"

      # Everything that is NOT string-like still answers false and clears `$~`.
      puts "against an Integer : #{(re === 42).inspect}"
      puts "cleared            : #{Regexp.last_match.inspect}"
      puts "against a Symbol   : #{(/\Aab/ === :abc).inspect}"
    RUBY

    _(result).must_answer <<~'OUT'
      is_a String        : true
      regexp ===         : true
      regexp === to_s    : true
      regexp match?      : true
      regexp =~          : 0
      string =~          : 0
      no match           : false
      ignores to_s       : true
      case when          : tag
      last match         : "abc-123"
      against an Integer : false
      cleared            : nil
      against a Symbol   : true
    OUT
  end

  it "Regexp.new with a literal argument matches like a literal, and an interpolated one tracks its value" do
    result = zr(<<~'RUBY')
      # `Regexp.new("literal")` / `Regexp.compile("literal")` with a
      # string-literal argument folds into the same static pattern table
      # as a `/literal/` regex literal. The LV/const holding the value
      # is a placeholder; `.match?` / `.match` / `=~` resolve at the call
      # site through `regex_pat_c_expr`, dispatching to `sp_re_pat_<i>`.
      # Without this, the LV was typed `obj_Regexp` and codegen emitted
      # `sp_Regexp *lv_x = NULL;` which doesn't compile (no such type).

      # Direct call on the constructor expression.
      puts Regexp.new("foo").match?("foobar")   # true
      puts Regexp.new("xyz").match?("foobar")   # false

      # Local variable bound to a Regexp.new result.
      pat = Regexp.new("\\d+")
      puts pat.match?("hello 42")                # true
      puts pat =~ "abc 123"                      # 4

      # Compile alias.
      pat2 = Regexp.compile("foo")
      puts pat2.match?("foobar")                 # true

      # Constant bound to a Regexp.new result.
      RE = Regexp.new("foo")
      puts RE.match?("foobar")                   # true
      puts "abc foo def" =~ RE                   # 4

      # Dynamic-arg form: the argument is built at runtime via interpolation.
      # scan_features registers the CallNode with the per-call-site
      # `sp_re_dyn_<idx>` cache; at the read site `regex_pat_c_expr`
      # re-evaluates the arg string and the cache returns the compiled
      # pattern (recompile only on key change).
      tag = "div"
      puts Regexp.new("<#{tag}").match?("<div>")  # true
      puts Regexp.new("<#{tag}").match?("<span>") # false

      # LV bound to a dyn Regexp.new -- read site re-emits the dyn-cache
      # call, so the cache lookup uses the LV's free variables (here `tag`)
      # in scope at the read site.
      pat_dyn = Regexp.new("<#{tag}>")
      puts pat_dyn.match?("<div>")                # true
      puts pat_dyn =~ "before <div> after"        # 7

      # Dyn arg from method parameters -- the common idiom for an
      # assert_select-style helper.
      def find_tag(body, tag)
        re = Regexp.new("<#{tag}[^>]*>")
        body =~ re
      end
      puts find_tag("foo <span class=\"y\"> bar", "span") # 4

      # Regexp.escape neutralizes regex metachars so the resulting
      # string matches the original bytes literally inside `Regexp.new`.
      puts Regexp.escape("foo+bar")              # foo\+bar
      puts Regexp.escape("a.b*c")                # a\.b\*c
      content = "foo.bar"
      literal_pat = Regexp.new(Regexp.escape(content))
      puts literal_pat.match?("foo.bar")         # true
      puts literal_pat.match?("fooXbar")         # false (the . is now literal)

      # `=~` returns Integer|nil matching CRuby (not -1 for no-match).
      puts ("abc" =~ /b/).inspect                # 1
      puts ("abc" =~ /xyz/).inspect              # nil
      puts ("abc" =~ /xyz/).nil?                 # true
      puts ("abc" =~ /b/).nil?                   # false

      # $~ / $& / $` / $' -- regex match globals. $~ is a real MatchData
      # (its to_s is the whole match, so `puts $~` prints like $&).
      "hello world" =~ /(o w)/
      puts $~                                    # o w
      puts $&                                    # o w
      puts $`                                    # hell
      puts $'                                    # orld
    RUBY

    _(result).must_answer <<~'OUT'
      true
      false
      true
      4
      true
      true
      4
      true
      false
      true
      7
      4
      foo\+bar
      a\.b\*c
      true
      false
      1
      nil
      true
      false
      o w
      o w
      hell
      orld
    OUT
  end

  it "an unknown character property raises RegexpError on one line" do
    result = zr(<<~'RUBY')
      # An unknown character property raises RegexpError with ruby's one-line
      # message ("invalid character property name {Nope}: /\p{Nope}/"); zr
      # leaks the regex engine's own multi-line rendering. The unclosed-paren
      # and bad-quantifier messages already match. (Found by the 2026-08-24
      # probe sweep.)
      begin
        Regexp.new("\\p{Nope}")
      rescue RegexpError => e
        puts e.message
      end
    RUBY

    _(result).must_answer "invalid character property name {Nope}: /\\p{Nope}/\n"
  end

  it "casefold?, options, try_convert, union, timeout and ~ answer the reflection surface" do
    result = zr(<<~'RUBY')
      # Regexp reflection/class-method surface
      # #2492 casefold?, #2493 option constants, #2494 last_match, #2495 try_convert,
      # #2496 options, #2497 ~, #2498/#2527 timeout, #2508/#2509 union, #2528 new(re)
      p(/abc/i.casefold?)
      p(/abc/.casefold?)
      p(Regexp::IGNORECASE)
      p(Regexp::EXTENDED)
      p(Regexp::MULTILINE)
      p(/abc/.options)
      p(/abc/i.options)
      p(/abc/m.options)
      "abc" =~ /b/
      p(Regexp.last_match)
      p(Regexp.last_match(0))
      p(Regexp.try_convert(/x/))
      p(Regexp.try_convert("x"))
      p(Regexp.new("ab").options)
      p(/re/.timeout)
      p(Regexp.timeout)
      r = Regexp.new(/ab/i)
      p(r.source)
      p(r.casefold?)
      arr = [/foo/, /bar/]
      p(Regexp.union(arr))
      p(Regexp.union(/foo/i, /bar/).match?("FOO"))
      $_ = "hello world"
      p(~/world/)
      p(~/xyz/)
    RUBY

    _(result).must_answer <<~'OUT'
      true
      false
      1
      2
      4
      0
      1
      4
      #<MatchData "b">
      "b"
      /x/
      nil
      0
      nil
      nil
      "ab"
      true
      /(?-mix:foo)|(?-mix:bar)/
      true
      6
      nil
    OUT
  end

  it "String#split by a pattern places the captures, the empty fields and the limit the way ruby does" do
    result = zr(<<~'RUBY')
      # spinel-side String#split(regexp[, limit]) compatibility, mirroring CRuby and
      # upstream mruby-regexp string_regexp.rb#split (62a55cefe split compat,
      # b61e44b35 limit). Fixes: zero-width matches split into characters instead of
      # emitting empty fields, trailing empty fields are stripped under the default
      # limit (kept under a negative limit), an empty subject is always [], unmatched
      # optional capture groups are omitted, and a positive limit caps the field
      # count with the remainder as the last field.

      # zero-width / empty pattern
      p("abc".split(//))               # ["a", "b", "c"]
      p("abc".split(//, -1))           # ["a", "b", "c", ""]
      p("abc".split(//, 2))            # ["a", "bc"]
      p("héllo".split(//))             # ["h", "é", "l", "l", "o"]
      p("hello".split(/l/))            # ["he", "", "o"]

      # trailing empties: stripped by default, kept by negative limit
      p("a1b2c3".split(/(\d)/))        # ["a", "1", "b", "2", "c", "3"]
      p("a1b2c3".split(/(\d)/, -1))    # ["a", "1", "b", "2", "c", "3", ""]
      p("a,b,,".split(/,/))            # ["a", "b"]
      p("a,b,,".split(/,/, -1))        # ["a", "b", "", ""]

      # positive limit caps fields; captures still spliced
      p("a1b2c3".split(/(\d)/, 2))     # ["a", "1", "b2c3"]
      p("1-2-3".split(/-/, 2))         # ["1", "2-3"]

      # empty subject, no match, leading empty, unmatched optional group
      p("".split(/,/))                 # []
      p("".split(//))                  # []
      p("abc".split(/x/))              # ["abc"]
      p("1a2b".split(/(\d)/))          # ["", "1", "a", "2", "b"]
      p("ab".split(/(x)?/))            # ["a", "b"]
    RUBY

    _(result).must_answer <<~'OUT'
      ["a", "b", "c"]
      ["a", "b", "c", ""]
      ["a", "bc"]
      ["h", "é", "l", "l", "o"]
      ["he", "", "o"]
      ["a", "1", "b", "2", "c", "3"]
      ["a", "1", "b", "2", "c", "3", ""]
      ["a", "b"]
      ["a", "b", "", ""]
      ["a", "1", "b2c3"]
      ["1", "2-3"]
      []
      []
      ["abc"]
      ["", "1", "a", "2", "b"]
      ["a", "b"]
    OUT
  end

  it "a pattern interpolates into a string as its (?flags:source) form" do
    result = zr(<<~'RUBY')
      # A Regexp interpolates into a string as its to_s ("(?-mix:abc)" form),
      # both as a literal and through a variable.
      r = /abc/x
      p "v: #{r}"
      p "w: #{/abc/}"
      puts "x: #{/a.c/im}"
    RUBY

    _(result).must_answer <<~'OUT'
      "v: (?x-mi:abc)"
      "w: (?-mix:abc)"
      x: (?mi-x:a.c)
    OUT
  end

  it "split named backref rindex and match position" do
    result = zr(<<~'RUBY')
      # Empty-pattern split drops the leading zero-width field; \k<name> expands
      # in a replacement (unknown name -> IndexError); rindex/rpartition find the
      # rightmost anchored match start; match? honors a start position.

      p "abc".split(//)
      p "abc".split(//, -1)
      puts "foobar".gsub(/(?<x>o+)/, "[\\k<x>]")
      r = (begin; "x".gsub(/(?<a>x)/, "\\k<y>"); rescue => e; e.class; end)
      p r
      p "hello123world".rindex(/\d+/)
      p "hello123world".rpartition(/\d+/)
      p(/hello/.match?("hello world", 6))
      p(/world/.match?("hello world", 6))
    RUBY

    _(result).must_answer <<~'OUT'
      ["a", "b", "c"]
      ["a", "b", "c", ""]
      f[oo]bar
      IndexError
      7
      ["hello12", "3", "world"]
      false
      true
    OUT
  end

  it "split with no match returns the whole string unsplit" do
    result = zr(<<~'RUBY')
      # The empty-haystack-returns-an-empty-array case is exercised elsewhere
      # instead -- `puts`-ing it here would conflate this phase's own
      # behavior with a separate, pre-existing, unrelated gap:
      # `Kernel#puts` on an EMPTY `Array` currently prints a blank line
      # (real Ruby prints nothing at all for `puts []`) -- confirmed via a
      # plain, regex-free `puts []; puts "x"` repro, so not something this
      # phase introduces or should fix as a side effect. `Array#length`
      # doesn't sidestep this cleanly either: `split`'s result stays a
      # generic type and hits the same "no static-array fast path"
      # limitation.

      puts "abc".split(/x/)
    RUBY

    _(result).must_answer "abc\n"
  end

  it "string partition regex and puts" do
    result = zr(<<~'RUBY')
      # Issue #854: String#partition with regex used to SEGV (the
      # string-only path passed the regex pattern pointer to strstr);
      # `puts <tuple>` with a partition result printed the struct
      # pointer as an integer instead of splatting elements.
      puts "hello world".partition(" ")
      puts "hello world".partition(/o/).inspect
      puts "hello,world".partition(",").inspect
      puts "no-sep".partition(",").inspect
    RUBY

    _(result).must_answer <<~'OUT'
      hello
       
      world
      ["hell", "o", " world"]
      ["hello", ",", "world"]
      ["no-sep", "", ""]
    OUT
  end

  it "string rpartition regex" do
    result = zr(<<~'RUBY')
      # Issue #1226: String#rpartition with a regex used to SEGV — rpartition
      # had no regex branch, so the pattern compiled to a NULL pointer that
      # was passed to strlen/strstr. The regex form must locate the *last*
      # match by start position: \d+ in "hello123world" matches at 5/6/7, so
      # the rightmost is the single "3" (not "123").
      puts "hello123world".rpartition(/\d+/).inspect
      puts "foo1bar2baz".rpartition(/\d/).inspect
      puts "no digits here".rpartition(/\d+/).inspect
      puts "a.b.c".rpartition(".").inspect
      puts "abc".rpartition("x").inspect
    RUBY

    _(result).must_answer <<~'OUT'
      ["hello12", "3", "world"]
      ["foo1bar", "2", "baz"]
      ["", "", "no digits here"]
      ["a.b", ".", "c"]
      ["", "", "abc"]
    OUT
  end

  it "thread regexp shared pattern" do
    result = zr(<<~'RUBY')
      # The pike VM's scratch state -- the visited array and the two thread lists --
      # is cached on the compiled PATTERN to avoid a malloc per match, behind a
      # re-entrancy flag. A pattern is shared by every thread matching against it, so
      # two threads both read the flag as clear, both took the same scratch arrays,
      # and corrupted each other's match: scan came back fragmented or short, gsub and
      # match diverged the same way (#4082). Claiming the cache atomically sends the
      # loser down the malloc path that already existed for re-entrancy.
      TEXT = "the quick brown fox jumps over the lazy dog"
      E_SCAN  = TEXT.scan(/[a-z]+/)
      E_GSUB  = TEXT.gsub(/[aeiou]/, "-")
      E_MATCH = TEXT.match(/(\w+) (\w+)/)[2]
      E_SUB   = TEXT.sub(/quick/, "slow")
      E_SPLIT = TEXT.split(/\s+/).length

      threads = 4.times.map do
        Thread.new do
          bad = 0
          300.times do
            bad += 1 if TEXT.scan(/[a-z]+/) != E_SCAN
            bad += 1 if TEXT.gsub(/[aeiou]/, "-") != E_GSUB
            bad += 1 if TEXT.match(/(\w+) (\w+)/)[2] != E_MATCH
            bad += 1 if TEXT.sub(/quick/, "slow") != E_SUB
            bad += 1 if TEXT.split(/\s+/).length != E_SPLIT
            bad += 1 unless TEXT =~ /brown/
          end
          bad
        end
      end

      p threads.map(&:value).sum
      p E_SCAN.length
      p E_GSUB
    RUBY

    _(result).must_answer <<~'OUT'
      0
      9
      "th- q--ck br-wn f-x j-mps -v-r th- l-zy d-g"
    OUT
  end

  it "value position misc" do
    result = zr(<<~'RUBY')
      # Value-position forms: a.v ||= / &&= evaluates to the attribute's value
      # (nullable-int slots key on the nil sentinel); `def` evaluates to :name;
      # a dynamic regexp compiles in any value position.
      class A
        def initialize
          @v = nil
          @w = [1]
        end
        def set
          @v = @w[5]
        end
        attr_accessor :v
      end
      a = A.new
      a.set
      x = (a.v ||= 5)
      p x
      p a.v
      y = (a.v &&= 9)
      p y
      p a.v
      p(def foo; end)
      xx = "b"
      r = /a#{xx}c/
      p("abc" =~ r)
      p("zzz" =~ r)
    RUBY

    _(result).must_answer <<~'OUT'
      5
      5
      9
      9
      :foo
      0
      nil
    OUT
  end
end
