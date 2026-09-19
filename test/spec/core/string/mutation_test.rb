# frozen_string_literal: true

require "spec_helper"

describe "String: changing in place" do
  it "appends and splices keep what a scan found only while it holds" do
    result = ze0(<<~'RUBY')
      # `<<` and `bytesplice` keep a String's known-ASCII state across a change
      # of plain ASCII, and lose it for a byte past ASCII: ascii_only?, index
      # and the encoding answer from the bytes as they are after each change.
      def show(label)
        v = yield
        v = [v, v.encoding, v.ascii_only?, v.valid_encoding?] if v.is_a?(String)
        puts "#{label}: #{v.inspect}"
      rescue => e
        puts "#{label}: #{e.class}: #{e.message}"
      end

      s = +"abc".b
      s.ascii_only?
      show("binary << binary past ASCII") { s << "\xFF".b }
      t = +"abc".b
      t.ascii_only?
      show("binary << UTF-8 ASCII") { t << "de" }
      show("then << UTF-8 past ASCII") { t << "é" }
      u = +"abc"
      u.ascii_only?
      show("UTF-8 << é") { u << "é" }
      show("index after it") { u.index("é") }
      v = +"héllo"
      show("index from a character") { v.index("l", 3) }
      show("rindex") { v.rindex("l") }
      w = +"abc".b
      w.ascii_only?
      w << "x".b
      w << "\x80".b
      show("two appends") { [w.ascii_only?, w.index("\x80".b)] }
      long = +""
      2000.times { |i| long << "n#{i}".b << "\0" }
      show("a long join") { [long.bytesize, long.encoding, long.ascii_only?, long.index("n1999"), long.count("\0")] }

      show("splice itself at the head") { x = +"abcdef"; x.bytesplice(0, 1, x) }
      show("splice itself in the middle") { x = +"abcdef"; x.bytesplice(2, 3, x) }
      show("splice a range") { x = +"hello"; x.bytesplice(1..2, "EE") }
      show("splice past ASCII into ASCII") { x = +"hello"; x.ascii_only?; x.bytesplice(1, 1, "é") }
      show("index after that splice") { x = +"hello"; x.ascii_only?; x.bytesplice(1, 1, "é"); x.index("l") }
      show("splice binary into UTF-8") { x = +"hello"; x.bytesplice(1, 1, "\xFF".b) }
      show("splice UTF-8 into binary past ASCII") { x = +"h\xFFllo".b; x.bytesplice(0, 1, "é") }
      show("splice binary ASCII into UTF-8") { x = +"héllo"; x.bytesplice(0, 1, "Z".b) }
      show("splice inside a character") { x = +"héllo"; x.bytesplice(2, 1, "Z") }
      show("splice a frozen String") { "abc".freeze.bytesplice(0, 1, "Z") }
      show("splice part of the text") { x = +"hello"; x.bytesplice(0, 1, "WXYZ", 1, 2) }
      show("splice that grows") { x = +"ab"; x.bytesplice(1, 0, "0123456789" * 20); [x.bytesize, x.ascii_only?] }
      show("many splices then index") { x = +("abcdefgh" * 50); x.ascii_only?; 50.times { |i| x.bytesplice(i * 8, 1, "Z") }; [x.index("Zb", 390), x.count("Z")] }

    RUBY

    _(result).must_answer <<~'OUT'
      binary << binary past ASCII: ["abc\xFF", #<Encoding:BINARY (ASCII-8BIT)>, false, true]
      binary << UTF-8 ASCII: ["abcde", #<Encoding:BINARY (ASCII-8BIT)>, true, true]
      then << UTF-8 past ASCII: ["abcdeé", #<Encoding:UTF-8>, false, true]
      UTF-8 << é: ["abcé", #<Encoding:UTF-8>, false, true]
      index after it: 3
      index from a character: 3
      rindex: 3
      two appends: [false, 4]
      a long join: [10890, #<Encoding:UTF-8>, true, 10884, 2000]
      splice itself at the head: ["abcdefbcdef", #<Encoding:UTF-8>, true, true]
      splice itself in the middle: ["ababcdeff", #<Encoding:UTF-8>, true, true]
      splice a range: ["hEElo", #<Encoding:UTF-8>, true, true]
      splice past ASCII into ASCII: ["héllo", #<Encoding:UTF-8>, false, true]
      index after that splice: 2
      splice binary into UTF-8: ["h\xFFllo", #<Encoding:BINARY (ASCII-8BIT)>, false, true]
      splice UTF-8 into binary past ASCII: Encoding::CompatibilityError: incompatible character encodings: BINARY (ASCII-8BIT) and UTF-8
      splice binary ASCII into UTF-8: ["Zéllo", #<Encoding:UTF-8>, false, true]
      splice inside a character: IndexError: offset 2 does not land on character boundary
      splice a frozen String: FrozenError: can't modify frozen String: "abc"
      splice part of the text: ["XYello", #<Encoding:UTF-8>, true, true]
      splice that grows: [202, true]
      many splices then index: [392, 50]
    OUT
  end

  it "array op assign concat" do
    result = ze0(<<~'RUBY')
      # `arr += other` on a typed array local — operator-assignment with `+`,
      # which is `arr = arr + other` (a fresh concatenation). Previously only
      # Int/Float/String/object locals had an op-assign path; a typed array
      # local fell through to "unsupported operator assignment". `<<` and
      # `concat` already worked; this covers `+=`.
      a = [1, 2]
      a += [3, 4]
      p a

      s = ["a"]
      s += ["b", "c"]
      p s

      f = [1.5]
      f += [2.5, 3.5]
      p f

      # genuinely heterogeneous (poly) array
      h = [1, "a", :sym]
      h += [2, "b"]
      p h

      # empty-literal RHS (must not build a wrong-kind array)
      e = [1, 2]
      e += []
      p e

      # poly array from a method whose element type the compiler widens
      def ids
        r = []
        r << "x"
        r
      end
      q = ids
      q += ids
      puts q.length
    RUBY

    _(result).must_answer <<~'OUT'
      [1, 2, 3, 4]
      ["a", "b", "c"]
      [1.5, 2.5, 3.5]
      [1, "a", :sym, 2, "b"]
      [1, 2]
      2
    OUT
  end

  it "array sum concat init" do
    result = ze0(<<~'RUBY')
      # Array#sum with a String or Array initial value folds by concatenation.
      p ["a", "b", "c"].sum("")
      p ["b", "c"].sum("a:")
      p [[1], [2], [3]].sum([])
      p [[1], [2]].sum([0])
      p [1, 2, 3].sum(0.5)
      p [1, 2, 3].sum
    RUBY

    _(result).must_answer <<~'OUT'
      "abc"
      "a:bc"
      [1, 2, 3]
      [0, 1, 2]
      6.5
      6
    OUT
  end

  it "class shovel self attr accessor backs onto class level ivars" do
    result = ze0(<<~'RUBY')
      # `class << self; attr_accessor :x; end` is THE idiomatic way to declare
      # class-level state, and it works by generating `def self.x; @x; end` --
      # so it only works once class-level `@x` has real storage.

      module Reg
        class << self
          attr_accessor :handler
          def helper; "helped"; end
        end
      end
      Reg.handler = "H"
      p Reg.handler
      p Reg.helper

      class Cfg
        class << self
          attr_reader :mode
          attr_writer :mode
        end
        @mode = "default"
      end
      p Cfg.mode
      Cfg.mode = "custom"
      p Cfg.mode
    RUBY

    _(result).must_answer <<~'OUT'
      "H"
      "helped"
      "default"
      "custom"
    OUT
  end

  it "concat boxed source" do
    result = ze0(<<~'RUBY')
      # A boxed source for #concat: the element read out of a poly array is an array
      # at run time, and reading it as the receiver's C type did not compile (#3850).
      g = [[1, 2], [3, 4]]
      p g.each_with_object([]) { |r, acc| acc.concat(r) }
      acc2 = []
      g.each { |r| acc2.concat(r) }
      p acc2
      s = ["a", "b"]
      out = []
      [s].each { |r| out.concat(r) }
      p out
      p [1, 2].concat([3, 4])
    RUBY

    _(result).must_answer <<~'OUT'
      [1, 2, 3, 4]
      [1, 2, 3, 4]
      ["a", "b"]
      [1, 2, 3, 4]
    OUT
  end

  it "concat chain operand gc root" do
    result = ze0(<<~'RUBY')
      # A chained string concat `a + b + c` lowers to sp_str_concat3 (and
      # `a+b+c+d` to sp_str_concat4). The operands must be rooted before the
      # call: argument evaluation order is unspecified, so a fresh GC string
      # produced by one operand can be collected while a sibling operand
      # allocates. Here each tag() allocates and forces a GC, so a later
      # operand's GC.start collects an earlier operand's unrooted result.
      def tag(s)
        r = "[" + s + "]"   # fresh heap string
        GC.start            # collect; pre-fix frees sibling operands still pending
        r
      end

      three = tag("a") + "\n" + tag("b") + "\n" + tag("c")
      four  = tag("w") + tag("x") + tag("y") + tag("z")
      puts three
      puts four
    RUBY

    _(result).must_answer <<~'OUT'
      [a]
      [b]
      [c]
      [w][x][y][z]
    OUT
  end

  it "concat print poly unbox" do
    result = ze0(<<~'RUBY')
      # Conditional-assign of a poly value (e.g. nullable hash lookup
      # fused with a nil-guard fallback) leaves the local typed sp_RbVal
      # even when both branches produce strings. Downstream concat and
      # print sites must coerce on the sp_RbVal -> const char * boundary
      # rather than fall through to a struct-into-pointer cc error.
      #
      #   * `"a" + poly + "b"` -- chained concat collapses to
      #     sp_str_concat3; collect_concat_parts now wraps poly with
      #     sp_poly_to_s (mirrors the existing 2-arg sp_str_concat
      #     coercion at the single-`+` site).
      #   * `print poly` -- compile_print routes through sp_poly_to_s
      #     instead of the broken `printf("%lld", (long long)val)`
      #     fallback (sp_RbVal is a struct; the cast rejects).
      #
      # str_poly_hash lookup is the canonical shape that triggers the
      # poly local: { "text" => "hi", "n" => 42 }["text"] is sp_RbVal
      # because the value union spans String and Integer.

      def show_concat(node)
        raw = node["text"]
        text = if raw.nil?
                 ""
               else
                 raw
               end
        puts "[ " + text + " ]"
      end

      def show_print(node)
        raw = node["text"]
        text = if raw.nil?
                 ""
               else
                 raw
               end
        print "[ "
        print text
        print " ]\n"
      end

      # --- Present-key String value (the canonical bug-report shape).
      # Mixed-value hash -> str_poly_hash; the else branch produces a poly
      # value (raw), the if branch produces a string literal. The union of
      # the two branches stays sp_RbVal. Without the codegen-side coercion,
      # the downstream concat / print sites emit cc-rejected C.
      h_present = { "text" => "hello", "n" => 42 }
      show_concat(h_present)
      show_print(h_present)

      # --- Missing-key fallback. Exercises the if-true branch of the
      # nil-guard: raw is nil, text becomes "", concat / print emit
      # "[  ]" / "[  ]\n". h_missing keeps the same str_poly_hash shape
      # (mixed String + Integer values so the value union widens to
      # poly) but omits the "text" key so the lookup returns nil.
      # Without this case the if-branch of the conditional assignment
      # was untested.
      h_missing = { "other" => "x", "n" => 42 }
      show_concat(h_missing)
      show_print(h_missing)

      # --- Symbol-valued poly via `print`. CRuby's `print :sym` calls
      # `Symbol#to_s` -> "sym"; spinel's compile_print poly arm routes
      # through `sp_poly_to_s` whose SP_TAG_SYM case returns the same
      # rendering. Exercises the tag dispatch beyond SP_TAG_STR.
      def show_print_sym(node)
        raw = node["k"]
        text = raw.nil? ? "" : raw
        print "sym="
        print text
        puts ""
      end
      h_sym = { "k" => :hello, "n" => 42 }
      show_print_sym(h_sym)

      # --- Integer-valued poly via `print`. SP_TAG_INT path through
      # `sp_poly_to_s` returns `sp_int_to_s(...)`; CRuby's `print 42`
      # calls `Integer#to_s`. (Skipped for concat: CRuby raises
      # TypeError on `String + Integer`; the coercion path stays
      # behind `print` to preserve parity.)
      def show_print_int(node)
        raw = node["k"]
        text = raw.nil? ? "" : raw
        print "int="
        print text
        puts ""
      end
      h_int = { "k" => 42, "n" => "x" }
      show_print_int(h_int)

      # --- Explicit 4-part chained concat that exercises sp_str_concat4.
      # Uses bound prefix/suffix locals (rather than bare string literals)
      # so the part shape is unambiguous regardless of any literal-folding
      # optimization pass.
      def label_concat4(node)
        raw = node["text"]
        text = raw.nil? ? "" : raw
        prefix = "OPEN"
        suffix = "CLOSE"
        puts prefix + " " + text + " " + suffix
      end
      label_concat4(h_present)
      label_concat4(h_missing)

      # --- Variable-length sp_str_concat_arr (>= 5 parts) with bound
      # prefix / suffix to ensure the chain stays unambiguous.
      def label_wrap(node)
        raw = node["text"]
        text = raw.nil? ? "" : raw
        pre1 = "<"
        pre2 = "open "
        post1 = " close"
        post2 = ">"
        puts pre1 + pre2 + text + post1 + post2
      end
      label_wrap(h_present)
    RUBY

    _(result).must_answer <<~'OUT'
      [ hello ]
      [ hello ]
      [  ]
      [  ]
      sym=hello
      int=42
      OPEN hello CLOSE
      OPEN  CLOSE
      <open hello close>
    OUT
  end

  it "concat source evaluated once" do
    result = ze0(<<~'RUBY')
      $calls = 0

      def src
        $calls += 1
        [1, 2, 3]
      end

      a = [0]
      a.concat(src)
      p a
      p $calls

      b = []
      b.concat(src, src)
      p b
      p $calls

      # a string's bytes: the source is a fresh array each time it is evaluated
      out = []
      out.concat("abc".bytes)
      out.concat("de".bytes)
      p out

      # mixed kinds still coerce
      poly = [:x]
      poly.concat([1, 2])
      p poly
      ints = [9]
      ints.concat([1, 2].map { |v| v })
      p ints
      strs = ["a"]
      strs.concat(%w[b c])
      p strs
    RUBY

    _(result).must_answer <<~'OUT'
      [0, 1, 2, 3]
      1
      [1, 2, 3, 1, 2, 3]
      3
      [97, 98, 99, 100, 101]
      [:x, 1, 2]
      [9, 1, 2]
      ["a", "b", "c"]
    OUT
  end

  it "element assignment splices in place" do
    result = ze0(<<~'RUBY')
      s = +"héllo wörld"
      s[1] = "E"; p s
      s[0, 3] = "日本"; p s, s.encoding, s.valid_encoding?
      s[-5..] = "!"; p s
      s["!"] = "?!?"; p s
      begin; s[/(ll)/, 1] = "LL"; rescue => e; p e.class; end
      p s
      t = +"abc"; t[1, 1] = t; p t
      u = +"x"; 20.times { |i| u[u.bytesize, 0] = "ab#{i}" }; p u, u.bytesize
      b = ("\0" * 16).b; b[4, 4] = [0xdeadbeef].pack("L<"); p b.bytes
      begin; b[0, 0] = "é"; p b.encoding, b.bytesize; rescue => e; p e.class; end
      ascii = +"plain"; ascii[0] = "ü"; p ascii, ascii.encoding
      begin; "frozen".freeze[0] = "x"; rescue => e; p e.class; end
      begin; bin = "\xff".b.dup; bin[0, 0] = "é"; p bin, bin.encoding; rescue => e; p e.class, e.message; end
      begin; x = +"é"; x[0, 0] = "\xff".b; p x; rescue => e; p e.class, e.message; end
      v = +"hello"; p v.insert(2, "XY"), v.insert(-1, "!"), v.insert(0, v)
      w = +"abc"; w[3, 0] = "d"; w[1, 5] = ""; p w
      begin; (+"ab")[5] = "x"; rescue => e; p e.class, e.message; end
      e = "".encode("UTF-16LE"); e[0, 0] = "a".encode("UTF-16LE"); p e.bytes


    RUBY

    _(result).must_answer <<~'OUT'
      "hEllo wörld"
      "日本lo wörld"
      #<Encoding:UTF-8>
      true
      "日本lo !"
      "日本lo ?!?"
      IndexError
      "日本lo ?!?"
      "aabcc"
      "xab0ab1ab2ab3ab4ab5ab6ab7ab8ab9ab10ab11ab12ab13ab14ab15ab16ab17ab18ab19"
      71
      [0, 0, 0, 0, 239, 190, 173, 222, 0, 0, 0, 0, 0, 0, 0, 0]
      Encoding::CompatibilityError
      "ülain"
      #<Encoding:UTF-8>
      FrozenError
      Encoding::CompatibilityError
      "incompatible character encodings: BINARY (ASCII-8BIT) and UTF-8"
      Encoding::CompatibilityError
      "incompatible character encodings: UTF-8 and BINARY (ASCII-8BIT)"
      "heXYllo!heXYllo!"
      "heXYllo!heXYllo!"
      "heXYllo!heXYllo!"
      "a"
      IndexError
      "index 5 out of string"
      [97, 0]
    OUT
  end

  it "empty parens are nil and concat snapshots its sources" do
    result = ze0(<<~'RUBY')
      # `()` is nil (falsy as a condition, a nil value in expression position);
      # `Array#concat` copies all sources before appending, so a self-aliasing
      # `a.concat(a, a)` terminates at 6 elements rather than feeding itself.

      p(())
      p((() && true))
      n = 0
      while () ; n += 1 ; end
      p n
      a = [1, 2]
      a.concat(a, a)
      p a
    RUBY

    _(result).must_answer <<~'OUT'
      nil
      nil
      0
      [1, 2, 1, 2, 1, 2]
    OUT
  end

  it "hash default array fetch concat wave9" do
    result = ze0(<<~'RUBY')
      # Hash store/default reader+writer/Hash.new(default) literal folds,
      # Array concat value form, fetch with default or block, repeated_permutation.
      p({ a: 1 }.store(:b, 2))
      h = { "x" => 1 }
      p(h.store("y", 5))
      p h
      g = { 1 => "a" }
      g.store(2, "b")
      p g
      p(Hash.new(7).default)
      p(({}.default = 9))
      p(Hash.new(0)[:missing])
      p(Hash.new("d")["nope"])
      h = Hash.new(42)
      p h.default
      h.default = 5
      p h.default
      p h[:zzz]
      a = [1, 2]
      a.concat([3, 4])
      p a
      b = [1, 2]
      r = b.concat([3])
      p r
      p([10, 20, 30].fetch(5, "default"))
      p([10, 20, 30].fetch(1, "default"))
      p([10, 20, 30].fetch(5) { |i| "missing #{i}" })
      p([10, 20, 30].fetch(-1))
      p([10, 20, 30].fetch(1) { |i| i * 100 })
      p([10, 20, 30].fetch(9) { |i| i * 100 })
      mixed = [1, "x"]
      p(mixed.fetch(7, :none))
      p([1, 2].concat([3, 4]))
      b = [1, 2]
      r = b.concat([3])
      p r
      p b
      s = %w[a b]
      p(s.concat(%w[c], %w[d e]))
      sc = [1, 2]
      p(sc.concat(sc))
      p([1, 2].repeated_permutation(2).to_a)
      p(%w[a b].repeated_permutation(2).to_a)
      p([1, 2, 3].repeated_permutation(0).to_a)
    RUBY

    _(result).must_answer <<~'OUT'
      2
      5
      {"x" => 1, "y" => 5}
      {1 => "a", 2 => "b"}
      7
      9
      0
      "d"
      42
      5
      5
      [1, 2, 3, 4]
      [1, 2, 3]
      "default"
      20
      "missing 5"
      30
      20
      900
      :none
      [1, 2, 3, 4]
      [1, 2, 3]
      [1, 2, 3]
      ["a", "b", "c", "d", "e"]
      [1, 2, 1, 2]
      [[1, 1], [1, 2], [2, 1], [2, 2]]
      [["a", "a"], ["a", "b"], ["b", "a"], ["b", "b"]]
      [[]]
    OUT
  end

  it "incompatible concatenation raises the compatibility error" do
    result = ze0(<<~'RUBY')
      # Two differently-encoded NON-7-bit strings; CRuby's exact message,
      # receiver's encoding first in its `inspect` form. `<<` past 255 on a
      # byte-encoded receiver is the RangeError, not a promotion.

      begin
        "é".b + "é"
      rescue Encoding::CompatibilityError => e
        puts "plus: #{e.message}"
      end
      begin
        ("é".b) << "é"
      rescue Encoding::CompatibilityError => e
        puts "shovel: #{e.message}"
      end
      begin
        "".b << 0x1F600
      rescue RangeError => e
        puts "range: #{e.message}"
      end
    RUBY

    _(result).must_answer <<~'OUT'
      plus: incompatible character encodings: BINARY (ASCII-8BIT) and UTF-8
      shovel: incompatible character encodings: BINARY (ASCII-8BIT) and UTF-8
      range: 128512 out of char range
    OUT
  end

  it "poly concat chain rooted" do
    result = ze0(<<~'RUBY')
      # A chained poly `+` whose later operand allocates.
      #
      # `a + b + c` on poly operands compiles to sp_poly_add(sp_poly_add(a, b), c).
      # The inner result is a freshly built string living only in a C temporary, and
      # `c` is evaluated after it -- so an allocation there collects with the
      # intermediate held nowhere the root scan can see. The sweep freed it and the
      # outer concat read freed memory: a use-after-free that ASAN names and a plain
      # build turns into a segfault or silent corruption, depending on what reused
      # the block.
      #
      # The monomorphic chain never had this; only the poly path left the
      # intermediate unrooted.

      def build_name(prefix, mid, i)
        prefix + mid + i.to_s
      end

      # an Integer call site widens the parameters to poly, which is what routes the
      # `+` through sp_poly_add
      def widen_them
        build_name(1, 2, 0)
      end

      s = ""
      i = 0
      while i < 2000
        s = build_name("blk.", "attn_k.head_", i)
        i += 1
      end
      p s
      p s.length

      # the same shape with the allocating operand in the middle
      def middle(a, b)
        a + b.to_s + "!"
      end

      def widen_middle
        middle(1, 2)
      end

      p middle("n=", 41)

      # a longer chain: every intermediate has to survive the next operand
      def four(a, b, c, d)
        a + b + c + d
      end

      def widen_four
        four(1, 2, 3, 4)
      end

      p four("a", "b", 3.to_s, "d")
    RUBY

    _(result).must_answer <<~'OUT'
      "blk.attn_k.head_1999"
      20
      "n=41!"
      "ab3d"
    OUT
  end

  it "str append accumulator" do
    result = ze0(<<~'RUBY')
      # An append accumulator -- a string local appended to inside a loop -- rides
      # the growable handle so each `<<` is amortized O(1) rather than a copy of the
      # whole accumulation. The representation change must be invisible: what these
      # pin is that the results, the aliasing, and the shapes that must NOT be
      # promoted all still behave.
      def build(n)
        out = +""
        i = 0
        while i < n
          out << "ab"
          i += 1
        end
        out
      end
      p build(5).length
      p build(5)

      # a block-form loop accumulates the same way, and the value survives the method
      def joined(list)
        s = +""
        list.each { |x| s << x.to_s }
        s
      end
      p joined([1, 2, 3])

      # read after the loop, several ways
      acc = +""
      3.times { |i| acc << i.to_s }
      p acc
      p acc.length
      p acc[1]
      p acc.upcase
      p acc == "012"
      p acc + "!"
      p [acc].first

      # a local READ inside the loop keeps its plain representation and its answers
      r = +""
      sizes = []
      4.times do |i|
        r << "x"
        sizes << r.length
      end
      p sizes
      p r

      # a param appended through a call stays byref: the caller sees the append
      def feed(buf)
        buf << "!"
      end
      b = +""
      2.times { feed(b) }
      p b

      # a captured local is shared storage, and both writers are visible
      w = +""
      f = proc { w << "c" }
      2.times { w << "a" }
      f.call
      p w

      # `<<` outside any loop is unchanged
      z = +""
      z << "one"
      z << "two"
      p z

      # an each_with_object memo is the iterator's slot, not ours
      p({ "a" => 1, "b" => 2 }.each_with_object(+"") { |(k, _v), a| a << k })
    RUBY

    _(result).must_answer <<~'OUT'
      10
      "ababababab"
      "123"
      "012"
      3
      "1"
      "012"
      true
      "012!"
      "012"
      [1, 2, 3, 4]
      "xxxx"
      "!!"
      "aac"
      "onetwo"
      "ab"
    OUT
  end

  it "str array min max" do
    result = ze0(<<~'RUBY')
      # Array#min / #max / #minmax (no block) on String arrays, by String#<=> (byte
      # comparison). Previously rejected for String arrays while Integer/Float arrays
      # worked. Receivers route through a per-kind identity method so the typed
      # runtime path is exercised rather than a compile-time fold.
      def sw(x); x; end
      def si(x); x; end
      def sf(x); x; end

      p sw(%w[banana apple cherry]).min
      p sw(%w[banana apple cherry]).max
      p sw(%w[banana apple cherry]).minmax
      # byte ordering: uppercase precedes lowercase; lexicographic, not numeric
      p sw(%w[Z a]).min
      p sw(%w[10 9 100]).max
      p sw(%w[b a a c]).min
      # single element
      p sw(["only"]).min
      p sw(["only"]).minmax

      # empty -> nil
      def empty; a = ["x"]; a.clear; a; end
      p empty.min
      p empty.max

      # Integer / Float arrays remain unaffected
      p si([3, 1, 2]).min
      p si([3, 1, 2]).max
      p si([3, 1, 2]).minmax
      p sf([3.0, 1.0, 2.0]).min
      p sf([3.0, 1.0, 2.0]).minmax
    RUBY

    _(result).must_answer <<~'OUT'
      "apple"
      "cherry"
      ["apple", "cherry"]
      "Z"
      "9"
      "a"
      "only"
      ["only", "only"]
      nil
      nil
      1
      3
      [1, 3]
      1.0
      [1.0, 3.0]
    OUT
  end

  it "str chomp paragraph mode" do
    result = ze0(<<~'RUBY')
      # String#chomp edge cases: no-arg strips ONE separator,
      # paragraph mode (chomp("")) strips trailing \r\n/\n sequences
      # but not standalone \r.

      # No-arg chomp: one separator
      puts "hello\r\n".chomp.inspect
      puts "hello\n".chomp.inspect
      puts "hello\r".chomp.inspect
      puts "hello\r\n\r\n".chomp.inspect
      puts "hello".chomp.inspect

      # Paragraph mode
      puts "hello\r\n".chomp("").inspect
      puts "hello\n".chomp("").inspect
      puts "hello\r".chomp("").inspect
      puts "hello\r\n\r\n".chomp("").inspect
    RUBY

    _(result).must_answer <<~'OUT'
      "hello"
      "hello"
      "hello"
      "hello\r\n"
      "hello"
      "hello"
      "hello"
      "hello\r"
      "hello"
    OUT
  end

  it "str concat raise operand" do
    result = ze0(<<~'RUBY')
      # A String-returning method unresolved on a poly value, used as a String#+
      # operand, must raise NoMethodError at run time -- not fail C compilation with a
      # sp_RbVal-into-const-char* mismatch (#2457 Family 2).
      class Note
        def initialize(t); @created_at = t; end
        def created_at; @created_at; end
      end
      def show(note)
        "at " + note.created_at.strftime("%Y")
      end
      begin
        show(Note.new(nil))
        p :no_raise
      rescue NoMethodError
        p :raised
      end
      # the ordinary path still works
      p("a" + "b")
    RUBY

    _(result).must_answer <<~'OUT'
      :raised
      "ab"
    OUT
  end

  it "str str hash nullable bracket assign" do
    result = ze0(<<~'RUBY')
      # Silent-elision regression: `<str_str_hash?>[k] = v` previously
      # fell through every arm of compile_bracket_assign with no emit, so
      # the assignment vanished. The two missing entry points were the
      # `str_str_hash` / `str_int_hash` base arms (mirror of the existing
      # `sym_*_hash` / `int_str_hash` arms), plus the nullable-pointer
      # strip at the top so `str_str_hash?` reaches the same emit.
      # Issue #610: roundhouse's `dispatch_request` builds a merged
      # str_str_hash from a path-params dup (typed str_str_hash? because
      # the source ivar is nullable) and then writes into it inside a
      # `.each` block; pre-fix the entire merge loop body disappeared.

      class HashHolder
        def initialize
          @h = nil
        end

        attr_accessor :h
      end

      def fill(holder)
        # Force the slot's static type to `str_str_hash?` by routing the
        # initial value through a method that returns the nullable shape.
        holder.h = path_params
        holder.h["c"] = "3"
        holder.h["d"] = "4"
      end

      def path_params
        { "a" => "1", "b" => "2" }
      end

      hh = HashHolder.new
      fill(hh)
      m = hh.h
      puts m["a"]   # 1
      puts m["b"]   # 2
      puts m["c"]   # 3
      puts m["d"]   # 4
      puts m.length # 4
    RUBY

    _(result).must_answer <<~'OUT'
      1
      2
      3
      4
      4
    OUT
  end

  it "<< through a helper grows the receiver, an ivar buffer included" do
    result = ze0(<<~'RUBY')
      def fill(str, n)
        n.times { |i| str << "ab" << i.to_s }
        str
      end

      s = String.new
      fill(s, 5)
      p s
      p s.length

      # an ivar filled through a helper that takes it as a parameter
      class Doc
        def initialize
          @buf = String.new
        end

        def add(n)
          n.times { |i| append(@buf, i) }
        end

        def append(str, i)
          str << "<" << i.to_s << ">"
        end

        def buf
          @buf
        end
      end

      d = Doc.new
      d.add(4)
      p d.buf
      p d.buf.bytesize

      # a frozen receiver still raises
      f = "abc".freeze
      begin
        f << "d"
        p :no_raise
      rescue FrozenError => e
        p e.class
      end

      # the value read out before the append is not disturbed by a later grow
      a = String.new
      a << "one"
      b = a.dup
      a << "-two"
      p [a, b]

      # binary content survives
      bin = String.new
      bin << "x" << 0.chr << "y"
      p bin.bytes
      p bin.bytesize
    RUBY

    _(result).must_answer <<~'OUT'
      "ab0ab1ab2ab3ab4"
      15
      "<0><1><2><3>"
      12
      FrozenError
      ["one-two", "one"]
      [120, 0, 121]
      3
    OUT
  end

  it "gsub!, sub!, tr!, delete! and slice! change the receiver in place" do
    result = ze0(<<~'RUBY')
      # In-place gsub!/sub!/tr!/delete!/slice! reassign the transformed value
      # (statement position; the nil-when-unchanged return is not modeled, like
      # the other bang methods).
      s = "hello"
      s.gsub!("l", "L")
      puts s
      t = "hello"
      t.sub!("l", "_")
      puts t
      u = "hello"
      u.tr!("el", "ip")
      puts u
      v = "hello"
      v.delete!("l")
      puts v
      w = "hello world"
      w.slice!(5, 6)
      puts w
      x = "hello"
      x.slice!("ll")
      puts x
      y = "hello"
      y.slice!(2, 99)
      puts y
      z = "hello"
      z.gsub!(/l+/, "L")
      puts z
    RUBY

    _(result).must_answer <<~'OUT'
      heLLo
      he_lo
      hippo
      heo
      hello
      heo
      he
      heLo
    OUT
  end

  it "upcase! answers nil when nothing changed, and sum and chr read the bytes" do
    result = ze0(<<~'RUBY')
      s = "abc"; p s.upcase!; p s; p s.upcase!
      t = "  hi  "; t.strip!; p t
      u = "hello"; u.reverse!; p u
      v = "a b c"; v.gsub!(" ", "-"); p v
      w = "az"; w.succ!; p w
      p "hello".sum
      p "hello".chr
    RUBY

    _(result).must_answer <<~'OUT'
      "ABC"
      "ABC"
      nil
      "hi"
      "olleh"
      "a-b-c"
      "ba"
      532
      "h"
    OUT
  end

  it "a bang mutator on an empty string answers the receiver, not nil" do
    result = ze0(<<~'RUBY')
      p (+"").reverse!
      p (+"").succ!
      p (+"").next!
      p (+"a").reverse!
    RUBY

    _(result).must_answer <<~'OUT'
      ""
      ""
      ""
      "a"
    OUT
  end

  it "chomp! writes back to the receiver, and a frozen literal raises" do
    result = ze0(<<~'RUBY')
      # Issue #859: String#chomp! on a mutable_str mutates in place.
      # Pre-fix, chomp! was a no-op (recursed into chomp which produces
      # a new string but doesn't write back to the receiver).
      # Frozen string literals raise FrozenError per #886.
      s = String.new("hello\n")
      s.chomp!
      puts s.to_s

      s2 = String.new("hi\r\n")
      s2.chomp!
      puts s2.to_s

      # upcase! / downcase! / strip! / lstrip! / rstrip! also mutate.
      u = String.new("abc")
      u.upcase!
      puts u.to_s

      t = String.new("  spaces  ")
      t.strip!
      puts t.to_s
    RUBY

    _(result).must_answer <<~'OUT'
      hello
      hi
      ABC
      spaces
    OUT
  end

  it "concat takes any number of arguments, and an Integer appends its codepoint" do
    result = ze0(<<~'RUBY')
      s = "a"
      s.concat("b", "c", "d")
      puts s
      t = "x"
      t << "y" << "z"
      puts t
      u = "n"
      u.concat(65, 66)
      puts u
      puts "keep".concat
    RUBY

    _(result).must_answer <<~'OUT'
      abcd
      xyz
      nAB
      keep
    OUT
  end

  it "concat mixes strings and codepoints, and no argument at all is a no-op" do
    result = ze0(<<~'RUBY')
      # String#concat accepts any number of arguments (appended left to right);
      # `<<` is the single-argument operator spelling.
      s = "a"
      s.concat("b", "c", "d")
      puts s

      t = "greet"
      t << "-" << "world"
      puts t

      # Integer arguments append the corresponding codepoint's character.
      u = "n"
      u.concat(0x61, 0x62)
      puts u

      # No arguments is a no-op that returns the receiver.
      puts "unchanged".concat

      # Mixed string and codepoint arguments.
      v = "x"
      v.concat("y", 0x7A, "!")
      puts v
    RUBY

    _(result).must_answer <<~'OUT'
      abcd
      greet-world
      nab
      unchanged
      xyz!
    OUT
  end

  it "lines splits on a given separator, and prepend inserts every argument in order" do
    result = ze0(<<~'RUBY')
      # String#lines / #each_line take an optional separator and a chomp: keyword.
      p "one\ntwo\nthree".lines
      p "one\ntwo\nthree".lines(chomp: true)
      p "a\r\nb\r\n".lines(chomp: true)     # default sep also strips a preceding \r
      p "a|b|c".lines("|")

      seen = []
      "red\ngreen\nblue\n".each_line(chomp: true) { |line| seen << line.upcase }
      p seen

      # String#prepend accepts any number of strings, inserted in order at the front.
      greeting = "world"
      greeting.prepend("hello, ", "dear ")
      p greeting
    RUBY

    _(result).must_answer <<~'OUT'
      ["one\n", "two\n", "three"]
      ["one", "two", "three"]
      ["a", "b"]
      ["a|", "b|", "c"]
      ["RED", "GREEN", "BLUE"]
      "hello, dear world"
    OUT
  end

  it "lines with chomp: strips a CRLF, and each_line yields the same lines to a block" do
    result = ze0(<<~'RUBY')
      p "a\nb\nc".lines
      p "a\nb\nc".lines(chomp: true)
      p "a\r\nb\r\nc\r\n".lines(chomp: true)
      p "a-b-c".lines("-")
      collected = []
      "x\ny\n".each_line(chomp: true) { |l| collected << l }
      p collected
      t = "world"
      t.prepend("hello ", "big ")
      p t
    RUBY

    _(result).must_answer <<~'OUT'
      ["a\n", "b\n", "c"]
      ["a", "b", "c"]
      ["a", "b", "c"]
      ["a-", "b-", "c"]
      ["x", "y"]
      "hello big world"
    OUT
  end

  it "strip nul" do
    result = ze0(<<~'RUBY')
      # strip/lstrip/rstrip remove the NUL byte (CRuby strips "\0\t\n\v\f\r ").
      # Embedded NUL needs a heap string (literals truncate at \0); build via pack.
      s = [0, 104, 105, 0].pack("C*")          # "\0hi\0"
      p s.strip.bytes
      p s.lstrip.bytes
      p s.rstrip.bytes
      mid = [0, 0, 104, 0, 105, 0].pack("C*")  # "\0\0h\0i\0" -- interior NUL survives
      p mid.strip.bytes
      # normal strings unchanged
      p "  hi  ".strip
      p "\tx\n".strip
      p "ab  ".rstrip
      p "  ab".lstrip
    RUBY

    _(result).must_answer <<~'OUT'
      [104, 105]
      [104, 105, 0]
      [0, 104, 105]
      [104, 0, 105]
      "hi"
      "x"
      "ab"
      "ab"
    OUT
  end

  it "volatile strip skips coerced arg" do
    result = ze0(<<~'RUBY')
      # #700 secondary shape: cast_away_volatile_arg was wrapping a
      # coerced call-arg value with the LV's declared type, producing
      # `(sp_SymPolyHash *)sp_StrPolyHash_from_sym_poly_hash(lv_form_attrs)`
      # -- a SymPoly cast on a StrPoly result.
      #
      # Requires @needs_setjmp == 1 (any begin/rescue in the file), an
      # LV recv with a typed-hash declared type, a callee expecting a
      # different hash variant, and the call site to go through
      # compile_typed_call_args' compile_expr_for_expected_type +
      # cast_away_volatile_arg wrapping.

      def takes_str_poly(h)
        h.length
      end

      def trigger_setjmp
        begin
          raise "x"
        rescue
          1
        end
      end

      def build_and_call
        form_attrs = {a: "x", b: 1}    # sym_poly_hash
        takes_str_poly(form_attrs)     # callee expects str_poly_hash -> coerce
      end

      trigger_setjmp                    # arms @needs_setjmp = 1 globally
      puts build_and_call
    RUBY

    _(result).must_answer "2\n"
  end

  it "appends a code point without cutting a String to hold it" do
    result = ze0(<<~'RUBY')
      # `s << byte` writes the byte where it goes when the receiver's
      # characters are bytes, and spells a code point in UTF-8 when they are
      # not. rb_str_concat keeps the plain-ASCII flag, turns a US-ASCII
      # receiver binary at the first byte past ASCII, and refuses a byte
      # above 255 on a binary one.
      s = +"".b
      s << 65 << 200 << 0
      p s, s.encoding, s.bytes
      u = +"ab"
      u << 233
      p u, u.encoding, u.valid_encoding?
      w = +"ab"
      w << 0x1F600
      p w, w.encoding, w.bytes.size
      a = +"ab".force_encoding("US-ASCII")
      a << 200
      p a, a.encoding
      b = +"ab".force_encoding("US-ASCII")
      b << 65
      p b, b.encoding
      e = +"".force_encoding("EUC-JP")
      e << 0xA4A2
      p e.bytes, e.encoding
      begin; (+"a".b) << 256; rescue RangeError => x; puts x.message; end
      big = +"x" * 300
      300.times { |i| big << (i % 256) }
      p big.bytesize, big.getbyte(300), big.getbyte(599)
      asc = +"abc"
      p asc.ascii_only?
      asc << 65
      p asc.ascii_only?
      asc << 200
      p asc.ascii_only?, asc.encoding
      # Array#pack writes every byte of an integer that way.
      p [0x12345678].pack("L<").bytes, [0x12345678].pack("L>").bytes
      p (1..6).to_a.pack("Q<*").bytesize, [-1].pack("q>").bytes
    RUBY

    _(result).must_answer <<~'OUT'
      "A\xC8\x00"
      #<Encoding:BINARY (ASCII-8BIT)>
      [65, 200, 0]
      "abé"
      #<Encoding:UTF-8>
      true
      "ab😀"
      #<Encoding:UTF-8>
      6
      "ab\xC8"
      #<Encoding:BINARY (ASCII-8BIT)>
      "abA"
      #<Encoding:US-ASCII>
      [164, 162]
      #<Encoding:EUC-JP>
      256 out of char range
      728
      0
      149
      true
      true
      false
      #<Encoding:UTF-8>
      [120, 86, 52, 18]
      [18, 52, 86, 120]
      48
      [255, 255, 255, 255, 255, 255, 255, 255]
    OUT
  end
end
