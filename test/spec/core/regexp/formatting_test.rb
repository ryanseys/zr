# frozen_string_literal: true

require "spec_helper"

describe "Regexp: formatting and inspection" do
  it "bare property escape warns" do
    result = ze0(<<~'RUBY')
      def t(label)
        r = begin
          yield.inspect
        rescue => e
          e.class.to_s
        end
        puts label + " | " + r
      end

      t("bs-K")   { Regexp.new("a\\Kb") =~ "ab" }
      t("bare-p") { Regexp.new("\\p").match("p")[0] }
      t("pL")     { Regexp.new("\\pL").match("pL")[0] }
    RUBY

    _(result).must_answer <<~'OUT', stderr: "core/regexp/formatting_test.rb:11: warning: invalid Unicode Property \\p: /\\p/\ncore/regexp/formatting_test.rb:12: warning: invalid Unicode Property \\p: /\\pL/\n"
      bs-K | 0
      bare-p | "p"
      pL | "pL"
    OUT
  end

  it "group name holds any character" do
    result = ze0(<<~'RUBY')
      def t(label)
        r = begin
          yield.inspect
        rescue => e
          e.class.to_s
        end
        puts label + " | " + r
      end

      t("paren-name-def") { Regexp.new("(?<)>x)").match("x")[0] }
      t("paren-name-ref") { Regexp.new("(?<)>x)\\k<)>").match("xx")[0] }
    RUBY

    _(result).must_answer <<~'OUT'
      paren-name-def | "x"
      paren-name-ref | "xx"
    OUT
  end

  it "i1009" do
    result = ze0(<<~'RUBY')
      s = "a\e[31mred\e[0mb"
      puts s.gsub(/\033\[[0-9;]*[A-Za-z]/, "")

      t = "x\033y"
      puts (t =~ /\033/).inspect
      puts t.match?(/\033/)

      u = "p\x1bq"
      puts (u =~ /\x1b/).inspect
    RUBY

    _(result).must_answer <<~'OUT'
      aredb
      1
      true
      1
    OUT
  end

  it "i974" do
    result = ze0(<<~'RUBY')
      m = /(\w+)(\s+)(\w+)/.match("hello world")
      puts m.offset(0).inspect
      puts m.offset(1).inspect
      puts m.offset(3).inspect
      puts m.begin(1)
      puts m.end(1)
      puts m.begin(3)
      puts m.end(3)
      puts m[0]
      puts m[1]
      puts m[3]
      puts m.pre_match.inspect
      puts m.post_match.inspect
      puts m.captures.inspect
      puts m.to_a.inspect

      m2 = "xx-yy".match(/(\w+)-(\w+)/)
      puts m2.begin(2)
      puts m2.end(2)
      puts m2.pre_match.inspect
      puts m2.post_match.inspect

      puts "abc".match(/z/).nil?
    RUBY

    _(result).must_answer <<~'OUT'
      [0, 11]
      [0, 5]
      [6, 11]
      0
      5
      6
      11
      hello world
      hello
      world
      ""
      ""
      ["hello", " ", "world"]
      ["hello world", "hello", " ", "world"]
      3
      5
      ""
      ""
      true
    OUT
  end

  it "inspect to s and errors show the pattern as ruby does" do
    result = ze0(<<~'RUBY')
      # Regexp#inspect, #to_s and a RegexpError's message show the pattern as
      # rb_reg_expr_str writes it: a bare `/` escaped, a control byte as \xHH,
      # a character past ASCII as \uXXXX when the reader's encoding is not the
      # pattern's, and to_s folds a whole `(?opts:...)` group into its options.

      p Regexp.new("a/b\t\x01").inspect
      p Regexp.new("日本/").inspect
      p Regexp.new("\\/").inspect
      p Regexp.new("\xff/".b).inspect
      p Regexp.new("é", Regexp::IGNORECASE | Regexp::EXTENDED).inspect
      p /a/n.inspect

      p Regexp.new("(?i:ab)").to_s
      p Regexp.new("(?i-mx:ab)").to_s
      p Regexp.new("(?m)a").to_s
      p Regexp.new("(?i:a)b").to_s
      p Regexp.new("(?x)(?i:a").then { :unreachable } rescue p $!.message
      p Regexp.new("a/\n").to_s
      p Regexp.new("é/").to_s.encoding

      ["(日", "(é/\x01", "[b-a]", "(?<a\0b>x)", "\\k<nope>", "\\u{110000}", "\\xe3\\x81"].each do |pattern|
        Regexp.new(pattern)
      rescue RegexpError => e
        p [e.message, e.message.encoding]
      end

      [["(\xff".b, 0], ["(\xe9".dup.force_encoding("ISO-8859-1"), 0], ["(", Regexp::MULTILINE | Regexp::IGNORECASE | Regexp::EXTENDED]].each do |pattern, options|
        Regexp.new(pattern, options)
      rescue RegexpError => e
        p [e.message.b, e.message.encoding]
      end

    RUBY

    _(result).must_answer <<~'OUT'
      "/a\\/b\t\\x01/"
      "/\\u65E5\\u672C\\//"
      "/\\//"
      "/\\xFF\\//"
      "/é/ix"
      "/a/n"
      "(?i-mx:ab)"
      "(?i-mx:ab)"
      "(?m-ix:a)"
      "(?-mix:(?i:a)b)"
      "end pattern with unmatched parenthesis: /(?x)(?i:a/"
      "(?-mix:a\\/\n)"
      #<Encoding:UTF-8>
      ["end pattern with unmatched parenthesis: /(日/", #<Encoding:UTF-8>]
      ["end pattern with unmatched parenthesis: /(\\u00E9\\/\\x01/", #<Encoding:UTF-8>]
      ["empty range in char class: /[b-a]/", #<Encoding:UTF-8>]
      ["undefined name <nope> reference: /\\k<nope>/", #<Encoding:UTF-8>]
      ["invalid Unicode range: /\\u{110000}/", #<Encoding:UTF-8>]
      ["too short escaped multibyte character: /\\xe3\\x81/", #<Encoding:UTF-8>]
      ["end pattern with unmatched parenthesis: /(\\xFF/", #<Encoding:BINARY (ASCII-8BIT)>]
      ["end pattern with unmatched parenthesis: /(\\xE9/", #<Encoding:ISO-8859-1>]
      ["end pattern with unmatched parenthesis: /(/mix", #<Encoding:UTF-8>]
    OUT
  end

  it "matchdata in container" do
    result = ze0(<<~'RUBY')
      a001 = ["aa".match(/a/), "bb".match(/b/)]
      p a001[0][0]
      p a001.map { |m001| m001[0] }
      h001 = { x: "zz".match(/z/) }
      p h001[:x][0]
      m = "hello world".match(/(\w+)\s(\w+)/)
      arr = [m]
      p arr[0][1]
      p arr[0][2]
      p arr[0].class.to_s
      p arr[0].to_s
      p arr.first.inspect
    RUBY

    _(result).must_answer <<~'OUT'
      "a"
      ["a", "b"]
      "z"
      "hello"
      "world"
      "MatchData"
      "hello world"
      "#<MatchData \"hello world\" 1:\"hello\" 2:\"world\">"
    OUT
  end

  it "matchdata inspect shows groups and regexp string methods" do
    result = ze0(<<~'RUBY')
      p "hello".match(/l(l)o/)
      p "2024-01".match(/(?<y>\d+)-(?<m>\d+)/)
      p "hello".start_with?(/he/)
      p "hello".start_with?(/ell/)
      p "hello".byteindex(/l+/)
      p "hello".byterindex(/l+/)
    RUBY

    _(result).must_answer <<~'OUT'
      #<MatchData "llo" 1:"l">
      #<MatchData "2024-01" y:"2024" m:"01">
      true
      false
      2
      3
    OUT
  end

  it "matchdata methods" do
    result = ze0(<<~'RUBY')
      # MatchData reflection/pattern methods (#2499, #2500, #2501, #2503, #2530, #2532)
      md = "abc".match(/(a)(b)(c)/)
      p md.inspect
      p md.regexp
      p md.match(1)
      p md.match_length(2)
      p md.deconstruct
      p md[1..2]
      p md[1...3]
      p md[0..-1]
      md2 = "abc".match(/(?<x>a)(?<y>b)/)
      p md2.named_captures(symbolize_names: true)
      p md2.deconstruct_keys(nil)
      p md2.named_captures
      p md2.inspect
    RUBY

    _(result).must_answer <<~'OUT'
      "#<MatchData \"abc\" 1:\"a\" 2:\"b\" 3:\"c\">"
      /(a)(b)(c)/
      "a"
      1
      ["a", "b", "c"]
      ["a", "b"]
      ["a", "b"]
      ["abc", "a", "b", "c"]
      {x: "a", y: "b"}
      {x: "a", y: "b"}
      {"x" => "a", "y" => "b"}
      "#<MatchData \"ab\" x:\"a\" y:\"b\">"
    OUT
  end

  it "matchdata value varargs symstr" do
    result = ze0(<<~'RUBY')
      # MatchData as a first-class value (p/inspect/.class); String#index with a
      # variable Regexp and String#[] with a variable Range; Symbol's string-
      # flavored methods (regex match/slice, comparisons) through the name text.
      p("hello".match(/xyz/))
      p("hello".match(/l/).class)
      m = "hello".match(/l(l)o/)
      p m[0]
      p m[1]
      p m
      n = "2024-01".match(/(?<y>\d+)-(?<m>\d+)/)
      p n
      a = "abcabc"; r = /b/; p(a.index(r))
      s = "hello"; rg = 1..3; p(s[rg])
      p(:hello.match(/l(l)o/)[1])
      p(:hello =~ /llo/)
      p(:hello.start_with?(/he/))
      p(:hello[/l+/])
      p(:hello.between?(:aaa, :zzz))
      p(:abc <=> :abd)
      p(:a < :b)
    RUBY

    _(result).must_answer <<~'OUT'
      nil
      MatchData
      "llo"
      "l"
      #<MatchData "llo" 1:"l">
      #<MatchData "2024-01" y:"2024" m:"01">
      1
      "ell"
      "l"
      2
      true
      "ll"
      true
      -1
      true
    OUT
  end

  it "named captures disable numbered groups" do
    result = ze0(<<~'RUBY')
      # When a regexp contains a named group, ruby stops plain `(...)` groups from
      # capturing at all (onig's dont-capture-group behavior): group 1 of
      # /(\d+)(?<tail>\w+)/ is `tail`, and `captures` holds only the named one. zeo
      # compiles the pattern with plain groups still capturing, so md[1], captures,
      # and begin(1) all answer for the wrong group.
      md = "foo123bar".match(/(\d+)(?<tail>\w+)/)
      puts md[0].inspect
      puts md[1].inspect
      puts md[:tail].inspect
      puts md.names.inspect
      puts md.captures.inspect
      puts md.named_captures.inspect
      puts md.begin(1)

      both_plain = "foo123bar".match(/(\d+)(\w+)/)
      puts both_plain.captures.inspect
    RUBY

    _(result).must_answer <<~'OUT'
      "123bar"
      "bar"
      "bar"
      ["tail"]
      ["bar"]
      {"tail" => "bar"}
      6
      ["123", "bar"]
    OUT
  end

  it "regex backref oob nil" do
    result = ze0(<<~'RUBY')
      # Issue #848: out-of-range / unmatched backreference ($3 when
      # the regex has 2 captures) returns nil, not "". Codegen now
      # returns sp_re_captures[N] directly (NULL for unset) so
      # downstream NULL-safe paths render it as nil.
      "ab" =~ /(a)(b)/
      puts "$1=#{$1.inspect}"
      puts "$2=#{$2.inspect}"
      puts "$3=#{$3.inspect}"
      puts "$4=#{$4.inspect}"

      # No match clears all captures.
      "hello" =~ /xyz/
      puts "$1=#{$1.inspect}"
    RUBY

    _(result).must_answer <<~'OUT'
      $1="a"
      $2="b"
      $3=nil
      $4=nil
      $1=nil
    OUT
  end

  it "regex unanchored class seq" do
    result = ze0(<<~'RUBY')
      # Issue #909. Unanchored class-sequence patterns (e.g. /\w\w/, /(.)(.)/ )
      # used to skip position 0 because a later-starting Pike VM thread
      # overwrote the earlier-starting match's captures. Now the MATCH
      # update picks the best match per Ruby semantics: earliest start
      # wins, longest-at-same-start wins.
      puts ("abc" =~ /\w\w/).inspect
      puts ("abc def" =~ /\w\w/).inspect
      puts "abc def".scan(/(.)(.)/).inspect

      # Greedy still works.
      puts ("aaabbb" =~ /a+/).inspect
      puts "aaabbb".scan(/a+/).inspect
      puts "aaa-bbb-ccc".scan(/\w+/).inspect
    RUBY

    _(result).must_answer <<~'OUT'
      0
      0
      [["a", "b"], ["c", " "], ["d", "e"]]
      0
      ["aaa"]
      ["aaa", "bbb", "ccc"]
    OUT
  end

  it "regexp capture ceiling" do
    result = ze0(<<~'RUBY')
      # A pattern wider than the match registers hold is refused rather than
      # truncated. It used to compile and lose everything past the thirty-first
      # group: `m.size` answered 32 where CRuby answers 41, and m[32] onward were
      # nil, with nothing said about it. The ceiling and the registers agree now.
      #
      # CRuby has no such ceiling, so the refusals below are a deliberate divergence
      # and this file does not read the same there; see docs/limitations.md. What is
      # NOT a divergence is everything up to the ceiling, and the point of refusing
      # is that a pattern past it no longer answers a question about a narrower one.
      def show(n)
        re = Regexp.new("(a)" * n)
        m = re.match("a" * n)
        puts "#{n}: size=#{m.size} last=#{m[n].inspect}"
      rescue RegexpError => e
        puts "#{n}: #{e.message[0, 40]}"
      end

      show(1)
      show(15)
      show(30)
      show(31)
      show(32)
      show(40)
      show(200)

      # a literal past the ceiling is refused when the program is compiled, not when
      # it runs, so there is nothing here to show for it; see `make re-lit-test`.

      # the ceiling counts capture groups, not groups: (?:...) is free
      big = "(?:a)" * 100 + "(a)"
      m = Regexp.new(big).match("a" * 101)
      p [m.size, m[1]]

      # and a named group counts the same way
      named = (1..31).map { |i| "(?<g#{i}>a)" }.join
      p Regexp.new(named).match("a" * 31).size
      begin
        Regexp.new((1..32).map { |i| "(?<h#{i}>a)" }.join)
        puts "accepted"
      rescue RegexpError => e
        puts e.message[0, 40]
      end
    RUBY

    _(result).must_answer <<~'OUT'
      1: size=2 last="a"
      15: size=16 last="a"
      30: size=31 last="a"
      31: size=32 last="a"
      32: size=33 last="a"
      40: size=41 last="a"
      200: size=201 last="a"
      [2, "a"]
      32
      accepted
    OUT
  end

  it "regexp class open bracket" do
    result = ze0(<<~'RUBY')
      # A '[' inside a character class never stands for itself in CRuby: it opens a
      # POSIX bracket, a collating element, an equivalence class, or a class nested
      # in this one. Only the bracket was read here and the rest taken as members, so
      # [[a][b]] compiled to a different pattern than the one written.
      # Ported from mruby-regexp cafc53ae4.
      def t(label)
        r = begin
          yield.inspect
        rescue => e
          e.class.to_s
        end
        puts label + " | " + r
      end

      t("nested")     { Regexp.new("[[a][b]]") =~ "a" }
      t("nested2")    { Regexp.new("[a[b]") =~ "a" }
      t("collating")  { Regexp.new("[[.a.]]") =~ "a" }
      t("equivalent") { Regexp.new("[[=a=]]") =~ "a" }

      # a bracket whose name does not close says so, where the class does close
      t("bracket-end"){ Regexp.new("[[:alpha]") =~ "a" }

      # and where the class does not close either, the older complaint stands
      t("no-close")   { Regexp.new("[[:alpha") =~ "a" }

      # the bracket itself is written with a backslash, in CRuby as well
      t("escaped")    { Regexp.new("[\\[]").match("[")[0] }
      t("escaped-b")  { Regexp.new("[a\\[b]").match("[")[0] }

      # a complete POSIX bracket still reads
      t("posix")      { Regexp.new("[[:alpha:]]").match("a")[0] }
      t("posix-neg")  { Regexp.new("[[:^alpha:]]").match("1")[0] }
      t("posix-mix")  { Regexp.new("[[:digit:]x]").match("x")[0] }
    RUBY

    _(result).must_answer <<~'OUT'
      nested | 0
      nested2 | RegexpError
      collating | 0
      equivalent | 0
      bracket-end | RegexpError
      no-close | RegexpError
      escaped | "["
      escaped-b | "["
      posix | "a"
      posix-neg | "1"
      posix-mix | "x"
    OUT
  end

  it "regexp group name validation" do
    result = ze0(<<~'RUBY')
      def t(label)
        r = begin
          yield.inspect
        rescue => e
          e.class.to_s
        end
        puts label + " | " + r
      end

      t("num-name")       { Regexp.new("(?<1>x)") =~ "x" }
      t("dash-lead-name") { Regexp.new("(?<-1>x)") =~ "x" }
      t("quote-num")      { Regexp.new("(?'1'x)") =~ "x" }

      t("paren-in-name")  { Regexp.new("(?<a)b>x)") =~ "x" }
      t("ref-bad-paren")  { Regexp.new("(?<a>x)\\k<a)b>") =~ "x" }

      t("dash-in-name")   { Regexp.new("(?<a-b>x)").match("x")[0] }
      t("space-in-name")  { Regexp.new("(?<a b>x)").match("x")[0] }

      t("ref-num")        { Regexp.new("(x)\\k<1>").match("xx")[0] }
      t("ref-rel")        { Regexp.new("(x)\\k<-1>").match("xx")[0] }

      t("names")          { Regexp.new("(?<w>a)(?<z>b)").names }
    RUBY

    _(result).must_answer <<~'OUT'
      num-name | RegexpError
      dash-lead-name | RegexpError
      quote-num | RegexpError
      paren-in-name | RegexpError
      ref-bad-paren | RegexpError
      dash-in-name | "x"
      space-in-name | "x"
      ref-num | "xx"
      ref-rel | "xx"
      names | ["w", "z"]
    OUT
  end

  it "regexp new options arg" do
    result = ze0(<<~'RUBY')
      # Regexp.new's second argument is an Integer of option bits, or nil/false for
      # none, or anything else truthy for IGNORECASE -- a choice CRuby makes from the
      # VALUE. Where the analyzer could not see the type statically the choice was
      # settled on the truthy arm, so an option that arrived as a block parameter, a
      # hash read or a method return answered /i whatever it held, 0 included.
      def show(label, re)
        puts "#{label}: #{re.options} #{re.inspect}"
      end

      show("literal", Regexp.new("a", 4))
      f = 2
      show("local", Regexp.new("a", f))
      [6].each { |x| show("block param", Regexp.new("a", x)) }
      [["a", 3]].each { |s, g| show("destructured", Regexp.new(s, g)) }
      h = { "k" => 5 }
      show("hash read", Regexp.new("a", h["k"]))
      show("hash miss", Regexp.new("a", h["nope"]))
      def opts; 1; end
      show("method ret", Regexp.new("a", opts))

      # zero must not read as truthy, by any route
      show("zero literal", Regexp.new("a", 0))
      [0].each { |z| show("zero via block", Regexp.new("a", z)) }
      [["a", 0]].each { |s, z| show("zero destructured", Regexp.new(s, z)) }

      # the arms CRuby keeps for a non-Integer
      show("nil", Regexp.new("a", nil))
      show("false", Regexp.new("a", false))
      show("true", Regexp.new("a", true))

      # and the flags reach the match, not just #options
      [["A", 1]].each { |s, g| p("a" =~ Regexp.new(s, g)) }
      [["A", 0]].each { |s, g| p("a" =~ Regexp.new(s, g)) }
      [["a b", 2]].each { |s, g| p("ab" =~ Regexp.new(s, g)) }
      [["a.b", 4]].each { |s, g| p("a\nb" =~ Regexp.new(s, g)) }
    RUBY

    _(result).must_answer <<~'OUT'
      literal: 4 /a/m
      local: 2 /a/x
      block param: 6 /a/mx
      destructured: 3 /a/ix
      hash read: 5 /a/mi
      hash miss: 0 /a/
      method ret: 1 /a/i
      zero literal: 0 /a/
      zero via block: 0 /a/
      zero destructured: 0 /a/
      nil: 0 /a/
      false: 0 /a/
      true: 1 /a/i
      0
      nil
      0
      0
    OUT
  end

  it "regexp new options string" do
    result = ze0(<<~'RUBY')
      def show(o)
        r = Regexp.new("a", o)
        puts "#{o.inspect} => #{r.options} #{r.inspect}"
      rescue ArgumentError => e
        puts "#{o.inspect} => ArgumentError: #{e.message}"
      end

      show("i")
      show("m")
      show("x")
      show("mix")
      show("xi")
      show("ii")
      show("")
      show("z")
      show("X")
      show("o")
      show("n")
      show("u")

      v = "m"
      show(v)
      ["x"].each { |s| show(s) }
      [["a", "im"]].each { |p, o| r = Regexp.new(p, o); puts "destructured => #{r.options} #{r.inspect}" }

      p("A" =~ Regexp.new("a", "i"))
      p("A" =~ Regexp.new("a", ""))
      p("ab" =~ Regexp.new("a b", "x"))
      p("a\nb" =~ Regexp.new("a.b", "m"))
    RUBY

    _(result).must_answer <<~'OUT'
      "i" => 1 /a/i
      "m" => 4 /a/m
      "x" => 2 /a/x
      "mix" => 7 /a/mix
      "xi" => 3 /a/ix
      "ii" => 1 /a/i
      "" => 0 /a/
      "z" => ArgumentError: unknown regexp option: z
      "X" => ArgumentError: unknown regexp option: X
      "o" => ArgumentError: unknown regexp option: o
      "n" => ArgumentError: unknown regexp option: n
      "u" => ArgumentError: unknown regexp option: u
      "m" => 4 /a/m
      "x" => 2 /a/x
      destructured => 5 /a/mi
      0
      nil
      0
      0
    OUT
  end

  it "regexp octal escape is not a backreference" do
    result = ze0(<<~'RUBY')
      # A Ruby octal escape `\033` is the ESC byte, not a group-0 backreference;
      # it must compile and match rather than raising "Invalid back reference".

      s = "a\e[31mred\e[0mb"
      puts s.gsub(/\033\[[0-9;]*[A-Za-z]/, "")
      puts ("x\033y" =~ /\033/).inspect
    RUBY

    _(result).must_answer <<~'OUT'
      aredb
      1
    OUT
  end

  it "regexp onig" do
    result = ze0(<<~'RUBY')
      # Ruby-specific regex semantics backed by the real Oniguruma engine.

      # `^`/`$` are line anchors, but a trailing newline does not open a new line,
      # so there is no phantom match after it.
      puts "a\nb\n".scan(/^/).size          # 2, not 3
      puts(/^$/.match?("a\n"))              # false

      # Inline `(?m:...)` is Ruby's DOTALL (`.` spans `\n`), and it is scoped to the
      # group -- `(?i-m:...)` turns the flag back off.
      puts(/(?m:a.c)/ =~ "a\nc")            # 0
      puts((/a.c/ =~ "a\nc").inspect)      # nil

      # The absence operator `(?~...)` matches any run that does NOT contain the
      # subpattern.
      puts(/\A(?~foo)\z/.match?("bar"))    # true
      puts(/\A(?~foo)\z/.match?("xfooy"))  # false

      # Alternation keeps each branch's capture in its own slot.
      p(/(a)|(b)|(c)/.match("c").captures) # [nil, nil, "c"]
    RUBY

    _(result).must_answer <<~'OUT'
      2
      false
      0
      nil
      true
      false
      [nil, nil, "c"]
    OUT
  end

  it "regexp render source variable" do
    result = ze0(<<~'RUBY')
      # Regexp values render: #source/#inspect/#to_s/#options work through a
      # variable (the literal-resolution arm read node attributes the variable
      # lacks), p/puts print a Regexp, and boxed Regexps render inside containers.
      a = /hello\d+/
      p a.source
      p a
      p a.inspect
      p a.to_s
      p(/x/.source)
      p [/a/, /b/]
      p(/abc/.inspect)
      p(/abc/.to_s)
      p /abc/
      puts /abc/
      b = /ca.e/im
      p b
      p b.to_s
      c1 = /pat/ix
      p c1.options
      p c1.source
    RUBY

    _(result).must_answer <<~'OUT'
      "hello\\d+"
      /hello\d+/
      "/hello\\d+/"
      "(?-mix:hello\\d+)"
      "x"
      [/a/, /b/]
      "/abc/"
      "(?-mix:abc)"
      /abc/
      (?-mix:abc)
      /ca.e/mi
      "(?mi-x:ca.e)"
      3
      "pat"
    OUT
  end

  it "regexp unsupported escapes" do
    result = ze0(<<~'RUBY')
      def t(label)
        r = begin
          yield.inspect
        rescue => e
          e.class.to_s
        end
        puts label + " | " + r
      end

      t("bs-R")      { Regexp.new("\\R") =~ "\n" }
      t("bs-X")      { Regexp.new("\\X") =~ "a" }

      t("bs-G")      { Regexp.new("\\Ga") =~ "a" }
      t("bs-G-mid")  { Regexp.new("a\\Gb") =~ "ab" }
      t("bs-g-name") { Regexp.new("(?<x>a|b)\\g<x>").match("ab")[0] }
      t("bs-g-quote"){ Regexp.new("(?<x>a|b)\\g'x'").match("ab")[0] }
      t("prop-p")    { Regexp.new("\\p{Alpha}") =~ "a" }
      t("prop-P")    { Regexp.new("\\P{Alpha}") =~ "1" }
      t("prop-unknown") { Regexp.new("\\p{Hiragana}") =~ "a" }

      t("bare-g")    { Regexp.new("\\g").match("g")[0] }

      t("class-R")   { Regexp.new("[\\R]").match("R")[0] }
      t("class-K")   { Regexp.new("[\\K]").match("K")[0] }

      t("class-p")     { Regexp.new("[\\p{Alpha}]") =~ "a" }
      t("class-P-neg") { Regexp.new("[^\\p{Word}\\- \\t]").match("a d_1") }
    RUBY

    _(result).must_answer <<~'OUT'
      bs-R | 0
      bs-X | 0
      bs-G | 0
      bs-G-mid | nil
      bs-g-name | "ab"
      bs-g-quote | "ab"
      prop-p | 0
      prop-P | 0
      prop-unknown | nil
      bare-g | "g"
      class-R | "R"
      class-K | "K"
      class-p | 0
      class-P-neg | nil
    OUT
  end

  it "string nul regexp" do
    result = ze0(<<~'RUBY')
      s = "a\0b\0c"
      def r(l); v = yield; puts "#{l}: #{v.inspect}"; end

      r("scan .")        { s.scan(/./m) }
      r("scan (.)")      { s.scan(/(.)/m) }
      r("scan NUL")      { s.scan(/\0/) }
      r("$~ capture")    { s =~ /a(.)b/m; $~[1] }
      r("$1")            { s =~ /a(.)b/m; $1 }
      r("post_match")    { s.match(/b/).post_match }
      r("pre_match")     { s.match(/b/).pre_match }
      r("gsub block")    { s.gsub(/./m) { |m| m.bytes.inspect } }
      r("split keep")    { s.split(/(\0)/) }
      r("slice re")      { s[/a(.)b/m, 1] }
      r("sub rep NUL")   { "ab".sub(/b/, "x\0y") }
      r("gsub rep NUL")  { "ab".gsub(/./, "\0") }
      r("gsub blk NUL")  { "ab".gsub(/./) { "\0" } }
      r("Regexp.new")    { s =~ Regexp.new("a\0b") }
      r("source")        { Regexp.new("a\0b").source.bytes }
      r("match at pos")  { s.match(/\0/, 2)[0].bytes }

      r("source bytes")  { Regexp.new("a\0b").source.bytes }
      r("to_s bytes")    { Regexp.new("a\0b").to_s.bytes }
      r("inspect bytes") { Regexp.new("a\0b").inspect.bytes }
      r("escape")        { Regexp.escape("a\0b").bytes }
      r("union 1")       { Regexp.union("a\0b").source.bytes }
      r("union 2")       { Regexp.union("a\0b", "z").source.bytes }
      r("union match")   { ("a\0b" =~ Regexp.union("a\0b", "z")) }
      r("to_s slash")    { Regexp.new("a/b").to_s }

      big = "\0" * 5 + "x" + "\0" * 5
      r("split pieces")  { big.split("x").map { |q| q.bytesize } }
      r("split mid")     { "\0x\0".split("x").map { |q| q.bytesize } }
      r("split plain")   { "ax b".split("x").map { |q| q.bytesize } }

      m = s.match(/a(.)b(.)c/m)
      r("to_a")          { m.to_a }
      r("captures")      { m.captures }
      r("values_at")     { m.values_at(1, 2) }
      r("named")         { s.match(/a(?<p>.)b/m).named_captures }
      r("begin/end")     { [m.begin(1), m.end(1)] }
    RUBY

    _(result).must_answer <<~'OUT'
      scan .: ["a", "\u0000", "b", "\u0000", "c"]
      scan (.): [["a"], ["\u0000"], ["b"], ["\u0000"], ["c"]]
      scan NUL: ["\u0000", "\u0000"]
      $~ capture: "\u0000"
      $1: "\u0000"
      post_match: "\u0000c"
      pre_match: "a\u0000"
      gsub block: "[97][0][98][0][99]"
      split keep: ["a", "\u0000", "b", "\u0000", "c"]
      slice re: "\u0000"
      sub rep NUL: "ax\u0000y"
      gsub rep NUL: "\u0000\u0000"
      gsub blk NUL: "\u0000\u0000"
      Regexp.new: 0
      source: [97, 0, 98]
      match at pos: [0]
      source bytes: [97, 0, 98]
      to_s bytes: [40, 63, 45, 109, 105, 120, 58, 97, 92, 120, 48, 48, 98, 41]
      inspect bytes: [47, 97, 92, 120, 48, 48, 98, 47]
      escape: [97, 0, 98]
      union 1: [97, 0, 98]
      union 2: [97, 0, 98, 124, 122]
      union match: 0
      to_s slash: "(?-mix:a\\/b)"
      split pieces: [5, 5]
      split mid: [1, 1]
      split plain: [1, 2]
      to_a: ["a\u0000b\u0000c", "\u0000", "\u0000"]
      captures: ["\u0000", "\u0000"]
      values_at: ["\u0000", "\u0000"]
      named: {"p" => "\u0000"}
      begin/end: [1, 2]
    OUT
  end
end
