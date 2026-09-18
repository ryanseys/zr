# frozen_string_literal: true

require "spec_helper"

describe "Syntax programs" do
  it "argv is seeded from the command line" do
    result = ze0(<<~'RUBY')
      # No args in this harness: ARGV exists and is empty (CRuby startup
      # parity; argv-carrying coverage lives in the conformance corpus).

      p ARGV
      puts ARGV.length
    RUBY

    _(result).must_answer <<~'OUT'
      []
      0
    OUT
  end

  it "bang op ruby truthy" do
    result = ze0(<<~'RUBY')
      # Issue #703: !0 / !:foo are false in Ruby (only nil/false are
      # falsy). spinel previously used C's `!` directly, treating 0
      # as falsy.
      puts !!0
      puts !!:foo
      puts !!""
      puts !nil
      puts !false
      puts !true
      puts !"hello"
    RUBY

    _(result).must_answer <<~'OUT'
      true
      true
      true
      true
      true
      false
      false
    OUT
  end

  it "bang result through shared handle" do
    result = ze0(<<~'RUBY')
      # A bang mutator on a String read out of a container answers the receiver on a
      # change and nil on none. The "did it change?" test compared the receiver's old
      # text against the new -- but the old text is the LIVE payload of a shared
      # handle, so once the mutation had written the new contents into it the two
      # compared equal and the method answered nil after a substitution that plainly
      # happened (#4042). The test is made before the mutation now.
      h = { a: +"abc" }
      s = h[:a]
      p s.sub!("b", "*")
      p h
      p s

      h2 = { a: +"abc" }
      t = h2[:a]
      p t.sub!("z", "*")
      p h2

      h3 = { a: +"abc" }
      u = h3[:a]
      p u.gsub!("b", "*")
      p u.upcase!
      p u.upcase!
      p u.swapcase!
      p u.reverse!
      p h3

      a = [+"abc"]
      v = a[0]
      p v.sub!("b", "*")
      p a

      # a plain local, which already worked
      w = +"abc"
      p w.sub!("b", "*")
      p w.sub!("z", "*")

      # strip!/squeeze!/chomp! answer nil when they change nothing
      x = { a: +"  pad  " }[:a]
      p x.strip!
      p x.strip!
    RUBY

    _(result).must_answer <<~'OUT'
      "a*c"
      {a: "a*c"}
      "a*c"
      nil
      {a: "abc"}
      "a*c"
      "A*C"
      nil
      "a*c"
      "c*a"
      {a: "c*a"}
      "a*c"
      ["a*c"]
      "a*c"
      nil
      "pad"
      nil
    OUT
  end

  it "bigint literal" do
    result = ze0(<<~'RUBY')
      # An integer literal wider than int64 is an arbitrary-precision Bignum in every
      # overflow mode (CRuby semantics), not a saturated int. Underscores are allowed.
      puts 100000000000000000000
      puts(-100000000000000000000)
      puts 10_000_000_000_000_000_000_000
      x = 100000000000000000000
      puts x + 1
      puts x * 3
      puts 18446744073709551616        # 2**64
      puts 99999999999999999999999999999999 - 1
    RUBY

    _(result).must_answer <<~'OUT'
      100000000000000000000
      -100000000000000000000
      10000000000000000000000
      100000000000000000001
      300000000000000000000
      18446744073709551616
      99999999999999999999999999999998
    OUT
  end

  it "bool logical operators" do
    result = ze0(<<~'RUBY')
      # TrueClass / FalseClass #& #| #^ return a boolean, not an int.
      p (true & true)
      p (true | false)
      p (true ^ false)
      p (false & true)
      p (true & false)
      p (false | false)
      p (true ^ true)
      p (false ^ false)
    RUBY

    _(result).must_answer <<~'OUT'
      true
      true
      true
      false
      false
      false
      false
      false
    OUT
  end

  it "branch empty literal" do
    result = ze0(<<~'RUBY')
      # An empty `[]` / `{}` caches TY_UNKNOWN because it has no ELEMENT type until
      # something supplies one -- not because it has no value. Every branch emitter
      # read that as "value-less tail", ran the literal for effect and left the slot
      # at its default, and every inference site let ty_unify() drop it and answer
      # whatever the OTHER arm said. So the branch answered nil, or "", or 0, or
      # refused to compile when the sibling was an Integer.
      #
      # #4102 fixed the `case` arm merged with a sibling of the same container kind.
      # This covers the rest: no sibling at all, a sibling of another kind, and the
      # if / unless / ternary / case-in forms.
      def s(l); v = yield; puts "#{l}: #{v.inspect}"; end

      s("if both empty")   { if true then [] else [] end }
      s("if no else")      { if true then [] end }
      s("if vs string")    { if true then [] else "x" end }
      s("if vs int")       { if true then [] else 1 end }
      s("unless both")     { unless false then [] else [] end }
      s("unless no else")  { unless false then [] end }
      s("ternary both")    { true ? [] : [] }
      s("ternary vs int")  { true ? [] : 1 }
      s("case both empty") { case "s" when String then [] else [] end }
      s("case no else")    { case "s" when String then [] end }
      s("case vs string")  { case "s" when String then [] else "x" end }
      s("case vs int")     { case "s" when String then [] else 1 end }
      s("case hash both")  { case "s" when String then {} else {} end }
      s("case hash vs s")  { case "s" when String then {} else "x" end }
      s("casein both")     { case 1; in Integer; []; else; []; end }
      s("casein vs int")   { case 1; in Integer; []; else; 1; end }
      s("begin both")      { begin; []; rescue; []; end }

      # what #4102 already covered stays covered
      s("case vs concrete"){ case "s" when String then [] else ["x"] end }
      s("case hash conc")  { case "s" when String then {} else { "a" => 1 } end }

      # && / || answer the same question about the same literal
      s("and")             { true && [] }
      s("or")              { false || [] }

      # the value is a real container, not one that only prints right
      def use(l); v = yield; v << 9 if v.is_a?(Array); v["k"] = 9 if v.is_a?(Hash); puts "#{l}: #{v.inspect} size=#{v.size}"; end
      use("if no else")    { if true then [] end }
      use("case vs int")   { case "s" when String then [] else 1 end }
      use("casein both")   { case 1; in Integer; []; else; []; end }
      use("hash vs s")     { case "s" when String then {} else "x" end }
    RUBY

    _(result).must_answer <<~'OUT'
      if both empty: []
      if no else: []
      if vs string: []
      if vs int: []
      unless both: []
      unless no else: []
      ternary both: []
      ternary vs int: []
      case both empty: []
      case no else: []
      case vs string: []
      case vs int: []
      case hash both: {}
      case hash vs s: {}
      casein both: []
      casein vs int: []
      begin both: []
      case vs concrete: []
      case hash conc: {}
      and: []
      or: []
      if no else: [9] size=1
      case vs int: [9] size=1
      casein both: [9] size=1
      hash vs s: {"k" => 9} size=1
    OUT
  end

  it "case empty literal branch" do
    result = ze0(<<~'RUBY')
      # An empty `[]`/`{}` literal as a `case` branch value, merged with a branch
      # of the same container kind, must build a real empty container rather than
      # a null pointer statically typed as one.
      r1 = case "s"
           when String then []
           else ["x"]
           end
      p r1                    # []
      r1.each { |e| puts e }  # nothing printed, no crash

      r2 = case "s"
           when String then {}
           else { "a" => 1 }
           end
      p r2                    # {}
      r2.each { |k, v| puts "#{k}=#{v}" }  # nothing printed, no crash

      # else-branch is the empty one.
      p(case "s"
        when Integer then [1]
        else []
        end)                   # []

      # The `case <int>` jump-table fast path lowers branch values through the same
      # emitter as the if-chain form above; keep it covered separately.
      def by_int(x)
        case x
        when 1 then []
        when 2 then [9]
        else [3]
        end
      end
      p by_int(1)              # []
      p by_int(2)              # [9]
      p by_int(3)              # [3]
      by_int(1).each { |e| puts e }  # nothing printed, no crash

      # A non-empty literal in the same position is unaffected (regression guard).
      p(case "s"
        when String then ["a"]
        else ["b"]
        end)                   # ["a"]
    RUBY

    _(result).must_answer <<~'OUT'
      []
      {}
      []
      []
      [9]
      [3]
      ["a"]
    OUT
  end

  it "empty literal operand coercion" do
    result = ze0(<<~'RUBY')
      # An empty `[]` / `{}` used as a receiver, argument, or interpolation takes
      # its kind from that use.

      # --- receivers: any method on a bare [] runs over an empty poly array
      p([] * 2)
      p([] * ",")
      p([].dup)
      p([].cycle.first(2))
      p([].chunk_while { |x, y| x == y }.to_a)
      p([].each.class)
      p([].reverse_each.class)
      p([].inject(:+))
      p([].reduce(1, :+))
      p([].sum)
      p([].max)
      p([].assoc(1))

      # --- receivers: any method on a bare {} runs over the bare hash
      p({}.slice(1))
      p({}.except(1))
      p({}.values_at(1))
      p({}.assoc(1))
      p({}.each_with_object([]) { |(k, v), m| m << k })
      p({}.reduce(0) { |s, (k, v)| s + v })
      p({}.each_pair.to_a)
      p({}.each.class)
      p({}.delete(:x))

      # --- arguments: an empty literal handed to a typed-array method takes that
      #     array's kind for the combining methods, and stays a boxed array otherwise
      a = [1, 2].sort
      b = [1.5].sort
      c = %w[x y].sort
      a.concat([]); p a
      b.concat([]); p b
      c.concat([]); p c
      p(a + [])
      p(a - [])
      p(a & [])
      p(a | [])
      p(a == [])
      p(a <=> [])
      p(a.union([]))
      p(a.difference([]))
      p(a.intersect?([]))
      p a.include?([])
      p a.index([])
      p a.rindex([])
      p a.find_index([])
      p a.member?([])
      p b.include?([])
      p c.include?([])
      p c.index([])
      p a.zip([])
      p a.product([])
      p([[1], [2]].sum([]))
      r = [3, 4].sort
      r.replace([]); p r

      # --- a bare [] receiver combined with a typed array takes that array's kind
      p([] + a)
      p([] - a)
      p([] & a)
      p([] | a)
      p([].union(a))
      p([].intersection(a))
      p([].difference(a))
      p([] + b)
      p([] + c)
      p([] == a)
      p([] <=> a)

      # --- when both operands are bare [], they share the poly-array layout
      p([] == [])
      p([] != [])
      p([] | [])

      # --- an empty [] argument on a hash receiver is a poly array
      p({}.each_with_object([]) { })
      p({"a" => 1}.each_with_object([]) { |(k, v), m| m << k })

      # --- the same mismatch with a non-empty array argument
      p a.include?([1])
      p a.index([1])
      p c.include?(1)
      p c.index(1)

      # --- interpolation
      p "#{{}}"
      p "#{[]}"
      p "x#{{}}y#{[]}z"

      # --- `h[k], h[j] = ...` on a bare {} picks the variant from its keys, like
      #     `h[k] = v` does
      hh = {}
      hh[:a], hh[:b] = 1, 2
      p hh
      hi = {}
      hi[1], hi[2] = "x", "y"
      p hi

      # --- the local back-fill is untouched
      x = []
      x << 1
      p x
      p x.sum
      y = {}
      y["k"] = 2
      p y

      # --- the seed of an array's each_with_object / inject / reduce is written
      #     through the block parameter and back-fills like a local
      z = [1, 2, 3].each_with_object([]) { |v, m| m << v * 2 }
      p z
      p z[0] + 1
      p [1, 2, 3].inject([]) { |m, v| m << v }
      p [1, 2, 3].reduce([]) { |m, v| m.push(v) }
    RUBY

    _(result).must_answer <<~'OUT'
      []
      ""
      []
      []
      []
      Enumerator
      Enumerator
      nil
      1
      0
      nil
      nil
      {}
      {}
      [nil]
      nil
      []
      0
      []
      Enumerator
      nil
      [1, 2]
      [1.5]
      ["x", "y"]
      [1, 2]
      [1, 2]
      []
      [1, 2]
      false
      1
      [1, 2]
      [1, 2]
      false
      false
      nil
      nil
      nil
      false
      false
      false
      nil
      [[1, nil], [2, nil]]
      []
      [1, 2]
      []
      [1, 2]
      []
      []
      [1, 2]
      [1, 2]
      []
      []
      [1.5]
      ["x", "y"]
      false
      -1
      true
      false
      []
      []
      ["a"]
      false
      nil
      false
      nil
      "{}"
      "[]"
      "x{}y[]z"
      {a: 1, b: 2}
      {1 => "x", 2 => "y"}
      [1]
      1
      {"k" => 2}
      [2, 4, 6]
      3
      [1, 2, 3]
      [1, 2, 3]
    OUT
  end

  it "empty literal receiver" do
    result = ze0(<<~'RUBY')
      # Methods on a bare empty-array literal receiver: the ntype pin serves
      # product/reduce/inject (a literally-empty reduce IS its init, nil
      # without one), alongside the flatten/first arms.
      p [].product([1, 2])
      p [].reduce { |a, b| a + b }
      p [].reduce(5) { |a, b| a + b }
      p [].inject { |a, b| a + b }
      p [].flatten
      p [].first
    RUBY

    _(result).must_answer <<~'OUT'
      []
      nil
      5
      nil
      []
      nil
    OUT
  end

  it "expression shapes" do
    result = ze0(<<~'RUBY')
      # Expression shapes that were previously clean compile rejections:
      # multi-value return/break/next, parenthesized statement sequences, the
      # fuller interpolation forms, and top-level instance variables.

      # --- return / break / next with several values ------------------------------
      # More than one value builds an implicit array -- the same array the
      # equivalent literal would, splats included.
      def pair
        return 1, 2
      end
      p pair

      def triple
        return 1, 2, 3
      end
      p triple

      def with_splat(a)
        return 1, *a
      end
      p with_splat([2, 3])

      # A SINGLE splat is an array too -- `return *a` where a == [1] is [1], not 1.
      def splat_only(a)
        return *a
      end
      p splat_only([1, 2])
      p splat_only([1])
      p splat_only([])

      # A bare `return` is still nil.
      def nothing
        return
      end
      p nothing

      # break/next take the same shape.
      p([1].each { break 1, 2 })
      p([[1, 2]].map { |a, b| next a, b })

      # --- parenthesized statement sequences --------------------------------------
      # `(a; b)` evaluates each in order and answers the LAST.
      p((1; 2; 3))

      # It introduces NO scope of its own -- a local assigned inside is still
      # readable afterwards.
      doubled = (n = 5; n * 2)
      p doubled
      p n

      # Newline-separated is the same construct.
      computed = (
        base = 7
        base + 1
      )
      p computed

      # In argument and element position, and nested.
      p((puts "side effect"; 42))
      p [(1; 2), 3]
      p((1; (2; 3)))

      # A statement can be any expression, including an `if`.
      p((if true then "yes" else "no" end; "after"))

      # One statement in parens is just that expression.
      p (5)

      # --- string interpolation forms ---------------------------------------------
      # Several statements inside #{ } answer the last...
      p "v=#{1; 2}"
      p "v=#{x = 3; x * 2}"
      p x                       # ...and, like parens, leak their locals

      # An empty #{} interpolates nothing.
      p "a#{}b"

      # Brace-less #@ivar / #$global interpolation.
      $greeting = "hi"

      class Speaker
        def initialize
          @name = "sam"
        end

        def to_s
          "#$greeting, #@name"
        end
      end
      puts Speaker.new

      # --- top-level instance variables -------------------------------------------
      # At the top level `self` is `main`, an ordinary object -- so `@x` there is
      # just its instance variable. A top-level `def` is a private method OF that
      # same object, so it sees the same storage.
      @config = "set at top level"
      p @config
      p @never_assigned          # nil, not an error

      def read_config
        @config
      end
      p read_config

      def bump
        @count = (@count || 0) + 1
      end
      bump
      bump
      bump
      p @count
    RUBY

    _(result).must_answer <<~'OUT'
      [1, 2]
      [1, 2, 3]
      [1, 2, 3]
      [1, 2]
      [1]
      []
      nil
      [1, 2]
      [[1, 2]]
      3
      10
      5
      8
      side effect
      42
      [2, 3]
      3
      "after"
      5
      "v=2"
      "v=6"
      3
      "ab"
      hi, sam
      "set at top level"
      nil
      "set at top level"
      3
    OUT
  end

  it "infinite generators iterate lazily" do
    result = ze0(<<~'RUBY')
      # An INFINITE generator proves the fiber suspend is real: `next`/`peek`
      # advance lazily, and `take`/`first` terminate via the Break-based early
      # exit (internal iteration restarts from scratch each time -- CRuby).

      inf = Enumerator.new do |y|
        n = 0
        loop do
          y << n
          n += 1
        end
      end
      p inf.next
      p inf.next
      p inf.peek
      p inf.next
      p inf.take(3)
      p inf.first(2)
    RUBY

    _(result).must_answer <<~'OUT'
      0
      1
      2
      2
      [0, 1, 2]
      [0, 1]
    OUT
  end

  it "the transforming bang mutators show through a container that holds the string" do
    result = ze0(<<~'RUBY')
      # Shared-mutable strings: container-held aliases observe the in-place
      # transforming mutators, not just <<.
      m = "low"
      box = [m]
      m.upcase!
      p box[0]

      s = "a"
      arr = [s]
      s << "b"
      s.upcase!
      p arr[0]

      t = "hello"
      h = { k: t }
      t.gsub!("l", "L")
      p h[:k]

      r = "abc"
      c = [r]
      r.replace("xyz")
      p c[0]

      q = "tail"
      d = [q]
      q.prepend("head-")
      p d[0]

      u = "abc"
      e = [u]
      u.reverse!
      p e[0]
      p e[0].equal?(u)

      w = "  padded  "
      f = [w]
      w.strip!
      p f[0]

      x = "prefix-body"
      g = [x]
      x.delete_prefix!("prefix-")
      p g[0]
    RUBY

    _(result).must_answer <<~'OUT'
      "LOW"
      "AB"
      "heLLo"
      "xyz"
      "head-tail"
      "cba"
      true
      "padded"
      "body"
    OUT
  end

  it "issue236 chain empty literal" do
    result = ze0(<<~'RUBY')
      # Issue #236 follow-up to #234: chained `@a = @b = {}` (or `[]`)
      # with slots promoted to a typed container (e.g. `str_str_hash`)
      # emitted a default `sp_StrIntHash *` temp and assigned it to both
      # slots, mismatching the promoted slot's pointer type. The fix
      # detects empty-literal RHS in compile_chained_ivar_writes and,
      # when every chain participant agrees on the same promoted type,
      # emits the slot-typed constructor for the temp so the assignment
      # type-checks and Ruby's "one shared object" semantic is preserved
      # (both slots receive the same pointer).

      # Hash: both slots promoted to str_str_hash via @h["k"] = "v" writes.
      class HashOwner
        def initialize
          @a = {}
          @a["seed"] = "value"
          @b = {}
          @b["seed"] = "value"
        end

        def reset
          @a = @b = {}
        end

        # Sharing test: write to @a, observe through @b. Pre-fix this
        # wouldn't compile; if the chain helper accidentally regressed to
        # per-slot constructors, sharing would be lost and @b would still
        # report length 0 after the @a write.
        def post_reset_share_check
          @a["after"] = "ok"
          puts @b.length            # 1 if shared, 0 if separate objects
          puts @b["after"]          # "ok" if shared
        end
      end

      ho = HashOwner.new
      ho.reset
      ho.post_reset_share_check

      # Array: both slots promoted to str_array via push("x"/"y").
      class ArrayOwner
        def initialize
          @a = []
          @a.push("x")
          @b = []
          @b.push("y")
        end

        def reset
          @a = @b = []
        end

        def post_reset_share_check
          @a.push("z")
          puts @b.length            # 1 if shared
          puts @b[0]                # "z" if shared
        end
      end

      ao = ArrayOwner.new
      ao.reset
      ao.post_reset_share_check

      # Three-chain to confirm the consensus check covers length-3 chains.
      class ThreeChain
        def initialize
          @a = {}; @a["s"] = "v"
          @b = {}; @b["s"] = "v"
          @c = {}; @c["s"] = "v"
        end

        def reset
          @a = @b = @c = {}
        end

        def show
          puts @a.length
          puts @b.length
          puts @c.length
        end
      end

      tc = ThreeChain.new
      tc.reset
      tc.show
    RUBY

    _(result).must_answer <<~'OUT'
      1
      ok
      1
      z
      0
      0
      0
    OUT
  end

  it "leaves" do
    result = ze0(<<~'RUBY')
      # The smaller corners of Ruby's syntax: the last-match globals, BEGIN/END,
      # undef, the alias forms, hash shorthand, interpolated symbols, and the
      # places a splat can appear.
      #
      # `__FILE__`/`__LINE__`/`__dir__` are exercised in the test suite rather than
      # here: their answers embed this file's own path, which differs per machine
      # and so can't be diffed against a fixed expectation.

      # --- BEGIN / END ------------------------------------------------------------
      # BEGIN bodies run before ANY main statement, in source order; END bodies run
      # at exit, in REVERSE order (END is `at_exit` exactly).
      END { puts "end: written first, runs last" }
      BEGIN { puts "begin: written second, runs first" }

      # --- the last-match globals -------------------------------------------------
      if "hello world" =~ /(\w+)\s(\w+)/
        p $1
        p $2
        p $3                    # a group that doesn't exist is nil
        p $&                    # the whole match
        p $`                    # before it
        p $'                    # after it
        p $~.class
      end

      # The match was at the start, so `$\`` is empty rather than nil -- nil is
      # reserved for "there was no match at all".
      "xyz" =~ /y/
      p [$`, $&, $']

      # A FAILED match CLEARS them all. This is what makes the `if ... then $1`
      # shape safe to reuse: a stale previous match can never leak through.
      "zzz" =~ /(\d+)/
      p [$1, $&, $~]

      # `match?` is the allocation-free predicate: it builds no MatchData, so it
      # leaves the slot alone.
      "abc" =~ /b/
      "xyz".match?(/y/)
      p $&                      # still "b"

      # `Regexp#match` does set it.
      /(\d)/.match("a1")
      p $1

      # `$~` is a real MatchData.
      "hello" =~ /e(l+)(o)/
      m = $~
      p m[0]
      p m[1]
      p m.captures
      p m.pre_match
      p m.post_match

      # --- named-capture auto-binding ---------------------------------------------
      # `/(?<name>..)/ =~ str` assigns each named group to a LOCAL of that name.
      if /(?<first>\w+) (?<last>\w+)/ =~ "John Smith"
        puts first
        puts last
      end

      # It still answers what `=~` answers, so it works as a condition.
      p(/(?<n>\d+)/ =~ "abc123")
      p n

      # A failed match leaves each name nil.
      /(?<z>\d+)/ =~ "none"
      p z

      # Only with the literal on the LEFT: `str =~ /(?<a>.)/` binds nothing. That
      # asymmetry is Ruby's own -- the parser can only declare the locals when it
      # can see the names.

      # --- undef ------------------------------------------------------------------
      class Base
        def inherited_m = "from Base"
        def kept = "kept"
      end

      class Child < Base
        def own_m = "own"
        undef own_m
        undef inherited_m       # works on a name this class only INHERITS
      end

      begin
        Child.new.own_m
      rescue NoMethodError
        puts "own_m: NoMethodError"
      end

      begin
        Child.new.inherited_m
      rescue NoMethodError
        puts "inherited_m: NoMethodError"
      end

      p Base.new.inherited_m    # the ancestor is untouched
      p Child.new.kept          # other inherited methods still work
      p Child.new.respond_to?(:inherited_m)

      # Several at once.
      class Multi
        def a = 1
        def b = 2
        undef a, b
      end
      p Multi.new.respond_to?(:a)

      # --- alias ------------------------------------------------------------------
      # On a method: a second name for the same body. (The `alias_method` spelling
      # is not exercised here -- it is a separate, still-open gap.)
      class Greeter
        def hello = "hi"
        alias greet hello
      end
      p [Greeter.new.hello, Greeter.new.greet]

      # On a GLOBAL: a real, bidirectional alias -- one slot, two names. Writing
      # either is visible through the other, which is why it isn't a copy.
      $orig = 5
      alias $copy $orig
      p $copy
      $copy = 7
      p $orig                   # written through the alias
      $orig = 9
      p [$orig, $copy]          # ...and through the original

      # Aliasing a never-set global is legal; both read nil until one is written.
      alias $late $not_yet_set
      p $late
      $not_yet_set = "now"
      p $late

      # --- hash shorthand ---------------------------------------------------------
      # `{x:}` means `{x: x}`.
      x = 1
      name = "shorthand"
      p({x:, name:})

      # It works for keyword arguments too.
      def describe(a:, b:)
        "#{a}/#{b}"
      end
      a = "left"
      b = "right"
      puts describe(a:, b:)

      # --- interpolated symbols ---------------------------------------------------
      who = "world"
      p :"hello_#{who}"
      p :"sum_#{1 + 1}"
      p :"plain"
      p :"a#{1}b".class

      # --- splat positions --------------------------------------------------------
      # In a `when`: every element is tested.
      small = [1, 2]
      case 1
      when *small then puts "when-splat: hit"
      else puts "when-splat: miss"
      end

      case 9
      when *small then puts "when-splat: hit"
      else puts "when-splat: miss"
      end

      # Mixed with listed values, and over a list of classes (`===` is is_a?).
      case 5
      when 3, *small, 5 then puts "when-splat: mixed hit"
      end

      kinds = [Integer, String]
      case "s"
      when *kinds then puts "when-splat: class hit"
      end

      # An empty splat matches nothing.
      case 1
      when *[] then puts "never"
      else puts "when-splat: empty ok"
      end

      # Splatting a NON-array follows Ruby's `to_a` rules.
      p [*[1, 2]]               # an Array is itself
      p [*nil]                  # nil contributes NOTHING
      p [*1]                    # no to_a: wrapped
      p [*(1..3)]               # Range#to_a
      p [*{a: 1}]               # Hash#to_a
      p [*"str"]                # NOT chars -- String has no to_a

      class HasToA
        def to_a = [7, 8]
      end
      p [*HasToA.new]           # a user to_a is honored

      # The same rules drive a splatted multi-assignment RHS.
      g, h = *1
      p [g, h]
      i, j = *[1, 2]
      p [i, j]
      k, l = *nil
      p [k, l]

      # In a `return`, and as a call argument.
      def splat_return(a)
        return *a
      end
      p splat_return([1, 2])
      p splat_return([1])       # a single splat is still an ARRAY
    RUBY

    _(result).must_answer <<~'OUT'
      begin: written second, runs first
      "hello"
      "world"
      nil
      "hello world"
      ""
      ""
      MatchData
      ["x", "y", "z"]
      [nil, nil, nil]
      "b"
      "1"
      "ello"
      "ll"
      ["ll", "o"]
      "h"
      ""
      John
      Smith
      3
      "123"
      nil
      own_m: NoMethodError
      inherited_m: NoMethodError
      "from Base"
      "kept"
      false
      false
      ["hi", "hi"]
      5
      7
      [9, 9]
      nil
      "now"
      {x: 1, name: "shorthand"}
      left/right
      :hello_world
      :sum_2
      :plain
      Symbol
      when-splat: hit
      when-splat: miss
      when-splat: mixed hit
      when-splat: class hit
      when-splat: empty ok
      [1, 2]
      []
      [1]
      [1, 2, 3]
      [[:a, 1]]
      ["str"]
      [7, 8]
      [1, nil]
      [1, 2]
      [nil, nil]
      [1, 2]
      [1]
      end: written first, runs last
    OUT
  end

  it "line anchors are always line based even without the m flag" do
    result = ze0(<<~'RUBY')
      # Real Ruby's `^`/`$` ALWAYS match at line boundaries -- there is no
      # separate opt-in the way most other regex flavors need one. `/m`
      # instead makes `.` match a newline too (verified against real `ruby`
      # directly, since this is a common point of confusion between Ruby's
      # flag vocabulary and most other engines').

      puts("line1\nline2" =~ /^line2/)
      s = "abc\ndef"
      puts(s =~ /c.d/)
      puts(s =~ /c.d/m)
    RUBY

    _(result).must_answer <<~'OUT'
      6

      2
    OUT
  end

  it "map bang empty receiver" do
    result = ze0(<<~'RUBY')
      # An empty receiver leaves the block's tail nothing to widen against, so a
      # statically typed tail (`0`) reached the poly slot raw where a boxed value is
      # what it holds.
      a = []
      a.map! { 0 }
      p a

      a << 1
      a.map! { |x| x + 1 }
      p a

      b = []
      b.map! { "s" }
      p b

      c = []
      c.collect! { nil }
      p c

      d = [1, "x", 2.5]
      d.map! { |v| v.to_s }
      p d

      e = []
      e.map! { |x| x }
      p e
    RUBY

    _(result).must_answer <<~'OUT'
      []
      [2]
      []
      []
      ["1", "x", "2.5"]
      []
    OUT
  end

  it "map bang widens element type" do
    result = ze0(<<~'RUBY')
      # map! REPLACES every element, so a block answering a value the receiver's
      # element type cannot hold has to widen the receiver -- the same reasoning a
      # push of a foreign element already gets. Without it the typed setter took the
      # tail raw and the C build failed.
      a = [1, 2]
      a.map! { |x| x.to_s }
      p a

      b = [1, 2]
      b.map! { |x| [x] }
      p b

      c = ["a", "bb"]
      c.map! { |s| s.length }
      p c

      d = [1.5, 2.5]
      d.collect! { |x| x > 2 }
      p d

      # A tail the element type DOES hold keeps the narrow array.
      e = [1, 2]
      e.map! { |x| x * 2 }
      p e
      p e.sum

      f = [1, 2, 3]
      f.map! { |x| x.to_s }
      p f.join("-")
    RUBY

    _(result).must_answer <<~'OUT'
      ["1", "2"]
      [[1], [2]]
      [1, 2]
      [false, true]
      [2, 4]
      6
      "1-2-3"
    OUT
  end

  it "map bang with index" do
    result = ze0(<<~'RUBY')
      # map!.with_index / collect!.with_index: collect like map.with_index,
      # then write the result back into the receiver in place; the chain
      # evaluates to the mutated receiver.
      a = [1, 2, 3]
      a.map!.with_index { |x, i| x + i }
      p a
      s = %w[a b]
      s.map!.with_index { |x, i| x * (i + 1) }
      p s
      r = [5, 6].collect!.with_index(10) { |x, i| x + i }
      p r
    RUBY

    _(result).must_answer <<~'OUT'
      [1, 3, 5]
      ["a", "bb"]
      [15, 17]
    OUT
  end

  it "mutator value forms bang nil" do
    result = ze0(<<~'RUBY')
      # String mutators as expressions (with lvalue write-back and the
      # nil-when-unchanged bang contract), Array#insert with several values
      # (negative index normalized once), Array#flatten!/uniq!/compact! as
      # expressions returning self-or-nil.
      p "ab".concat("cd")
      s = "ab"
      p s.concat("cd", "ef")
      p s
      p "ab" << "x"
      t = "world"
      p t.prepend("hello ", "big ")
      p t
      u = "hello"
      p u.insert(2, "XX")
      p u
      p "hey".insert(-1, "!")
      v = "abc"
      p v.replace("zzz")
      p v
      w = "Hello World"
      p w.gsub!(/o/, "0")
      p w
      p w.gsub!(/zzz/, "x")
      p "abc".upcase!
      p "ABC".upcase!
      x = "  hi  "
      p x.strip!
      p x
      p "abc".reverse!
      y = "hello"
      p y.slice!(1..2)
      p y
      p "hello".slice!(0)
      p "hi".slice!(99)
      p [1, 2, 3].insert(1, 9, 8)
      p [1, 2, 3].insert(-2, 9, 8)
      p ["a", "c"].insert(1, "b", "x")
      p [1, :a].insert(1, 9, 8)
      p [1, [2, [3]]].flatten!
      p [1, 2].flatten!
      p [1, 2, 3].uniq!
      p [1, 1, 2].uniq!
      p ["a", "a"].uniq!
      p [1, nil, 2].compact!
      p [1, 2].compact!
    RUBY

    _(result).must_answer <<~'OUT'
      "abcd"
      "abcdef"
      "abcdef"
      "abx"
      "hello big world"
      "hello big world"
      "heXXllo"
      "heXXllo"
      "hey!"
      "zzz"
      "zzz"
      "Hell0 W0rld"
      "Hell0 W0rld"
      nil
      "ABC"
      nil
      "hi"
      "hi"
      "cba"
      "el"
      "hlo"
      "h"
      nil
      [1, 9, 8, 2, 3]
      [1, 2, 9, 8, 3]
      ["a", "b", "x", "c"]
      [1, 9, 8, :a]
      [1, 2, 3]
      nil
      nil
      [1, 2]
      ["a"]
      [1, 2]
      nil
    OUT
  end

  it "nomethod message shapes" do
    result = ze0(<<~'RUBY')
      # The NoMethodError a gated (unresolved) call raises names the receiver the
      # way CRuby does: nil/true/false read as themselves, everything else as
      # "an instance of <Class>" from the runtime value -- not the lattice name
      # ("for poly").
      class Cell
        def initialize(x)
          @x = x
        end
      end

      begin
        [Cell.new(1), Cell.new(2)].map(&:id)
      rescue NoMethodError => e
        puts e.message
      end

      begin
        [nil].each { |v| v.bogus }
      rescue NoMethodError => e
        puts e.message
      end

      begin
        [true].each { |v| v.bogus }
      rescue NoMethodError => e
        puts e.message
      end

      begin
        [3.5].each { |v| v.bogus }
      rescue NoMethodError => e
        puts e.message
      end
    RUBY

    _(result).must_answer <<~'OUT'
      undefined method 'id' for an instance of Cell
      undefined method 'bogus' for nil
      undefined method 'bogus' for true
      undefined method 'bogus' for an instance of Float
    OUT
  end

  it "or empty container literal type" do
    result = ze0(<<~'RUBY')
      # The empty literal on the right of `||` / `&&` was emitted with its own
      # default representation (an Integer array, whatever the left held), so the C
      # conditional mixed sp_StrArray * with sp_IntArray *. The arm has to take the
      # expression's container type, the way a ternary arm already did. #3462.
      a = ["x"]
      p(a || [])
      h = { "a" => 1 }
      p(h.keys || [])
      rows = [{ "a" => 1 }]
      p(rows.first.keys || [])
      f = [1.5]
      p(f || [])
      i = [1]
      p(i || [])
      p(a || ["z"])
      p(a && [])
      p((nil || []).size)
      syms = [:a]
      p(syms || [])
      objs = [[1], [2]]
      p(objs || [])
      p((h.values || []).size)
      def pick(x) = x || []
      p pick(["y"])
      p pick(nil).size
    RUBY

    _(result).must_answer <<~'OUT'
      ["x"]
      ["a"]
      ["a"]
      [1.5]
      [1]
      ["x"]
      []
      0
      [:a]
      [[1], [2]]
      1
      ["y"]
      0
    OUT
  end

  it "paren receiver shapes" do
    result = ze0(<<~'RUBY')
      # Parentheses around a receiver carry no meaning, but they hid the receiver
      # from every shape check that asks what it IS: the scan for a Hash.new used as
      # a receiver, the anonymous-struct receiver scan, the empty-literal receiver
      # marking. Each left the value untyped, so its methods read as unresolved calls
      # ("undefined method 'size' for unknown") even though the same call without the
      # parentheses compiled. They are stripped once now, as `&(expr)` already was.
      p((Hash.new(0)).size)
      p((Hash.new(0)).inspect)
      p((Hash.new(0))[:missing])
      p((Struct.new(:a)).new(1))
      p((Struct.new(:a, :b)).new(1, 2).to_a)
      p((Data.define(:b)).new(2))
      p(([]).size)
      p(({}).size)
      p(([]).push(1))
      p(({}).size)
      p((("x")).size)
      p((1..3).to_a)
      p(([1, 2].map { |x| x * 2 }).size)
      p((Hash.new { |h, k| k.to_s }))
      h = (Hash.new(7))
      p h[:nope]
      p (["a", "b"]).join("-")
    RUBY

    _(result).must_answer <<~'OUT'
      0
      "{}"
      0
      #<struct a=1>
      [1, 2]
      #<data b=2>
      0
      0
      [1]
      0
      1
      [1, 2, 3]
      2
      {}
      7
      "a-b"
    OUT
  end

  it "parenthesized multi statement expression answers its last statement" do
    result = ze0(<<~'RUBY')
      # `(a; b)` introduces NO scope: `a` below is still readable afterwards,
      # which is why this lowers to a plain `Seq` rather than anything that
      # pushes a scope.

      x = (1; 2; 3)
      p x
      y = (a = 5; a * 2)
      p y
      p a
      p((puts "side"; 42))
      p [(1; 2), 3]
      z = (
        q = 7
        q + 1
      )
      p z
      p((1; (2; 3)))
      w = (if true then "yes" else "no" end; "after")
      p w
      p (5)
    RUBY

    _(result).must_answer <<~'OUT'
      3
      10
      5
      side
      42
      [2, 3]
      8
      3
      "after"
      5
    OUT
  end

  it "parser long ast record" do
    result = ze0(<<~'RUBY')
      # Regression for spinel_parse text-AST records longer than 4096 bytes.
      #
      # The parser's array field emitter already builds a growable string, but
      # the final out_add formatting step used to clamp the emitted line to a
      # fixed stack buffer. This array has enough elements to force the
      # `A <id> elements ...` record past that old limit; truncating it drops
      # tail elements from the compiled program.

      xs = [
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0
      ]

      puts xs.length
      puts xs[0]
      puts xs[1179]
    RUBY

    _(result).must_answer <<~'OUT'
      1180
      0
      0
    OUT
  end

  it "poly operator builtin operand" do
    result = ze0(<<~'RUBY')
      # A poly receiver's operator with a BUILTIN operand is served by the runtime
      # operator, so it must not bind a same-named user method's parameter: doing so
      # pinned the bundled Set#superset?'s `other` to Time and made set.rb itself
      # uncompilable.
      require "set"

      # `t` is a second ahead so the ordering is decided by arithmetic, not by
      # whether the clock ticked between two Time.now calls (it did not on macOS).
      vals = [Time.now, 1]
      t = Time.now + 1
      p (vals[0] >= t).class
      p (vals[0] > t).class
      p (vals[0] <= t).class

      mixed = [[1, 2], 3]
      p (mixed[0] == [1, 2])

      # the Set surface still works, and its own methods still type
      a = Set.new([1, 2])
      b = Set.new([1, 2, 3])
      p a.subset?(b)
      p b.superset?(a)
      p (b >= a)
      p (a >= b)

      # a user class with the same operator name still binds from a real call
      class Ver
        attr_reader :n
        def initialize(n)
          @n = n
        end

        def >=(other)
          n >= other.n
        end
      end

      p (Ver.new(3) >= Ver.new(2))
    RUBY

    _(result).must_answer <<~'OUT'
      FalseClass
      FalseClass
      TrueClass
      true
      true
      true
      true
      false
      true
    OUT
  end

  it "poly recv user operator arg" do
    result = ze0(<<~'RUBY')
      # An operator reached through a poly receiver goes out to the runtime's
      # user-binop dispatch, which hands the argument over boxed. Typed from the one
      # call site the compiler could resolve -- the `1 / box` coercion, whose
      # argument is a Box -- the dispatch arm was guarded on that class, and the same
      # operator called with an Integer fell through to NoMethodError on a method the
      # class defines (#3511).
      class Box
        attr_reader :v
        def initialize(v); @v = v; end
        def self.scalar(x); new(x); end
        def coerce(other); [Box.scalar(other), self]; end
        def +(o); Box.new(@v + (o.is_a?(Box) ? o.v : o)); end
        def /(other)
          o = other.is_a?(Box) ? other : Box.scalar(other)
          Box.new(Rational(@v) / o.v)
        end
        def *(other)
          o = other.is_a?(Box) ? other : Box.scalar(other)
          Box.new(@v * o.v)
        end
        def to_s; "Box(#{@v})"; end
      end

      time = Box.new(2)
      puts "1 / time = #{1 / time}"

      items = [Box.new(3), Box.new(4)]
      total = items.inject(Box.new(0)) { |acc, r| acc + r }
      puts "mean = #{total / items.length}"
      puts "twice = #{total * 2}"
      puts "by box = #{total / Box.new(2)}"
      puts "sum = #{total}"

      # the same operator on a monomorphic receiver keeps working
      direct = Box.new(9)
      puts "direct = #{direct / 3}"
      puts "direct box = #{direct / Box.new(3)}"

      # and through the coercion in both directions
      puts "2 * box = #{2 * Box.new(5)}"
      puts "box * 2 = #{Box.new(5) * 2}"
    RUBY

    _(result).must_answer <<~'OUT'
      1 / time = Box(1/2)
      mean = Box(7/2)
      twice = Box(14)
      by box = Box(7/2)
      sum = Box(7)
      direct = Box(3/1)
      direct box = Box(3/1)
      2 * box = Box(10)
      box * 2 = Box(10)
    OUT
  end

  it "program that does not parse prints rubys report" do
    result = ze0(<<~'RUBY')
      # ruby reports a program that does not parse, and exits 1 without
      # running any of it.
      puts "never printed"
      class O; def s=(v) = @s = v; end
      # The two lines after the error are in the report, so the recording
      # below never is.
    RUBY

    _(result).must_answer "", stderr: <<~'ERR', status: 1
      lang/syntax/syntax_test.rb: --> lang/syntax/syntax_test.rb

      invalid method name; a setter method cannot be defined in an endless method definition

      > 3  puts "never printed"
      > 4  class O; def s=(v) = @s = v; end

      lang/syntax/syntax_test.rb:4: syntax error found (SyntaxError)
        2 | # running any of it.
        3 | puts "never printed"
      > 4 | class O; def s=(v) = @s = v; end
          |              ^~ invalid method name; a setter method cannot be defined in an endless method definition
        5 | # The two lines after the error are in the report, so the recording
        6 | # below never is.

    ERR
  end

  it "ruby engine identifies as ruby" do
    result = ze0(<<~'RUBY')
      # The north star is byte-for-byte MRI parity, so the engine-identity
      # constants report CRuby's own: RUBY_ENGINE == "ruby", RUBY_ENGINE_VERSION
      # == RUBY_VERSION, and RUBY_DESCRIPTION takes version.c's exact banner
      # (`ruby <ver> (<date> revision <short-rev>) +PRISM [<platform>]`).

      puts RUBY_ENGINE
      puts RUBY_ENGINE_VERSION == RUBY_VERSION
      puts RUBY_DESCRIPTION.start_with?("ruby #{RUBY_VERSION} ")
      puts RUBY_DESCRIPTION.include?("+PRISM")
    RUBY

    _(result).must_answer <<~'OUT'
      ruby
      true
      true
      true
    OUT
  end

  it "unary minus on negative literal" do
    result = ze0(<<~'RUBY')
      # `-(-7)` puts the two signs side by side in the generated C, where `--7LL`
      # reads as a pre-decrement of a literal and the C compiler rejects it. Routing
      # the inner value through a local first always worked, which is what isolates
      # the doubled sign on a literal (#4008).
      p(-(-7))
      p(- -7)
      p(-(-3.5))
      p(-(-(-7)))
      p(-(-7) + 1)
      x = -(-2)
      p x

      # the same doubling with a plus, and the mixed pairs that were never ambiguous
      p(+(+7))
      p(-(+7))
      p(+(-7))
      p(+(+2.5))

      # a bignum negates through its own helper, not a C sign
      p(-(2**70))
      p(-(-(2**70)))

      # and the ordinary spellings keep their tight form
      a = -7
      p(-a)
      p(-7)
      p(- 7)
    RUBY

    _(result).must_answer <<~'OUT'
      7
      7
      3.5
      -7
      8
      2
      7
      -7
      -7
      2.5
      -1180591620717411303424
      1180591620717411303424
      7
      -7
      -7
    OUT
  end

  it "unary operator methods" do
    result = ze0(<<~'RUBY')
      # Unary operator methods `def -@` / `def +@` must mangle to valid C
      # identifiers and dispatch on `-obj` / `+obj`. Found via the spinelgems
      # harness (latinum, as-duration negate via `-@`).
      class Money
        attr_reader :cents
        def initialize(c)
          @cents = c
        end
        def -@
          Money.new(-@cents)
        end
        def +@
          Money.new(@cents)
        end
      end

      puts((-Money.new(5)).cents)
      puts((+Money.new(7)).cents)
      puts((-(-Money.new(9))).cents)
    RUBY

    _(result).must_answer <<~'OUT'
      -5
      7
      9
    OUT
  end

  it "unary operators" do
    result = ze0(<<~'RUBY')
      x = 5
      puts(-x)
      puts(+x)
      puts(~x)
    RUBY

    _(result).must_answer <<~'OUT'
      -5
      5
      -6
    OUT
  end

  it "user bang value object" do
    result = ze0(<<~'RUBY')
      # A user-defined #! on an object with ivars: the receiver is passed the way
      # its layout says, by value for a value type, and the cast to a pointer did
      # not even compile (#3819).
      class N1
        def initialize(b); @b = b; end
        def !; @b == 0; end
      end
      p(!N1.new(1))
      p(!N1.new(0))
      x = N1.new(0)
      p(!x)
      p(!!x)

      class N2
        def initialize(b); @b = b; end
        def !=(o); @b != o; end
      end
      p(N2.new(3) != 3)
      p(N2.new(3) != 4)
    RUBY

    _(result).must_answer <<~'OUT'
      false
      true
      true
      false
      false
      true
    OUT
  end
end
