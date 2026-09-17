# frozen_string_literal: true

require "spec_helper"

describe "Programs programs" do
  it "bitwise mask over int64" do
    result = ze0(<<~'RUBY')
      # A bitwise op whose literal operand exceeds int64 (a 64-bit mask such as
      # 0xFFFFFFFFFFFFFFFF, typed as a bigint) must still lower -- the result slot
      # is int and takes the low-64 bit pattern. The xorshift64 / 64-bit-mask
      # idiom. (#1513)
      x = 12345
      puts(x & 0xFFFFFFFFFFFFFFFF)        # 12345
      puts(255 & 0xFFFFFFFFFFFFFFFF)      # 255
      puts(0 & 0xFFFFFFFFFFFFFFFF)        # 0
      y = 0xDEADBEEF
      puts((y ^ 0x12345678) & 0xFFFFFFFFFFFFFFFF)   # 3432638615
      # one xorshift64 step on a fixed seed (deterministic)
      s = 88172645463325252
      s ^= (s << 13) & 0xFFFFFFFFFFFFFFFF
      s ^= (s >> 7)  & 0xFFFFFFFFFFFFFFFF
      s ^= (s << 17) & 0xFFFFFFFFFFFFFFFF
      puts(s & 0xFFFFFFFF)                # low-32 of the mixed state
    RUBY

    _(result).must_answer <<~'OUT'
      12345
      255
      0
      3432638615
      4225635760
    OUT
  end

  it "case mapping methods take no options" do
    result = ze0(<<~'RUBY')
      # `upcase`/`downcase`/`capitalize`/`swapcase` -- and their `!` and `Symbol`
      # twins -- accept NO arguments in zeo, so every one of ruby's case-mapping
      # options is an `ArgumentError`.
      #
      # Ruby's options are four, and they are not decoration:
      #
      #   :ascii        map only `a-z`/`A-Z` and leave every other codepoint
      #                 alone. This is what a protocol wants -- an HTTP header
      #                 name, a hex digit -- and getting it wrong is a silent data
      #                 change, not an error: `"straße".upcase(:ascii)` is
      #                 `"STRAßE"`, where the full mapping gives `"STRASSE"` and
      #                 the string gets LONGER.
      #   :turkic       dotted/dotless I. `"i".upcase(:turkic)` is `"İ"`.
      #   :lithuanian   the accent rules, currently only for `i`.
      #   :fold         case folding rather than case mapping, for `downcase`.
      #
      # zeo's rows are declared with no parameters at all, so this is a DSL arity
      # question first and a mapping question second: the tables behind the option
      # are Unicode's `SpecialCasing.txt` conditional mappings, which the encoding
      # work already parses for the unconditional case.
      #
      # Two or more options may be given together (`:turkic, :lithuanian`), and an
      # unknown one is `ArgumentError: invalid option` -- a different message from
      # the arity error zeo raises today, which is what makes a caller's `rescue
      # ArgumentError` around a probe silently take the wrong branch.
      #
      # Oracle: every row answers.
      %w[straße ÄB äb äB i I].each_with_index do |s, i|
        p [i, s.upcase(:ascii), s.downcase(:ascii), s.capitalize(:ascii), s.swapcase(:ascii)]
      end
      p "i".upcase(:turkic)
      p "I".downcase(:turkic)
      p "i".upcase(:lithuanian)
      p "İ".downcase(:fold)
      p "i".upcase(:turkic, :lithuanian)
      p :äb.upcase(:ascii)
      s = "äb".dup
      s.upcase!(:ascii)
      p s
      begin
        "i".upcase(:nope)
      rescue ArgumentError => e
        p e.message
      end
    RUBY

    _(result).must_answer <<~'OUT'
      [0, "STRAßE", "straße", "Straße", "STRAßE"]
      [1, "ÄB", "Äb", "Äb", "Äb"]
      [2, "äB", "äb", "äb", "äB"]
      [3, "äB", "äb", "äb", "äb"]
      [4, "I", "i", "I", "I"]
      [5, "I", "i", "I", "i"]
      "İ"
      "ı"
      "I"
      "i̇"
      "İ"
      :äB
      "äB"
      "invalid option"
    OUT
  end

  it "case value untaken arm effects" do
    result = ze0(<<~'RUBY')
      # case-as-value: an untaken arm's value construction must not run. The arm
      # values here need setup statements (array literals, a raising call as an
      # element), which used to hoist ahead of the branch dispatch and fire
      # unconditionally.

      def bad
        raise "boom"
      end

      def pick(kind)
        case kind
        when "A" then [1, 0]
        when "B" then [2, bad]
        end
      end

      p pick("A")

      # side effects in the TAKEN arm run exactly once
      $count = 0
      def tick
        $count += 1
        $count
      end

      def build(kind)
        case kind
        when :a then [tick, 10]
        when :b then [tick, 20]
        else [tick, 30]
        end
      end

      p build(:b)
      p $count
      p build(:x)
      p $count

      # int scrutinee with literal labels (the C-switch fast path) scopes arm
      # construction the same way
      def by_num(n)
        case n
        when 1 then [1, bad]
        when 2 then ["two", 2]
        else [0, bad]
        end
      end

      p by_num(2)

      # the raising arm still raises when it IS taken
      begin
        pick("B")
      rescue RuntimeError => e
        puts e.message
      end
    RUBY

    _(result).must_answer <<~'OUT'
      [1, 0]
      [1, 20]
      1
      [2, 30]
      2
      ["two", 2]
      boom
    OUT
  end

  it "core breadth" do
    result = ze0(<<~'RUBY')
      # Phase 17.1 -- Tier A breadth across String/Symbol/Array/Hash/Range/
      # Enumerable/Kernel, resolved down the CRuby-exact ancestor chains
      # (Comparable driving <=>, Enumerable driving each, Kernel's universals).

      p "hello world".capitalize
      p "  hi  ".strip
      p "a,b,,c".split(",")
      p "hello".gsub("l") { |m| m.upcase }
      p "hello".tr("a-y", "b-z")
      p "az".succ
      p "Hello %s, you are %d" % ["Bob", 42]
      p "hi".center(7, "*")
      p :hello.length
      p [3, 1, 2].map(&:to_s)

      p "abc" < "abd"
      p "m".clamp("a", "f")
      p 5.between?(1, 10)

      p [1, 2] | [2, 3]
      p [1, [2, [3]]].flatten
      p [1, 2, 2, 3, 1].uniq
      p [1, 2, 3].join("-")
      p [[1, [2, 3]]].dig(0, 1, 0)
      p [1, 2, 3].zip([4, 5, 6])
      p [0, 1, 2, 3, 4][1..3]
      p [3, 1, 2].sort { |a, b| b <=> a }

      h = { a: 1, b: 2 }
      p h.merge({ a: 9 }) { |k, old, new| old + new }
      p h.invert
      p h.transform_values { |v| v * 10 }
      p h.select { |k, v| v > 1 }
      p({ x: { y: 5 } }.dig(:x, :y))

      p (1..6).group_by { |x| x % 3 }
      p [1, 2, 3, 4].partition { |x| x.even? }
      p ["a", "b", "a"].tally
      p [1, 2, 3].each_with_object([]) { |x, memo| memo << x * 10 }
      acc = []
      (1..10).step(3) { |x| acc << x }
      p acc
      p ("a".."e").to_a

      puts [1, [2, nil]], "done"
      r = p 1, "two"
      p r
      caught = catch(:stop) do
        [5, 6, 7].each { |x| throw :stop, x * 2 if x == 6 }
      end
      p caught

      case 42
      when 1..50 then puts "in range"
      end
      p [1, 2].respond_to?(:map)
      p 5.is_a?(Comparable)
    RUBY

    _(result).must_answer <<~'OUT'
      "Hello world"
      "hi"
      ["a", "b", "", "c"]
      "heLLo"
      "ifmmp"
      "ba"
      "Hello Bob, you are 42"
      "**hi***"
      5
      ["3", "1", "2"]
      true
      "f"
      true
      [1, 2, 3]
      [1, 2, 3]
      [1, 2, 3]
      "1-2-3"
      2
      [[1, 4], [2, 5], [3, 6]]
      [1, 2, 3]
      [3, 2, 1]
      {a: 10, b: 2}
      {1 => :a, 2 => :b}
      {a: 10, b: 20}
      {b: 2}
      5
      {1 => [1, 4], 2 => [2, 5], 0 => [3, 6]}
      [[2, 4], [1, 3]]
      {"a" => 2, "b" => 1}
      [10, 20, 30]
      [1, 4, 7, 10]
      ["a", "b", "c", "d", "e"]
      1
      2

      done
      1
      "two"
      [1, "two"]
      12
      in range
      true
      true
    OUT
  end

  it "defined op" do
    result = ze0(<<~'RUBY')
      # Issue #711. `defined?(expr)` used to emit a raw pointer value
      # (printed as a giant integer) instead of a tag string. Now resolves
      # at compile time to "local-variable" / "instance-variable" /
      # "constant" / "method" / "expression" with a NULL `const char*`
      # for the nil cases (which `puts` already handles as an empty line).

      puts defined?(undefined_local)
      z = 1
      puts defined?(z)
      puts defined?(@undef_ivar)
      puts defined?(Object)
      puts defined?(undefined_method)
      puts defined?(nil)
      puts defined?(self)

      @written_ivar = "x"
      puts defined?(@written_ivar)
    RUBY

    _(result).must_answer <<~'OUT'

      local-variable

      constant

      nil
      self
      instance-variable
    OUT
  end

  it "each entry reverse each" do
    result = ze0(<<~'RUBY')
      # Enumerable#each_entry alias of each; Enumerable#reverse_each
      # walks the receiver in reverse.

      [1, 2, 3].each_entry { |x| puts x }
      puts "---"
      [1, 2, 3].reverse_each { |x| puts x }
      puts "---"
      ["a", "b", "c"].reverse_each { |s| puts s }
    RUBY

    _(result).must_answer <<~'OUT'
      1
      2
      3
      ---
      3
      2
      1
      ---
      c
      b
      a
    OUT
  end

  it "env key p" do
    result = ze0(<<~'RUBY')
      # ENV.key? / has_key? / include? / member? -> getenv presence (bool).
      # Previously an unresolved call ("undefined method 'key?' for unknown").
      p ENV.key?("PATH")
      p ENV.key?("SPINEL_NO_SUCH_VAR_12345")
      ENV["SPINEL_ENV_KEY_TEST"] = "1"
      p ENV.has_key?("SPINEL_ENV_KEY_TEST")
      p ENV.include?("SPINEL_ENV_KEY_TEST")
      p ENV.member?("SPINEL_ENV_KEY_TEST")
      ENV["SPINEL_ENV_KEY_TEST"] = nil
      p ENV.key?("SPINEL_ENV_KEY_TEST")
      minimal = ENV.key?("MINIMAL_NO_SUCH")
      p minimal ? 1 : 0
    RUBY

    _(result).must_answer <<~'OUT'
      true
      false
      true
      true
      true
      false
      0
    OUT
  end

  it "fiddle" do
    skip "runs only on macos" unless ["macos"].include?(Ze0::Spec.platform)

    result = ze0(<<~'RUBY')

      require "fiddle"

      # -- the TYPE_* constant table (values are the C extension's, verified) --
      puts [Fiddle::TYPE_VOID, Fiddle::TYPE_VOIDP, Fiddle::TYPE_CHAR, Fiddle::TYPE_UCHAR,
            Fiddle::TYPE_SHORT, Fiddle::TYPE_USHORT, Fiddle::TYPE_INT, Fiddle::TYPE_UINT,
            Fiddle::TYPE_LONG, Fiddle::TYPE_ULONG, Fiddle::TYPE_LONG_LONG, Fiddle::TYPE_ULONG_LONG,
            Fiddle::TYPE_FLOAT, Fiddle::TYPE_DOUBLE, Fiddle::TYPE_VARIADIC, Fiddle::TYPE_CONST_STRING,
            Fiddle::TYPE_BOOL].join(",")
      puts [Fiddle::TYPE_INT8_T, Fiddle::TYPE_UINT8_T, Fiddle::TYPE_INT16_T, Fiddle::TYPE_UINT16_T,
            Fiddle::TYPE_INT32_T, Fiddle::TYPE_UINT32_T, Fiddle::TYPE_INT64_T, Fiddle::TYPE_UINT64_T,
            Fiddle::TYPE_SSIZE_T, Fiddle::TYPE_SIZE_T, Fiddle::TYPE_PTRDIFF_T, Fiddle::TYPE_INTPTR_T,
            Fiddle::TYPE_UINTPTR_T].join(",")
      puts [Fiddle::SIZEOF_VOIDP, Fiddle::SIZEOF_CHAR, Fiddle::SIZEOF_SHORT, Fiddle::SIZEOF_INT,
            Fiddle::SIZEOF_LONG, Fiddle::SIZEOF_LONG_LONG, Fiddle::SIZEOF_FLOAT, Fiddle::SIZEOF_DOUBLE,
            Fiddle::SIZEOF_BOOL, Fiddle::SIZEOF_SIZE_T, Fiddle::SIZEOF_INT64_T,
            Fiddle::SIZEOF_CONST_STRING].join(",")
      puts [Fiddle::ALIGN_VOIDP, Fiddle::ALIGN_CHAR, Fiddle::ALIGN_SHORT, Fiddle::ALIGN_INT,
            Fiddle::ALIGN_LONG, Fiddle::ALIGN_LONG_LONG, Fiddle::ALIGN_FLOAT, Fiddle::ALIGN_DOUBLE,
            Fiddle::ALIGN_BOOL, Fiddle::ALIGN_SIZE_T, Fiddle::ALIGN_INT64_T].join(",")
      p [Fiddle::RTLD_LAZY, Fiddle::RTLD_NOW, Fiddle::RTLD_GLOBAL]
      p Fiddle::WINDOWS

      # -- Handle + sym --
      h = Fiddle.dlopen(nil)
      p h.class
      p h.sym("strlen").class
      p !!Fiddle::Handle.sym_defined?("strlen")
      p !!Fiddle::Handle.sym_defined?("zzz_no_such_symbol")
      begin
        h.sym("zzz_no_such_symbol")
      rescue Fiddle::DLError => e
        p [e.class, e.message]
      end
      p Fiddle::Handle::DEFAULT.class
      h2 = Fiddle::Handle.new
      p h2.close
      begin
        h2.sym("strlen")
      rescue Fiddle::DLError => e
        p [e.class, e.message]
      end

      # -- Function: fixed-arg calls across the scalar types --
      strlen = Fiddle::Function.new(h.sym("strlen"), [Fiddle::TYPE_VOIDP], Fiddle::TYPE_SIZE_T)
      p strlen.call("hello, fiddle")
      pow = Fiddle::Function.new(h.sym("pow"), [Fiddle::TYPE_DOUBLE, Fiddle::TYPE_DOUBLE], Fiddle::TYPE_DOUBLE)
      p pow.call(2.0, 10.0)
      labs = Fiddle::Function.new(h.sym("labs"), [Fiddle::TYPE_LONG], Fiddle::TYPE_LONG)
      p labs.call(-42)
      strcpy = Fiddle::Function.new(h.sym("strcpy"), [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP], Fiddle::TYPE_VOIDP)
      buf = Fiddle::Pointer.malloc(32, Fiddle::RUBY_FREE)
      r = strcpy.call(buf, "copied!")
      p r.class
      p r.to_s
      p buf.to_s

      # -- Pointer surface --
      p Fiddle::NULL.class
      p Fiddle::NULL.null?
      p Fiddle::NULL.to_i
      p Fiddle::NULL.size
      p (Fiddle::NULL + 5).to_i
      s = Fiddle::Pointer["hello world"]
      p s.class
      p s.size
      p s.to_s
      p s.to_s(5)
      p s.to_str
      p s[0]
      p s[0, 5]
      s[0] = 72
      p s.to_s
      q = s + 6
      p q.to_s
      p q.size
      p (q - 6) == s
      p [s <=> q, q <=> s, s <=> s]
      p s.eql?(s)
      p s == 12
      mem = Fiddle::Pointer.malloc(16, Fiddle::RUBY_FREE)
      mem[0, 8] = "abcdefgh"
      p mem[0, 8]
      p mem.size
      ref = mem.ref
      p ref.class
      p ref.ptr.to_i == mem.to_i
      p (-mem).ptr.to_i == mem.to_i
      p (+ref).to_i == mem.to_i
      p mem.freed?
      mem2 = Fiddle::Pointer.malloc(4)
      p mem2.free
      src = Fiddle::Pointer["ABCDEF"]
      p Fiddle::Pointer.read(src.to_i, 3)
      Fiddle::Pointer.write(src.to_i, "xy")
      p src.to_s

      # -- module malloc/free (C semantics: a raw address Integer) --
      a = Fiddle.malloc(8)
      p a.class
      p Fiddle.free(a)

      # -- NULL access error shapes --
      begin
        Fiddle::NULL.to_s
      rescue ArgumentError => e
        p [e.class, e.message]
      end
      p Fiddle::NULL.to_str
      begin
        Fiddle::NULL[0]
      rescue Fiddle::DLError => e
        p [e.class, e.message]
      end
      begin
        Fiddle::NULL[0] = 65
      rescue Fiddle::DLError => e
        p [e.class, e.message]
      end

      # -- errors hierarchy --
      p Fiddle::DLError.ancestors[0, 3]
      p Fiddle::ClearedReferenceError.ancestors[0, 3]

      # -- last_error --
      Fiddle.last_error = 0
      p Fiddle.last_error

      # -- closures: qsort through a BlockCaller --
      cmp = Fiddle::Closure::BlockCaller.new(Fiddle::TYPE_INT, [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP]) do |x, y|
        x[0] - y[0]
      end
      qsort = Fiddle::Function.new(h.sym("qsort"),
        [Fiddle::TYPE_VOIDP, Fiddle::TYPE_SIZE_T, Fiddle::TYPE_SIZE_T, Fiddle::TYPE_VOIDP],
        Fiddle::TYPE_VOID)
      data = Fiddle::Pointer["edcba"]
      qsort.call(data, 5, 1, cmp)
      p data.to_s
      p cmp.freed?
      p cmp.args
      p cmp.ctype
      cmp2 = Fiddle::Closure::BlockCaller.new(Fiddle::TYPE_INT, [Fiddle::TYPE_INT]) { |x| x * 2 }
      p cmp2.to_i.class
      cmp2.free
      p cmp2.freed?

      # -- a closure as a Function target --
      dbl = Fiddle::Closure::BlockCaller.new(Fiddle::TYPE_INT, [Fiddle::TYPE_INT]) { |x| x + x }
      f = Fiddle::Function.new(dbl, [Fiddle::TYPE_INT], Fiddle::TYPE_INT)
      p f.call(21)

      # -- Function odds --
      p strlen.to_proc.call("abc")
      named = Fiddle::Function.new(h.sym("strlen"), [Fiddle::TYPE_VOIDP], Fiddle::TYPE_INT, name: "strlen")
      p named.name
      p named.abi == Fiddle::Function::DEFAULT
      p strlen.to_i.class
      begin
        Fiddle::Function.new(h.sym("strlen"), Fiddle::TYPE_VOIDP, Fiddle::TYPE_INT)
      rescue TypeError => e
        p [e.class, e.message]
      end
      begin
        Fiddle::Function.new(h.sym("strlen"), [Fiddle::TYPE_VOIDP], 99)
      rescue RuntimeError => e
        p [e.class, e.message]
      end

      # -- variadic --
      snprintf = Fiddle::Function.new(h.sym("snprintf"),
        [Fiddle::TYPE_VOIDP, Fiddle::TYPE_SIZE_T, Fiddle::TYPE_CONST_STRING, Fiddle::TYPE_VARIADIC],
        Fiddle::TYPE_INT)
      out = Fiddle::Pointer.malloc(64, Fiddle::RUBY_FREE)
      n = snprintf.call(out, 64, "d=%d s=%s f=%.2f", Fiddle::TYPE_INT, 42, :const_string, "hi", Fiddle::TYPE_DOUBLE, 2.5)
      p n
      p out.to_s

      # -- Pinned --
      pin = Fiddle::Pinned.new("obj")
      p pin.ref
      p pin.cleared?
      pin.clear
      p pin.cleared?
      begin
        pin.ref
      rescue Fiddle::ClearedReferenceError => e
        p [e.class, e.message]
      end
    RUBY

    _(result).must_answer <<~'OUT'
      0,1,2,-2,3,-3,4,-4,5,-5,6,-6,7,8,9,10,11
      2,-2,3,-3,4,-4,5,-5,5,-5,5,5,-5
      8,1,2,4,8,8,4,8,1,8,8,8
      8,1,2,4,8,8,4,8,1,8,8
      [1, 2, 8]
      false
      Fiddle::Handle
      Integer
      true
      false
      [Fiddle::DLError, "unknown symbol \"zzz_no_such_symbol\""]
      Fiddle::Handle
      0
      [Fiddle::DLError, "closed handle"]
      13
      1024.0
      42
      Fiddle::Pointer
      "copied!"
      "copied!"
      Fiddle::Pointer
      true
      0
      0
      5
      Fiddle::Pointer
      11
      "hello world"
      "hello"
      "hello world"
      104
      "hello"
      "Hello world"
      "world"
      5
      true
      [-1, 1, 0]
      true
      false
      "abcdefgh"
      16
      Fiddle::Pointer
      true
      true
      true
      false
      nil
      "ABC"
      "xyCDEF"
      Integer
      nil
      [ArgumentError, "NULL pointer given"]
      ""
      [Fiddle::DLError, "NULL pointer dereference"]
      [Fiddle::DLError, "NULL pointer dereference"]
      [Fiddle::DLError, Fiddle::Error, StandardError]
      [Fiddle::ClearedReferenceError, Fiddle::Error, StandardError]
      0
      "abcde"
      false
      [1, 1]
      4
      Integer
      true
      42
      3
      "strlen"
      true
      Integer
      [TypeError, "wrong argument type Integer (expected Array)"]
      [RuntimeError, "unknown type 99"]
      16
      "d=42 s=hi f=2.50"
      "obj"
      false
      true
      [Fiddle::ClearedReferenceError, "`ref` called on a cleared object"]
    OUT
  end

  it "flat map take rooted" do
    result = ze0(<<~'RUBY')
      # flat_map's receiver is the array the loop walks, and the block body allocates
      # (the result array, each spliced value). A freshly built receiver -- here the
      # array `take` returns -- is held by nothing, so a collection inside the loop
      # freed it and the walk stopped early. Run under SPINEL_GC_STRESS=1 to see the
      # short count without the root.
      rings = [
        [-64.5630852, 46.2938887],
        [-64.5630733, 46.2939199],
      ]
      struct = Struct.new :x, :y

      rings.map do |lon, lat|
        struct.new lon, lat
      end.group_by do |v|
        [v.y, v.x]
      end.then do |grouped|
        puts "bins: #{grouped.size}"
        n = 0
        grouped.each_with_index.take(5000).flat_map do |((i, j), g), _i|
          n += 1
          g.map do |vertex|
            []
          end
        end
        p n
      end

      a = [[1, 2], [3, 4], [5, 6]]
      m = 0
      a.each_with_index.take(5000).flat_map do |(x, y), i|
        m += 1
        []
      end
      p m
    RUBY

    _(result).must_answer <<~'OUT'
      bins: 2
      2
      3
    OUT
  end

  it "hello" do
    _(ze0(<<~'RUBY')).must_answer "ok\n"
      puts :ok
    RUBY
  end

  it "hello world" do
    _(ze0(<<~'RUBY')).must_answer "Hello, world!\n"
      puts "Hello, world!"
    RUBY
  end

  it "i1021" do
    result = ze0(<<~'RUBY', path: "lang/programs/i1021.rb")
      s = GC.stat
      puts s.key?("bytes")
      puts s.key?("old_bytes")
      puts s.key?("threshold")
      puts s.key?("cycle")
      puts s.key?("full_runs")
      puts s["bytes"] >= 0
      puts s["threshold"] > 0
      GC.start
      t = GC.stat
      puts t["cycle"] >= s["cycle"]
      puts "done"
    RUBY

    _(result).must_answer <<~'OUT', stderr: "lang/programs/i1021.rb:7:in '<main>': undefined method '>=' for nil (NoMethodError)\n\nputs s[\"bytes\"] >= 0\n                ^^\n", status: 1
      false
      false
      false
      false
      false
    OUT
  end

  it "i919" do
    result = ze0(<<~'RUBY')
      add = -> (a, b) { a + b }
      add5 = add.curry[5]
      puts add5[3]
      puts add.curry[5][3]
      mul = -> (a, b, c) { a * b * c }
      f = mul.curry[2]
      g = f[3]
      puts g[4]
      c = add.curry
      puts c[10][20]
      sub = -> (a, b) { a - b }
      puts sub.curry[10][3]
    RUBY

    _(result).must_answer <<~'OUT'
      8
      8
      24
      30
      7
    OUT
  end

  it "index target takes every index shape" do
    result = ze0(<<~'RUBY')
      # `[]=` is an ordinary method, so an indexed assignment target carries
      # however many indexes the receiver's `[]=` takes -- in compound
      # assignment, in multi-assignment, and through a splat, each index
      # expression evaluated exactly once.
      #
      # zeo's multi-assignment arm demanded a single index, and a SPLAT index in
      # compound assignment fell off the end of the lowering (red-chainer's
      # `gx[*i] += dot / (2 * eps)`).
      class Grid
        def initialize
          @cells = {}
        end

        def [](*coords)
          @cells[coords] || 0
        end

        def []=(*coords, value)
          @cells[coords] = value
        end
      end

      g = Grid.new

      # Multi-assignment with a two-argument index target.
      g[1, 2], g[3, 4] = "a", "b"
      puts g[1, 2]
      puts g[3, 4]

      # Compound assignment through a splat index, the coordinate array built
      # (and its builder run) exactly once.
      built = 0
      coords = lambda do
        built += 1
        [5, 6]
      end
      g[*coords.call] += 10
      g[*[5, 6]] += 1
      puts g[5, 6]
      puts built

      # A splat index in multi-assignment position.
      g[*[7, 8]], g[9] = "x", "y"
      puts g[7, 8]
      puts g[9]
    RUBY

    _(result).must_answer <<~'OUT'
      a
      b
      11
      1
      x
      y
    OUT
  end

  it "issue drb missing" do
    _(ze0(<<~'RUBY')).must_answer "\"constant\"\n"
      # `require "drb"` -- the vendored gem loads and defines `DRb`.
      require "drb"
      p defined?(DRb)
    RUBY
  end

  it "multi write scalar rhs" do
    result = ze0(<<~'RUBY')
      # Scalar int RHS to multi-assign: `a, b = 1` previously emitted
      # `sp_IntArray *_t = 1LL;` which failed to compile. CRuby treats
      # the scalar as `[scalar]` so the first slot gets it; the extra
      # targets are nil (an under-filled slot lands its nil sentinel).
      a, b = 1
      puts a
      puts b

      e, f, g = 42
      puts e
      puts f
      puts g
    RUBY

    _(result).must_answer <<~'OUT'
      1

      42


    OUT
  end

  it "pop and shift take a count" do
    result = ze0(<<~'RUBY')
      # `pop`/`shift` answer ONE element; `pop(n)`/`shift(n)` answer an ARRAY
      # -- a different return type, not just a different count, which is why
      # the no-arg form can't be `pop(1)`. Both were `arity!(args, 0)`, so the
      # count form raised a spurious ArgumentError on a call Ruby accepts.

      a = [1, 2, 3, 4]
      p a.pop(2)
      p a
      b = [1, 2, 3, 4]
      p b.shift(2)
      p b
      p [1, 2].pop(5)
      p [1, 2].pop(0)
      c = [1, 2]
      p c.shift(0)
      p c
      p [1, 2].pop
      p [].pop
      p [].shift
    RUBY

    _(result).must_answer <<~'OUT'
      [3, 4]
      [1, 2]
      [1, 2]
      [3, 4]
      [1, 2]
      []
      []
      [1, 2]
      2
      nil
      nil
    OUT
  end

  it "strbuf shovel chain value" do
    result = ze0(<<~'RUBY')
      # A value-position << chain over a buffer-promoted string local must land
      # every link in the base: `r = (u << "2" << "3")` used to keep only the
      # first append in u (the second link concatenated a read-out copy).

      s = "ab"
      s << "c" << "d"
      p s

      t = "x"
      t << "y" << "z" << "w"
      p t

      u = "1"
      r = (u << "2" << "3")
      p u
      p r

      v = "a"
      q = (v << "b" << "c" << "d")
      v << "e"
      p v
      p q
    RUBY

    _(result).must_answer <<~'OUT'
      "abcd"
      "xyzw"
      "123"
      "123"
      "abcde"
      "abcde"
    OUT
  end

  it "toplevel return" do
    result = ze0(<<~'RUBY')
      # frozen_string_literal: true

      # A `return` written at a file's top level ends that file: ruby stops
      # reading it there, and the value is dropped.

      puts "start"

      def helper = :helper
      p helper

      return if [].any?

      puts "still here"

      class C
        def go
          return :from_method
        end
      end
      p C.new.go

      [1].each { p :in_block }

      return if [1].any?

      puts "never"
    RUBY

    _(result).must_answer <<~'OUT'
      start
      :helper
      still here
      :from_method
      :in_block
    OUT
  end

  it "values at" do
    result = ze0(<<~'RUBY')
      # Issue #742 (partial -- values_at). `arr.values_at(i, j, ...)`
      # picks elements at the given indices and returns a fresh array of
      # the same element type. spinel used to fall through to the
      # unresolved-call warning for every array variant.

      # sym_array
      puts [:a, :b, :c].values_at(0, 2).inspect

      # int_array
      puts [1, 2, 3, 4, 5].values_at(0, 2, 4).inspect

      # str_array
      puts ["x", "y", "z"].values_at(1).inspect

      # Single index, multiple of same value.
      puts [10, 20, 30].values_at(1, 1, 1).inspect

      # combination + permutation remain unimplemented and stay out
      # of scope for this fix.
    RUBY

    _(result).must_answer <<~'OUT'
      [:a, :c]
      [1, 3, 5]
      ["y"]
      [20, 20, 20]
    OUT
  end

  it "zeo dev promote probe" do
    _(ze0(<<~'RUBY')).must_answer "promoted\n"
      puts "promoted"
    RUBY
  end
end
