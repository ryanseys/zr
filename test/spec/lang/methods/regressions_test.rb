# frozen_string_literal: true

require "spec_helper"

describe "Methods: regressions" do
  it "int array literal lshift heterogeneous" do
    result = zr(<<~'RUBY')
      # `<Integer array literal> << <non-Integer>` shape (`[1, 2] << "c"`).
      # Pushing a non-Integer element onto a literal Integer array gives
      # a heterogeneous array, as in CRuby.
      #
      # This test covers direct ArrayNode literals on the LHS only, not a
      # stored ivar / local (`@slots = [nil] * N; @slots << ...`).
      p ([1, 2] << "c") == [1, 2, "c"]       # true
      p ([1, 2] << nil) == [1, 2, nil]       # true
      p ([1, 2] << 3) == [1, 2, 3]           # true (int <<, no lift)
    RUBY

    _(result).must_answer <<~'OUT'
      true
      true
      true
    OUT
  end

  it "int array replace expr" do
    result = zr(<<~'RUBY')
      # `Array#replace` in *expression* position on an int_array.
      # The stmt-form arm has long supported this; the expr-form was
      # missing — unresolved-call warning + literal `0` emitted.
      # Surfaced via optcarrot's `def load_battery; ...; @wrk.replace(sav.bytes); end`,
      # where the call sits at the tail of the method (its value is
      # the implicit return).

      a = [1, 2, 3]
      b = [10, 20, 30, 40]

      # Expression position: assigned. Should yield the (mutated) `a`.
      c = a.replace(b)

      # `a` mutated in place
      puts a[0]
      puts a[1]
      puts a[2]
      puts a[3]
      puts a.length

      # `c` is the same array (replace returns the receiver)
      puts c[0]
      puts c.length
    RUBY

    _(result).must_answer <<~'OUT'
      10
      20
      30
      40
      4
      10
      4
    OUT
  end

  it "int eq nil strict" do
    result = zr(<<~'RUBY')
      # In CRuby `0 == nil` is false -- only nil equals nil. A stored 0,
      # also a 0 read from a Hash, is not nil, so `v != nil` is true.

      # Pure int (no hash)
      v = 0
      puts (v == nil).inspect   # false
      puts (v != nil).inspect   # true

      w = 5
      puts (w == nil).inspect   # false
      puts (w != nil).inspect   # true

      # Float / bool same.
      f = 0.0
      puts (f == nil).inspect   # false
      puts (f != nil).inspect   # true

      b = false
      puts (b == nil).inspect   # false

      # Hash<String,Int> stored 0 case reports != nil correctly.
      h = {}
      h["x"] = 0
      h["y"] = 5
      vx = h["x"]
      vy = h["y"]
      puts (vx == nil).inspect  # false
      puts (vx != nil).inspect  # true
      puts (vy == nil).inspect  # false
      puts (vy != nil).inspect  # true

      # Symmetric: nil == int is also false.
      puts (nil == 0).inspect   # false
      puts (nil != 0).inspect   # true
    RUBY

    _(result).must_answer <<~'OUT'
      false
      true
      false
      true
      false
      true
      false
      false
      true
      false
      true
      false
      true
    OUT
  end

  it "local or and write" do
    result = zr(<<~'RUBY')
      # `LocalVariableOrWriteNode` (`a ||= b`) and
      # `LocalVariableAndWriteNode` (`a &&= b`) parse as their own
      # AST nodes — distinct from `LocalVariableOperatorWriteNode`
      # (which carries `+`, `-`, `*`, etc. via a binary_operator field).
      # Without dedicated parser cases the prism nodes were dropped on
      # the floor, so `a ||= b` produced no C output.

      # (1) Statement-form ||=
      a = nil
      a ||= 10
      puts a       # 10
      a ||= 99     # already truthy → no-op
      puts a       # 10

      # (2) Statement-form &&=
      b = 5
      b &&= b + 1
      puts b       # 6
      c = nil
      c &&= 99     # nil → no-op
      puts c.nil? ? "nil" : c.to_s   # nil

      # (3) Expression-form ||=
      x = nil
      y = (x ||= 7)
      puts x       # 7
      puts y       # 7

      # (4) Expression-form &&=
      p = 3
      q = (p &&= p * 2)
      puts p       # 6
      puts q       # 6
    RUBY

    _(result).must_answer <<~'OUT'
      10
      10
      6
      nil
      7
      7
      6
      6
    OUT
  end

  it "multi target nested" do
    result = zr(<<~'RUBY')
      # MultiTargetNode -- nested LHS in destructuring multi-assign.
      #
      #   a, (b, c), d = 1, [2, 3], 4
      #
      # Each parenthesized group on the LHS is a MultiTargetNode that
      # recursively unpacks its slot of the RHS. Here each inner-array RHS
      # slot holds one element type (Integer, String or Float). This test
      # does not cover two-level nesting where intermediate slots are
      # heterogeneous.

      a, (b, c), d = 1, [2, 3], 4
      puts a    # 1
      puts b    # 2
      puts c    # 3
      puts d    # 4

      # String-typed inner array
      x, (s, t), y = 10, ["hello", "world"], 20
      puts x    # 10
      puts s    # hello
      puts t    # world
      puts y    # 20
    RUBY

    _(result).must_answer <<~'OUT'
      1
      2
      3
      4
      10
      hello
      world
      20
    OUT
  end

  it "numbered block params" do
    result = zr(<<~'RUBY')
      # Numbered block params (`_1`) and Ruby 3.4 implicit `it`.
      #
      # `_1` was already supported via Prism's NumberedParametersNode + a
      # regular LocalVariableReadNode at the use site. Implicit `it` (Ruby
      # 3.4) was emitted as PM_IT_PARAMETERS_NODE / PM_IT_LOCAL_VARIABLE_READ_NODE
      # which the codegen had no handler for. spinel_parse now lowers both
      # to their `_1` equivalents so the codegen reuses the existing path.

      # 1. `_1` over an int array — each.
      [1, 2, 3].each { puts _1 }
      # 1
      # 2
      # 3

      # 2. `_1` over a map+each chain.
      [10, 20].map { _1 * 2 }.each { puts _1 }
      # 20
      # 40

      # 3. `it` over an int array — each with arithmetic.
      [1, 2, 3].each { puts it * 2 }
      # 2
      # 4
      # 6

      # 4. `it` over a map+each chain.
      [10, 20, 30].map { it * 2 }.each { puts it }
      # 20
      # 40
      # 60

      # 5. `it` mixed with arithmetic and comparison.
      [1, 2, 3, 4].select { it > 2 }.each { puts it }
      # 3
      # 4

      # 6. `it` over a string array.
      ["alice", "bob"].each { puts it }
      # alice
      # bob
    RUBY

    _(result).must_answer <<~'OUT'
      1
      2
      3
      20
      40
      2
      4
      6
      20
      40
      60
      3
      4
      alice
      bob
    OUT
  end

  it "numbered params destructure" do
    result = zr(<<~'RUBY')
      # Multi-arg numbered block params (`_1`, `_2`, ...) destructure the
      # yielded sub-array: `_1` does not bind to the whole element.
      # CRuby ref: arity-N blocks over a single Array argument auto-destructure.

      # Plain int-tuple sub-arrays - max=2 destructure
      [[1, 10], [2, 20], [3, 30]].each { puts "#{_1}=#{_2}" }

      # Three-element sub-arrays exercise _3
      [[1, 2, 3], [10, 20, 30]].each { puts "#{_1}-#{_2}-#{_3}" }

      # Sum of paired elements via destructured slots in `.each`
      total = 0
      [[1, 100], [2, 200], [3, 300]].each { total = total + _1 + _2 }
      puts total

      # Two-stage: outer each with _1+_2, inner reuse outside the block
      running = 0
      [[10, 1], [20, 2], [30, 3]].each { running = running + _1 - _2 }
      puts running

      # Short sub-array: the yielded element is shorter than the block's
      # max numbered param, so the missing param is nil. This test adds
      # `_2` only when `_2` is not nil. `_2` is mentioned in the block, so
      # the block destructures at least 2 params.
      short_total = 0
      [[1], [2, 20], [3, 30]].each { short_total = short_total + _1 + (_2.nil? ? 0 : _2) }
      puts short_total
    RUBY

    _(result).must_answer <<~'OUT'
      1=10
      2=20
      3=30
      1-2-3
      10-20-30
      606
      54
      56
    OUT
  end

  it "parens multi stmt and local write expr" do
    result = zr(<<~'RUBY')
      # Verify two expression-context constructs:
      # - `(stmt1; stmt2; ...; expr)` — leading statements run for
      #   side effects; the value of the parens is the last expression.
      # - `local = expr` and `local OP= expr` used as expressions —
      #   they assign and yield the new value of the local.

      # (1) Multi-stmt parens — leading side effects must run.
      x = 0
      y = (x = x + 1; x = x + 1; x)
      puts x      # 2
      puts y      # 2

      # (2) `local = expr` as the value of an outer expression.
      a = 0
      b = (a = 5)
      puts a      # 5
      puts b      # 5

      # (3) `local OP= expr` as the value of an outer expression.
      c = 10
      d = (c += 3)
      puts c      # 13
      puts d      # 13
    RUBY

    _(result).must_answer <<~'OUT'
      2
      2
      5
      5
      13
      13
    OUT
  end

  it "sort reduce" do
    result = zr(<<~'RUBY')
      # Test Array#sort, reduce, min, max, sum

      arr = (1..10).to_a
      arr.reverse!

      # sort
      sorted = arr.sort
      puts sorted.first  # 1
      puts sorted.last   # 10

      # min/max/sum
      puts arr.min   # 1
      puts arr.max   # 10
      puts arr.sum   # 55

      # reduce
      puts arr.reduce(0) { |sum, x| sum + x }   # 55
      puts arr.reduce(1) { |prod, x| prod * x } # 3628800

      # inject (alias)
      puts arr.inject(0) { |s, x| s + x }  # 55
    RUBY

    _(result).must_answer <<~'OUT'
      1
      10
      1
      10
      55
      55
      3628800
      55
    OUT
  end

  it "gc root map accumulator" do
    result = zr(<<~'RUBY')
      # A nested map block — outer iteration allocates plenty of inner
      # objects — can trigger a GC pass between pushes into the outer
      # accumulator. The GC must keep the accumulator alive.
      #
      # Each .map below crosses the GC threshold mid-loop (each block
      # iteration allocates a discarded scratch string alongside the
      # kept result), so the outer accumulator must survive a
      # collection.

      # (1) Integer-array recv → String results (string-return block).
      ints = []
      i = 0
      while i < 20000
        ints << i
        i += 1
      end

      r1 = ints.map do |x|
        _scratch = "scratch-#{x}-discarded-inner-allocation-padding"
        "kept-string-value-#{x}"
      end
      puts r1.length            # 20000
      puts r1[0]                # kept-string-value-0
      puts r1[19999][-3, 3]     # 999

      # (2) Integer-array recv → Integer results (int-return block).
      r2 = ints.map do |x|
        _scratch = "scratch-#{x}-discarded-inner-allocation-padding"
        x * 2
      end
      puts r2.length            # 20000
      puts r2[0]                # 0
      puts r2[19999]            # 39998

      # (3) String-array recv → String results (string-return block).
      strs = []
      i = 0
      while i < 20000
        strs << "src-#{i}"
        i += 1
      end

      r3 = strs.map do |s|
        _scratch = "scratch-#{s}-discarded-inner-allocation-padding"
        "out-#{s}"
      end
      puts r3.length            # 20000
      puts r3[0]                # out-src-0
      puts r3[19999][-3, 3]     # 999

      # (4) String-array recv → Integer results (int-return block).
      r4 = strs.map do |s|
        _scratch = "scratch-#{s}-discarded-inner-allocation-padding"
        s.length
      end
      puts r4.length            # 20000
      puts r4[0]                # 5  (out-0 → "src-0")
      puts r4[19999]            # 9  ("src-19999")
    RUBY

    _(result).must_answer <<~'OUT'
      20000
      kept-string-value-0
      999
      20000
      0
      39998
      20000
      out-src-0
      999
      20000
      5
      9
    OUT
  end

  it "gc root range and times map" do
    result = zr(<<~'RUBY')
      # `Range#map` and `N.times.map` build a fresh accumulator
      # (of Integers, Strings or Floats) and push each block result.
      # When the block allocates inside (e.g. string interpolation), a
      # GC pass can run mid-loop. The GC must keep the accumulator
      # alive.
      #
      # The "gc root map accumulator" test covers Array receivers. This
      # one covers `Range#map` and `N.times.map`.

      # (1) Range#map with string-allocating block.
      r1 = (0..3000).map { |i| "padded-string-#{i}-with-some-extra-text" }
      puts r1.length          # 3001
      puts r1[0][0, 6]        # padded
      puts r1[3000][-3, 3]    # ext

      # (2) Range#map with int block (heap pressure from inner allocations).
      r2 = (0...3000).map do |i|
        _scratch = "scratch-#{i}-discarded-inner-allocation-padding"
        i * 2
      end
      puts r2.length          # 3000
      puts r2[0]              # 0
      puts r2[2999]           # 5998

      # (3) N.times.map.
      r3 = 3000.times.map { |i| "kept-#{i}-with-extra-padding-text" }
      puts r3.length          # 3000
      puts r3[0]              # kept-0-with-extra-padding-text
      puts r3[2999][-3, 3]    # ext

      # (4) N.times.map with int block + scratch allocations.
      r4 = 3000.times.map do |i|
        _scratch = "scratch-#{i}-discarded-inner-allocation-padding"
        i + 1
      end
      puts r4.length          # 3000
      puts r4[0]              # 1
      puts r4[2999]           # 3000
    RUBY

    _(result).must_answer <<~'OUT'
      3001
      padded
      ext
      3000
      0
      5998
      3000
      kept-0-with-extra-padding-text
      ext
      3000
      1
      3000
    OUT
  end

  it "transpose gc root" do
    result = zr(<<~'RUBY')
      # `Array#transpose` builds the result array and its inner columns.
      # A collection that the next column's allocation triggers must not
      # free the result array.
      #
      # Trigger: a transpose of a large array-of-arrays. Optcarrot's
      # `(0..7).map { (0...0x10000).map {...} }.transpose` allocates
      # 8 outer + 65536 × 8 inner ints in close succession.

      big = (0..7).map { |a| (0..1023).map { |b| a * 1000 + b } }.transpose
      puts big.length        # 1024
      puts big[0].length     # 8
      puts big[100][3]       # 3*1000 + 100 = 3100
      puts big[1023][7]      # 7*1000 + 1023 = 8023
    RUBY

    _(result).must_answer <<~'OUT'
      1024
      8
      3100
      8023
    OUT
  end

  it "utf8" do
    result = zr(<<~'RUBY')
      s = "あいうえお"

      puts s.length          # 5
      puts s.size            # 5
      puts s.bytesize        # 15

      puts s.chars.length    # 5
      s.chars.each { |c| puts c }

      puts s.reverse         # おえういあ

      puts s[0]              # あ
      puts s[1]              # い
      puts s[4]              # お
      puts s[-1]             # お
      puts s[1, 2]           # いう
      puts s[1..3]           # いうえ
      puts s.slice(2, 2)     # うえ

      puts "hello#{s}world".index(s)   # 5  (char index, not byte)
      puts s.index("う")               # 2
      puts "あいあい".rindex("い")    # 3

      puts "あいう".tr("い", "X")     # あXう
      puts "ababab".count("a")        # 3
      puts "あいあいあ".count("あ")   # 3
      puts "あいあいあ".delete("い")  # あああ
      puts "ああいいうう".squeeze     # あいう

      puts "あ".ljust(5, "*")          # あ****
      puts "あ".rjust(5, "*")          # ****あ
      puts "あ".center(5)              # _あ__   (with spaces)
      puts "あ".ljust(5).length        # 5   (chars, including padding)

      puts "あ".succ                  # ぃ
      puts "az".succ                  # ba

      puts s.include?("うえ")          # true
      puts s.start_with?("あい")       # true
      puts s.end_with?("えお")         # true

      # each_char with non-ASCII
      out = ""
      "日本語".each_char { |c| out = out + "[" + c + "]" }
      puts out                          # [日][本][語]

      # split on empty separator
      "あいう".split("").each { |c| puts c }   # あ\nい\nう

      # bytes is still byte-based
      puts "あ".bytes.length            # 3
    RUBY

    _(result).must_answer <<~'OUT'
      5
      5
      15
      5
      あ
      い
      う
      え
      お
      おえういあ
      あ
      い
      お
      お
      いう
      いうえ
      うえ
      5
      2
      3
      あXう
      3
      3
      あああ
      あいう
      あ****
      ****あ
        あ  
      5
      ぃ
      ba
      true
      true
      true
      [日][本][語]
      あ
      い
      う
      3
    OUT
  end

  it "str nul bound slice bytes" do
    result = zr(<<~'RUBY')
      # A string with embedded NUL bytes is not cut at the first NUL:
      #
      #   - an s[a, n] slice reads past a NUL that comes after a.
      #   - s.bytes[i] includes the bytes after the first NUL.
      #
      # Concat also keeps the NULs.

      nul = 0.chr
      s = "abc" + nul + "def"
      puts "len=#{s.length}"
      puts "slice_full=#{s[0, 7].length}"
      puts "slice_after_nul=#{s[4, 3].length}"
      puts "slice_around_nul=#{s[2, 3].length}"
      puts "b0=#{s.bytes[0]}"
      puts "b3=#{s.bytes[3]}"
      puts "b4=#{s.bytes[4]}"
      puts "b6=#{s.bytes[6]}"
      puts "bytes_len=#{s.bytes.length}"
    RUBY

    _(result).must_answer <<~'OUT'
      len=7
      slice_full=7
      slice_after_nul=3
      slice_around_nul=3
      b0=97
      b3=0
      b4=100
      b6=102
      bytes_len=7
    OUT
  end

  it "str poly hash merge" do
    result = zr(<<~'RUBY')
      # `Hash#merge` on a String-keyed hash with mixed value types.
      #
      # Coverage:
      #   - mixed-value seed + Integer-valued override.
      #   - mixed-value seed + String-valued override.
      #   - mixed-value seed + mixed-value override.
      #
      # This test does not cover an argument whose Hash kind is only
      # known at run time.

      h = { "a" => 1, "b" => "two" }  # mixed values
      m = h.merge({ "c" => 3 })       # Integer-valued arg
      puts m.length                    # 3
      puts m["a"] == 1 ? "a-ok" : "a-bad"
      puts m["c"] == 3 ? "c-ok" : "c-bad"

      # String-valued override of a mixed-value recv.
      h2 = { "x" => 1, "y" => "two" }
      m2 = h2.merge({ "z" => "three" })
      puts m2.length                   # 3
      puts m2["z"] == "three" ? "z-ok" : "z-bad"

      # mixed-value override of a mixed-value recv.
      h3 = { "p" => 1, "q" => "two" }
      extra = { "r" => 3, "s" => "four" }
      m3 = h3.merge(extra)
      puts m3.length                   # 4
    RUBY

    _(result).must_answer <<~'OUT'
      3
      a-ok
      c-ok
      3
      z-ok
      4
    OUT
  end

  it "kw nil default string call" do
    result = zr(<<~'RUBY')
      # Each inner top-level def has a per-test prefix, so its name is
      # unique across the tests.


      def t_kw_show(x: nil)
        puts x
      end

      def t_kw_nil_default_string_call
        t_kw_show(x: "hi")
        t_kw_show(x: nil)
      end
      t_kw_nil_default_string_call
    RUBY

    _(result).must_answer "hi\n\n"
  end

  it "optional string param method" do
    result = zr(<<~'RUBY')
      # Each inner top-level def has a per-test prefix, so its name is
      # unique across the tests.


      def t_osp_parse(source, file_path = nil)
        if file_path
          puts file_path.length
        else
          puts source.length
        end
      end

      def t_optional_string_param_method
        t_osp_parse("abc", "name.rb")
        t_osp_parse("abc")
        t_osp_parse("longer", "another_name.rb")
      end
      t_optional_string_param_method
    RUBY

    _(result).must_answer <<~'OUT'
      7
      3
      15
    OUT
  end

  it "poly box int array" do
    result = zr(<<~'RUBY')
      # Each inner top-level def has a per-test prefix, so its name is
      # unique across the tests.


      def t_pbia_kind_of(a)
        a.nil? ? "nil" : "something"
      end

      def t_poly_box_int_array
        puts t_pbia_kind_of(Object.new)
        puts t_pbia_kind_of([1, 2, 3])
      end
      t_poly_box_int_array
    RUBY

    _(result).must_answer "something\nsomething\n"
  end

  it "poly or returns value" do
    result = zr(<<~'RUBY')
      # Each inner top-level def has a per-test prefix, so its name is
      # unique across the tests.


      def t_porv_pick(a, b)
        a || b
      end

      def t_porv_pick_int(a, b)
        a || b
      end

      def t_poly_or_returns_value
        puts t_porv_pick(nil, "fallback")
        puts t_porv_pick("actual", "fallback")
        puts t_porv_pick_int(0, 5)
        puts(nil || "direct")
      end
      t_poly_or_returns_value
    RUBY

    _(result).must_answer <<~'OUT'
      fallback
      actual
      0
      direct
    OUT
  end

  it "each with object seed shadow" do
    result = zr(<<~'RUBY')
      # Each inner top-level def has a per-test prefix, so its name is
      # unique across the tests.


      def t_ewoss_f
        obj = 42
        out = [1, 2, 3].each_with_object([]) { |x, obj| obj.push(x * 2) }
        puts out[0]   # 2
        puts out[1]   # 4
        puts out[2]   # 6
        puts obj      # 42
      end
      t_ewoss_f
    RUBY

    _(result).must_answer <<~'OUT'
      2
      4
      6
      42
    OUT
  end

  it "fetch nil default int lv" do
    result = zr(<<~'RUBY')
      # Each inner top-level def has a per-test prefix, so its name is
      # unique across the tests.


      def t_fndi_f(opts = {})
        v = opts.fetch(:k, nil)
        v.nil? ? "missing" : "found"
      end

      def t_fetch_nil_default_int_lv
        puts t_fndi_f
      end
      t_fetch_nil_default_int_lv
    RUBY

    _(result).must_answer "missing\n"
  end

  it "no keywords param" do
    result = zr(<<~'RUBY')
      # Each inner top-level def has a per-test prefix, so its name is
      # unique across the tests.


      def t_nkp_add(a, b, **nil)
        a + b
      end

      def t_no_keywords_param
        puts t_nkp_add(1, 2)
        puts t_nkp_add(10, 20)
      end
      t_no_keywords_param
    RUBY

    _(result).must_answer "3\n30\n"
  end

  it "sym case" do
    result = zr(<<~'RUBY')
      # Each inner top-level def has a per-test prefix, so its name is
      # unique across the tests.


      def t_sc_classify(sym)
        case sym
        when :red then "warm"
        when :orange then "warm"
        when :blue then "cool"
        when :green then "cool"
        else "unknown"
        end
      end

      def t_sym_case
        puts t_sc_classify(:red)
        puts t_sc_classify(:orange)
        puts t_sc_classify(:blue)
        puts t_sc_classify(:purple)
      end
      t_sym_case
    RUBY

    _(result).must_answer <<~'OUT'
      warm
      warm
      cool
      unknown
    OUT
  end

  it "a user class that defines length does not make every other class's array parameter poly" do
    result = zr(<<~'RUBY')
      # Defining `def length` on a class does not change the Integer-array
      # params of methods on unrelated classes. A param whose only called
      # method is `.length` can still be an Integer array, because every
      # built-in container also has `.length`. The call sites decide the
      # param's type.

      class Mat
        attr_accessor :flat, :nrows, :ncols
        def initialize(nrows, ncols)
          @nrows = nrows
          @ncols = ncols
          @flat  = Array.new(nrows * ncols, 0.0)
        end
      end

      class Net
        def backward(input_ids, logits)
          n_pred = input_ids.length - 1
          if n_pred <= 0
            return 0.0
          end
          self.cross_entropy_grad(logits, input_ids)
        end

        def cross_entropy_grad(logits, token_ids)
          n     = token_ids.length - 1
          total = 0.0
          i = 0
          while i < n
            target = token_ids[i + 1]
            total += logits.flat[target]
            i += 1
          end
          total
        end
      end

      def make_ids(s)
        parts = s.split(" ")
        ids   = [parts[0].to_i]
        k = 1
        while k < parts.length
          ids.push(parts[k].to_i)
          k += 1
        end
        ids
      end

      # The class with `def length` is the trigger. Net#backward and
      # Net#cross_entropy_grad must still take Integer-array
      # `input_ids` / `token_ids` params.
      class Bag
        attr_accessor :data
        def initialize(data); @data = data; end
        def length;           0;             end
      end

      prompt = make_ids("0 1 2")
      puts Net.new.backward(prompt, Mat.new(3, 4))
    RUBY

    _(result).must_answer "0.0\n"
  end

  it "a method writes into the Hash it was handed and the caller sees it" do
    result = zr(<<~'RUBY')
      def fill(h)
        h[1] = 100
      end
      h = {}
      fill(h)
      p h
      # also symbol key + direct-arg form
      def fill2(m)
        m[:x] = 9
        m[:y] = 8
      end
      g = {}
      fill2(g)
      p g
    RUBY

    _(result).must_answer "{1 => 100}\n{x: 9, y: 8}\n"
  end

  it "include? and index use ==, where uniq uses eql?" do
    result = zr(<<~'RUBY')
      class Point
        attr_reader :x
        def initialize(x) = @x = x
        def ==(o) = o.is_a?(Point) && @x == o.x
      end
      pts = [Point.new(1), Point.new(2), Point.new(3)]
      p pts.include?(Point.new(2))
      p pts.include?(Point.new(9))
      p pts.index(Point.new(3))
      p pts.index(Point.new(9))
      # uniq / Hash keys use eql? (identity for a class defining only ==), not ==
      p [Point.new(1), Point.new(1), Point.new(2)].uniq.map(&:x)
    RUBY

    _(result).must_answer <<~'OUT'
      true
      false
      2
      nil
      [1, 1, 2]
    OUT
  end

  it "reduce folds through a class's own + operator" do
    result = zr(<<~'RUBY')
      class Money
        attr_reader :cents
        def initialize(c) = @cents = c
        def +(o) = Money.new(@cents + o.cents)
        def to_s = "$#{@cents}"
      end
      xs = [Money.new(1), Money.new(2), Money.new(4)]
      p xs.reduce(Money.new(0)) { |a, x| a + x }.to_s
      p [1r, 2r].reduce(0r) { |a, x| a + x }
      p [1, 2, 3].reduce(0) { |a, x| a + x }
      p [Complex(1, 1), Complex(2, -1)].reduce(Complex(0, 0)) { |a, x| a + x }
    RUBY

    _(result).must_answer <<~'OUT'
      "$7"
      (3/1)
      6
      (3+0i)
    OUT
  end

  it "a method writes a key it was handed into the Hash it was handed" do
    result = zr(<<~'RUBY')
      def mark(h, k)
        h[k] = true
      end
      h = {}
      mark(h, :a)
      mark(h, :b)
      p h
      def put(m, k, v)
        m[k] = v
      end
      n = {}
      put(n, 7, "x")
      p n
    RUBY

    _(result).must_answer <<~'OUT'
      {a: true, b: true}
      {7 => "x"}
    OUT
  end

  it "Set membership goes through eql? and hash, so 1 and 1.0 are two members" do
    result = zr(<<~'RUBY')
      # Set membership uses #eql?/#hash (like CRuby's Hash-backed Set), so an
      # equal-but-distinct value object is found, and 1 / 1.0 are distinct members.
      require "set"

      class Point
        attr_reader :x, :y
        def initialize(x, y); @x = x; @y = y; end
        def hash = [x, y].hash
        def eql?(other) = other.is_a?(Point) && x == other.x && y == other.y
      end

      s = Set.new
      s << Point.new(3, 4)
      p s.include?(Point.new(3, 4))
      p s.add?(Point.new(3, 4))
      p s.size
      s.delete(Point.new(3, 4))
      p s.include?(Point.new(3, 4))

      n = Set.new
      n << 1
      p n.include?(1.0)
      p n.include?(1)
    RUBY

    _(result).must_answer <<~'OUT'
      true
      nil
      1
      false
      false
      true
    OUT
  end

  it "NoMethodError carries the arguments and whether the call was private" do
    result = zr(<<~'RUBY')
      p NoMethodError.new("m", :nm, [1, 2]).args
      p NoMethodError.new("m", :nm, [1], true).private_call?
      p NoMethodError.new("m", :nm, [1]).private_call?
    RUBY

    _(result).must_answer <<~'OUT'
      [1, 2]
      true
      false
    OUT
  end

  it "a keyword parameter after a splat takes only what is written as a keyword" do
    result = zr(<<~'RUBY')
      def f(*a, foo: nil); p a; p foo; end
      f("xyz", "bar")
      f("xyz", "bar", foo: 9)
      def g(a, foo: 1); p [a, foo]; end
      g(10)
      g(10, foo: 2)
      def h(*a, foo: 5, bar: 6); p [a, foo, bar]; end
      h(1, 2, 3)
      h(1, bar: 9)
    RUBY

    _(result).must_answer <<~'OUT'
      ["xyz", "bar"]
      nil
      ["xyz", "bar"]
      9
      [10, 1]
      [10, 2]
      [[1, 2, 3], 5, 6]
      [[1], 5, 9]
    OUT
  end

  it "an attr_accessor with no ivar written reads as nil, and a written false reads false" do
    result = zr(<<~'RUBY')
      class A
        attr_accessor :b, :i
        def initialize
          @i = 5
        end
        def setb = @b = true
      end
      a = A.new
      p a.b.nil?
      p a.i
      p a.i.nil?
      class C
        attr_accessor :flag
        def initialize
          @flag = false
        end
      end
      p C.new.flag
      p C.new.flag.nil?
    RUBY

    _(result).must_answer <<~'OUT'
      true
      5
      false
      false
      false
    OUT
  end

  it "a reader called inside initialize reaches the ivar it was just given" do
    result = zr(<<~'RUBY')
      class C
        attr_reader :arr, :nums
        def initialize
          @arr = []
          @nums = []
          arr << "a"
          arr << "b"
          nums << 1
        end
      end
      c = C.new
      p c.arr
      p c.nums
      class D
        attr_accessor :mix
        def initialize
          @mix = []
          mix << 1
          mix << "s"
        end
      end
      p D.new.mix
    RUBY

    _(result).must_answer <<~'OUT'
      ["a", "b"]
      [1]
      [1, "s"]
    OUT
  end

  it "tap on a fresh object writes to that object, not to the next one" do
    result = zr(<<~'RUBY')
      class Crash
        attr_accessor :foo
        def initialize = @foo = nil
      end

      Crash.new.tap { _1.foo = true }

      p Crash.new.foo
    RUBY

    _(result).must_answer "nil\n"
  end

  it "tap inside a method appends to the receiver's own collection" do
    result = zr(<<~'RUBY')
      class Crash
        attr_reader :foo

        def initialize = @foo = []
        def add(list) = list.tap { foo << _1 }
      end

      c = Crash.new
      c.add(Crash.new)
      c.add(Crash.new)
      p c.foo.size
      p c.foo.all? { |e| e.is_a?(Crash) }

      # explicit block param form
      class Box
        attr_reader :items
        def initialize = @items = []
        def push(x) = x.tap { |v| items << v }
      end
      b = Box.new
      b.push("a")
      b.push("b")
      p b.items
    RUBY

    _(result).must_answer <<~'OUT'
      2
      true
      ["a", "b"]
    OUT
  end

  it "a collection passed to another method is the same object the reader answers" do
    result = zr(<<~'RUBY')
      class Flag ; end
      class Config
        attr_reader :flags
        def initialize = @flags = []
        def add = add_to(flags)
        def add_to(collection) = collection << Flag.new
      end
      config = Config.new
      config.add
      config.add
      p config.flags.size
      p config.flags[0].is_a?(Flag)

      # direct @ivar arg + a manual reader
      class Box
        def initialize; @items = []; end
        def push_one; fill(@items); end
        def fill(coll); coll << Flag.new; end
        def items; @items; end
      end
      b = Box.new
      b.push_one
      p b.items[0].is_a?(Flag)
    RUBY

    _(result).must_answer <<~'OUT'
      2
      true
      true
    OUT
  end

  it "||= through a Hash parameter writes only the first time" do
    result = zr(<<~'RUBY')
      def store(memo, n)
        memo[n] ||= n * 10
      end
      memo = {}
      store(memo, 1)
      store(memo, 2)
      store(memo, 1)
      p memo.size
      p memo
      # string-key ||= through a param
      def store_s(h, k) = h[k] ||= "v"
      hs = {}
      store_s(hs, "x"); store_s(hs, "x")
      p hs
    RUBY

    _(result).must_answer <<~'OUT'
      2
      {1 => 10, 2 => 20}
      {"x" => "v"}
    OUT
  end

  it "a collection handed down two calls deep still collects" do
    result = zr(<<~'RUBY')
      class Flag; end
      class Crash
        attr_reader :flags
        def initialize
          @flags = []
          append(["--help"], @flags)
        end
        def append(names, collection)
          available = []
          names.each { available << _1 }
          add(Flag.new).tap { collection << _1 }
        end
        def add(flag) = flag
      end
      c = Crash.new
      p c.flags.size
      p c.flags[0].is_a?(Flag)
    RUBY

    _(result).must_answer "1\ntrue\n"
  end

  it "sub and gsub take their pattern and replacement from attribute readers" do
    result = zr(<<~'RUBY')
      class Config
        attr_accessor :name
      end
      config = Config.new
      config.name = "app"
      p "app".sub(config.name, config.name)
      p "banana".gsub(config.name, config.name)
      class C2; attr_accessor :pat, :rep; end
      c = C2.new; c.pat = "o"; c.rep = "0"
      p "foo".sub(c.pat, c.rep)
      p "foo".gsub(c.pat, c.rep)
    RUBY

    _(result).must_answer <<~'OUT'
      "app"
      "banana"
      "f0o"
      "f00"
    OUT
  end

  it "a method takes a value that is a String or nil and calls a String method on it" do
    result = zr(<<~'RUBY')
      def maybe_string(flag) = flag ? "foo" : nil
      def crash(value) = value.end_with?("o")
      p crash(maybe_string(true))
      def sw(v) = v.start_with?("f")
      p sw(maybe_string(true))
    RUBY

    _(result).must_answer "true\ntrue\n"
  end

  it "a shared string stays shared across a method boundary and through a reader" do
    result = zr(<<~'RUBY')
      # Shared-mutable strings across method boundaries (P5): a shared handle
      # passed into a string-mutating parameter, and aliases taken through
      # readers outside the class.
      def scream(x)
        x << "!"
      end
      def outer(y)
        scream(y)
        y << "?"
      end

      s = +"a"
      t = s
      s << +"b"
      scream(s)
      p s
      p t
      p s.equal?(t)

      u = +"plain"
      scream(u)
      p u

      v = +"deep"
      w = v
      v << "-"
      outer(v)
      p v
      p w

      scream(+"lit")

      class Doc
        attr_reader :title
        def initialize(t) = @title = t
        def bump = @title << "+"
      end
      d = Doc.new(+"aaa")
      ext = d.title
      d.bump
      p ext
      p ext.equal?(d.title)

      class Memo
        def initialize = @body = +"b"
        def body = @body
        def grow = @body << "1"
      end
      m = Memo.new
      x = m.body
      m.grow
      p x
    RUBY

    _(result).must_answer <<~'OUT'
      "ab!"
      "ab!"
      true
      "plain!"
      "deep-!?"
      "deep-!?"
      "aaa+"
      true
      "b1"
    OUT
  end

  it "every in-place String mutator reaches every binding that holds the string" do
    result = zr(<<~'RUBY')
      # mutator × storage 最終確認 matrix
      puts "== local alias =="
      a1=+"x"; a2=a1; a1<<"1"; p a2
      b1=+"x"; b2=b1; b1.upcase!; p b2
      c1=+"x"; c2=c1; c1.replace("R"); p c2
      d1=+"ax"; d2=d1; d1.slice!(0); p d2
      e1=+"x"; e2=e1; e1.insert(0,">"); p e2
      f1=+"x"; f2=f1; f1[0]="Z"; p f2
      g1=+"x"; g2=g1; g1.clear; p g2
      h1=+"Ab"; h2=h1; h1.setbyte(0,97); p h2
      puts "== container =="
      s=+"x"; arr=[s]; s<<"1"; s.upcase!; arr[0].reverse!; p arr; p s
      h={k:+"v"}; h[:k]<<"1"; p h
      puts "== ivar =="
      class C1; def initialize; @s=+"x"; t=@s; @s<<"1"; p t; end; end; C1.new
      puts "== param =="
      def mm(x)=x.gsub!(+"x","G"); q=+"x"; r=q; mm(q); p r
      puts "== capture =="
      cs=+"x"; ct=cs; pr=->{ cs<<"c" }; pr.call; p ct
      puts "== return =="
      $g=[]; def mk; s=+"x"; $g<<s; s; end; rr=mk; rr<<"r"; p $g[0]
      puts "== iteration =="
      ls=[+"a",+"b"]; ls.each{|x| x<<"!"}; p ls
      puts "== frozen =="
      fz="x".freeze; fw=fz; (fz<<"!" rescue p :frozen); p fw
    RUBY

    _(result).must_answer <<~'OUT'
      == local alias ==
      "x1"
      "X"
      "R"
      "x"
      ">x"
      "Z"
      ""
      "ab"
      == container ==
      ["1X"]
      "1X"
      {k: "v1"}
      == ivar ==
      "x1"
      == param ==
      "G"
      == capture ==
      "xc"
      == return ==
      "xr"
      == iteration ==
      ["a!", "b!"]
      == frozen ==
      :frozen
      "x"
    OUT
  end

  it "a promoted ivar read through reflection or interpolation hands out the current text" do
    result = zr(<<~'RUBY')
      # Promoted-ivar reads through reflection and formatting paths hand out safe
      # copies (never the raw handle); instance_variable_set joins the shared set.
      class W
        attr_reader :a, :b
        def initialize
          @a = +"aa"
          @b = "bb"
          t = @a
          @a << "!"
          p t
        end
      end
      w = W.new
      p w.a
      p w.instance_variable_get(:@a)
      puts "#{w.a}/#{w.b}"
      p({ x: w.a })
      p [w.a, w.b]
      p w.a.length
      p w.a == "aa!"
      s = w.a.dup
      s << "?"
      p s
      p w.a
      w.instance_variable_set(:@a, "set")
      p w.a
    RUBY

    _(result).must_answer <<~'OUT'
      "aa!"
      "aa!"
      "aa!"
      aa!/bb
      {x: "aa!"}
      ["aa!", "bb"]
      3
      true
      "aa!?"
      "aa!"
      "set"
    OUT
  end

  it "Method#super_method answers the superclass's method, or nil" do
    result = zr(<<~'RUBY')
      def dbl(n) = n * 2
      p method(:dbl) === 5
      p method(:dbl).super_method

      class Base
        def greet = "base"
      end
      class Sub < Base
        def greet = "sub"
      end
      sm = Sub.new.method(:greet).super_method
      p sm.class
      p sm.call
      p sm.inspect.start_with?("#<Method: Base#greet")
      p Sub.instance_method(:greet).super_method.inspect.start_with?("#<UnboundMethod: Base#greet")
      p Base.instance_method(:greet).source_location.is_a?(Array)
    RUBY

    _(result).must_answer <<~'OUT'
      10
      nil
      Method
      "base"
      true
      true
      true
    OUT
  end

  it "iterator? says whether the calling method was given a block" do
    result = zr(<<~'RUBY')
      def has_block? = iterator?
      p(has_block? { 1 })
      p(has_block?)
      def hb2
        iterator? ? "yes" : "no"
      end
      p(hb2 { })
      p(hb2)
    RUBY

    _(result).must_answer <<~'OUT'
      true
      false
      "yes"
      "no"
    OUT
  end

  it "an if with an empty then arm answers nil" do
    result = zr(<<~'RUBY')
      module TypedStore
        def self.parse(serialized)
          h = {}
          raw = serialized.to_s
          h["k"] = if raw == "true"
          elsif raw.length >= 2
            raw[1, raw.length - 2].to_s
          else
            raw
          end
          h
        end

        def self.write(serialized)
          parse(serialized)
        end
      end

      module Seeder
        def self.seed(stream)
          stream.write("")
        end
      end

      p TypedStore.write("abc")
      p TypedStore.write("true")
      p TypedStore.write("x")
    RUBY

    _(result).must_answer <<~'OUT'
      {"k" => "b"}
      {"k" => nil}
      {"k" => "x"}
    OUT
  end

  it "+= on an ivar array in initialize keeps what it accumulated" do
    result = zr(<<~'RUBY')
      class MyClass
        attr_reader :switches
        def initialize(opts)
          @switches = []
          @switches += opts
          @switches += []
          @more = [1]
          @more += [2, 3]
        end
        attr_reader :more
      end
      obj = MyClass.new(["--name", "-n"])
      p obj.switches
      p obj.more
    RUBY

    _(result).must_answer <<~'OUT'
      ["--name", "-n"]
      [1, 2, 3]
    OUT
  end

  it "a curried Method takes one argument at a time, or several" do
    result = zr(<<~'RUBY')
      def add(a, b) = a + b
      def add3(a, b, c) = a + b + c
      p(method(:add).curry[1][2])
      p(method(:add3).curry[1][2][3])
      p(method(:add3).curry[10, 20][12])

      def cat(a, b) = "#{a}-#{b}"
      c = method(:cat).curry
      p c["x"]["y"]

      class Calc
        def mul(a, b) = a * b
      end
      p(Calc.new.method(:mul).curry[6][7])
    RUBY

    _(result).must_answer <<~'OUT'
      3
      6
      42
      "x-y"
      42
    OUT
  end

  it "delete_at on an array of strings answers the element, or nil past the end" do
    result = zr(<<~'RUBY')
      # Two bugs from the Rails-emit boot crash: a poly-array receiver had no
      # delete_at arm, and "Set-Cookie" in a string tripped the textual Set
      # auto-require, whose top-of-buffer prepend pushed this file's magic
      # comment off the scanned lines (reverting the pragma to the default).
      class R
        attr_accessor :cookies
        def initialize
          @cookies = [+""]
          @cookies.delete_at(0)
        end
        def add(line) = @cookies.push(line)
      end
      r = R.new
      r.add("a=1")
      r.add("b=2")
      head = +""
      i = 0
      while i < r.cookies.length
        head << "Set-Cookie: " + r.cookies[i] + "\r\n"
        i += 1
      end
      puts head
      p r.cookies.delete_at(0)
      p r.cookies
      p r.cookies.delete_at(5)
    RUBY

    _(result).must_answer <<~'OUT'
      Set-Cookie: a=1
      Set-Cookie: b=2
      "a=1"
      ["b=2"]
      nil
    OUT
  end

  it "a parenthesised assignment from shift on an empty array compiles" do
    result = zr(<<~'RUBY')
      module Slap
        def self.parse(argv = ARGV) = Main.new.parse(argv)

        class Main
          def parse(argv) = Parser.new.parse(argv)
        end

        class Parser
          attr_reader :queue

          def parse(argv)
            @queue = argv
            parse_argv
          end

          def parse_argv
            (item = queue.shift)
          end
        end
      end

      argv = []
      Slap.parse(argv)
      puts "ok"
    RUBY

    _(result).must_answer "ok\n"
  end

  it "box, curry, clone and dup keep a Method's signature" do
    result = zr(<<~'RUBY')
      # The Method/UnboundMethod reflection tail: `#box` (nil for a method in no
      # namespace), `#curry`, and `#clone`/`#dup` keeping the signature.
      def dbl(n) = n * 2
      def add(a, b) = a + b
      p(method(:dbl).box)

      c1 = method(:add).curry
      raise "FAIL" unless c1[3][4] == 7
      raise "FAIL2" unless c1.lambda?

      class Calc
        def add(n)
          n + 1
        end
      end
      p(Calc.instance_method(:add).clone.arity)
      um = Calc.instance_method(:add)
      c = um.clone
      p(c.arity)
      d = method(:dbl).dup
      p(d.arity)
      b = method(:dbl).clone
      p(b.box)
      puts "ok"
    RUBY

    _(result).must_answer <<~'OUT'
      nil
      1
      1
      1
      nil
      ok
    OUT
  end

  it "insert and delete_at on an array of strings place and remove by index" do
    result = zr(<<~'RUBY')
      class R
        attr_accessor :cookies
        def initialize
          @cookies = [""]
          @cookies.delete_at(0)
        end

        def add(line)
          @cookies.push(line)
        end
      end

      r = R.new
      r.add("a=1")
      r.cookies.insert(0, "z=9")
      r.cookies.insert(-1, "t=2")
      head = +""
      i = 0
      while i < r.cookies.length
        head << "Set-Cookie: " + r.cookies[i] + "\r\n"
        i += 1
      end
      puts head
      p r.cookies.delete_at(0)
      p r.cookies.delete_at(5)
      p r.cookies
    RUBY

    _(result).must_answer <<~'OUT'
      Set-Cookie: z=9
      Set-Cookie: a=1
      Set-Cookie: t=2
      "z=9"
      nil
      ["a=1", "t=2"]
    OUT
  end

  it "a string reached through two readers is mutated in place" do
    result = zr(<<~'RUBY')
      class Sub
        attr_accessor :topic, :fd, :mode
        def initialize(topic, fd, mode)
          @topic = topic
          @fd = fd
          @mode = mode
        end
      end

      class App
        attr_accessor :subs
        def initialize
          @subs = [Sub.new("_", -1, 0)]
          @subs.delete_at(0)
        end

        def register(topic, fd)
          @subs << Sub.new(topic, fd, 1)
        end

        def grow_topics
          @subs[0].topic << "x" unless @subs.empty?
        end
      end

      a = App.new
      a.register(+"news", 3)
      a.grow_topics
      puts a.subs[0].topic

      subs = [Sub.new(+"local", 1, 0)]
      subs[0].topic << "!"
      subs[0].topic.upcase!
      puts subs[0].topic

      begin
        a.register("frozen-lit", 4)
        a.subs[1].topic << "x"
        puts "BUG: no raise"
      rescue FrozenError
        puts "FrozenError"
      end
    RUBY

    _(result).must_answer <<~'OUT'
      newsx
      LOCAL!
      BUG: no raise
    OUT
  end

  it "clear empties an array that was seeded with one element, and a Hash through a parameter" do
    result = zr(<<~'RUBY')
      class Res
        attr_accessor :cookies
        def initialize
          @cookies = [""]
          @cookies.clear
        end

        def add(name, value)
          @cookies.push(name + "=" + value)
        end
      end

      res = Res.new
      res.add("flash", "hello")
      head = +""
      res.cookies.each do |line|
        head << "Set-Cookie: " + line + "\r\n"
      end
      print head

      h = { a: 1 }
      def touch(x) = x
      v = touch(h)
      v.clear
      p h
    RUBY

    _(result).must_answer "Set-Cookie: flash=hello\n{}\n"
  end

  it "Integer#chr and String#chr both answer a one-character string" do
    result = zr(<<~'RUBY')
      def hexd(n)
        n < 10 ? ("0".getbyte(0) + n).chr : ("A".getbyte(0) + n - 10).chr
      end

      def pct(byte)
        "%" + hexd(byte >> 4) + hexd(byte & 15)
      end

      p pct("=".getbyte(0))
      p pct("&".getbyte(0))
      x = [61, "a"]
      v = x[0]
      p v.chr
      s = x[1]
      p s.chr
    RUBY

    _(result).must_answer <<~'OUT'
      "%3D"
      "%26"
      "="
      "a"
    OUT
  end

  it "probe arguments" do
    result = zr(<<~'RUBY')
      # Differential probe: ARGUMENT VALIDATION.
      #
      # Feeds deliberately-wrong arguments to the reflection and collection
      # surface and prints the exception class and message per row. A GOLDEN: the
      # `.expected` beside it is ruby 4.0.6's own answers, so every row is a
      # differential assertion and a divergence fails the suite.
      #
      # The point is to convert a long tail of one-off "zr accepts what ruby
      # refuses" findings into a finite list. Sixteen gap files were written one
      # at a time before this existed.
      #
      # Add rows freely, then re-bless: a row that AGREES costs one line of output
      # and becomes regression cover the moment someone breaks it.

      ROWS = {}

      def probe(name, &blk) = ROWS[name] = blk

      # Rows zr does not answer yet, each naming the gap that tracks it. A carved
      # row is left OUT of the output rather than recorded wrong -- one row cannot
      # be allowed to hold the other 74 out of the suite. When a gap is promoted,
      # delete its entry here and re-bless; the row comes back.
      SKIP = {
        "Module.new(arg)" => "tests/gaps/module_new_refuses_an_argument.rb",
      }.freeze

      # --- Names: ivars, constants, attributes, methods -------------------------
      o = Object.new
      probe("instance_variable_get(@@x)") { o.instance_variable_get("@@x") }
      probe("instance_variable_get(x)") { o.instance_variable_get("x") }
      probe("instance_variable_get(@1x)") { o.instance_variable_get("@1x") }
      probe("instance_variable_get(@)") { o.instance_variable_get("@") }
      probe("instance_variable_get(sym)") { o.instance_variable_get(:@ok) }
      probe("instance_variable_set(bad)") { o.instance_variable_set("@@x", 1) }
      probe("instance_variable_defined?(bad)") { o.instance_variable_defined?("x") }
      probe("remove_instance_variable(bad)") { o.remove_instance_variable("x") }
      probe("remove_instance_variable(absent)") { o.remove_instance_variable(:@nope) }

      k = Class.new
      probe("const_set(lower)") { k.const_set(:lower, 1) }
      probe("const_set(path)") { k.const_set("A::B", 1) }
      probe("const_set(empty)") { k.const_set("", 1) }
      probe("const_set(digit)") { k.const_set("1A", 1) }
      probe("const_get(lower)") { k.const_get(:lower) }
      probe("const_get(absent)") { k.const_get(:Absent) }
      probe("remove_const(absent)") { k.send(:remove_const, :Absent) }

      probe("attr_accessor(1bad)") { Class.new { attr_accessor :"1bad" } }
      probe("attr_accessor(ok then bad)") do
        c = Class.new { attr_accessor :ok, :"1bad" }
        c.instance_methods(false).sort.inspect
      end
      probe("attr_accessor(bang)") { Class.new { attr_accessor :"x!" } }
      probe("attr_accessor(int)") { Class.new { attr_accessor 1 } }
      probe("define_method(no body)") { Class.new { define_method(:x) } }
      probe("define_method(int)") { Class.new { define_method(:x, 1) } }
      probe("alias_method(absent)") { Class.new { alias_method :a, :nope } }
      probe("instance_method(absent)") { Class.new.instance_method(:nope) }

      # --- Modules and classes --------------------------------------------------
      probe("include(Class)") { Class.new { include String } }
      probe("include(Integer)") { Class.new { include 1 } }
      probe("include(self)") do
        m = Module.new
        m.send(:include, m)
      end
      probe("include(frozen, bad)") { Class.new.freeze.send(:include, String) }
      probe("include(frozen, good)") { Class.new.freeze.send(:include, Comparable) }
      probe("include(mod, Class)") { Class.new { include Comparable, String } }
      probe("prepend(Class)") { Class.new { prepend String } }
      probe("extend(Class)") { Object.new.extend(String) }
      probe("Class.new(Module)") { Class.new(Module.new) }
      probe("Class.new(Class)") { Class.new(Class) }
      probe("Class.new(Integer)") { Class.new(1) }
      probe("Class.new(singleton)") { Class.new(Object.new.singleton_class) }
      probe("Module.new(arg)") { Module.new(1) }

      # --- Procs and callables --------------------------------------------------
      pr = proc { |x| x }
      probe("proc >> Integer") { pr >> 7 }
      probe("proc << Integer") { pr << 7 }
      probe("proc >> Symbol") { (pr >> :to_s).call(1) }
      probe("proc >> proc") { (pr >> proc { |v| v }).call(1) }
      probe("Method#>> Integer") { 1.method(:+) >> 7 }
      probe("curry(bad)") { pr.curry(:x) }

      # --- Collections ----------------------------------------------------------
      probe("bsearch(String)") { [1, 2, 3].bsearch { "x" } }
      probe("bsearch(Float)") { [1, 2, 3].bsearch { 0.0 }.inspect }
      probe("bsearch(nil)") { [1, 2, 3].bsearch { nil }.inspect }
      probe("bsearch(NaN)") { [1, 2, 3].bsearch { Float::NAN }.inspect }
      probe("Array#fill(bad)") { [1].fill(1, :x) }
      probe("Array#first(-1)") { [1].first(-1) }
      probe("Array#take(-1)") { [1].take(-1) }
      probe("Array#sample(-1)") { [1].sample(-1) }
      probe("Array#[]=(bad)") { [1][:x] = 1 }
      probe("Array#flatten(bad)") { [1].flatten(:x) }
      probe("Hash#fetch(absent)") { {}.fetch(:x) }
      probe("Hash#merge(Integer)") { {}.merge(1) }
      probe("Hash#dig(bad)") { { a: 1 }.dig(:a, :b) }
      probe("Range#new(incomparable)") { Range.new(1, "a") }
      probe("Range#step(0)") { (1..3).step(0).to_a }
      probe("Range#step(-1)") { (1..3).step(-1).to_a }
      probe("String#*(-1)") { "a" * -1 }
      probe("String#[]=(absent)") { (+"a")["z"] = "b" }
      probe("Integer(bad)") { Integer("z") }
      probe("Integer(nil)") { Integer(nil) }
      probe("Float(bad)") { Float("z") }
      probe("Array#pack(bad)") { [1].pack("Z-") }
      probe("String#unpack(bad)") { "a".unpack("Z-") }

      # --- Queues and threads ---------------------------------------------------
      probe("Queue.new(arg)") { Thread::Queue.new(1) }
      probe("SizedQueue.new(0)") { Thread::SizedQueue.new(0) }
      probe("SizedQueue.new(-1)") { Thread::SizedQueue.new(-1) }
      probe("Queue#pop(true) empty") { Thread::Queue.new.pop(true) }
      probe("Queue#pop(true, timeout:)") { Thread::Queue.new.pop(true, timeout: 1) }

      # --- Marshal --------------------------------------------------------------
      probe("Marshal.dump(proc)") { Marshal.dump(proc {}) }
      probe("Marshal.dump(IO)") { Marshal.dump($stdout) }
      probe("Marshal.dump(singleton)") do
        s = Object.new
        def s.x = 1
        Marshal.dump(s)
      end
      probe("Marshal.dump(extended)") do
        s = Object.new
        s.extend(Comparable)
        Marshal.dump(s).bytesize.positive?
      end

      ROWS.each do |name, fn|
        next if SKIP.key?(name)

        r = begin
          v = fn.call
          "ok #{v.inspect}"
        rescue Exception => e
          "#{e.class}: #{e.message}"
        end
        puts "#{name}\t#{r}"
      end
    RUBY

    _(result).must_answer <<~'OUT'
      instance_variable_get(@@x)	NameError: '@@x' is not allowed as an instance variable name
      instance_variable_get(x)	NameError: 'x' is not allowed as an instance variable name
      instance_variable_get(@1x)	NameError: '@1x' is not allowed as an instance variable name
      instance_variable_get(@)	NameError: '@' is not allowed as an instance variable name
      instance_variable_get(sym)	ok nil
      instance_variable_set(bad)	NameError: '@@x' is not allowed as an instance variable name
      instance_variable_defined?(bad)	NameError: 'x' is not allowed as an instance variable name
      remove_instance_variable(bad)	NameError: 'x' is not allowed as an instance variable name
      remove_instance_variable(absent)	NameError: instance variable @nope not defined
      const_set(lower)	NameError: wrong constant name lower
      const_set(path)	NameError: wrong constant name A::B
      const_set(empty)	NameError: wrong constant name 
      const_set(digit)	NameError: wrong constant name 1A
      const_get(lower)	NameError: wrong constant name lower
      const_get(absent)	NameError: uninitialized constant #<Class:0xADDR>::Absent
      remove_const(absent)	NameError: constant #<Class:0xADDR>::Absent not defined
      attr_accessor(1bad)	NameError: invalid attribute name '1bad'
      attr_accessor(ok then bad)	NameError: invalid attribute name '1bad'
      attr_accessor(bang)	NameError: invalid attribute name 'x!'
      attr_accessor(int)	TypeError: 1 is not a symbol nor a string
      define_method(no body)	ArgumentError: tried to create Proc object without a block
      define_method(int)	TypeError: wrong argument type Integer (expected Proc/Method/UnboundMethod)
      alias_method(absent)	NameError: undefined method 'nope' for class '#<Class:0xADDR>'
      instance_method(absent)	NameError: undefined method 'nope' for class '#<Class:0xADDR>'
      include(Class)	TypeError: wrong argument type Class (expected Module)
      include(Integer)	TypeError: wrong argument type Integer (expected Module)
      include(self)	ArgumentError: cyclic include detected
      include(frozen, bad)	TypeError: wrong argument type Class (expected Module)
      include(frozen, good)	FrozenError: can't modify frozen Class: #<Class:0xADDR>
      include(mod, Class)	TypeError: wrong argument type Class (expected Module)
      prepend(Class)	TypeError: wrong argument type Class (expected Module)
      extend(Class)	TypeError: wrong argument type Class (expected Module)
      Class.new(Module)	TypeError: superclass must be an instance of Class (given an instance of Module)
      Class.new(Class)	TypeError: can't make subclass of Class
      Class.new(Integer)	TypeError: superclass must be an instance of Class (given an instance of Integer)
      Class.new(singleton)	TypeError: can't make subclass of singleton class
      proc >> Integer	TypeError: callable object is expected
      proc << Integer	TypeError: callable object is expected
      proc >> Symbol	TypeError: callable object is expected
      proc >> proc	ok 1
      Method#>> Integer	TypeError: callable object is expected
      curry(bad)	TypeError: no implicit conversion of Symbol into Integer
      bsearch(String)	TypeError: wrong argument type String (must be numeric, true, false or nil)
      bsearch(Float)	ok "2"
      bsearch(nil)	ok "nil"
      bsearch(NaN)	ArgumentError: comparison of Float with 0 failed
      Array#fill(bad)	TypeError: no implicit conversion of Symbol into Integer
      Array#first(-1)	ArgumentError: negative array size
      Array#take(-1)	ArgumentError: attempt to take negative size
      Array#sample(-1)	ArgumentError: negative sample number
      Array#[]=(bad)	TypeError: no implicit conversion of Symbol into Integer
      Array#flatten(bad)	TypeError: no implicit conversion of Symbol into Integer
      Hash#fetch(absent)	KeyError: key not found: :x
      Hash#merge(Integer)	TypeError: no implicit conversion of Integer into Hash
      Hash#dig(bad)	TypeError: Integer does not have #dig method
      Range#new(incomparable)	ArgumentError: bad value for range
      Range#step(0)	ArgumentError: step can't be 0
      Range#step(-1)	ok []
      String#*(-1)	ArgumentError: negative argument
      String#[]=(absent)	IndexError: string not matched
      Integer(bad)	ArgumentError: invalid value for Integer(): "z"
      Integer(nil)	TypeError: can't convert nil into Integer
      Float(bad)	ArgumentError: invalid value for Float(): "z"
      Array#pack(bad)	TypeError: no implicit conversion of Integer into String
      String#unpack(bad)	ArgumentError: unknown unpack directive '-' in 'Z-'
      Queue.new(arg)	TypeError: can't convert Integer into Array
      SizedQueue.new(0)	ArgumentError: queue size must be positive
      SizedQueue.new(-1)	ArgumentError: queue size must be positive
      Queue#pop(true) empty	ThreadError: queue empty
      Queue#pop(true, timeout:)	ArgumentError: can't set a timeout if non_block is enabled
      Marshal.dump(proc)	TypeError: no _dump_data is defined for class Proc
      Marshal.dump(IO)	TypeError: can't dump IO
      Marshal.dump(singleton)	TypeError: singleton can't be dumped
      Marshal.dump(extended)	ok true
    OUT
  end
end
