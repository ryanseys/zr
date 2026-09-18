# frozen_string_literal: true

require "spec_helper"

describe "Regexp: searching and matching" do
  it "anchor takes a quantifier" do
    result = ze0(<<~'RUBY')
      p(/(?:(?!a))*b?/.match("b").to_a)
      p(/a(?:(?<=a))*b?/.match("ab").to_a)
    RUBY

    _(result).must_answer <<~'OUT'
      ["b"]
      ["ab"]
    OUT
  end

  it "array index and size error messages match cruby" do
    result = ze0(<<~'RUBY')
      # Array error messages that CRuby spells precisely: a too-small negative index
      # to `[]=` carries `; minimum: -N` (the number, so an empty array reads
      # `minimum: 0`, not `-0`), and `drop`/`take` name the method that was actually
      # called rather than always saying "take".

      def msg
        yield
      rescue => e
        puts "#{e.class}: #{e.message}"
      end

      msg { [1, 2, 3][-999] = 9 }
      msg { [][-1] = 9 }
      msg { [1, 2].drop(-1) }
      msg { [1, 2].take(-1) }
    RUBY

    _(result).must_answer <<~'OUT'
      IndexError: index -999 too small for array; minimum: -3
      IndexError: index -1 too small for array; minimum: 0
      ArgumentError: attempt to drop negative size
      ArgumentError: attempt to take negative size
    OUT
  end

  it "back ref" do
    result = ze0(<<~'RUBY')
      # BackReferenceReadNode -- `$&`, `$~`, `$'`, $`, `$+`.
      #
      # Special globals populated by regex matches. Spinel's regex engine
      # already populates sp_re_match* state for $1..$9 (NumberedReferenceReadNode);
      # this extends to the symbolic back-references.
      #
      #   $&  -- the entire matched substring
      #   $~  -- the MatchData object (aliased to $& in Spinel; no MatchData wrapper)
      #   $`  -- the substring before the match
      #   $'  -- the substring after the match
      #   $+  -- the contents of the last group matched

      "hello world" =~ /lo wo/
      puts $&     # lo wo
      puts $`     # hel
      puts $'     # rld

      # Re-match updates the state
      "abcdef" =~ /cd/
      puts $&     # cd
      puts $`     # ab
      puts $'     # ef

      # $+ -- last group matched. For a multi-group pattern, $+ holds the
      # highest-indexed group that successfully participated.
      "abc123" =~ /([a-z]+)(\d+)/
      puts $1     # abc
      puts $2     # 123
      puts $+     # 123

      # When the last optional group doesn't participate, $+ steps back to
      # the previous successful group.
      "abc" =~ /([a-z]+)(\d+)?/
      puts $1     # abc
      puts $+     # abc
    RUBY

    _(result).must_answer <<~'OUT'
      lo wo
      hel
      rld
      cd
      ab
      ef
      abc
      123
      123
      abc
      abc
    OUT
  end

  it "captured regexp cell scan" do
    result = ze0(<<~'RUBY')
      # A Regexp is not a GC object: it is a compiled program the regexp engine
      # mallocs, which sp_mark_rbval already excludes from sp_gc_mark. A closure cell
      # holding one missed that exclusion, so marking a captured Regexp read a GC
      # header one byte in front of the engine's allocation and the collector faulted
      # on whatever it found -- SIGBUS from sp_gc_mark_all, or a heap-buffer-overflow
      # under -fsanitize=address (#4063). The cell itself is GC-allocated and keeps
      # itself alive; the pattern it points at is never collected.
      WORDS = ["alpha", "gamma"]

      def lines_of(i)
        Array.new(20) { |j| "file #{i} line #{j} mentions alpha and beta" }
      end

      total = 0
      60.times do |i|
        matchers = WORDS.map do |text|
          re = Regexp.new("\\b#{text}\\b")
          ->(line) { !re.match(line).nil? }
        end
        matchers.push(->(line) { line.include?("beta") })
        lines_of(i).each { |line| matchers.each { |m| total += 1 if m.call(line) } }
      end
      p total

      # the captured pattern still matches after many collections, and reassigning
      # the captured cell is still visible to the closure
      pat = Regexp.new("z+")
      probe = ->(s) { pat.match(s).nil? ? "no" : "yes" }
      100.times { Array.new(20) { |k| "junk #{k}" } }
      p probe.call("azzb")
      pat = Regexp.new("q+")
      p probe.call("azzb")
      p probe.call("aqqb")
    RUBY

    _(result).must_answer <<~'OUT'
      2400
      "yes"
      "no"
      "yes"
    OUT
  end

  it "case string when sym no match" do
    result = ze0(<<~'RUBY')
      # Issue #378: `case <string> when :sym_literal` (and the
      # symmetric `case <symbol> when "string_literal"`) used to lower
      # to `strcmp(str, SPS_<sym>) == 0` / `mrb_int == const char *` —
      # C type errors on every such arm because `compile_expr` on a
      # SymbolNode returns the `sp_sym` numeric id (a long long), and
      # strcmp expects `const char *`.
      #
      # CRuby semantics: `:sym === "string"` is false (Symbol#=== only
      # matches Symbols), and `"string" === :sym` is also false. The
      # fix emits a literal `0` for these cross-type when arms — the
      # C compiles, and the runtime pick correctly falls through to
      # the else clause to match CRuby.

      def lookup(name)
        case name
        when :id
          1
        when :body
          2
        else
          -1
        end
      end

      # String case-expr against symbol when-arms — every arm misses,
      # else clause runs.
      puts lookup("id")     # -1 (not 1)
      puts lookup("body")   # -1 (not 2)
      puts lookup("nope")   # -1

      def reverse(sym)
        case sym
        when "id"
          1
        when "body"
          2
        else
          -1
        end
      end

      # Symbol case-expr against string when-arms — symmetric: every
      # arm misses, else runs.
      puts reverse(:id)     # -1
      puts reverse(:body)   # -1

      # Sanity: matching arms still work.
      def lookup_sym(s)
        case s
        when :id
          1
        when :body
          2
        else
          -1
        end
      end
      puts lookup_sym(:id)   # 1
      puts lookup_sym(:body) # 2
    RUBY

    _(result).must_answer <<~'OUT'
      -1
      -1
      -1
      -1
      -1
      1
      2
    OUT
  end

  it "case when regex" do
    result = ze0(<<~'RUBY')
      # Issue #852: `case <string> when /regex/` SEGV'd because the
      # generic strcmp arm consumed the RegularExpressionNode's
      # fallthrough value `0`. Route through sp_re_match_p.
      case "hello"
      when /^h/
        puts "starts with h"
      when /world/
        puts "contains world"
      end

      case "world!"
      when /^h/
        puts "starts with h"
      when /world/
        puts "contains world"
      end

      case "abc"
      when /xy/
        puts "match"
      else
        puts "no match"
      end
    RUBY

    _(result).must_answer <<~'OUT'
      starts with h
      contains world
      no match
    OUT
  end

  it "class of a failed match is nilclass not matchdata" do
    result = ze0(<<~'RUBY')
      # str.match(re) types as MatchData but returns nil on no match, so .class
      # must be read at runtime rather than constant-folded to MatchData.

      p "hi".match(/h/).class
      p "hi".match(/z/).class
      m = "hi".match(/z/)
      p m.class
    RUBY

    _(result).must_answer <<~'OUT'
      MatchData
      NilClass
      NilClass
    OUT
  end

  it "failed match clears the last match specials" do
    result = ze0(<<~'RUBY')
      # They are RESET, not left holding the previous match -- the property
      # that makes `if s =~ re then $1 end` safe to reuse in a loop.

      "ab" =~ /(a)/
      p $1
      "zzz" =~ /(\d+)/
      p $1
      p $&
      p $~
    RUBY

    _(result).must_answer <<~'OUT'
      "a"
      nil
      nil
      nil
    OUT
  end

  it "fnmatch honours its flags" do
    result = ze0(<<~'RUBY')
      # `File.fnmatch` honours every flag it accepts.
      #
      # It used to accept all five and honour one (`FNM_CASEFOLD`), which made
      # two of them wrong in opposite directions: `FNM_EXTGLOB` treated `{a,b}`
      # as literal characters, so a match FAILED where ruby succeeds, and
      # `FNM_PATHNAME` let `*` cross a `/`, so it answered true where ruby has
      # no match -- the more dangerous direction, since a caller using it to ask
      # "is this path inside one directory" got yes for a nested path.
      #
      # Rewriting it against CRuby's own rules closed four more the file never
      # named: the leading-DOT rule (`fnmatch("*", ".x")` is false without
      # `FNM_DOTMATCH`), backslash escapes (`FNM_NOESCAPE` turns them off),
      # bracket RANGES (`[a-c]`), and a `]` in the first position of a set,
      # which ends the set in `fnmatch` where glob reads it as a member.

      p File.fnmatch("{a,b}.rb", "b.rb", File::FNM_EXTGLOB)
      p File.fnmatch("{a,{b,c}}.rb", "c.rb", File::FNM_EXTGLOB)
      p File.fnmatch("{a,b}.rb", "b.rb")
      p File.fnmatch("*", "a/b", File::FNM_PATHNAME)
      p File.fnmatch("a/*", "a/b", File::FNM_PATHNAME)
      p File.fnmatch("*", ".x", File::FNM_DOTMATCH)
      p File.fnmatch("A*", "abc", File::FNM_CASEFOLD)
      p File.fnmatch("[[:alpha:]]", "a")
      p File.fnmatch("a?c", "abc")
    RUBY

    _(result).must_answer <<~'OUT'
      true
      true
      false
      false
      true
      true
      true
      false
      true
    OUT
  end

  it "hash and range breadth match the oracle" do
    result = ze0(<<~'RUBY')
      # The Hash + Range Tier A surface: merge (with conflict block), fetch
      # shapes, dig, invert/key/value?, filters + transforms, each_key/value,
      # Range size/step/last(n), and String-range iteration via succ.

      h = { a: 1, b: 2 }
      p h.merge({ c: 3 })
      p h.merge({ a: 9 }) { |k, old, new| old + new }
      p h.to_a
      p h.invert
      p h.key(2)
      p h.key(9)
      p h.fetch(:a)
      p h.fetch(:x, 0)
      begin
        h.fetch(:x)
      rescue KeyError => e
        puts "KeyError: #{e.message}"
      end
      p(h.fetch(:x) { |k| "no #{k}" })
      p(h.select { |k, v| v > 1 })
      p(h.reject { |k, v| v > 1 })
      p(h.transform_values { |v| v * 10 })
      p(h.any? { |k, v| v > 1 })
      p h.count
      p(h.min_by { |k, v| v })
      p h.value?(2)
      p h.value?(9)
      p({ x: { y: 5 } }.dig(:x, :y))
      h2 = { a: 1 }
      h2.update({ b: 2 })
      p h2
      acc = []
      h.each_key { |k| acc << k }
      h.each_value { |v| acc << v }
      p acc
      p h == { b: 2, a: 1 }
      p h == { a: 1 }
      r = (1..10)
      p r.sum
      p r.min
      p r.max
      p r.count
      p r.size
      p r.first(3)
      p r.last(3)
      p (1...5).size
      acc2 = []
      (1..10).step(3) { |i| acc2 << i }
      p acc2
      p ("a".."e").to_a
      p ("a".."e").include?("c")
    RUBY

    _(result).must_answer <<~'OUT'
      {a: 1, b: 2, c: 3}
      {a: 10, b: 2}
      [[:a, 1], [:b, 2]]
      {1 => :a, 2 => :b}
      :b
      nil
      1
      0
      KeyError: key not found: :x
      "no x"
      {b: 2}
      {a: 1}
      {a: 10, b: 20}
      true
      2
      [:a, 1]
      true
      false
      5
      {a: 1, b: 2}
      [:a, :b, 1, 2]
      true
      false
      55
      1
      10
      10
      10
      [1, 2, 3]
      [8, 9, 10]
      4
      [1, 4, 7, 10]
      ["a", "b", "c", "d", "e"]
      true
    OUT
  end

  it "incompatible regexp match raises" do
    result = ze0(<<~'RUBY')
      # A STRING pattern must be encoding-compatible with the receiver --
      # CRuby's `rb_enc_check`, the same test `+` makes. Without it the
      # pattern's bytes were reinterpreted under the receiver's encoding and
      # could MATCH, so a substitution happened where ruby raises.
      #
      # CORRECTION to this file's original note, which said the regexp rows
      # raise: they do not. `/x/` is US-ASCII and EUC-JP is ASCII-compatible, so
      # ruby simply does not match, and the first three rows below record that
      # -- they agreed all along. Only the String-pattern row was wrong.
      e = "日".encode("EUC-JP")
      def show
        p yield
      rescue Exception => ex
        puts "#{ex.class}: #{ex.message}"
      end
      show { e =~ /x/ }
      show { e.match?(/x/) }
      show { e.match(/x/) }
      show { "日".encode("Shift_JIS").gsub("日".encode("EUC-JP"), "x") }
    RUBY

    _(result).must_answer <<~'OUT'
      nil
      false
      nil
      Encoding::CompatibilityError: incompatible character encodings: Shift_JIS and EUC-JP
    OUT
  end

  it "is a against regexp and matchdata" do
    result = ze0(<<~'RUBY')
      r = /abc/
      puts r.is_a?(Regexp)
      puts r.is_a?(Object)
      m = "abc".match(/a/)
      puts m.is_a?(MatchData)
    RUBY

    _(result).must_answer <<~'OUT'
      true
      true
      true
    OUT
  end

  it "keep escape moves the match but not the search" do
    result = ze0(<<~'RUBY')
      r = Regexp.new('a\Kb')

      p r =~ "ab"
      p r.match("ab").begin(0)
      p r.match("ab")[0]
      p "ab".index(r)
      p "ab" =~ r
      p "ab".sub(r, "Z")

      long = Regexp.new('xa\Kb')
      p long =~ "xab"
      p long.match("xab").begin(0)

      p "ab".scan(r)
      p "ab".split(Regexp.new('a\K'))
    RUBY

    _(result).must_answer <<~'OUT'
      0
      1
      "b"
      1
      0
      "aZ"
      0
      2
      ["b"]
      ["a", "b"]
    OUT
  end

  it "last match globals" do
    result = ze0(<<~'RUBY')
      # Last-match globals ($~, $1.., $&, $`, $') and Regexp#~ / Regexp.timeout.

      # `=~` populates the last-match globals.
      "hello world" =~ /(\w+) (\w+)/
      p $~.class.to_s
      p $1
      p $2
      p $&
      p $`
      p $'
      p $~[0]

      # A failed match resets them to nil.
      "abc" =~ /(\d+)/
      p $~
      p $1

      # `~ /re/` matches the pattern against $_, returning the position (or nil) and
      # setting the match globals.
      $_ = "the year 2026 arrives"
      p(~ /(\d+)/)
      p $1
      $_ = "no digits here"
      p(~ /\d+/)

      # Regexp#timeout / Regexp.timeout report the (absent) default.
      p(/x/.timeout)
      p Regexp.timeout
    RUBY

    _(result).must_answer <<~'OUT'
      "MatchData"
      "hello"
      "world"
      "hello world"
      ""
      ""
      "hello world"
      nil
      nil
      9
      "2026"
      nil
      nil
      nil
    OUT
  end

  it "last match named group" do
    result = ze0(<<~'RUBY')
      # GAP -- imported from the spinel corpus at c55d9bdb.
      # Regexp.last_match with a String name raises "no implicit conversion";
      # ruby accepts a name.
      #
      "2024-01" =~ /(?<y>\d+)-(?<mo>\d+)/
      p Regexp.last_match("mo")
      p Regexp.last_match(:mo)
      p Regexp.last_match("y")
      p Regexp.last_match(1)
      p Regexp.last_match(2)
      p Regexp.last_match(0)
      p Regexp.last_match[0]
      n = "mo"
      p Regexp.last_match(n)
    RUBY

    _(result).must_answer <<~'OUT'
      "01"
      "01"
      "2024"
      "2024"
      "01"
      "2024-01"
      "2024-01"
      "01"
    OUT
  end

  it "last match specials read off the most recent match" do
    result = ze0(<<~'RUBY')
      if "hello world" =~ /(\w+)\s(\w+)/
        p $1
        p $2
        p $3
        p $&
        p $`
        p $'
        p $~[0]
        p $~.class
      end
    RUBY

    _(result).must_answer <<~'OUT'
      "hello"
      "world"
      nil
      "hello world"
      ""
      ""
      "hello world"
      MatchData
    OUT
  end

  it "match at a position anchors g against the true string" do
    result = ze0(<<~'RUBY')
      s = "aaa bbb ccc"

      # \G anchors at the search start position, not at the string start.
      p s.match(/\G\w+/, 0)[0]
      p s.match(/\G\w+/, 4)[0]
      p s.match(/\Gbbb/, 4)[0]
      p s.match(/\Gccc/, 4)
      p s.match(/\G\s/, 3)[0]

      # The scan loop StringScanner is built from: match at pos, advance by end(0).
      pos = 0
      tokens = []
      while (m = s.match(/\G\s*(\w+)/, pos))
        tokens << m[1]
        pos = m.end(0)
      end
      p tokens
      p pos

      # MatchData offsets are absolute, never slice-relative.
      m = s.match(/\G(b+)/, 4)
      p m.begin(0)
      p m.begin(1)
      p m.pre_match
      p m.post_match

      # Regexp#match takes the same optional position.
      re = /\G(?<word>\w+)/
      m = re.match(s, 8)
      p m[:word]
      p m.begin(0)
      p re.match(s, 3)
      p re.match(s, -3)[0]
      p re.match(s, 11)
      p re.match(s, 12)
      p re.match(s, -99)

      # A positioned Regexp#match still fills $~.
      /\G(b+)/.match(s, 4)
      p $~[1]

      # ^ beside \G takes a different engine route than a plain \G pattern.
      t = "one\ntwo\nthree"
      p t.match(/\G\w+$/, 4)[0]
      p t.match(/^\w+$/, 5)[0]

      # Lookaround beside \G is the backtracking route.
      p s.match(/\G(?=a)a+/, 0)[0]
      p s.match(/\G(?=b)/, 4).begin(0)
      p s.match(/\G(?!z)\w+/, 8)[0]

      # Lookbehind sees the true string to the LEFT of the position.
      p s.match(/(?<= )\w+/, 3)[0]
      p s.match(/\G(?<=a )bbb/, 4)[0]
      p s.match(/\G(?<=z )bbb/, 4)

      # The block form runs on a hit and the call answers the block's value.
      p(/\G\w+/.match(s, 4) { |md| md[0].upcase })
      p(/\Gzzz/.match(s, 4) { |md| :never })

      # match? at a position, same anchoring, no MatchData.
      p(/\Gbbb/.match?(s, 4))
      p(/\Gbbb/.match?(s, 3))
    RUBY

    _(result).must_answer <<~'OUT'
      "aaa"
      "bbb"
      "bbb"
      nil
      " "
      ["aaa", "bbb", "ccc"]
      11
      4
      4
      "aaa "
      " ccc"
      "ccc"
      8
      nil
      "ccc"
      nil
      nil
      nil
      "bbb"
      "two"
      "three"
      "aaa"
      4
      "ccc"
      "bbb"
      "bbb"
      nil
      "BBB"
      nil
      true
      false
    OUT
  end

  it "match globals" do
    result = ze0(<<~'RUBY')
      # frozen_string_literal: true

      # `$~` and the family that reads through it. All of them come off one
      # last-match slot, which is FRAME-LOCAL: a method that matches and
      # returns leaves the caller's `$1` alone.

      if "hello world" =~ /(\w+)\s(\w+)/
        p $1, $2, $3
        p $~.class, $~[0], $~[2]
        p $&, $`, $', $+
      end

      # A miss clears the slot rather than leaving the last hit behind.
      p("abc" =~ /z/)
      p $~, $1, $&

      # The numbers reach past nine, and a group the pattern never declared
      # is nil rather than an error.
      p("abcdefghijk" =~ /(a)(b)(c)(d)(e)(f)(g)(h)(i)(j)/)
      p $10, $11

      # `$+` is the highest group that PARTICIPATED, skipping one that was
      # declared but did not match.
      p("ab" =~ /(a)(b)|(z)/)
      p $+, $3

      module Parse
        def self.number(text)
          text =~ /(\d+)/ ? $1.to_i : nil
        end
      end

      # The method's own match does not reach here.
      "outer" =~ /(outer)/
      p Parse.number("x42y"), $1
      p Parse.number("none"), $1

      # A block shares the method's slot, and the method's stays its own.
      def scanned(list)
        list.map do |word|
          word =~ /(\w)$/
          $1
        end
      end
      p scanned(%w[one two]), $1

      # A class body is its own scope too.
      class Opened
        "class" =~ /(c)/
        p $1
      end
      p $1

      # `=~` with a named pattern on the LEFT binds each name to a local.
      if /(?<year>\d{4})-(?<month>\d{2})/ =~ "2026-09"
        p year, month
      end

      # A miss leaves the names nil rather than raising.
      /(?<absent>\d)/ =~ "no digits"
      p absent

      # `MatchData` answers the same groups the globals do.
      found = /(?<a>\w)(?<b>\w)/.match("xy")
      p found[:a], found[:b], found.captures, found.named_captures, found.pre_match

      # `defined?` reads the slot without disturbing it.
      p defined?($~), defined?($1), defined?($&)
      "z" =~ /(z)/
      p defined?($~), defined?($1), defined?($2), defined?($&), $1
    RUBY

    _(result).must_answer <<~'OUT'
      "hello"
      "world"
      nil
      MatchData
      "hello world"
      "world"
      "hello world"
      ""
      ""
      "world"
      nil
      nil
      nil
      nil
      0
      "j"
      nil
      0
      "b"
      nil
      42
      "outer"
      nil
      "outer"
      ["e", "o"]
      "outer"
      "c"
      "outer"
      "2026"
      "09"
      nil
      "x"
      "y"
      ["x", "y"]
      {"a" => "x", "b" => "y"}
      ""
      "global-variable"
      "global-variable"
      "global-variable"
      "global-variable"
      "global-variable"
      nil
      "global-variable"
      "z"
    OUT
  end

  it "match globals frame local" do
    result = ze0(<<~'RUBY')
      def f(s)
        s =~ /(l)/
        $1
      end
      p f("hello")
      "abc" =~ /(b)/
      p f("hello")
      p $1

      def g(s)
        s.scan(/(\d)/)
        1
      end
      "abc" =~ /(b)/
      g("x1")
      p $1

      def h(s); s.gsub(/(o)/) { "0" }; end
      "abc" =~ /(b)/
      h("foo")
      p $1

      def blk
        [1].each { "zz" =~ /(z)/ }
        $1
      end
      "abc" =~ /(b)/
      p blk
      p $1

      def early(s)
        return "no" unless s =~ /(x)/
        $1
      end
      "abc" =~ /(b)/
      p early("zz")
      p $1
      p early("xy")
      p $1

      def outer(s)
        s =~ /(o)/
        inner("zzz")
        $1
      end
      def inner(s); s =~ /(z)/; $1; end
      p outer("foo")
      p $~ && $~[0]
    RUBY

    _(result).must_answer <<~'OUT'
      "l"
      "l"
      "b"
      "b"
      "b"
      "z"
      "b"
      "no"
      "b"
      "x"
      "b"
      "o"
      "b"
    OUT
  end

  it "match globals in blocks" do
    result = ze0(<<~'RUBY')
      p("a1b2".gsub(/(?<l>[a-z])(?<n>\d)/) { $~[:n] })
      z001 = []; "a1b2".scan(/(?<l>[a-z])(?<n>\d)/) { z001 << $~[:n] }; p z001
      p("a1b2".gsub(/([a-z])(\d)/) { $~[2] })
      p("a1b2".gsub(/(?<l>[a-z])(?<n>\d)/) { "#{$2}#{$1}" })
      p("a1b2".gsub(/(?<l>[a-z])(?<n>\d)/) { $~.captures.join("-") })
      "hello" =~ /(?<x>l+)/; p $~[:x]
      z = []; "a1b2".scan(/([a-z])(\d)/) { z << $~[2] }; p z
      z2 = []; "a1b2".scan(/([a-z])(\d)/) { z2 << $1 }; p z2
      z3 = []; "a1b2".scan(/(?<l>[a-z])(?<n>\d)/) { z3 << $~.captures }; p z3
    RUBY

    _(result).must_answer <<~'OUT'
      "12"
      ["1", "2"]
      "12"
      "1a2b"
      "a-1b-2"
      "ll"
      ["1", "2"]
      ["a", "b"]
      [["a", "1"], ["b", "2"]]
    OUT
  end

  it "match holds the text as it was and shares it while unchanged" do
    result = ze0(<<~'RUBY')
      # A MatchData holds its text frozen, as it was when it matched: a String
      # of its own for each match of a text that is not frozen, and the text
      # itself when it is. A change of any kind leaves the earlier matches
      # their text and gives later ones the new one.
      s = +"hello world"
      m1 = s.match(/o/)
      m2 = s.match(/w/)
      p m1.string, m1.string.frozen?, m1.string.equal?(m2.string), m1.string.equal?(s)

      s << "!"
      p m1.string, s.match(/!/).string, m1.string.equal?(s.match(/!/).string)
      s.setbyte(0, 72)
      p s.match(/H/).string, m2.string
      s[0] = "J"
      p s.match(/J/).string
      s.insert(1, "_")
      p s.match(/_/).pre_match
      s.replace("new text")
      p s.match(/t/).pre_match, m1.pre_match
      s.upcase!
      p s.match(/T/).post_match
      s.force_encoding("BINARY")
      p s.match(/N/).string.encoding
      s.clear
      p s.match(/\A\z/).string, m2[0]
      s.concat("again", " and", " again")
      p s.match(/and/).string
      s.prepend(">")
      p s.match(/>/).post_match
      s.squeeze!("a")
      s.tr!("g", "G")
      p s.match(/G/).string
      s.sub!(/aGain/, "once")
      p s.match(/once/).string, $~.pre_match
      s.gsub!(/n/) { "N" }
      p s.match(/N/).string

      # Every match of a scan holds its own String, which stays as it was.
      t = +"a1 b2 c3"
      found = []
      t.scan(/(\w)(\d)/) { found << $~ }
      p found.map(&:string).map(&:object_id).uniq.size, found.map { _1[1] }
      t.gsub!(/\d/, "#")
      p found.map(&:string).uniq, t

      # A chilled literal is changed by its first write.
      lit = "chilled text"
      m = lit.match(/text/)
      Warning[:deprecated] = false
      lit << "!"
      p m.string, lit.match(/!/).string

      # A subclass keeps its class in the frozen text.
      class Tag < String; end
      tag = Tag.new("tagged")
      p tag.match(/g+/).string.class, tag.match(/e/).string.equal?(tag.match(/d/).string)
      frozen = "fixed".freeze
      p frozen.match(/x/).string.equal?(frozen), frozen.match(/f/).string.equal?(frozen.match(/d/).string)
      m = frozen.match(/i/).freeze
      p m.string, m.dup.string.equal?(m.string)

      # Two texts matched in turn each keep theirs.
      a = +"alpha"
      b = +"beta"
      ma = a.match(/l/)
      mb = b.match(/e/)
      p a.match(/p/).string.equal?(ma.string), b.match(/t/).string.equal?(mb.string)
      a << "!"
      p a.match(/!/).string.equal?(ma.string), ma.string

      # A read buffer that gives up its front does not leave a match stale.
      r, w = IO.pipe
      w.write("first line\nsecond line\nthird\n")
      w.close
      line = r.gets
      p line.match(/line/).string, r.gets("nd"), r.read.match(/\w+/).string
      r.close

    RUBY

    _(result).must_answer <<~'OUT'
      "hello world"
      true
      false
      false
      "hello world"
      "hello world!"
      false
      "Hello world!"
      "hello world"
      "Jello world!"
      "J"
      "new "
      "hell"
      "EXT"
      #<Encoding:BINARY (ASCII-8BIT)>
      ""
      "w"
      "again and again"
      "again and again"
      ">aGain and aGain"
      ">once and aGain"
      ">"
      ">oNce aNd aGaiN"
      3
      ["a", "b", "c"]
      ["a1 b2 c3"]
      "a# b# c#"
      "chilled text"
      "chilled text!"
      Tag
      false
      true
      true
      "fixed"
      true
      false
      false
      false
      "alpha"
      "first line\n"
      "second"
      " line\nthird\n"
    OUT
  end

  it "match operator non regexp" do
    result = ze0(<<~'RUBY')
      begin
        "Hello" =~ 0
      rescue NoMethodError => e
        p e.class
      end
      p("Hello" =~ nil)
      begin
        :abc =~ [1]
      rescue NoMethodError => e
        p e.class
      end
      p(:abc =~ nil)
    RUBY

    _(result).must_answer <<~'OUT'
      NoMethodError
      nil
      NoMethodError
      nil
    OUT
  end

  it "match p does not touch the last match but match does" do
    result = ze0(<<~'RUBY')
      # `match?` is specifically the allocation-free predicate: it builds no
      # MatchData and so leaves the slot alone. `Regexp#match` sets it.

      "abc" =~ /b/
      p $&
      "xyz".match?(/y/)
      p $&
      /(\d)/.match("a1")
      p $1
    RUBY

    _(result).must_answer <<~'OUT'
      "b"
      "b"
      "1"
    OUT
  end

  it "match p works from both the string and the regexp receiver" do
    result = ze0(<<~'RUBY')
      puts "hello".match?(/l+/)
      puts "hello".match?(/xyz/)
      puts(/l+/.match?("hello"))
    RUBY

    _(result).must_answer <<~'OUT'
      true
      false
      true
    OUT
  end

  it "match predicate bindings escape to the enclosing scope" do
    result = ze0(<<~'RUBY')
      arr = [1, "hi"]
      arr in [Integer => a, String => b]
      puts a
      puts b
    RUBY

    _(result).must_answer <<~'OUT'
      1
      hi
    OUT
  end

  it "match predicate one liner is a boolean that never raises" do
    result = ze0(<<~'RUBY')
      if [1, 2] in [Integer, Integer]
        puts "matched"
      end
      if [1, "x"] in [Integer, Integer]
        puts "should not print"
      else
        puts "did not match"
      end
    RUBY

    _(result).must_answer <<~'OUT'
      matched
      did not match
    OUT
  end

  it "match required one liner binds on success" do
    result = ze0(<<~'RUBY')
      arr = [1, 2]
      arr => [first, second]
      puts first
      puts second
    RUBY

    _(result).must_answer <<~'OUT'
      1
      2
    OUT
  end

  it "match required one liner raises no matching pattern error on failure" do
    result = ze0(<<~'RUBY')
      5 => String
    RUBY

    _(result).must_answer "", stderr: <<~'ERR', status: 1
      core/regexp/search_test.rb:1:in '<main>': 5: String === 5 does not return true (NoMatchingPatternError)
    ERR
  end

  it "match tilde pre post" do
    result = ze0(<<~'RUBY')
      # $~ answers its MatchData face (pre_match / post_match / to_s) from the same
      # match registers the back-references read.
      /foo/ =~ 'barfoobaz'
      p $~.pre_match
      p $~.post_match
      p $~.to_s
      p $~.pre_match == $`
      p $~.post_match == $'
    RUBY

    _(result).must_answer <<~'OUT'
      "bar"
      "baz"
      "foo"
      true
      true
    OUT
  end

  it "matchdata hash is value based" do
    result = ze0(<<~'RUBY')
      # MatchData#hash/#eql? are value-based (subject + pattern + regions), so
      # two matches produced by separate calls hash equal and work as the same
      # Hash key -- while a different subject keys apart.

      m1 = "abc".match(/b/)
      m2 = "xbz".match(/b/)
      m3 = "abc".match(/b/)
      p(m1.hash == m2.hash)
      p(m1.hash == m3.hash)
      p(m1.hash.is_a?(Integer))
      h = {}
      h[m1] = 99
      p h[m3]
      p h[m2]
      p m1.eql?(m3)
    RUBY

    _(result).must_answer <<~'OUT'
      false
      true
      true
      99
      nil
      true
    OUT
  end

  it "matchdata index bounds" do
    result = ze0(<<~'RUBY')
      # GAP -- imported from the spinel corpus at c55d9bdb.
      # MatchData#[] past the last group answers the group text instead of nil.
      #
      # A negative MatchData index reaches the capture groups only, so the one that
      # would land on the whole match is nil. A beginless or endless bound carries
      # the range sentinel, which the negative-index fixup turned into a wild offset.
      m = "hello".match(/(l)(o)/)
      p m[-1]
      p m[-2]
      p m[-3]
      p m[0]
      p m[1]
      p m[..1]
      p m[1..]
      p m[0,2]
      p m[0..]
      n = "abc".match(/(a)(b)(c)/)
      p n[-3]
      p n[-4]
    RUBY

    _(result).must_answer <<~'OUT'
      "o"
      "l"
      nil
      "lo"
      "l"
      ["lo", "l"]
      ["l", "o"]
      ["lo", "l"]
      ["lo", "l", "o"]
      "a"
      nil
    OUT
  end

  it "matchdata index eq" do
    result = ze0(<<~'RUBY')
      # MatchData#[] with a negative group index or a (start, length) pair, and
      # MatchData#== / #eql? (#2507, #2529, #2531).
      md = "abc".match(/(a)(b)(c)/)
      p md[-1]
      p md[-2]
      p md[1, 2]
      p md[0, 2]
      p md[2, 5]
      p md.eql?(md)
      p(md == "abc".match(/(a)(b)(c)/))
      p(md == "abd".match(/(a)(b)(d)/))
      p(md == nil)
      md2 = "hello".match(/(?<x>l+)/)
      p md2[-1]
    RUBY

    _(result).must_answer <<~'OUT'
      "c"
      "b"
      ["a", "b"]
      ["abc", "a"]
      ["b", "c"]
      true
      true
      false
      false
      "ll"
    OUT
  end

  it "matchdata index range" do
    result = ze0(<<~'RUBY')
      # An index outside a MatchData's groups is CRuby's IndexError. begin, end and
      # offset answered nil (and offset a pair of nils) instead.
      m = "hello".match(/(l)/)
      p((m.begin(5) rescue $!.class))
      p((m.end(5) rescue $!.class))
      p((m.offset(5) rescue $!.class))
      p((m.begin(-1) rescue $!.message))
      p m.begin(0)
      p m.begin(1)
      p m.end(1)
      p m.offset(1)
      p((m.bytebegin(9) rescue $!.class))
    RUBY

    _(result).must_answer <<~'OUT'
      IndexError
      IndexError
      IndexError
      "index -1 out of matches"
      2
      2
      3
      [2, 3]
      IndexError
    OUT
  end

  it "matchdata match by name" do
    result = ze0(<<~'RUBY')
      # GAP -- imported from the spinel corpus at c55d9bdb.
      # Regexp.last_match with a Symbol name raises "no implicit conversion";
      # ruby accepts a name.
      #
      "2024-01-15" =~ /(?<y>\d+)-(?<mo>\d+)-(?<d>\d+)/
      p Regexp.last_match(:y)
      p Regexp.last_match(:mo)
      v001 = Regexp.last_match(:d); p v001
      m001 = "2024-01".match(/(?<y>\d+)-(?<mo>\d+)/)
      p m001.match(:y)
      p m001.match(:mo)
      p m001.match_length(:y)
      p m001.match_length(:mo)
      p m001[:y]
      p m001[:mo]
    RUBY

    _(result).must_answer <<~'OUT'
      "2024"
      "01"
      "15"
      "2024"
      "01"
      4
      2
      "2024"
      "01"
    OUT
  end

  it "matchdata named group access by symbol string and named captures hash" do
    result = ze0(<<~'RUBY')
      m = "John Smith".match(/(?<first>\w+) (?<last>\w+)/)
      puts m[:first]
      puts m["last"]
      h = m.named_captures
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

  it "matchdata named groups" do
    result = ze0(<<~'RUBY')
      # MatchData named-group access: md[:name] / md["name"] select a named capture
      # group (previously returned the whole match), plus #named_captures and #names.
      # A non-participating named group is nil; an unknown name raises IndexError.
      def s(x); x; end

      m = "2026-06".match(/(?<y>\d+)-(?<mo>\d+)/)
      p m[:mo]
      p m[:y]
      p m["mo"]
      p m.named_captures
      p m.names
      # positional indexing is unchanged
      p m[0]
      p m[1]

      # non-literal symbol key routes through the runtime path
      k = s(:mo)
      p m[k]

      # non-participating named group -> nil (value side is poly)
      alt = "x".match(/(?<a>x)|(?<b>y)/)
      p alt[:a]
      p alt[:b]
      p alt.named_captures

      # no named groups
      plain = "ab".match(/(a)(b)/)
      p plain.named_captures
      p plain.names

      # unknown name raises IndexError
      begin
        p m[:nope]
      rescue => e
        puts "#{e.class}: #{e.message}"
      end
    RUBY

    _(result).must_answer <<~'OUT'
      "06"
      "2026"
      "06"
      {"y" => "2026", "mo" => "06"}
      ["y", "mo"]
      "2026-06"
      "2026"
      "06"
      "x"
      nil
      {"a" => "x", "b" => nil}
      {}
      []
      IndexError: undefined group name reference: nope
    OUT
  end

  it "matchdata offset names regexp and regexp class methods" do
    result = ze0(<<~'RUBY')
      m = "abc123".match(/([a-z]+)(\d+)/)
      p m.offset(2)
      p m.byteoffset(2)
      p "x1".match(/(?<a>[a-z])(?<b>\d)/).names
      p Regexp.union("a", "b").source
      p Regexp.union.source
      p Regexp.linear_time?(/(a+)+/)
      p Regexp.linear_time?(/(a)\1/)
      p Regexp.try_convert("x")
    RUBY

    _(result).must_answer <<~'OUT'
      [3, 6]
      [3, 6]
      ["a", "b"]
      "a|b"
      "(?!)"
      true
      false
      nil
    OUT
  end

  it "matchdata offsets match and deconstruction" do
    result = ze0(<<~'RUBY')
      # MatchData begin/end, bytebegin/byteend, match, inspect, deconstruct, and
      # deconstruct_keys with CRuby's key rules.

      m = "hello world".match(/(\w+)(\s+)(\w+)/)
      p [m.begin(1), m.end(1), m.begin(3)]
      md = "a1b2".match(/(\d)(\w)/); p [md.bytebegin(1), md.byteend(1)]
      m2 = "abc".match(/(a)(b)(c)/)
      p m2.inspect
      p m2.deconstruct
      p m2.match(2)
      n = "abc".match(/(?<x>b)(?<y>c)/)
      p [n.deconstruct_keys([:x]), n.deconstruct_keys([:y, :x]), n.deconstruct_keys(nil), n.deconstruct_keys([:x, :y, :z])]
      p n.named_captures(symbolize_names: true)
    RUBY

    _(result).must_answer <<~'OUT'
      [0, 5, 6]
      [1, 2]
      "#<MatchData \"abc\" 1:\"a\" 2:\"b\" 3:\"c\">"
      ["a", "b", "c"]
      "b"
      [{x: "b"}, {y: "c", x: "b"}, {x: "b", y: "c"}, {}]
      {x: "b", y: "c"}
    OUT
  end

  it "matchdata regexp extended" do
    result = ze0(<<~'RUBY')
      m = "abc123".match(/([a-z]+)(\d+)/)
      p m.offset(0); p m.offset(1); p m.offset(2)
      p m.byteoffset(0); p m.byteoffset(2)
      p m.names
      p m.regexp
      n = "abc123".match(/(?<letters>[a-z]+)(?<digits>\d+)/)
      p n.offset(:letters); p n.names
      p Regexp.union("a+b", /c.d/, "e")
      p Regexp.union("a+b", /c.d/, "e").source
      p Regexp.union(["x", "y"]).source
      p Regexp.union.source
      p Regexp.linear_time?(/a*/)
      p Regexp.linear_time?(/(a+)+/)
      p Regexp.try_convert(/x/); p Regexp.try_convert("x"); p Regexp.try_convert(42)
    RUBY

    _(result).must_answer <<~'OUT'
      [0, 6]
      [0, 3]
      [3, 6]
      [0, 6]
      [3, 6]
      []
      /([a-z]+)(\d+)/
      [0, 3]
      ["letters", "digits"]
      /a\+b|(?-mix:c.d)|e/
      "a\\+b|(?-mix:c.d)|e"
      "x|y"
      "(?!)"
      true
      true
      /x/
      nil
      nil
    OUT
  end

  it "matchdata to a and captures" do
    result = ze0(<<~'RUBY')
      m = "hello world".match(/(\w+) (\w+)/)
      puts m.to_a
      puts "---"
      puts m.captures
    RUBY

    _(result).must_answer <<~'OUT'
      hello world
      hello
      world
      ---
      hello
      world
    OUT
  end

  it "matchdata unknown named group raises index error" do
    result = ze0(<<~'RUBY')
      # An unknown named-group key raises IndexError (previously an abort);
      # a known name resolves its capture.

      m = "2026-06".match(/(?<y>\d+)-(?<mo>\d+)/)
      p m[:mo]
      begin
        m[:nope]
      rescue IndexError => e
        puts "#{e.class}: #{e.message}"
      end
    RUBY

    _(result).must_answer <<~'OUT'
      "06"
      IndexError: undefined group name reference: nope
    OUT
  end

  it "matchdata values at and string to r" do
    result = ze0(<<~'RUBY')
      m = "2024-01-15".match(/(\d+)-(\d+)-(\d+)/)
      p m.values_at(1, 3)
      p m.values_at(0, 2)
      p "123".to_r
      p "3/4".to_r
      p "1.5".to_r
      p "abc".to_r
      p "  -12".to_r
      p "1_000".to_r
    RUBY

    _(result).must_answer <<~'OUT'
      ["2024", "15"]
      ["2024-01-15", "01"]
      (123/1)
      (3/4)
      (3/2)
      (0/1)
      (-12/1)
      (1000/1)
    OUT
  end

  it "matchdata values at named" do
    result = ze0(<<~'RUBY')
      # MatchData#values_at(:name) resolves each named group against this MatchData's
      # own regexp group table, like MatchData#[]. Spinel routed a Symbol/String
      # argument through the index accessor, which consulted a single first-seen global
      # name table -- so a second named-capture regexp's names resolved to nil.
      def one(s); s.match(/(?<a>\w)(?<b>\w)/).values_at(:a, :b); end
      def two(s); s.match(/(?<c>\w)(?<d>\w)/).values_at(:c, :d); end
      p one("hi")                    # ["h", "i"]
      p two("xy")                    # ["x", "y"]

      # String names and integer indices work too, including a mix.
      def mix(s); s.match(/(?<x>\w)(?<y>\w)/).values_at("x", 2, 0); end
      p mix("ab")                    # ["a", "b", "ab"]

      # A name that did not participate yields nil.
      def opt(s); s.match(/(?<p>\d)?(?<q>\w)/).values_at(:p, :q); end
      p opt("z")                     # [nil, "z"]

      # A poly-typed key (Symbol|Integer union) dispatches at runtime: a Symbol resolves
      # by name, an Integer by index -- for both #values_at and #[].
      def poly_va(s, byname); k = byname ? :y : 1; s.match(/(?<x>\w)(?<y>\w)/).values_at(k, 0); end
      p poly_va("ab", true)          # ["b", "ab"]
      p poly_va("ab", false)         # ["a", "ab"]
      def poly_idx(s, byname); k = byname ? :x : 2; s.match(/(?<x>\w)(?<y>\w)/)[k]; end
      p poly_idx("ab", true)         # "a"
      p poly_idx("ab", false)        # "b"
    RUBY

    _(result).must_answer <<~'OUT'
      ["h", "i"]
      ["x", "y"]
      ["a", "b", "ab"]
      [nil, "z"]
      ["b", "ab"]
      ["a", "ab"]
      "a"
      "b"
    OUT
  end

  it "matchdata whole match" do
    result = ze0(<<~'RUBY')
      # $~[0] is the whole match even when capture groups are present; $~[n] are groups.
      "hello world" =~ /(\w+) (\w+)/
      p $~[0]
      p $~[1]
      p $~[2]
    RUBY

    _(result).must_answer <<~'OUT'
      "hello world"
      "hello"
      "world"
    OUT
  end

  it "matchdata whole match captures pre and post match" do
    result = ze0(<<~'RUBY')
      m = "hello world".match(/(\w+) (\w+)/)
      puts m[0]
      puts m[1]
      puts m[2]
      puts m.pre_match
      puts m.post_match
    RUBY

    _(result).must_answer <<~'OUT'
      hello world
      hello
      world


    OUT
  end

  it "named captures dup names backref plus and nonstring match" do
    result = ze0(<<~'RUBY')
      # named_captures collects ALL indices for a name reused by several groups
      # (the engine collapses it, so this parses the source); \+ expands to the
      # highest participating group; Regexp#=~ against a non-String raises
      # TypeError (nil still answers nil).

      p /(?<a>x)(?<b>y)/.named_captures
      p /(?<a>x)(?<a>z)/.named_captures
      p /(?<a>x)(?<a>z)/.names
      p "ab".sub(/(a)(b)?/, '\+')
      p "a.".sub(/(a)(b)?/, '\+')
      p "1a 2. 3c".gsub(/(\d)([a-z])?/, '<\+>')
      r = (begin; /p/ =~ 5; rescue TypeError => e; "TE: " + e.message; end); p r
      p(/l/ =~ "hello")
      p(/z/ =~ "hello")
    RUBY

    _(result).must_answer <<~'OUT'
      {"a" => [1], "b" => [2]}
      {"a" => [1, 2]}
      ["a"]
      "b"
      "a."
      "<a> <2>. <c>"
      "TE: no implicit conversion of Integer into String"
      2
      nil
    OUT
  end

  it "named captures symbolize" do
    result = ze0(<<~'RUBY')
      # named_captures(symbolize_names: false) asks for the string keys the
      # no-argument form gives. The argument was ignored -- any argument meant
      # symbolize -- and the keys came back as symbols.
      m = "2024-01".match(/(?<y>\d+)-(?<mo>\d+)/)
      p m.named_captures(symbolize_names: false)
      p m.named_captures(symbolize_names: true)
      p m.named_captures
    RUBY

    _(result).must_answer <<~'OUT'
      {"y" => "2024", "mo" => "01"}
      {y: "2024", mo: "01"}
      {"y" => "2024", "mo" => "01"}
    OUT
  end

  it "names meta" do
    result = ze0(<<~'RUBY')
      # MatchData#string (the match subject), Regexp#names, and
      # Regexp#named_captures ({name => [group indices]}, duplicate names
      # collecting), on literal and variable receivers.
      m = /(?<y>\d+)-(?<m>\d+)/.match("2026-07")
      p m.string
      p /(?<a>x)(?<b>y)/.names
      p /(?<a>x)(?<b>y)/.named_captures
      p /(?<a>x)(?<a>z)/.named_captures
      p /nogroups/.names
      p /nogroups/.named_captures
      re = /(?<w>\w+)/
      p re.names
    RUBY

    _(result).must_answer <<~'OUT'
      "2026-07"
      ["a", "b"]
      {"a" => [1], "b" => [2]}
      {"a" => [1, 2]}
      []
      {}
      ["w"]
    OUT
  end

  it "nested class leaves the outer state as onigmo does" do
    result = ze0(<<~'RUBY')
      # A nested character class leaves the outer class's state as Onigmo
      # leaves it: a value before it still pends, and a '-' after a leading
      # one is a plain character with no warning.

      $VERBOSE = true
      pats = ["[[[:alnum:]]-_.]", "[a[x]-c]", "[[x]a-c]", "[a-b[x]-z]", "[[a]-[b]]", "[[:alpha:][0-9]-]", "[x[y]]", "[[a-c]&&[b]]"]
      pats.each do |s|
        begin
          r = Regexp.new(s)
          p [s, %w[a b _ - . x y z 5].select { |c| r.match?(c) }]
        rescue RegexpError => e
          p [s, e.message]
        end
      end

    RUBY

    _(result).must_answer <<~'OUT', stderr: <<~'ERR'
      ["[[[:alnum:]]-_.]", ["a", "b", "_", "-", ".", "x", "y", "z", "5"]]
      ["[a[x]-c]", ["a", "b", "x"]]
      ["[[x]a-c]", ["a", "b", "x"]]
      ["[a-b[x]-z]", ["a", "b", "-", "x", "z"]]
      ["[[a]-[b]]", ["a", "b", "-"]]
      ["[[:alpha:][0-9]-]", ["a", "b", "-", "x", "y", "z", "5"]]
      ["[x[y]]", ["x", "y"]]
      ["[[a-c]&&[b]]", ["b"]]
    OUT
      core/regexp/search_test.rb:9: warning: character class has '-' without escape: /[a-b[x]-z]/
    ERR
  end

  it "nil match op variable" do
    result = ze0(<<~'RUBY')
      # NilClass#=~ is always nil and nil !~ re is always true, including when the
      # nil is held in a variable (poly receiver path).
      n = nil
      p(n =~ /x/)
      p(n !~ /x/)
      m = nil
      p(m !~ /abc/)
    RUBY

    _(result).must_answer <<~'OUT'
      nil
      true
      true
    OUT
  end

  it "not match op" do
    result = ze0(<<~'RUBY')
      # Issue #732. `str !~ /pattern/` should return true when no match
      # and false when there is a match. spinel used to emit the unresolved-
      # call warning and return 0; now `!~` is the negation of `=~`.

      puts "hello" !~ /xyz/
      puts "hello" !~ /llo/
      puts "abc 123" !~ /\d+/
      puts "abc" !~ /\d+/
    RUBY

    _(result).must_answer <<~'OUT'
      true
      false
      false
      true
    OUT
  end

  it "not match operator negates from both receivers" do
    result = ze0(<<~'RUBY')
      puts("hello" !~ /xyz/)
      puts("hello" !~ /l+/)
      puts(/xyz/ !~ "hello")
    RUBY

    _(result).must_answer <<~'OUT'
      true
      false
      true
    OUT
  end

  it "oniguruma backed semantics match the oracle" do
    result = ze0(<<~'RUBY')
      # ^/$ do not match at the phantom position after a final newline
      p("a\n".scan(/^/).size)
      p("a\nb\n".scan(/^/).size)
      p(/^$/.match?("a\n"))
      p("x\n".match?(/x$/))
      # inline (?m:) is Ruby DOTALL (dot spans newline), scoped to the group
      p(/(?m:a.c)/ =~ "a\nc")
      p(/a.c/ =~ "a\nc")
      p(/(?i-m:a.b)/ =~ "A\nB")
      # absence operator: match only text NOT containing "foo"
      p(/\A(?~foo)\z/.match?("bar"))
      p(/\A(?~foo)\z/.match?("xfooy"))
      # alternation captures land in the right slots
      p(/(a)|(b)|(c)/.match("c").captures)
      # onig accepts a redundant nested repeat that stricter engines reject
      p(Regexp.new("a***").match?("aaa"))
    RUBY

    _(result).must_answer <<~'OUT', stderr: <<~'ERR'
      1
      2
      false
      true
      0
      nil
      nil
      true
      false
      [nil, nil, "c"]
      true
    OUT
      core/regexp/search_test.rb:16: warning: regular expression has redundant nested repeat operator '*': /a***/
      core/regexp/search_test.rb:16: warning: regular expression has redundant nested repeat operator '*': /a***/
    ERR
  end

  it "regex atomic group" do
    result = ze0(<<~'RUBY')
      p("aaa".match(/(?>a+)a/))
      p("aaa".match?(/(?>a+)a/))
      p("aaa".match(/a++a/))
      p("aaab".match(/(?>a+)b/)[0])
      p("aaab".match(/a++b/)[0])
      p("aaab" =~ /a*+b/)
      p("abcd".match(/(?>\w+)/)[0])
      p("aaa".match(/a?+a/))
      p("foo bar".match(/(?>\w+)\s(\w+)/)[1])
      p("aaa".scan(/(?>a)/).length)
      p("2026-08-10".match(/(?>\d++)-(\d+)/)[1])
    RUBY

    _(result).must_answer <<~'OUT'
      nil
      false
      nil
      "aaab"
      "aaab"
      0
      "abcd"
      #<MatchData "aa">
      "bar"
      3
      "08"
    OUT
  end

  it "regex backreferences and lookaround via fancy engine" do
    result = ze0(<<~'RUBY')
      # Constructs the linear-time `regex` crate can't do; a backtracking engine
      # transparently backs them. The fast path stays unaffected.

      puts("hello" =~ /(\w)\1/)             # 2
      p("abc" =~ /(\w)\1/)                  # nil
      puts "foobar".match?(/foo(?=bar)/)    # true
      puts "foobaz".match?(/foo(?=bar)/)    # false
      puts "$100".gsub(/(?<=\$)\d+/, "N")   # $N
      puts "catfish".match?(/cat(?!fish)/)  # false
      puts "abc".match?(/a(?#c)bc/)         # true
      puts "book".match?(/(?<c>o)\k<c>/)    # true
      # fast path unaffected
      m = "2024-01-15".match(/(\d+)-(\d+)-(\d+)/)
      puts m[2]                             # 01
      p "a,b,c".split(/,/)                  # ["a", "b", "c"]
    RUBY

    _(result).must_answer <<~'OUT'
      2
      nil
      true
      false
      $N
      false
      true
      true
      01
      ["a", "b", "c"]
    OUT
  end

  it "regex capture scan toproc count" do
    result = ze0(<<~'RUBY')
      # s[/re/, n] and s[/re/, :name] captures, the String#scan block form,
      # count on a boxed-array block parameter, explicit Symbol#to_proc, and
      # combination/permutation over non-integer arrays.
      p "2024-01-15"[/(\d+)-(\d+)/, 2]
      p "hello world"[/(\w+) (\w+)/, 1]
      p "2024-01"[/(?<y>\d+)-(?<m>\d+)/, :y]
      p "abc"[/(x)(y)/, 1]
      p "hello"[/l+/, 0]
      result = "hello world".scan(/\w+/) { |w| print w.upcase, " " }
      puts
      p result
      p [[1, 2], [3, 4, 5]].map { |a| a.count }
      p [[1, 2], [3, 4, 5]].map(&:count)
      p [[1, 2, 2], [3]].map { |a| a.count(2) }
      p [[1, 2, 3], [4]].map { |a| a.count { |x| x > 1 } }
      p [[1, 2, 3]].sum { |a| a.count }
      up = :upcase.to_proc
      p up.call("hi")
      add = :+.to_proc
      p add.call(2, 3)
      p ["a", "b", "c"].combination(2).to_a
      p [:a, :b, :c].combination(2).to_a
      p [1.0, 2.0, 3.0].combination(2).to_a
      p ["a", "b", "c"].permutation(2).to_a
      p ["a", "b"].repeated_combination(2).to_a
      p "ABC".scan(/[a-z]/i)
      p "Hello World!".gsub(/[^a-z]/i, "")
      p("ABC" =~ /[a-z]/i)
      p "aBc".scan(/[A-Z]/i)
      p "x1y2".scan(/[a-m0-5]/i)
    RUBY

    _(result).must_answer "\"01\"\n\"hello\"\n\"2024\"\nnil\n\"ll\"\nHELLO WORLD \n\"hello world\"\n[2, 3]\n[2, 3]\n[2, 0]\n[2, 1]\n3\n\"HI\"\n5\n[[\"a\", \"b\"], [\"a\", \"c\"], [\"b\", \"c\"]]\n[[:a, :b], [:a, :c], [:b, :c]]\n[[1.0, 2.0], [1.0, 3.0], [2.0, 3.0]]\n[[\"a\", \"b\"], [\"a\", \"c\"], [\"b\", \"a\"], [\"b\", \"c\"], [\"c\", \"a\"], [\"c\", \"b\"]]\n[[\"a\", \"a\"], [\"a\", \"b\"], [\"b\", \"b\"]]\n[\"A\", \"B\", \"C\"]\n\"HelloWorld\"\n0\n[\"a\", \"B\", \"c\"]\n[\"1\", \"2\"]\n"
  end

  it "regex fancy" do
    result = ze0(<<~'RUBY')
      # Regex parity — backreferences and look-around, backed by a backtracking
      # engine that transparently kicks in for constructs the fast engine can't do.
      # The common fast path is unaffected.

      # In-pattern backreferences.
      p "hello" =~ /(\w)\1/               # 2 (the doubled "l")
      p "abc"   =~ /(\w)\1/               # nil
      p "hello world world".scan(/(\w+) \1/)  # [["world"]]
      p "book".match?(/(?<c>o)\k<c>/)     # true (named backref)

      # Lookahead / negative lookahead.
      p "foobar".scan(/foo(?=bar)/)       # ["foo"]
      p "foobaz".scan(/foo(?=bar)/)       # []
      p "catfish cat".scan(/cat(?!fish)/) # ["cat"]

      # Lookbehind / negative lookbehind.
      p "$100 €50".gsub(/(?<=\$)\d+/, "#")  # "$# €50"
      p "1a2b3".scan(/(?<!\d)[a-z]/)        # ["a", "b"] — letters not preceded by a digit

      # Inline comment (ignored).
      p "abc".match?(/a(?#skip me)bc/)    # true

      # The fast path still handles the everyday cases identically.
      m = "2024-01-15".match(/(\d+)-(\d+)-(\d+)/)
      p [m[1], m[2], m[3]]                # ["2024", "01", "15"]
      p "a,b,,c".split(/,/)               # ["a", "b", "", "c"]
      p "Hello".gsub(/l/, "L")            # "HeLLo"
      p "aXbXc".scan(/X/).length          # 2
    RUBY

    _(result).must_answer <<~'OUT'
      2
      nil
      [["world"]]
      true
      ["foo"]
      []
      ["cat"]
      "$# €50"
      []
      true
      ["2024", "01", "15"]
      ["a", "b", "", "c"]
      "HeLLo"
      2
    OUT
  end

  it "regex gpos subexp" do
    result = ze0(<<~'RUBY')
      p("foo".match(/\Gfoo/))
      p("abcabc".match(/(?<x>abc)\g<x>/))
      p("xfoo".match(/\Gfoo/))
      p("abcabc".match(/(?<x>abc)\g<x>/)[1])
      p("aaa".scan(/\Ga/).length)
      p("abcabcabc".match(/(abc)\g<1>\g<1>/)[0])
    RUBY

    _(result).must_answer <<~'OUT'
      #<MatchData "foo">
      #<MatchData "abcabc" x:"abc">
      nil
      "abc"
      3
      "abcabcabc"
    OUT
  end

  it "regex match nonstring" do
    result = ze0(<<~'RUBY')
      # `Regexp#=~` (and match?/===) with a non-String operand raises
      # TypeError in CRuby; Spinel used to pass the scalar where a char* was
      # expected and segfault.
      x = 5
      begin
        if /p/ =~ x
          puts "matched"
        else
          puts "no match"
        end
        puts "NO RAISE"
      rescue TypeError => e
        puts "TE: " + e.message
      end

      # A real String operand still matches and returns the offset (or nil).
      puts(/l/ =~ "hello")
      p(/zz/ =~ "hello")
    RUBY

    _(result).must_answer <<~'OUT'
      TE: no implicit conversion of Integer into String
      2
      nil
    OUT
  end

  it "regex match p poly recv" do
    result = ze0(<<~'RUBY')
      # A poly receiver reaching String#match? / #!~ -- a block param over an array
      # whose element type never resolved, an element read out of a widened array.
      # emit_expr left the sp_RbVal in sp_re_match_p's const char * slot, so the
      # generated C did not compile.
      RE = /\A-(\w|-\w[\w-]*)\z/

      class Flag
        attr_reader :switches
        def check
          out = []
          switches.each do |s|
            out.push(s.match?(RE))
          end
          out
        end
      end

      f = Flag.new
      f.instance_variable_set(:@switches, ["-a", "--long", "x"])
      p f.check

      mixed = ["-a", 1, nil]
      p(mixed[0].match?(RE))
      p(mixed[0] !~ RE)
      # nil answers true for !~ (NilClass#=~ is nil) ...
      p(mixed[2] !~ RE)
      # ... but has no match? at all
      begin
        p mixed[2].match?(RE)
      rescue NoMethodError => e
        puts "NoMethodError"
      end
      # and a non-string, non-nil value has neither
      begin
        p mixed[1] !~ RE
      rescue NoMethodError => e
        puts "NoMethodError"
      end
    RUBY

    _(result).must_answer <<~'OUT'
      [true, true, false]
      true
      false
      true
      NoMethodError
      NoMethodError
    OUT
  end

  it "regex namespaced const" do
    result = ze0(<<~'RUBY')
      # Refs #1008. A regex in a namespaced constant must resolve like a top-level
      # one: gsub/sub/scan/=~ should dispatch to the engine, not silently no-op
      # (gsub) or raise undefined-method (scan).
      module M
        RE = /a/
      end
      puts "banana".gsub(M::RE, "X")
      puts "banana".scan(M::RE).length

      # nested namespace + .freeze
      module A
        module B
          WS = /\s+/.freeze
        end
      end
      puts "x  y   z".gsub(A::B::WS, "-")
      puts "x  y   z".scan(A::B::WS).length
    RUBY

    _(result).must_answer <<~'OUT'
      bXnXnX
      3
      x-y-z
      2
    OUT
  end

  it "regex negated shorthand toplevel" do
    result = ze0(<<~'RUBY')
      # Top-level \D \W \S must match the complement set (not double-negate).
      p("5" =~ /\D/); p("x" =~ /\D/)
      p("a" =~ /\W/); p(" " =~ /\W/)
      p("x" =~ /\S/); p(" " =~ /\S/)
      # Non-negated and bracket forms unchanged.
      p("5" =~ /\d/); p("x" =~ /\d/)
      p("a" =~ /\w/); p(" " =~ /\w/)
      p("5" =~ /[\D]/); p("x" =~ /[\D]/)
      p("héllo" =~ /\D/)
    RUBY

    _(result).must_answer <<~'OUT'
      nil
      0
      nil
      0
      0
      nil
      0
      nil
      0
      nil
      nil
      0
      0
    OUT
  end

  it "regex value as match arg" do
    result = ze0(<<~'RUBY')
      # A regex in argument position may be any expression, not just a local or a
      # constant read. An inline `Regexp.new(s)` / `Regexp.union(..)` / a method
      # returning a regex is the same pattern value, and String#match / #match? /
      # #=~ / #!~ / #scan must take it the way #sub / #gsub / #split already do.

      def re
        /\d/
      end

      # --- inline call in argument position
      p "1d".match(Regexp.new("\\d"))
      p "1d".match?(Regexp.new("\\d"))
      p("1d" =~ Regexp.new("\\d"))
      p("1d" !~ Regexp.new("\\d"))
      p "1d".scan(Regexp.new("\\d"))
      p "a1b2".match(Regexp.union("b", "1"))
      p "a1b2".scan(Regexp.union("1", "2"))

      # a call returning a plain literal is still a call
      p "1d".match(re)
      p "1d".match?(re)
      p("1d" =~ re)
      p "a1b2".scan(re)

      # --- the same expression bound to a local keeps working
      r = Regexp.new("\\d")
      p "1d".match(r)
      p "1d".match?(r)
      p("1d" =~ r)
      p("1d" !~ r)
      p "a1b2".scan(r)

      # --- literals and constant-bound literals stay on their own paths
      LIT = /\d/
      p "1d".match(/\d/)
      p "1d".match?(/\d/)
      p("1d" =~ /\d/)
      p "a1b2".scan(/\d/)
      p "a1b2".scan(/(\d)(\w)/)
      p "1d".match(LIT)

      # --- interpolated literal in argument position
      sep = "d"
      p "1d".match(/#{sep}/)
      p "1d".match?(/#{sep}/)
      p "a1b2d".scan(/#{sep}|\d/)
      p "a1b2".scan(/(#{sep}|\d)(\w)/)

      # --- a run-time pattern's capture groups are only knowable at run time:
      # no groups yields whole matches, groups yield a row per match
      p "a1b2".scan(Regexp.new("\\d"))
      p "a1b2".scan(Regexp.new("(\\d)(\\w)"))
      p "abc".scan(Regexp.new("\\d"))

      # --- scan's block form returns self and yields each whole match
      p("a1b2".scan(Regexp.new("\\d")) { |m| print m })

      # --- the reported site: an interpolated pattern built with Regexp.new,
      # consumed directly in an `if` condition
      INTERVALS = { "h" => 3600, "m" => 60 }
      def parse(param)
        if m = param.to_s.match(Regexp.new("\\A(\\d+)([#{INTERVALS.keys.join}])\\z"))
          m[1].to_i * INTERVALS[m[2]]
        end
      end
      p parse("12h")
      p parse("30m")
      p parse("nope")

      # --- the start-position form takes a run-time pattern too
      p "a1b2".match(Regexp.new("\\d"), 2)
      p "a1b2".match?(Regexp.new("\\d"), 2)
      p "a1b2".match(r, 2)

      # --- a poly receiver (a String read out of a widened container) is coerced
      # into the subject slot rather than passed through raw
      mixed = ["a1b2", 7]
      poly = mixed[0]
      p poly.match(Regexp.new("\\d"))
      p poly.match?(Regexp.new("\\d"))

      # --- Regexp on the receiver side is unchanged
      p Regexp.new("\\d").match("1d")
      p Regexp.new("\\d").match?("1d")
    RUBY

    _(result).must_answer <<~'OUT'
      #<MatchData "1">
      true
      0
      false
      ["1"]
      #<MatchData "1">
      ["1", "2"]
      #<MatchData "1">
      true
      0
      ["1", "2"]
      #<MatchData "1">
      true
      0
      false
      ["1", "2"]
      #<MatchData "1">
      true
      0
      ["1", "2"]
      [["1", "b"]]
      #<MatchData "1">
      #<MatchData "d">
      true
      ["1", "2", "d"]
      [["1", "b"]]
      ["1", "2"]
      [["1", "b"]]
      []
      12"a1b2"
      43200
      1800
      nil
      #<MatchData "2">
      true
      #<MatchData "2">
      #<MatchData "1">
      true
      #<MatchData "1">
      true
    OUT
  end

  it "regex value as match arg object recv" do
    result = ze0(<<~'RUBY')
      # Widening which regex arguments reach the string-side match path must not
      # pull an Object receiver off its own methods: a class that defines match /
      # match? answers those itself, whatever the argument expression looks like.
      # Kept apart from regex_value_as_match_arg.rb, which needs a program where
      # nothing defines #match so a poly receiver stays a String.

      class Matcher
        def match(re)
          "user match #{re.source}"
        end

        def match?(re)
          "user match? #{re.source}"
        end
      end

      m = Matcher.new

      # inline call in argument position
      p m.match(Regexp.new("\\d"))
      p m.match?(Regexp.new("\\d"))

      # a local, and a regex literal
      lv = Regexp.new("\\w")
      p m.match?(lv)
      p m.match(/\s/)

      # the String receiver in the same program still takes the regex path
      p "1d".match(Regexp.new("\\d"))
      p "1d".match?(Regexp.new("\\d"))
    RUBY

    _(result).must_answer <<~'OUT'
      "user match \\d"
      "user match? \\d"
      "user match? \\w"
      "user match \\s"
      #<MatchData "1">
      true
    OUT
  end

  it "alternation takes the leftmost branch that lets the whole match succeed" do
    result = ze0(<<~'RUBY')
      # Imported mruby-regexp alternation-priority fixes (leftmost-first).
      #
      # 4abed83f4: the linear-time Pike VM had no priority cut, so it kept the
      # longest match rather than the first alternative Ruby prefers.
      # 0df28ba5b: a 3+ branch SPLIT chain unwound its jump targets in reverse,
      # mis-ranking the middle branches.

      p(/a|ab/.match("ab")[0])              # "a"   (first alternative wins)
      p(/ab|a/.match("ab")[0])              # "ab"
      p(/cat|car|cart/.match("cart")[0])    # "car"
      p(/foo|foobar|foob/.match("foobar")[0]) # "foo"
      p(/one|two|three|four/.match("three")[0]) # "three"

      # Greedy quantifiers still take the longest match (a surviving higher-priority
      # thread overrides in a later step).
      p(/\d+|\d/.match("123")[0])           # "123"
      p(/a+|a/.match("aaa")[0])             # "aaa"
      p(/(ab)+|x/.match("abab")[0])         # "abab"

      # Captures across an alternation stay correct.
      p(/(foo)|(bar)/.match("bar").captures)   # [nil, "bar"]
      p(/(a)(b)|(c)/.match("ab").captures)     # ["a", "b", nil]

      # Alternation inside a group, with a suffix that forces a specific branch.
      p(/(cat|cats)dog/.match("catsdog")[0])   # "catsdog"
      p(/(cat|cats)$/.match("cats")[1])        # "cats"

      # scan over alternation
      p("a1b2".scan(/[a-z]|\d/))               # ["a","1","b","2"]
    RUBY

    _(result).must_answer <<~'OUT'
      "a"
      "ab"
      "car"
      "foo"
      "three"
      "123"
      "aaa"
      "abab"
      [nil, "bar"]
      ["a", "b", nil]
      "catsdog"
      "cats"
      ["a", "1", "b", "2"]
    OUT
  end

  it "a quantified atomic group keeps what it consumed and never gives it back" do
    result = ze0(<<~'RUBY')
      # Inserting a quantifier's SPLIT ahead of an atom relocates every jump target
      # that crosses the insertion, and the atomic group carries one in the same
      # field as the lookarounds do. It was left out of that walk, so `(?>a?)*` kept
      # the target the atom had before the insertion -- one short, which is the
      # sub-pattern's own MATCH. The match ended there, and the outer SAVE that
      # records where group 0 ends never ran.
      def show(re, s)
        m = re.match(s)
        p(m ? [m.begin(0), m.end(0), m[0]] : nil)
      end

      show(/(?>a?)*/, "b")
      show(/(?>a?)*/, "a")
      show(/(?>a?)*b/, "b")
      show(/x(?>a?)*/, "xb")
      show(/(?>a?)+/, "b")
      show(/(?>a?)?/, "b")
      show(/(?>a?){2}/, "b")
      show(/(?>a*)*/, "aab")
      show(/(?>ab|a)*c/, "abac")
      show(/(?>\d+)?x/, "12x")
      p "aaab".match(/(?>a*)ab/)
      p "aaa".scan(/(?>a)?/).size
    RUBY

    _(result).must_answer <<~'OUT'
      [0, 0, ""]
      [0, 1, "a"]
      [0, 1, "b"]
      [0, 1, "x"]
      [0, 0, ""]
      [0, 0, ""]
      [0, 0, ""]
      [0, 2, "aa"]
      [0, 4, "abac"]
      [0, 3, "12x"]
      nil
      4
    OUT
  end

  it "a backreference under /i matches the other case of what the group took" do
    result = ze0(<<~'RUBY')
      # GAP -- imported from the spinel corpus at fa06b601.
      #
      # A backreference compares case-SENSITIVELY even when the pattern is folded,
      # so `/(a)\1/i` does not match `"aA"` where CRuby's does.
      #
      # The comparison is a plain byte compare; under `/i` it has to fold both
      # sides the way the rest of the pattern already does.
      #
      # The original header follows. It describes the PREDECESSOR project's
      # version of this test and its own fix, not zeo's divergence above.
      #
      # The backreference comparison was a plain memcmp, so it stayed case-sensitive
      # even when the rest of the pattern was folded. Ported from mruby-regexp
      # (f9adb3017); folding stops at ASCII, as it does everywhere else here.
      p("aA" =~ /(a)\1/i ? true : false)
      p("aA" =~ /(a)\1/ ? true : false)
      p("abAB" =~ /(ab)\1/i ? true : false)
      p("aa" =~ /(a)\1/ ? true : false)
      p("aA" =~ /(a)\k<1>/i ? true : false)
      p("aA".match(/(?<g>a)\k<g>/i)[0])
      p("aA".match(/(?'g'a)\k'g'/i)[0])
      p "xAxa".scan(/(a)\1/i).size
      p("ÄÄ" =~ /(Ä)\1/i ? true : false)
    RUBY

    _(result).must_answer <<~'OUT'
      true
      false
      true
      true
      true
      "aA"
      "aA"
      0
      true
    OUT
  end

  it "a {0,m} quantifier may match nothing at all" do
    result = ze0(<<~'RUBY')
      # Imported mruby-regexp e246b2c05: {0,m} matched one copy too many. The
      # quantifier compiler emitted the atom once up front and counted it as the
      # first mandatory copy, which is wrong when the lower bound is zero. {0,m}/{0,}
      # now compile as {1,m}/{1,} wrapped in an optional split, and {0} drops the copy.

      p(/a{0,2}/.match("aaaa")[0])      # "aa"
      p(/\d{0,3}/.match("12345")[0])    # "123"
      p(/a{0,2}b/.match("aaab")[0])     # "aab"
      p("aaaa".scan(/a{0,2}/))          # ["aa", "aa", ""]
      p(/x{0,0}/.match("xxx")[0])       # ""
      p(/a{0}/.match("aaa")[0])         # ""  ({0} matches zero)
      p(/a{0,}/.match("aaaa")[0])       # "aaaa"  ({0,} == a*)
      p(/a{0,}b/.match("b")[0])         # "b"
      p(/a{0,}/.match("bbb")[0])        # ""  (zero a's)

      # Non-zero lower bounds and exact counts unchanged.
      p(/a{1,3}/.match("aaaaa")[0])     # "aaa"
      p(/a{2,4}/.match("aaaaaa")[0])    # "aaaa"
      p(/a{3}/.match("aaaaa")[0])       # "aaa"
      p(/a{2,}/.match("aaaa")[0])       # "aaaa"
      p(/\d{0,2}-\d{0,2}/.match("12-34")[0]) # "12-34"

      # Non-greedy zero-lower.
      p(/a{0,3}?/.match("aaa")[0])      # ""
      p("aaa".match(/a{0,3}?b?/)[0])    # ""
    RUBY

    _(result).must_answer <<~'OUT'
      "aa"
      "123"
      "aab"
      ["aa", "aa", ""]
      ""
      ""
      "aaaa"
      "b"
      ""
      "aaa"
      "aaaa"
      "aaa"
      "aaaa"
      "12-34"
      ""
      ""
    OUT
  end

  it "a repetition whose body may match empty ends on an empty capture" do
    result = ze0(<<~'RUBY')
      # GAP -- imported from the spinel corpus at fa06b601.
      #
      # A repetition whose body can match EMPTY runs one final iteration that
      # consumes nothing, and CRuby's captured group holds the empty string at the
      # position the loop stopped at. zeo's holds the last non-empty match instead,
      # so the group and the overall match disagree about where the loop ended.
      #
      # The original header follows. It describes the PREDECESSOR project's
      # version of this test and its own fix, not zeo's divergence above.
      #
      # A repetition whose body can match empty runs one final iteration that
      # consumes nothing, and that iteration is the one that ends the loop: the group
      # inside it holds the empty string at the position the loop stopped at. The VM
      # stopped one iteration earlier, so the group still held the text of the last
      # iteration that consumed something. Ported from mruby-regexp (45c588a83).
      p "a".match(/(a?)*/)[1]
      p "a".match(/(a?)*/).begin(1)
      p "aab".match(/(a*)*b/)[1]
      p "a".match(/(a?)+/)[1]
      p "b".match(/(a?)*/)[1]
      p "b".match(/(a*)*b/)[1]
      p "a".match(/(|a)*/)[0]
      p "ab".split(/(a?)*/, -1)
      p "ab".scan(/(a?)*/)

      # a body that always consumes keeps its single-pass walk
      p "aaa".match(/(a)*/)[1]
      p "aaa".match(/(a)+/)[0]
      p "abc".scan(/x?/).size
      p "xayb".scan(/(a|b)/).flatten
      p "aaa".gsub(/a*/, "-")
    RUBY

    _(result).must_answer <<~'OUT'
      ""
      1
      ""
      ""
      ""
      ""
      ""
      ["", "", "b", "", ""]
      [[""], [""], [""]]
      "a"
      "aaa"
      4
      ["a", "b"]
      "--"
    OUT
  end

  it "under /x the whitespace and comments in a pattern are not part of it" do
    result = ze0(<<~'RUBY')
      # Under `/x` the `regex` crate strips whitespace INSIDE a character class as
      # well as outside it -- unlike Ruby, which only ignores it between tokens. That
      # matters because zeo expands `\s` to a class, so a literal space written as one
      # of its members disappeared and `/\s/x` stopped matching a space.
      p(/\s/x =~ " ")
      p(/\S/x =~ "a")
      p(/a\s+b/x =~ "a b")
      p(/\A\s*(\d{1,2})/x =~ " 15")
      p($1)
      p(/\s/x.match?("\t"))
      p(/\s/x.match?("\n"))
      p(/\s/x.match?("\v"))
      p(/\s/x.match?("x"))

      # Written inside a class, and negated there.
      p(/[\s]/x =~ " ")
      p(/[^\s]/x =~ " a")
      p(/[\sx]/x =~ " ")

      # The other shorthand classes expand the same way and were never affected --
      # they carry no literal whitespace.
      p(/\d/x =~ "7")
      p(/\w/x =~ "_")
      p(/\h/x =~ "f")

      # Without `/x` nothing changed.
      p(/\s/ =~ " ")
      p(/[\s]/ =~ " ")

      # The shape this was found in: an RFC 2822 date, whose pattern is written
      # across several lines and so must be `/x`.
      re = /\A\s*
            (?:(?:Mon|Tue|Wed|Thu|Fri|Sat|Sun)\s*,\s*)?
            (\d{1,2})\s+
            (Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)\s+
            (\d{2,})\s+
            (\d{2})\s*
            :\s*(\d{2})
            (?:\s*:\s*(\d\d))?\s+
            ([+-]\d{4}|UT|GMT|EST|EDT|CST|CDT|MST|MDT|PST|PDT|[A-IK-Z])/ix
      p(re =~ "Mon, 15 Jan 2024 10:30:00 +0900")
      p [$1, $2, $3, $4, $5, $6, $7]
      p(re =~ "5 Feb 24 09:08 GMT")
      p [$1, $2, $3, $4, $5, $6, $7]
      p(re =~ "not a date")

      # A `#` comment is still a comment under `/x`, and an ESCAPED space still
      # matches one.
      p(/a # trailing comment
        b/x =~ "ab")
      p(/a\ b/x =~ "a b")
    RUBY

    _(result).must_answer <<~'OUT'
      0
      0
      0
      0
      "15"
      true
      true
      true
      false
      0
      1
      0
      0
      0
      0
      0
      0
      0
      ["15", "Jan", "2024", "10", "30", "00", "+0900"]
      0
      ["5", "Feb", "24", "09", "08", nil, "GMT"]
      nil
      0
      0
    OUT
  end

  it "^ and $ anchor to a line, where \\A and \\z anchor to the subject" do
    result = ze0(<<~'RUBY')
      # Ruby's ^ and $ are always line-anchored, independent of the /m flag
      # (which in Ruby only makes `.` match newlines). ^ matches at the start
      # of the string and after any newline; $ matches at the end and before
      # any newline. \A / \z / \Z are the absolute-boundary anchors.

      # $ matches before a trailing newline (the each_line + capture pattern).
      m = "FontName Times\n".match(/^(\w+) (.+)$/)
      p m[1]
      p m[2]

      # ^ and $ at interior line boundaries.
      p "a\nb\nc".scan(/^\w/)
      p "a\nb\nc".scan(/\w$/)
      p "foo 1\nbar 2".scan(/^(\w+) (\d+)$/)

      # Building a lookup table from "key value\n" lines with a $-anchored regex.
      table = {}
      "Name Ada\nLang Ruby\nYear 1995".each_line do |line|
        if (m = line.match(/^(\w+) (.+)$/))
          table[m[1]] = m[2]
        end
      end
      p table.keys
      p table["Name"]
      p table["Lang"]
      p table["Year"]

      # Absolute anchors are NOT line-anchored.
      p "abc\n".match?(/c$/)
      p "abc".match?(/b$/)
      p "a\nb".match?(/\Ab/)
      p "a\n".match?(/a\z/)
      p "a\n".match?(/a\Z/)
      p "a".match?(/a\z/)
    RUBY

    _(result).must_answer <<~'OUT'
      "FontName"
      "Times"
      ["a", "b", "c"]
      ["a", "b", "c"]
      [["foo", "1"], ["bar", "2"]]
      ["Name", "Lang", "Year"]
      "Ada"
      "Ruby"
      "1995"
      true
      false
      false
      false
      true
      true
    OUT
  end

  it "every literal pattern in a program compiles at startup" do
    result = ze0(<<~'RUBY')
      # Every literal pattern is compiled at startup into its own slot. A refusal
      # there used to leave the slot NULL for the first match to dereference; it now
      # reports and stops, the way CRuby refuses to run a file whose literal does not
      # parse. This holds the compiling half -- the refusing half ends the process,
      # so it cannot be a program that also prints.
      p("aa" =~ /(?'x'a)\k'x'/)
      p("ab" =~ /(?:)*/)
      p("ab" =~ /(?#c)a/)
      p(/a/.source)
    RUBY

    _(result).must_answer <<~'OUT'
      0
      0
      0
      "a"
    OUT
  end

  it "a lookbehind of alternatives matches at the position after any of them" do
    result = ze0(<<~'RUBY')
      # A lookbehind was measured by walking its code, and the walk gave up at the
      # first alternation -- "for simplicity", though branches of the same width are
      # as measurable as a plain sequence. Both branches are measured now and the
      # lookbehind is accepted when they agree in characters, which is the unit the
      # rewind uses; branches of different widths have no single answer and are still
      # refused. Found by a differential fuzzer against CRuby.
      def show(src, s)
        m = Regexp.new(src).match(s)
        p(m ? [m.begin(0), m[0]] : nil)
      rescue => e
        p e.class
      end

      show('(?<=a|b)c', "ac")
      show('(?<=a|b)c', "bc")
      show('(?<=a|b)c', "cc")
      show('(?<=ab|cd)e', "abe")
      show('(?<=ab|cd)e', "cde")
      show('(?<=あ|い)b', "あb")
      show('(?<=あ|い)b', "うb")
      show('\w+(?<=[^ab]|µ)', "xyz")
      show('(?<!a|b)c', "xc")
      show('(?<!a|b)c', "ac")
      show('(?<=(a|b))c', "ac")
      show('(?<=a|b|c)d', "cd")

      # Branches of DIFFERENT widths keep no single rewind and are still refused, as
      # every other variable-length lookbehind is: `(?<=ab|c)e` raises RegexpError
      # here where CRuby matches. That refusal cannot be a line of this test, since
      # the expected output is CRuby's.
    RUBY

    _(result).must_answer <<~'OUT'
      [1, "c"]
      [1, "c"]
      nil
      [2, "e"]
      [2, "e"]
      [1, "b"]
      nil
      [0, "xyz"]
      [1, "c"]
      nil
      [1, "c"]
      [1, "d"]
    OUT
  end

  it "a lookbehind counts characters, not bytes" do
    result = ze0(<<~'RUBY')
      # A lookbehind was measured and rewound in BYTES, so a class or a `.` inside
      # one -- each of which matches a character of whatever width -- landed the
      # rewind in the middle of a character (a silent no-match), and `.` was refused
      # outright for having no fixed byte length. Measuring and rewinding in
      # characters is what CRuby does. Ported from mruby-regexp (103e1a8bc,
      # 3df2926a1, bd21fe4aa).
      p("あb" =~ /(?<=[あい])b/ ? true : false)
      p("ab" =~ /(?<=[ab])b/ ? true : false)
      p("ab" =~ /(?<=[^x])b/ ? true : false)
      p("あb" =~ /(?<=[^x])b/ ? true : false)
      p("ab" =~ /(?<=.)b/ ? true : false)
      p("あb" =~ /(?<=.)b/ ? true : false)
      p("あいb" =~ /(?<=あい)b/ ? true : false)
      p("あb" =~ /(?<!あ)b/ ? true : false)
      p("いb" =~ /(?<!あ)b/ ? true : false)
      p "aあb".sub(/(?<=あ)b/, "-")
      p "aあbあb".gsub(/(?<=あ)b/, "-")
      p("あいうb".match(/(?<=..)うb/) ? true : false)
      p "xyz".match(/(?<=xy)z/)[0]
      p("b" =~ /(?<=a)b/ ? true : false)
    RUBY

    _(result).must_answer <<~'OUT'
      true
      true
      true
      true
      true
      true
      true
      false
      true
      "aあ-"
      "aあ-あ-"
      true
      "z"
      false
    OUT
  end

  it "compilation, named captures and unicode classes work in the binary" do
    result = ze0(<<~'RUBY')
      # The regexp engine is linked: compilation, named captures and unicode
      # classes all work in the binary.
      m = "2026-09-02".match(/(?<y>\d{4})-(?<m>\d{2})-(?<d>\d{2})/)
      puts m[:y], m[:m], m[:d]
      p "café niño".scan(/\p{L}+/)
      p "a1b22c333".gsub(/\d+/) { |d| "<#{d.length}>" }
    RUBY

    _(result).must_answer <<~'OUT'
      2026
      09
      02
      ["café", "niño"]
      "a<1>b<2>c<3>"
    OUT
  end

  it "Regexp#match with a block yields the MatchData and answers the block's value" do
    result = ze0(<<~'RUBY')
      # GAP -- imported from the spinel corpus at c55d9bdb.
      # Regexp#match with a block returns the MatchData instead of the block's
      # value.
      #
      # `re.match(str) { |m| ... }` yields the MatchData on a hit and evaluates to
      # the block's value. Only the String-receiver form had the arm, so with a
      # Regexp receiver the block never ran and the MatchData itself was the value.
      p(/a/.match("bab") { |m| m.begin(0) })
      p(/(a)/.match("bab") { |m| m[1] })
      p(/z/.match("bab") { |m| m.begin(0) })

      a = /(a)/
      p(a.match("bab") { |m| m[1] })
      p(a.match("zzz") { |m| m[1] })

      # the String-receiver form and the blockless forms are unchanged
      p("bab".match(/a/) { |m| m.begin(0) })
      p(/a/.match("bab"))
      p(a.match("bab"))
      p(/z/.match("bab"))
    RUBY

    _(result).must_answer <<~'OUT'
      1
      "a"
      nil
      "a"
      nil
      1
      #<MatchData "a">
      #<MatchData "a" 1:"a">
      nil
    OUT
  end

  it "match answers a MatchData that reads its groups by index" do
    result = ze0(<<~'RUBY')
      # Issue #867: String#match and Regexp#match return a MatchData-like
      # object instead of falling through to unresolved-call emit-0.
      md1 = "hello world".match(/\w+/)
      puts md1[0]

      md2 = /(\w+) (\w+)/.match("hello world")
      puts md2[0]
      puts md2[1]
      puts md2[2]

      md3 = "a".match(/(a)(b)?/)
      puts md3[2].nil? ? "nil capture" : "bad capture"
      puts "abc".match(/z/).nil? ? "nil match" : "bad match"

      md4 = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa".match(/(a)(a)(a)(a)(a)(a)(a)(a)(a)(a)(a)(a)(a)(a)(a)(a)(a)(a)(a)(a)(a)(a)(a)(a)(a)(a)(a)(a)(a)(a)(a)(a)(a)/)
      puts md4.length
      puts md4[31]
    RUBY

    _(result).must_answer <<~'OUT'
      hello
      hello world
      hello
      world
      nil capture
      nil match
      34
      a
    OUT
  end

  it "match? takes a start offset, and a negative one counts from the end" do
    result = ze0(<<~'RUBY')
      # Issue #869: Regexp#match?(str, pos) starts matching at byte
      # offset `pos`. Previously the position argument was silently
      # dropped and the call returned true for any non-empty pattern.
      puts /world/.match?("hello world", 6)
      puts /hello/.match?("hello world", 6)
      puts /hello/.match?("hello world")
      puts /world/.match?("hello world", -5)
    RUBY

    _(result).must_answer <<~'OUT'
      true
      false
      true
      true
    OUT
  end

  it "MatchData reports size, captures, offsets, names and named_captures" do
    result = ze0(<<~'RUBY')
      # MatchData carries its capture positions in the same block as the struct,
      # sized to the match. The read of the last group is what a mis-sized block
      # would get wrong, so the widest pattern this engine allows is exercised here
      # along with the narrow ones.
      m = "hello world".match(/(\w+) (\w+)/)
      p [m.size, m[0], m[1], m[2], m[3]]
      p m.pre_match
      p m.post_match
      p m.begin(0)
      p m.begin(2)
      p m.to_a
      p m.captures

      # no groups at all: the block is just the whole-match pair
      m0 = "abc".match(/b/)
      p [m0.size, m0[0], m0[1]]

      # an unmatched group in the middle keeps its neighbours' positions
      m1 = "ac".match(/(a)(b)?(c)/)
      p [m1.size, m1[1], m1[2], m1[3]]
      p m1.to_a

      # the widest pattern the registers hold: every group must read back
      src = (1..31).map { "(a)" }.join
      w = ("a" * 31).match(Regexp.new(src))
      p w.size
      p [w[1], w[15], w[30], w[31]]
      p w.captures.length
      p w.captures.uniq
      p w.begin(31)
      p w.end(31)

      # named groups reach the same positions
      n = "2026-08-25".match(/(?<y>\d+)-(?<mo>\d+)-(?<d>\d+)/)
      p [n[:y], n[:mo], n[:d]]
      p n.names
      p n.named_captures

      # $~ goes through the same block
      "xyz" =~ /(y)(z)/
      p [$~.size, $~[1], $~[2], $1, $2]
    RUBY

    _(result).must_answer <<~'OUT'
      [3, "hello world", "hello", "world", nil]
      ""
      ""
      0
      6
      ["hello world", "hello", "world"]
      ["hello", "world"]
      [1, "b", nil]
      [4, "a", nil, "c"]
      ["ac", "a", nil, "c"]
      32
      ["a", "a", "a", "a"]
      31
      ["a"]
      30
      31
      ["2026", "08", "25"]
      ["y", "mo", "d"]
      {"y" => "2026", "mo" => "08", "d" => "25"}
      [3, "y", "z", "y", "z"]
    OUT
  end

  it "\\k<name> matches what the group of that name took" do
    result = ze0(<<~'RUBY')
      # Imported mruby-regexp engine fix.
      #
      # 581092a75 (\k<name> named backreferences): named groups (?<n>...) existed but
      # \k<name> / \k'name' to reference them did not, so /(?<n>\w+)\k<n>/ never
      # matched. Numeric \k<1> (absolute) and relative \k<-1> forms also resolve to
      # the existing RE_BACKREF opcode.
      p(/(?<n>\w+)\k<n>/.match?("abcabc"))           # true
      p(/(?<n>\w+)\k<n>/.match?("abcdef"))           # false
      p(/(?<n>\w+)\k<n>/.match("abcabc")[0])         # "abcabc"
      p(/(?<n>\w+)\k<n>/.match("abcabc")[1])         # "abc"
      p(/(?<a>.)(?<b>.)\k<a>\k<b>/.match?("xyxy"))   # true
      p(/(?<a>.)(?<b>.)\k<a>\k<b>/.match?("xyyx"))   # false
      p(/(\w)\k<1>/.match?("zz"))                    # true (numeric)
      p(/(\w)\k<1>/.match?("xy"))                    # false
      p(/(.)\k<-1>/.match?("aa"))                    # true (relative)
      p(/(?<n>\w+)\k'n'/.match?("abcabc"))           # true (quote form)
    RUBY

    _(result).must_answer <<~'OUT'
      true
      false
      "abcabc"
      "abc"
      true
      false
      true
      false
      true
      true
    OUT
  end

  it "a named capture reads by name, and =~ on a literal assigns the locals" do
    result = ze0(<<~'RUBY')
      # A literal regexp on the left of `=~` binds each named group to a local
      # variable (CRuby's MatchWriteNode): a String when the group participated, nil
      # otherwise. The `=~` itself yields the match index, or nil on no match. The
      # subject string is a local so the match runs at runtime.

      date = "2026-06-15"
      if /(?<year>\d+)-(?<mon>\d+)-(?<day>\d+)/ =~ date
        puts year
        puts mon
        puts day
      end

      # the bound locals are usable as ordinary strings
      if /(?<word>\w+)/ =~ "hello"
        puts word.upcase
        puts word.length
      end

      # interpolation with two captures
      pair = "key=value"
      if /(?<k>\w+)=(?<v>\w+)/ =~ pair
        puts "#{k} -> #{v}"
      end

      # a group that did not participate binds nil
      if /(?<a>x)(?<b>y)?/ =~ "x"
        p a
        p b
      end

      # the value of `=~` is the match index, or nil on no match
      p(/(?<n>\d+)/ =~ "abc123")
      p(/(?<n>\d+)/ =~ "no digits here")

      # in a ternary / value position
      s = "id-7"
      label = (/(?<num>\d+)/ =~ s) ? "has #{num}" : "none"
      puts label

      # no match leaves the captures nil
      /(?<gone>\d+)/ =~ "letters"
      p defined?(gone)
      p gone
    RUBY

    _(result).must_answer <<~'OUT'
      2026
      06
      15
      HELLO
      5
      key -> value
      "x"
      nil
      3
      nil
      has 7
      "local-variable"
      nil
    OUT
  end

  it "a pattern with a named group has no numbered captures" do
    result = ze0(<<~'RUBY')
      m001 = "a1".match(/(?<l>[a-z])(\d)/)
      p m001.captures
      p m001.to_a
      p m001.size
      "a1" =~ /(?<l>[a-z])(\d)/
      p $~.size
      p m001[:l]
      p m001[1]
      p(/(?<l>[a-z])(\d)/.names)
      p "a1".match(/([a-z])(\d)/).captures
    RUBY

    _(result).must_answer <<~'OUT'
      ["a"]
      ["a1", "a"]
      2
      2
      "a"
      "a"
      ["l"]
      ["a", "1"]
    OUT
  end

  it "Regexp.new builds from a string and reports its source" do
    result = ze0(<<~'RUBY')
      # `Regexp.new` builds a Regexp from a pattern string (or copies another
      # Regexp). A second argument sets flags: an Integer OR-ing the `Regexp::`
      # constants, or the historical boolean shorthand for case-insensitivity.
      re = Regexp.new("ab+c")
      p re                                      # /ab+c/
      p(re =~ "xabbbc")                         # 1
      p re.match?("nope")                       # false

      ci = Regexp.new("hello", Regexp::IGNORECASE)
      p ci.match?("HELLO")                      # true

      # The flag bits combine.
      both = Regexp.new("a.b", Regexp::IGNORECASE | Regexp::MULTILINE)
      p both.match?("A\nB")                     # true

      # `true` is the boolean shorthand for case-insensitive.
      p Regexp.new("x", true).match?("X")       # true

      # A Regexp source is copied verbatim, flags and all.
      p Regexp.new(/foo/i).match?("FOO")        # true
      p Regexp.new("ab+c").source               # "ab+c"
    RUBY

    _(result).must_answer <<~'OUT'
      /ab+c/
      1
      false
      true
      true
      true
      true
      "ab+c"
    OUT
  end

  it "Regexp.new takes another Regexp and copies its source and flags" do
    result = ze0(<<~'RUBY')
      p(Regexp.new("a.c") =~ "xabc")
      p Regexp.new("hi", Regexp::IGNORECASE).match?("HI")
      p Regexp.new(/z/i).match?("Z")
      p Regexp.new("a.c").source
    RUBY

    _(result).must_answer <<~'OUT'
      1
      true
      true
      "a.c"
    OUT
  end

  it "a Regexp.new pattern matches a subject that arrives boxed" do
    result = ze0(<<~'RUBY')
      # Regexp#match on a Regexp.new pattern has to accept a subject that arrives
      # boxed: one call site handing it an untyped block parameter is enough to
      # widen the method's parameter, and the subject then reaches the runtime as a
      # boxed value rather than a C string.
      RE = Regexp.new("\\A(?<id>\\d+)\\z")

      def m(path) = RE.match(path)
      def mp(path) = RE.match?(path)
      def mat(path, pos) = RE.match(path, pos)

      EMPTY = [].freeze
      EMPTY.each { |path| p m(path) }
      EMPTY.each { |path| p mp(path) }

      p m("42")[:id]
      p m("x").nil?
      p mp("42")
      p mp("x")
      p mat("42", 0)[0]

      # a boxed subject that really is a String still matches
      subjects = ["42", "x"]
      subjects.each { |s| p RE.match(s).nil? }
    RUBY

    _(result).must_answer <<~'OUT'
      "42"
      true
      true
      false
      "42"
      false
      true
    OUT
  end

  it "an alternation whose winning branch is not the first keeps its capture" do
    result = ze0(<<~'RUBY')
      # Imported mruby-regexp engine fixes.
      #
      # c0c8c7d47 (capture loss in Pike VM thread compaction): an alternation whose
      # winning branch is not the first one used to come back with a nil capture,
      # because the per-step compaction renumbered capture slots in place and a low
      # slot was clobbered before a later thread read it.
      p(/(\d)|(x)/.match("1").captures)        # ["1", nil]
      p(/(a)|(b)|(c)/.match("b").captures)     # [nil, "b", nil]
      p(/(a)|(b)|(c)/.match("c").captures)     # [nil, nil, "c"]
      p(/(foo)|(bar)|(baz)/.match("baz")[3])   # "baz"
      p("a1b2".scan(/(\d)|([a-z])/))           # [[nil,"a"],["1",nil],[nil,"b"],["2",nil]]

      # 6d99e8dec (multiline ^ after final newline): a trailing '\n' does not start a
      # new line, so ^ must not match at end-of-string.
      p("a\n".scan(/^/).size)                  # 1
      p("a\nb\n".scan(/^/).size)               # 2
      p(/^$/.match?("a\n"))                    # false
      p("x\n".match?(/x$/))                    # true  ($ still matches before \n)
      p("a\nb".scan(/^./))                     # ["a", "b"]
    RUBY

    _(result).must_answer <<~'OUT'
      ["1", nil]
      [nil, "b", nil]
      [nil, nil, "c"]
      "baz"
      [[nil, "a"], ["1", nil], [nil, "b"], ["2", nil]]
      1
      2
      false
      true
      ["a", "b"]
    OUT
  end

  it "a quantified alternation backtracks into its other branch" do
    result = ze0(<<~'RUBY')
      # Imported mruby-regexp da41af3c9: keep a quantifier's loop-back after an
      # alternation SPLIT is inserted in front of its atom. A greedy `\d+` compiles
      # to the class plus a SPLIT looping back to it; when that class also starts
      # the first alternative, compile_alt inserts the alternation SPLIT in front of
      # it, shifting the class down. The loop-back target equalled the insertion
      # point and used to be left pointing at the new SPLIT, so `/\d+|\w/` matched
      # "1b" on "1b2c3" by falling into the alternation after one digit.

      p(/\d+|\w/.match("1b2c3")[0])     # "1"
      p(/a+|b/.match("aaab")[0])        # "aaa"
      p(/[0-9]+|z/.match("42z")[0])     # "42"
      p(/\w+|\d/.match("abc")[0])       # "abc"
      p(/(\d+)|(x)/.match("99").captures) # ["99", nil]

      # Quantifier kinds in front of an alternation atom still work.
      p(/a*|b/.match("aaa")[0])         # "aaa"
      p(/a?|b/.match("a")[0])           # "a"
      p(/\d{2,}|y/.match("123y")[0])    # "123"

      # Plain quantifier (no alternation) and skip-past-atom jumps unaffected.
      p(/\d+/.match("12ab")[0])         # "12"
      p(/(ab)+c/.match("ababc")[0])     # "ababc"
      p(/colou?r/.match("color")[0])    # "color"
      p(/colou?r/.match("colour")[0])   # "colour"

      # Lookaround (also routes through insert_inst) still works.
      p(/\d+(?=px)/.match("10px")[0])   # "10"
      p(/(?<=\$)\d+/.match("$50")[0])   # "50"
    RUBY

    _(result).must_answer <<~'OUT'
      "1"
      "aaa"
      "42"
      "abc"
      ["99", nil]
      "aaa"
      "a"
      "123"
      "12"
      "ababc"
      "color"
      "colour"
      "10"
      "50"
    OUT
  end

  it "(?'name'...) is the other spelling of a named group" do
    result = ze0(<<~'RUBY')
      # A named group has two spellings and the engine read both of them in \k while
      # accepting only one in a declaration: the scan that decides whether a plain
      # group still captures already knew (?'name'), so a pattern using it demoted
      # its plain groups and then fell through to a stray `?`.
      m = "abc".match(/(?'x'b)/)
      p [m[:x], m[0], m.size]

      p "abc".match(/(?<y>b)/)[:y]
      p "aa".match(/(?'z'a)\k'z'/)[0]
      p "aa".match(/(?'z'a)\k<z>/)[0]
      p "ab".match(/(a)(?'b'b)/).size
      p("x'y" =~ /(?<a'b>x'y)/ ? $~[:"a'b"] : nil)

      begin
        Regexp.new("(?'x'a")
      rescue => e
        p e.class
      end
      begin
        Regexp.new("(?<>a)")
      rescue => e
        p e.class
      end
      begin
        Regexp.new("(?''a)")
      rescue => e
        p e.class
      end
    RUBY

    _(result).must_answer <<~'OUT'
      ["b", "b", 2]
      "b"
      "aa"
      "aa"
      2
      "x'y"
      RegexpError
      RegexpError
      RegexpError
    OUT
  end

  it "a repeated group captures only its last iteration" do
    result = ze0(<<~'RUBY')
      # Imported mruby-regexp engine fix.
      #
      # f5cb8e139 (relocate internal jumps when copying a repeated group): a
      # quantifier copies its atom's bytecode for each repetition. Copying the
      # internal jump/split targets verbatim made a later copy of a grouped body
      # (e.g. (a{2,3}){2}) jump back into the first copy; the overall match still
      # landed right, but the capture recorded the wrong span. Each copy now relocates
      # its jump/split offsets, so a repeated group keeps only its last iteration,
      # like CRuby.
      p(/(a{2,3}){2}/.match("aaaaa")[0])    # "aaaaa"
      p(/(a{2,3}){2}/.match("aaaaa")[1])    # "aa"
      p(/(ab+){2}/.match("abbab")[1])       # "ab"
      p(/(\d{1,2}){3}/.match("123456")[1])  # "56"
      p(/(x{2}){2}/.match("xxxx")[1])       # "xx"
    RUBY

    _(result).must_answer <<~'OUT'
      "aaaaa"
      "aa"
      "ab"
      "56"
      "xx"
    OUT
  end

  it "two alternatives may share a capture name, and named_captures lists both slots" do
    result = ze0(<<~'RUBY')
      p(/(?<a>x)|(?<a>y)/.names)
      p("y".match(/(?<a>x)|(?<a>y)/).names)
      p(/(?<a>x)|(?<a>y)/.named_captures)
      p("y".match(/(?<a>x)|(?<a>y)/)[:a])
      p(/(?<a>x)(?<b>y)/.names)
    RUBY

    _(result).must_answer <<~'OUT'
      ["a"]
      ["a"]
      {"a" => [1, 2]}
      "y"
      ["a", "b"]
    OUT
  end

  it "a replacement string reads a group by number or by name" do
    result = ze0(<<~'RUBY')
      p "ab".sub(/(?<x>b)/, "[\\1]")
      p "abab".gsub(/(?<x>b)/, "[\\1]")
      p "ab".sub(/(?<a>a)(?<b>b)/, "[\\1\\2]")

      p "ab".sub(/(?<x>b)/, "[\\k<x>]")
      p "abab".gsub(/(?<x>b)/, "[\\k<x>]")

      p "ab".sub(/(?<x>b)/, "[\\0]")
      p "ab".sub(/(?<x>b)/, "[\\&]")
      p "ab".sub(/(?<x>b)/, "[\\+]")

      p "ab".sub(/(a)(b)/, "[\\2\\1]")
      p "abab".gsub(/(b)/, "[\\1]")

      m = /(?<x>b)/.match("ab")
      p m[1]
      p m["x"]
    RUBY

    _(result).must_answer <<~'OUT'
      "a[]"
      "a[]a[]"
      "[]"
      "a[b]"
      "a[b]a[b]"
      "a[b]"
      "a[b]"
      "a[b]"
      "[ba]"
      "a[b]a[b]"
      "b"
      "b"
    OUT
  end

  it "source is the pattern as written and options is the flag bits" do
    result = ze0(<<~'RUBY')
      # Issue #868: Regexp#source returns the original pattern string;
      # #options returns the CRuby flag bitmask (1=IGNORECASE, 2=EXTENDED,
      # 4=MULTILINE).
      # named_captures deferred -- would need a Hash + per-named-group
      # index array which the runtime doesn't expose yet.
      puts /hello/.source
      puts /hello/i.options
      puts /hello/.options
      puts /world/m.options
      puts /pat/x.options
    RUBY

    _(result).must_answer <<~'OUT'
      hello
      1
      0
      4
      2
    OUT
  end

  it "=== matches a string, which is what a case arm uses" do
    result = ze0(<<~'RUBY')
      # Regexp#=== matches a string against the pattern (the operator
      # `case x when /re/` uses). Previously fell through to the
      # unresolved-call path and raised at runtime.
      puts (/foo/ === "foobar")
      puts (/foo/ === "bar")

      case "hello"
      when /h.*o/ then puts "matched"
      else puts "no match"
      end

      case "world"
      when /^h/ then puts "starts with h"
      else puts "other"
      end
    RUBY

    _(result).must_answer <<~'OUT'
      true
      false
      matched
      other
    OUT
  end

  it "Regexp.union escapes the strings it is given" do
    result = ze0(<<~'RUBY')
      # Regexp.union builds an alternation of its operands. A String operand is
      # regexp-escaped; a (flagless) Regexp operand contributes its source; a single
      # Array argument is expanded into its elements; a single Regexp operand is
      # returned unchanged. Operands are routed through a method param where possible
      # to exercise the runtime build path too.
      def id(x); x; end

      # string operands, escaped
      p Regexp.union("a", "b").match?("xby")
      p Regexp.union("a", "b").match?("zz")
      p Regexp.union("a.c").match?("a.c")
      p Regexp.union("a.c").match?("abc")

      # regex operands (flagless) and mixed string/regex
      p Regexp.union(/a/, /b/).match?("zb")
      p Regexp.union(/foo/, "ba.r").match?("ba.r")
      p Regexp.union(/foo/, "ba.r").match?("baXr")

      # a constant bound to a regex literal resolves to its source
      PAT = /pp/
      p Regexp.union(PAT, "q").match?("ppx")

      # a single Array argument supplies the operands
      p Regexp.union(["x", "y"]).match?("zy")

      # a single operand: string is escaped, regex is returned unchanged (flags kept)
      p Regexp.union("only").match?("only")
      p Regexp.union(/sing/i).match?("SING")

      # usable as a normal Regexp (=~, non-literal string operand)
      p(Regexp.union("foo", "bar") =~ "say bar now")
      p Regexp.union(id("x"), "y").match?("zy")

      # empty union -> a pattern that never matches (CRuby's /(?!)/)
      p Regexp.union().match?("")
      p Regexp.union([]).match?("")
    RUBY

    _(result).must_answer <<~'OUT'
      true
      false
      true
      false
      true
      true
      false
      true
      true
      true
      true
      4
      true
      false
      false
    OUT
  end

  it "rindex regexp polypoly merge" do
    result = ze0(<<~'RUBY')
      # String#rindex(Regexp) keys on the rightmost match START (a later-starting
      # shorter match beats an earlier longer one), and a heterogeneous hash
      # absorbs a typed hash through merge!/update.

      p "hello".rindex(/l+/)
      p "aaa".rindex(/a+/)
      p "héllo".rindex(/l+/)
      p "abc".rindex(/x/)
      p "banana".rindex(/an/)

      h = { 1 => "a", :b => 2 }
      h.merge!({ "c" => 3.5 })
      p h
      h.update({ d: 4 }, { 5 => "e" })
      p h
    RUBY

    _(result).must_answer <<~'OUT'
      3
      2
      3
      nil
      3
      {1 => "a", b: 2, "c" => 3.5}
      {1 => "a", b: 2, "c" => 3.5, d: 4, 5 => "e"}
    OUT
  end

  it "scan block tracks the current match" do
    result = ze0(<<~'RUBY')
      # `String#scan` with a block sets `$~` to the CURRENT match on each iteration,
      # exactly as `sub`/`gsub`'s block forms do. The runtime's `scan` row collected
      # every match first and only then yielded, so `$~` sat at the LAST match for
      # every iteration; a typed fast path hid that, and it fires only when the
      # receiver is statically a String -- so a receiver that is not, or any call
      # through the dynamic path, read the wrong match.
      #
      # The `$~` a block reads belongs to the enclosing METHOD's svar scope, and
      # `$~` is frame-local: a method that matches and returns leaves the caller's
      # `$1` alone. Both rules are in play here at once.

      s = "1a2b3c"

      # The receiver is statically a String (the typed path).
      seen = []
      s.scan(/\d/) { seen << $~[0] }
      p seen

      # The same receiver reached dynamically -- an array element the compiler
      # cannot type.
      box = [s]
      seen = []
      box[0].scan(/\d/) { seen << $~[0] }
      p seen

      # A capture group: `$1` and the yielded value agree.
      pairs = []
      s.scan(/([a-z])/) { |g| pairs << [g, $1, $~[0]] }
      p pairs

      # The whole MatchData is live, not just the groups.
      around = []
      s.scan(/b/) { around << [$~.pre_match, $~.post_match] }
      p around

      # A match inside the block is what the NEXT read sees, until the next yield
      # replaces it.
      inner = []
      s.scan(/\d/) do
        "zz" =~ /(z)/
        inner << $1
      end
      p inner

      # `$~` is frame-local: the scan above ran at the top level, and a method that
      # scans leaves the caller's match alone.
      def counts(str)
        n = 0
        str.scan(/\d/) { n += 1 }
        n
      end
      "abc" =~ /(b)/
      p counts(s)
      p $1

      # A block that breaks stops the walk, and the match it broke on stands.
      "abc" =~ /(b)/
      def first_digit(str)
        str.scan(/(\d)/) { |g| break g.first }
      end
      p first_digit(s)
      p $1

      # The block form answers the RECEIVER, never the array of matches.
      p s.scan(/\d/) { }
    RUBY

    _(result).must_answer <<~'OUT'
      ["1", "2", "3"]
      ["1", "2", "3"]
      [[["a"], "a", "a"], [["b"], "b", "b"], [["c"], "c", "c"]]
      [["1a2", "3c"]]
      ["z", "z", "z"]
      3
      "b"
      "1"
      "b"
      "1a2b3c"
    OUT
  end

  it "scan locals def boundary" do
    result = ze0(<<~'RUBY')
      # #450 cascade 1. `scan_locals` walked into nested DefNode bodies
      # from any outer-context caller (notably infer_main_call_types' top-
      # level scan), pulling locals from inside unrelated methods into the
      # enclosing scope. Two methods that each defined `local_name = ...`
      # with disagreeing inferred types then collided via scan_locals'
      # repeated-write merge and widened the conflated slot to poly.
      # The poly local then poisoned every call-site arg type read of
      # that local name, propagating into callee params via the module-
      # dispatch widening arms in scan_new_calls.
      #
      # Real-world repro shape (after roundhouse-style boil-down):
      #
      #   module CgiIo
      #     def self.parse_request(env, stdin)
      #       path = env["PATH_INFO"] || "/"   # path local : nullable-via-||
      #       { path: path }
      #     end
      #   end
      #
      #   module Db
      #     def self.configure(path); ...; end  # path : should be string
      #   end
      #
      #   module Main
      #     def self.run_setup
      #       path = "/tmp/db"
      #       Db.configure(path)               # this call's arg was poly
      #                                        # because of cgi_io.parse_request's
      #                                        # path-local leakage
      #     end
      #   end
      #
      # Pin both shapes here so a future scan_locals regression that
      # re-introduces def-boundary crossing fails immediately.

      module CgiIo
        def self.parse_request(env)
          path = env["PATH_INFO"] || "/"
          { path: path }
        end
      end

      module Db
        def self.configure(path)
          "opening " + path
        end
      end

      module Main
        def self.run_setup
          db_path = "/tmp/db"
          path = (!db_path.nil? && !db_path.empty?) ? db_path : ":memory:"
          Db.configure(path)
        end
      end

      puts CgiIo.parse_request({ "PATH_INFO" => "/articles" })[:path]
      puts Main.run_setup
    RUBY

    _(result).must_answer <<~'OUT'
      /articles
      opening /tmp/db
    OUT
  end

  it "scan walkers def boundary" do
    result = ze0(<<~'RUBY')
      # Audit follow-up to #450 cascade 1. Several AST-walking helpers in
      # spinel_analyze.rb recursively descend into nested DefNode /
      # ClassNode / ModuleNode bodies without resetting scope context.
      # That leaks per-method state (locals, param-method observations,
      # push-element types) across method boundaries and pollutes the
      # outer scope. cascade 1 of #450 was scan_locals itself; this file
      # pins three siblings:
      #
      #   - scan_locals_first_type   (used by infer_lambda_param_types)
      #   - scan_poly_assigns         (used by detect_poly_locals)
      #   - collect_param_methods     (used by infer_cls_meth_param_from_body)
      #   - collect_param_push_elem_types  (used by infer_param_array_type_from_body)
      #   - scan_param_body_write_unify     (used by widen_param_types_from_body_writes)
      #
      # All of these now early-return at DefNode / ClassNode / ModuleNode.
      #
      # The shape: a top-level module with one def whose local shadows
      # an outer name. Pre-fix, the outer scope's poly-detection / param
      # inference would conflate the two and the resulting types would
      # either widen unnecessarily or fail to widen for the right call
      # site.

      module Outer
        def self.process(path)
          # `path` is the param; body uses it as a string.
          parts = path.split("/")
          parts.length
        end
      end

      # Top-level local with the same name as Outer.process's param.
      # Pre-fix, this main-level `path` would be conflated with Outer's
      # param in scan_poly_assigns / scan_locals if scan walked into
      # the module body.
      path = "/tmp/db"
      puts Outer.process(path)
      puts Outer.process("/articles/1")

      # Module with a deeper structure: two defs, each with the same
      # param name, calling each other. The cascade-1 shape.
      module Resolver
        def self.outer_resolve(path)
          inner_resolve(path)
        end

        def self.inner_resolve(path)
          path.upcase + ":" + path.length.to_s
        end
      end

      puts Resolver.outer_resolve("hello")
      puts Resolver.outer_resolve("world")
    RUBY

    _(result).must_answer <<~'OUT'
      3
      3
      HELLO:5
      WORLD:5
    OUT
  end

  it "scan with a block yields matches and returns the receiver" do
    result = ze0(<<~'RUBY')
      # The block form yields each match (a String, or an Array of groups) and
      # returns the RECEIVER, not the array of matches.

      out = []
      r = "hello world".scan(/\w+/) { |w| out << w.upcase }
      p out
      p r
      pairs = []
      "a1b2".scan(/([a-z])(\d)/) { |l, d| pairs << [l, d] }
      p pairs
    RUBY

    _(result).must_answer <<~'OUT'
      ["HELLO", "WORLD"]
      "hello world"
      [["a", "1"], ["b", "2"]]
    OUT
  end

  it "scan with a string pattern matches literally" do
    result = ze0(<<~'RUBY')
      # A String pattern is a literal (no metacharacters), matches
      # non-overlapping, and an empty pattern matches at every character
      # boundary. The block form yields each match and returns the receiver.

      p "MixedCase".scan("e")
      p "aaaa".scan("aa")
      p "abc".scan("z")
      p "café".scan("")
      matches = []
      returned = "banana".scan("an") { |m| matches << m.upcase }
      p matches
      p returned == "banana"
    RUBY

    _(result).must_answer <<~'OUT'
      ["e", "e"]
      ["aa", "aa"]
      []
      ["", "", "", "", ""]
      ["AN", "AN"]
      true
    OUT
  end

  it "scan without and with capture groups" do
    result = ze0(<<~'RUBY')
      puts "one two three".scan(/\w+/)
      puts "---"
      puts "a1b2c3".scan(/([a-z])(\d)/)
    RUBY

    _(result).must_answer <<~'OUT'
      one
      two
      three
      ---
      a
      1
      b
      2
      c
      3
    OUT
  end

  it "small api wins" do
    result = ze0(<<~'RUBY')
      require "set"
      m = "2026-06".match(/(\d+)-(\d+)/)
      p m.size
      p m.length
      p Set[1, 2, 3].join("-")
      p Complex::I
      p(Complex::I * Complex::I)
      p 5.method(:+).source_location
      p 5.method(:+).super_method
    RUBY

    _(result).must_answer <<~'OUT'
      3
      3
      "1-2-3"
      (0+1i)
      (-1+0i)
      nil
      nil
    OUT
  end

  it "str match position" do
    result = ze0(<<~'RUBY')
      # String#match and String#match? with position argument
      # The position is a codepoint index (not byte offset) that limits
      # where the regex search starts.

      # match? with position
      puts "hello".match?(/h/, 1)
      puts "hello".match?(/e/, 1)
      puts "hello".match?(/o/, -1)
      puts "hello".match?(/h/, 0)
      puts "hello".match?(/z/, 0)

      # match with position
      r = "hello".match(/h/, 1); puts r == nil ? "nil" : r[0]
      r = "hello".match(/e/, 1); puts r == nil ? "nil" : r[0]
      r = "hello".match(/o/, -1); puts r == nil ? "nil" : r[0]
    RUBY

    _(result).must_answer <<~'OUT'
      false
      true
      true
      true
      false
      nil
      e
      o
    OUT
  end

  it "strbuf index after mutation" do
    result = ze0(<<~'RUBY')
      s = String.new
      s << "abc"
      p s[0], s[2], s.length
      s << "de"
      p s[3], s[4], s[5], s.length
      s.insert(0, "Z")
      p s[0], s[1], s.length
      s.replace("hello")
      p s[0], s[4], s.length, s[1, 3], s[1..3]

      # a multibyte buffer indexes by character, not by byte
      u = String.new
      u << "あい"
      p u[0], u[1], u.length, u.bytesize
      u << "う"
      p u[2], u.length

      # the last match's $` and $' survive being read after other work
      "hello world" =~ /o w/
      mid = [$`, $&, $']
      p mid
      p "aXbXc".gsub(/X/) { "-" }
      p "one two three".sub(/two/) { |m| m.upcase }
      p [$`, $']
    RUBY

    _(result).must_answer <<~'OUT'
      "a"
      "c"
      3
      "d"
      "e"
      nil
      5
      "Z"
      "a"
      6
      "h"
      "o"
      5
      "ell"
      "ell"
      "あ"
      "い"
      2
      6
      "う"
      3
      ["hell", "o w", "orld"]
      "a-b-c"
      "one TWO three"
      ["one ", " three"]
    OUT
  end

  it "string index regex" do
    result = ze0(<<~'RUBY')
      # String#index with a Regexp argument returns the first match position
      # (Integer) or nil on no match, like the string-argument form. Previously the
      # regex lowered to 0 and fed a bogus arg to the plain-string index path.
      p("hello".index(/l/))
      p("hello".index(/z/))
      p("hello world".index(/o/))
      p("hello world".index(/\w+/))
      p("hello".index("l"))
      p("abcabc".index(/c/))
    RUBY

    _(result).must_answer <<~'OUT'
      2
      nil
      4
      0
      2
      2
    OUT
  end

  it "string match block" do
    result = ze0(<<~'RUBY')
      # String#match(/re/) { |m| } yields the MatchData on a hit and evaluates
      # to the block's value; nil (block not run) on a miss.
      p "foobar".match(/(o+)/) { |m| m[1].upcase }
      p "foobar".match(/xyz/) { |m| m[1] }
      r = "count=42".match(/(\d+)/) { |m| m[1].to_i * 2 }
      p r
    RUBY

    _(result).must_answer <<~'OUT'
      "OO"
      nil
      84
    OUT
  end

  it "string match operator returns char index or nil" do
    result = ze0(<<~'RUBY')
      puts("hello world" =~ /world/)
      puts("hello world" =~ /xyz/)
      puts("hello" =~ /l+/)
    RUBY

    _(result).must_answer <<~'OUT'
      6

      2
    OUT
  end

  it "string match position argument" do
    result = ze0(<<~'RUBY')
      # `String#match(pattern, pos)` starts the search at pos; zeo ignores the
      # second argument and matches from 0. `#match?` takes the same argument.
      # (Found by the 2026-08-24 probe sweep.)
      p "aXbX".match(/X/, 2).begin(0)
      p "aXbX".match?(/X/, 2)
      p "aXbX".match(/a/, 2)
    RUBY

    _(result).must_answer <<~'OUT'
      3
      true
      nil
    OUT
  end

  it "string regexp group index" do
    result = ze0(<<~'RUBY')
      # The Regexp-with-capture-group form of the String index family: `s[/re/, n]`
      # already read the group, but removing or replacing it had no arm at all --
      # slice! answered nil and left the receiver alone, and []= was refused.
      s = +"hello"
      p s.slice!(/(l)(l)/, 2)
      p s

      # the group's own span, not the first textual occurrence of its text: those
      # are different characters when the group repeats
      t = +"abab"
      p t.slice!(/(a)(b)(a)(b)/, 3)
      p t

      u = +"hello"
      p u.slice!(/l+/, 0)
      p u

      v = +"hello"
      v[/(l)(o)/, 2] = "O"
      p v

      w = +"abab"
      w[/(a)(b)(a)/, 3] = "X"
      p w

      y = +"hello"
      y[/l+/, 0] = "L"
      p y

      z = +"hello"
      begin
        z[/zz/, 1] = "q"
      rescue IndexError => e
        p e.class
      end
      p z

      # the reading forms keep working
      p "hello"[/(l)(o)/, 2]
      p "hello"[/l+/]
    RUBY

    _(result).must_answer <<~'OUT'
      "l"
      "helo"
      "a"
      "abb"
      "ll"
      "heo"
      "hellO"
      "abXb"
      "heLo"
      IndexError
      "hello"
      "o"
      "ll"
    OUT
  end

  it "string scan literal" do
    result = ze0(<<~'RUBY')
      # String#scan accepts a String pattern in both its value and block forms.
      p "MixedCase".scan("e")
      p "aaaa".scan("aa")
      p "abc".scan("z")

      pattern = "an"
      p "banana".scan(pattern)

      # An empty pattern matches at every character boundary, including both ends.
      p "abc".scan("")
      p "caf\u00e9".scan("")

      # Exercise the statement-form iterator lowering.
      statement_matches = []
      "cababa".scan("ba") { |match| statement_matches << match }
      p statement_matches

      matches = []
      source = "banana"
      returned = source.scan(pattern) { |match| matches << match.upcase }
      p matches
      p returned == source
    RUBY

    _(result).must_answer <<~'OUT'
      ["e", "e"]
      ["aa", "aa"]
      []
      ["an", "an"]
      ["", "", "", ""]
      ["", "", "", "", ""]
      ["ba", "ba"]
      ["AN", "AN"]
      true
    OUT
  end

  it "string succ scan slice tilde wave10" do
    result = ze0(<<~'RUBY')
      # String#succ carries alphanumerics only; scan with (named) capture groups
      # returns capture rows (value, block, and destructured block forms);
      # slice!(regexp); $~ is a first-class MatchData built from the registers.
      p("<<koala>>".succ)
      p("az".succ)
      p("zz".succ)
      p("a9".succ)
      p("Zz".succ)
      p("zz9".succ)
      p("1.9".succ)
      p("-9".succ)
      p("abc".succ)
      p("THX1138".succ)
      p("***".succ)
      p("1999".succ)
      p("a1b2".scan(/(?<d>\d)/))
      p("a1b2".scan(/\d/))
      p("a1b2".scan(/([a-z])(\d)/))
      "a1b2".scan(/(?<d>\d)/) { |m| p m }
      "a1b2".scan(/([a-z])(\d)/) { |x, y| p [x, y] }
      s = "hello"
      p(s.slice!(/l+/))
      p(s)
      t = "hello"
      p(t.slice!(/z+/))
      p(t)
      "hello" =~ /l(l)/
      p($~.class)
      p($~.is_a?(MatchData))
      p($~[0])
      p($~[1])
      p($~.pre_match)
      p($~.post_match)
      "zzz" =~ /q/
      p($~)
    RUBY

    _(result).must_answer <<~'OUT'
      "<<koalb>>"
      "ba"
      "aaa"
      "b0"
      "AAa"
      "aaa0"
      "2.0"
      "-10"
      "abd"
      "THX1139"
      "**+"
      "2000"
      [["1"], ["2"]]
      ["1", "2"]
      [["a", "1"], ["b", "2"]]
      ["1"]
      ["2"]
      ["a", "1"]
      ["b", "2"]
      "ll"
      "heo"
      nil
      "hello"
      MatchData
      true
      "ll"
      "l"
      "he"
      "o"
      nil
    OUT
  end

  it "succ kind flip carry and match block" do
    result = ze0(<<~'RUBY')
      # succ carries across a separator only when the alnum kind is preserved
      # ("1.9"->"2.0") and otherwise inserts ("a-9"->"a-10"); String#match with a
      # block yields the MatchData and answers the block value (nil on a miss).

      p "1.9".succ
      p "a-9".succ
      p "zz9".succ
      p "Az9".succ
      p "foobar".match(/(o+)/) { |m| m[1].upcase }
      p "foobar".match(/xyz/) { |m| m[1] }
      p("count=42".match(/(\d+)/) { |m| m[1].to_i * 2 })
    RUBY

    _(result).must_answer <<~'OUT'
      "2.0"
      "a-10"
      "aaa0"
      "Ba0"
      "OO"
      nil
      84
    OUT
  end

  it "value type tuple gc scan" do
    result = ze0(<<~'RUBY')
      class NameTag
        attr_reader :text

        def initialize(text)
          @text = text
        end
      end

      def tag_pair(i)
        return NameTag.new("label" + i.to_s), "pair" + i.to_s
      end

      pair = nil
      i = 0
      while i < 2000
        pair = tag_pair(i)
        i = i + 1
      end

      junk = []
      i = 0
      while i < 5000
        junk << "garbage" + i.to_s
        i = i + 1
      end

      puts pair[0].text
      puts pair[1]
    RUBY

    _(result).must_answer <<~'OUT'
      label1999
      pair1999
    OUT
  end
end
