# frozen_string_literal: true

require "spec_helper"

describe "String programs" do
  it "braceless hash non symbol keys" do
    result = ze0(<<~'RUBY')
      # A braceless hash argument is the keyword-argument spelling only when its keys
      # are Symbols. A non-Symbol key cannot be a keyword at all, so Ruby passes an
      # ordinary Hash positionally -- and pinning the collapsed parameter to the
      # symbol-keyed variant regardless made the callee read a string-keyed hash
      # through the wrong pointer: one empty-symbol key and no value, or a hang on
      # integer and mixed keys (#3487).
      #
      # Each form needs its own method: giving one method both a braceless and a
      # braced call site merges the inferred parameter type and hides the divergence.
      def s_key(h)
        p h
      end

      def i_key(h)
        p h
      end

      def mixed(h)
        p h
      end

      def sym_key(h)
        p h
      end

      def braced(h)
        p h
      end

      def dflt(h = {})
        p h
      end

      def after_positional(a, h)
        p [a, h]
      end

      def reads_it(h)
        p h["m"]
      end

      s_key('m' => 1)
      i_key(1 => 2)
      mixed('a' => 1, :b => 2)
      sym_key(k: 1)
      braced({ 'm' => 1 })
      dflt('z' => 9)
      dflt
      after_positional(5, 'q' => 7)
      reads_it('m' => 42)

      # the paths that already worked stay working
      h = { "z" => 9 }
      p h.merge('a' => 1)
      p [].push('a' => 1)
      f = ->(x) { x }
      p f.call('a' => 1)

      def rest(*a)
        p a
      end
      rest('a' => 1)
    RUBY

    _(result).must_answer <<~'OUT'
      {"m" => 1}
      {1 => 2}
      {"a" => 1, b: 2}
      {k: 1}
      {"m" => 1}
      {"z" => 9}
      {}
      [5, {"q" => 7}]
      42
      {"z" => 9, "a" => 1}
      [{"a" => 1}]
      {"a" => 1}
      [{"a" => 1}]
    OUT
  end

  it "catch string tag" do
    _(ze0(<<~'RUBY')).must_answer "UncaughtThrowError\n"
      begin
        catch("str") { throw "str", :s }
      rescue UncaughtThrowError => e
        p e.class
      end
    RUBY
  end

  it "clock symbol name" do
    result = ze0(<<~'RUBY')
      # `Process.clock_gettime` takes a clock as a SYMBOL name.
      #
      # The symbol spelling is the portable one -- a constant the platform does
      # not define is a `NameError` at the read, where the symbol form is a
      # rescuable `Errno::EINVAL` -- so it is the shape a library actually
      # writes. The name is looked up against `Process`'s own `CLOCK_*`
      # constants, so the two cannot drift.
      #
      # The original header follows. It describes the PREDECESSOR project's
      # version of this test and its own fix.
      #
      # `Process.clock_gettime` takes a clock as a SYMBOL name as well as a constant
      # or a raw id. The symbol went into an Integer slot and raised (#4044).

      p Process.clock_gettime(:CLOCK_MONOTONIC).class
      p Process.clock_gettime(Process::CLOCK_MONOTONIC).class
      p Process.clock_gettime(:CLOCK_REALTIME).class
      p Process.clock_gettime(:CLOCK_MONOTONIC, :nanosecond).class
      p Process.clock_gettime(:CLOCK_MONOTONIC, :millisecond).class
      p Process.clock_getres(:CLOCK_MONOTONIC).class
      p Process.clock_gettime(:CLOCK_REALTIME) > 0
      p Process.clock_gettime(:CLOCK_PROCESS_CPUTIME_ID) >= 0
    RUBY

    _(result).must_answer <<~'OUT'
      Float
      Float
      Float
      Integer
      Integer
      Float
      true
      true
    OUT
  end

  it "env string inference" do
    result = ze0(<<~'RUBY')
      # Issue #129: ENV["X"] was inferred as int at every call site even though
      # the dispatch correctly emits sp_str_dup_external(getenv(...)) returning
      # const char *. Fix is in `infer_operator_type`'s `[]` branch (early
      # ENV check) plus `compile_eq` for the `string == string` case (NULL-safe
      # via the new sp_str_eq runtime helper, since strcmp(NULL, ...) is UB and
      # segfaults on `"1" == ENV["UNSET"]`).
      #
      # Tests pin the four shapes from the issue body, plus the reverse-order
      # segfault case Sam called out.

      # Use a variable that's vanishingly unlikely to be set in any environment.
      UNSET = "SPINEL_TEST_VAR_THAT_DOES_NOT_EXIST_129"

      # 1. nil? on unset → true. Was: constant-folded to false at codegen.
      puts ENV[UNSET].nil?                      # true

      # 2. local capture + nil? roundtrip on unset → true.
      s = ENV[UNSET]
      puts s.nil?                                # true

      # 3. inline puts on unset → blank line. Was: printed pointer-as-int.
      puts ENV[UNSET]                            # (blank)

      # 4. equality on unset → false. Was: pointer-int compare, also always false
      #    but for the wrong reason (and would crash if the integer happened to
      #    be a valid pointer prefix).
      puts ENV[UNSET] == "1"                     # false

      # 5. Reverse-order equality on unset → false. Was: segfault. lt=string,
      #    at=int → fell through to strcmp("1", <int>), dereferencing the int
      #    as a pointer.
      puts "1" == ENV[UNSET]                     # false

      # 6. nil? on a likely-set var (PATH is universal on POSIX). The bootstrap
      #    needs PATH to find cc; if this test runs at all PATH is set. Pins the
      #    "set var" branch of the same fix.
      puts ENV["PATH"].nil?                      # false
    RUBY

    _(result).must_answer <<~'OUT'
      true
      true

      false
      false
      false
    OUT
  end

  it "eq string vs int" do
    result = ze0(<<~'RUBY')
      # A String and an Integer are never == in Ruby (no implicit coercion).
      # Spinel used to lock the == operand types and emit sp_str_eq(str, int)
      # (or int == char*), failing to compile.
      p("3" == 3)
      p(3 == "3")
      p("3" != 3)
      p(3 != "3")
      # Same-type comparisons still behave normally.
      p("3" == "3")
      p(3 == 3)
      p("3" == "4")

      # Both operands are still evaluated (side effects preserved).
      $c = 0
      def bump
        $c = $c + 1
        "x"
      end
      p(bump == 5)
      p $c
    RUBY

    _(result).must_answer <<~'OUT'
      false
      false
      true
      true
      true
      true
      false
      false
      1
    OUT
  end

  it "exception super interpolated message" do
    result = ze0(<<~'RUBY')
      # A user exception subclass whose #initialize forwards an interpolated
      # string to super must report that interpolated message, with the
      # construction args bound to the initialize params -- not just the
      # first construction arg. Covers both raise E.new(...) and an assigned
      # E.new(...). Regression for #1048.
      class NotFoundError < StandardError
        def initialize(kind, id)
          super("not found - kind `#{kind}`, id `#{id}`")
        end
      end

      begin
        raise NotFoundError.new("company", "123")
      rescue => e
        puts e.message
      end

      err = NotFoundError.new("user", "42")
      puts err.message

      # Plain `super(msg)` (no interpolation) must still report the message.
      class Plain < StandardError
        def initialize(msg)
          super(msg)
        end
      end
      begin
        raise Plain.new("plain message")
      rescue => e
        puts e.message
      end

      # A default-valued param used in the super message resolves to its
      # default when no construction arg is given.
      class Defaulted < StandardError
        def initialize(detail = "fallback")
          super("oops: #{detail}")
        end
      end
      puts Defaulted.new.message
      puts Defaulted.new("custom").message
    RUBY

    _(result).must_answer <<~'OUT'
      not found - kind `company`, id `123`
      not found - kind `user`, id `42`
      plain message
      oops: fallback
      oops: custom
    OUT
  end

  it "gc root ptr array literal" do
    _(ze0(<<~'RUBY')).must_answer "0\n"
      # Regression test: `@x = [Klass.new(...)]` literal must keep the freshly
      # allocated PtrArray reachable across each element's allocation. Without
      # the SP_GC_ROOT on the temp, GC fired during a later Klass.new sees the
      # half-built array as unreachable and frees it, leaving a dangling
      # pointer that gets stored into the ivar.
      #
      # Each Tile holds a 256-float buffer (~2 KB) so that allocating a few
      # hundred Containers crosses the 256 KB GC threshold and forces a
      # collect mid-construction. Repro is non-deterministic without the fix
      # but reliably produces nonzero `errors` at this scale on darwin/arm64.

      class Tile
        attr_accessor :tag, :data
        def initialize(tag)
          @tag  = tag
          @data = Array.new(256, tag.to_f)
        end
      end

      class Container
        attr_accessor :a, :b, :c
        def initialize
          @a = [Tile.new(10), Tile.new(20), Tile.new(30), Tile.new(40)]
          @b = [Tile.new(11), Tile.new(21), Tile.new(31), Tile.new(41)]
          @c = [Tile.new(12), Tile.new(22), Tile.new(32), Tile.new(42)]
        end
      end

      containers = [Container.new]
      containers.pop

      n = 0
      while n < 1000
        containers.push(Container.new)
        n += 1
      end

      errors = 0
      ci = 0
      while ci < containers.length
        c = containers[ci]
        ta = c.a; tb = c.b; tc = c.c
        if ta.length != 4 || tb.length != 4 || tc.length != 4
          errors += 1
        else
          bad = false
          if ta[0].tag != 10 || ta[1].tag != 20 || ta[2].tag != 30 || ta[3].tag != 40
            bad = true
          end
          if tb[0].tag != 11 || tb[1].tag != 21 || tb[2].tag != 31 || tb[3].tag != 41
            bad = true
          end
          if tc[0].tag != 12 || tc[1].tag != 22 || tc[2].tag != 32 || tc[3].tag != 42
            bad = true
          end
          if bad
            errors += 1
          end
        end
        ci += 1
      end

      puts errors
    RUBY
  end

  it "gc stat string heap" do
    result = ze0(<<~'RUBY', path: "core/string/gc_stat_string_heap.rb")
      # GC.stat surfaces the string heap (str_bytes / str_count). Spinel allocates
      # string data on a separate malloc'd heap (sp_str_heap) that is deliberately
      # excluded from the object-heap `bytes` figure (see sp_str_alloc), so a
      # string-heavy workload can hold gigabytes that `bytes` never reflects.
      # Retaining 1000 strings makes str_count >= 1000 and str_bytes > 0.
      arr = []
      i = 0
      while i < 1000
        arr.push(i.to_s)
        i += 1
      end
      g = GC.stat
      puts "str_count >= 1000: " + (g["str_count"] >= 1000 ? "yes" : "no")
      puts "str_bytes > 0: " + (g["str_bytes"] > 0 ? "yes" : "no")
      puts "retained: " + arr.length.to_s
    RUBY

    _(result).must_answer "", stderr: "core/string/gc_stat_string_heap.rb:13:in '<main>': undefined method '>=' for nil (NoMethodError)\n\nputs \"str_count >= 1000: \" + (g[\"str_count\"] >= 1000 ? \"yes\" : \"no\")\n                                             ^^\n", status: 1
  end

  it "gc str arg rooted" do
    result = ze0(<<~'RUBY')
      # Regression: string arguments to allocating sp_str.c helpers must be
      # GC-rooted. sp_str_bytes / sp_str_codepoints allocate an IntArray before
      # reading the argument; when the argument is a fresh unrooted temp (an
      # interpolation result) and that allocation crosses the GC threshold, the
      # collection freed the argument mid-call and the result came back empty or
      # garbage (observed in the Doom port: Colormap lost a row, black screen).
      total = 0
      lens = 0
      keep = []
      200.times do |i|
        n = 3000 + (i % 7) * 500
        b = "row#{i}-#{'x' * n}".bytes
        total += b.sum
        lens += b.length
        keep << b if i % 10 == 0
      end
      puts total
      puts lens

      cps = 0
      clen = 0
      200.times do |i|
        n = 2000 + (i % 5) * 700
        c = "cp#{i}-#{'y' * n}".codepoints
        cps += c.sum
        clen += c.length
        keep << c if i % 10 == 0
      end
      puts cps
      puts clen
      puts keep.length
    RUBY

    _(result).must_answer <<~'OUT'
      107743220
      898290
      82356620
      681090
      40
    OUT
  end

  it "hash strstr merge" do
    result = ze0(<<~'RUBY')
      a = { "O" => "Off-topic", "" => "Cancel" }
      b = a.merge({ "Q" => "Low Quality" })
      puts b.length
      p b["Q"]
      p a.length
      c = a.merge({ "O" => "Override" })
      p c["O"]
      p c.length
    RUBY

    _(result).must_answer <<~'OUT'
      3
      "Low Quality"
      2
      "Override"
      2
    OUT
  end

  it "hello prints a symbol" do
    _(ze0(<<~'RUBY')).must_answer "ok\n"
      puts :ok
    RUBY
  end

  it "inherited kwarg nil default string ivar" do
    result = ze0(<<~'RUBY')
      # Three intertwined fixes around kwarg param inference on an
      # inherited instance method:
      #
      # 1. Analyze: the inh_ branch (bare call inside a class body that
      #    resolves to a parent's method) was iterating arg_ids by
      #    position, so a trailing `KeywordHashNode` landed on whatever
      #    positional slot came next instead of the matching kwarg
      #    slot. `head(204, content_type: "x")` widened `content_type`'s
      #    slot with the *whole keyword hash type* (sym_str_hash) and
      #    left it un-pinned to "string". Route through
      #    widen_ptypes_from_args so each `key: value` lands on the
      #    named-param slot.
      #
      # 2. Codegen: compile_typed_call_args had the same positional-
      #    only loop on the emit side. Extract KeywordHashNode pairs
      #    up front, inject them into arg_ids at the matching named
      #    slot, and route the existing per-arg type-coerce loop
      #    through that. Without this, the kwarg expression
      #    disappeared at the call site — `head(204, content_type:
      #    "application/json")` emitted `sp_Base_head(self, 204, 0)`.
      #
      # 3. Analyze ivar heterogeneity: the same-base nullable variant
      #    case (`@x = "hi"` + `@x = some_nullable_string_param`)
      #    counted as 2 distinct observations and widened the ivar to
      #    poly. Both write the same C storage (const char *) with
      #    NULL as the nil sentinel. update_ivar_type and
      #    finalize_ivar_heterogeneity now treat T + T? as a single
      #    nullable observation, preserving the typed pointer slot.

      class Base
        def initialize
          @content_type = "text/html"
        end

        def head(status, content_type: nil)
          @status = status
          @content_type = content_type unless content_type.nil?
          nil
        end

        def show_content_type
          @content_type
        end
      end

      class Child < Base
        def render_json
          head(204, content_type: "application/json")
        end

        def render_html
          head(200)
        end
      end

      c = Child.new
      c.render_json
      puts c.show_content_type
      c2 = Child.new
      c2.render_html
      puts c2.show_content_type
    RUBY

    _(result).must_answer <<~'OUT'
      application/json
      text/html
    OUT
  end

  it "io buffer for aliases its string" do
    result = ze0(<<~'RUBY')
      # `IO::Buffer.for(string)` shares the STRING's own bytes, so a buffer write
      # is visible through the string before the block ends -- CRuby's buffer
      # really aliases its string's storage, and this one does too.
      #
      # The earlier answer copied in and copied back at block exit: the END state
      # matched and a mid-block read of the string saw the original. The recorded
      # fix shape was a stable byte address for the string, which zeo's
      # `Arc<Mutex<StrBuf>>` does not have and which is a value-model change.
      #
      # It was not needed. The buffer already held its source string, so the
      # backing can BE that string (`Mem::Str`): every read and write locks it and
      # uses its bytes in place. The string's own mutex is what CRuby models as
      # "the string is locked for the duration", and no address is pinned at all.
      # Nothing is copied in either direction now.
      $stderr.reopen(IO::NULL)
      s = +"abcdef"
      IO::Buffer.for(s) do |b|
        b.set_value(:U8, 0, 0x5a)
        p s
        b.set_value(:U8, 5, 0x5a)
        p s
      end
      p s

      # The readonly (no-block) form shares the same bytes, and refuses a write.
      r = +"hello"
      view = IO::Buffer.for(r)
      p view.get_string
      p view.readonly?
      begin
        view.set_value(:U8, 0, 0x41)
      rescue IO::Buffer::AccessError => e
        p [:refused, e.class]
      end

      # A multi-byte string keeps its encoding across a byte write.
      u = +"héllo"
      IO::Buffer.for(u) do |b|
        b.set_value(:U8, 0, 0x48)
      end
      p [u, u.encoding.to_s, u.valid_encoding?]

      # `IO::Buffer.new` owns its bytes and aliases nothing.
      own = IO::Buffer.new(4)
      own.set_value(:U8, 0, 0x41)
      p own.get_string
    RUBY

    _(result).must_answer <<~'OUT'
      "Zbcdef"
      "ZbcdeZ"
      "ZbcdeZ"
      "hello"
      true
      [:refused, IO::Buffer::AccessError]
      ["Héllo", "UTF-8", true]
      "A\x00\x00\x00"
    OUT
  end

  it "io buffer reads and writes bytes in place" do
    result = ze0(<<~'RUBY')
      # IO::Buffer is a window on bytes: its own, or a String's. A buffer made
      # `for` a String reads and writes that String's bytes in place, which is
      # what ruby means by locking the string for the block. Addresses in the
      # report are the object's, so this file scrubs them.
      $stderr.reopen(IO::NULL)
      p IO::Buffer::PAGE_SIZE.class
      p IO::Buffer::DEFAULT_SIZE
      p [IO::Buffer::EXTERNAL, IO::Buffer::INTERNAL, IO::Buffer::MAPPED, IO::Buffer::SHARED, IO::Buffer::LOCKED, IO::Buffer::PRIVATE, IO::Buffer::READONLY]
      p [IO::Buffer::LITTLE_ENDIAN, IO::Buffer::BIG_ENDIAN, IO::Buffer::HOST_ENDIAN, IO::Buffer::NETWORK_ENDIAN]
      p IO::Buffer.size_of(:U8)
      p IO::Buffer.size_of([:U32, :F64])
      b = IO::Buffer.new(8)
      p [b.size, b.external?, b.internal?, b.readonly?, b.valid?, b.empty?]
      b.set_value(:U16, 0, 0x1234)
      p b.get_value(:U16, 0)
      p b.get_string
      p b.to_s
      p b.inspect.sub(/0x\h{16}/, "0xADDR")
      b.set_string("hi", 4)
      p b.get_string(4, 2)
      p b.slice(0, 2).get_string
      p b.hexdump.class
      s = +"abcdef"
      v = IO::Buffer.for(s)
      p [v.size, v.readonly?, v.external?, v.get_string]
      begin; v.set_value(:U8, 0, 65); rescue => e; p [e.class, e.message]; end
      IO::Buffer.for(s) { |w| w.set_value(:U8, 0, 90); p [w.readonly?, s] }
      p s
      p IO::Buffer.string(3) { |w| w.set_string("xyz") }
      p [b.get_values([:U8, :U8], 0)]
      c = IO::Buffer.new(4)
      b.copy(c, 0, 4)
      p c.get_string
      p IO::Buffer.new(2).clear(7).get_string.bytes
      begin; IO::Buffer.new(2).get_value(:U8, 5); rescue => e; p [e.class, e.message]; end
      p [IO::Buffer::AccessError.superclass, IO::Buffer::AllocationError.superclass, IO::Buffer::InvalidatedError.superclass, IO::Buffer::LockedError.superclass, IO::Buffer::MaskError.superclass]
      p IO::Buffer.superclass
      b = IO::Buffer.new(8)
      %i[U8 S8 U16 S16 U32 S32 U64 S64 u16 s16 u32 s32 u64 s64 F32 F64 f32 f64].each { |t| print t, "=", IO::Buffer.size_of(t), " " }
      puts
      b.set_value(:u16, 0, 0x1234); p b.get_string(0, 2).bytes
      b.set_value(:S8, 0, -1); p b.get_value(:S8, 0)
      b.set_value(:F64, 0, 1.5); p b.get_value(:F64, 0)
      b.set_value(:f32, 0, 1.5); p [b.get_value(:f32, 0), b.get_string(0,4).bytes]
      p IO::Buffer.new(4).values(:U8, 0)
      p IO::Buffer.new(4).each(:U8, 0).to_a
      p IO::Buffer.new(0).empty?
      p IO::Buffer.for("abc").slice(1).get_string
      p IO::Buffer.for("abc") <=> IO::Buffer.for("abd")
      d = IO::Buffer.new(2); d.set_string("\x0f\xf0".b); p (d & IO::Buffer.for("\xff\x00".b)).get_string.bytes
      begin; IO::Buffer.new(2).set_value(:BAD, 0, 1); rescue => e; p [e.class, e.message]; end
      begin; IO::Buffer.for("x").resize(4); rescue => e; p [e.class, e.message]; end
      e2 = IO::Buffer.new(2); e2.free; p [e2.null?, e2.size]
      begin; e2.get_string; rescue => e; p [e.class, e.message]; end
    RUBY

    _(result).must_answer "Integer\n65536\n[1, 2, 4, 8, 32, 64, 128]\n[4, 8, 4, 8]\n1\n12\n[8, false, true, false, true, false]\n4660\n\"\\x124\\x00\\x00\\x00\\x00\\x00\\x00\"\n\"#<IO::Buffer 0xADDR+8 INTERNAL>\"\n\"#<IO::Buffer 0xADDR+8 INTERNAL>\\n0xADDR  12 34 00 00 00 00 00 00                         .4......\"\n\"hi\"\n\"\\x124\"\nString\n[6, true, true, \"abcdef\"]\n[IO::Buffer::AccessError, \"Buffer is not writable!\"]\n[false, \"Zbcdef\"]\n\"Zbcdef\"\n\"xyz\"\n[[18, 52]]\n\"\\x00\\x00\\x00\\x00\"\n[7, 7]\n[ArgumentError, \"Type extends beyond end of buffer! (offset=5 > size=2)\"]\n[RuntimeError, RuntimeError, RuntimeError, RuntimeError, ArgumentError]\nObject\nU8=1 S8=1 U16=2 S16=2 U32=4 S32=4 U64=8 S64=8 u16=2 s16=2 u32=4 s32=4 u64=8 s64=8 F32=4 F64=8 f32=4 f64=8 \n[52, 18]\n-1\n1.5\n[1.5, [0, 0, 192, 63]]\n[0, 0, 0, 0]\n[[0, 0], [1, 0], [2, 0], [3, 0]]\ntrue\n\"bc\"\n-1\n[15, 0]\n[ArgumentError, \"Invalid type name!\"]\n[IO::Buffer::AccessError, \"Cannot resize external buffer!\"]\n[true, 0]\n"
  end

  it "issue string subclass new with arg" do
    result = ze0(<<~'RUBY')
      # Instantiating a String subclass with a constructor argument
      # (`klass.new("x")`) raises ArgumentError ("wrong number of arguments") --
      # zeo doesn't forward the argument to String's own initializer for a
      # dynamically-created subclass.
      klass = Class.new(String) do
        def foo
          42
        end
      end
      s = klass.new("x")
      p s
      p s.foo
    RUBY

    _(result).must_answer <<~'OUT'
      "x"
      42
    OUT
  end

  it "issue203 string new" do
    result = ze0(<<~'RUBY')
      # Issue #203: `String.new` resolved to 0 because the constructor
      # dispatch had no String arm. Code that combined the result with
      # `<<` (the Rails view-emit accumulator pattern) failed to compile.

      # Bare String.new — empty mutable buffer.
      io = String.new
      io << "hello"
      puts io                   # hello

      # Constructor with seed.
      s = String.new("foo")
      s << "bar"
      puts s                    # foobar

      # Empty buffer reads as length 0.
      t = String.new
      puts t.length             # 0

      # Canonical Rails-style accumulator.
      def render(items)
        io = String.new
        io << "<ul>"
        items.each { |item| io << "<li>" << item << "</li>" }
        io << "</ul>"
        io
      end
      puts render(["a", "b"])   # <ul><li>a</li><li>b</li></ul>
    RUBY

    _(result).must_answer <<~'OUT'
      hello
      foobar
      0
      <ul><li>a</li><li>b</li></ul>
    OUT
  end

  it "method level rescue return string" do
    result = ze0(<<~'RUBY')
      # Method-level rescue return value with string-returning bodies.
      # The int-returning shape works once compile_body_into /
      # compile_rescue_chain_into capture the begin / rescue last expr.
      # The string-returning shape additionally needs the method's
      # inferred return type to unify across both branches, which
      # requires BeginNode in infer_type's arms.

      # Both branches return string — unify_return_type picks string.
      def fetch(s)
        raise "empty" if s == ""
        "got " + s
      rescue
        "default"
      end
      puts fetch("data")
      puts fetch("")

      # Rescue body with multiple statements. Last is the value.
      def parse(s)
        raise "blank" if s == ""
        "len=" + s.length.to_s
      rescue
        msg = "fallback"
        msg + "!"
      end
      puts parse("hi")
      puts parse("")

      # Method body that's a BeginNode at the top, with a return inside
      # the begin. collect_return_types must walk the begin body for the
      # explicit `return X` to contribute to the unified type.
      def explicit(s)
        raise "neg" if s == ""
        return "early " + s
      rescue
        "late"
      end
      puts explicit("yes")
      puts explicit("")
    RUBY

    _(result).must_answer <<~'OUT'
      got data
      default
      len=2
      fallback!
      early yes
      late
    OUT
  end

  it "module function promotes bareword and symbol forms" do
    result = ze0(<<~'RUBY')
      # A bare `module_function` promotes every following `def` to a module
      # method; `module_function :name` promotes an already-defined one.

      module M
        module_function
        def shout(s) = s.upcase
      end
      module N
        def whisper(s) = s.downcase
        module_function :whisper
      end
      puts M.shout("hi")
      puts N.whisper("HI")
    RUBY

    _(result).must_answer <<~'OUT'
      HI
      hi
    OUT
  end

  it "module function str method param" do
    _(ze0(<<~'RUBY')).must_answer "RED and bold text\n"
      # A module_function-promoted method whose body calls a string method
      # on its param, invoked with a string-literal arg, must route the
      # param to the string path (not the int "0" NoMethodError fallback).
      # Mirrors strings-ansi's Strings::ANSI.sanitize gsub-with-regex-const.
      module Strings
        module ANSI
          ANSI_MATCHER = /\e\[[0-9;]*m/
          def sanitize(string)
            string.gsub(ANSI_MATCHER, "")
          end
          module_function :sanitize
        end
      end
      puts Strings::ANSI.sanitize("\e[31mRED\e[0m and \e[1mbold\e[0m text")
    RUBY
  end

  it "param ptr from callee slot" do
    result = ze0(<<~'RUBY')
      # A method param passed unmodified to a callee whose corresponding
      # slot is `ptr` / a specific class pointer used to leave the caller's
      # param typed `mrb_int`. The C compile then failed at the call site
      # when the caller passed its mrb_int param into a `void *`-expecting
      # slot.
      #
      # Mirrors the Db.column_bool shape in real-blog: a thin wrapper
      # around a typed primitive (FFI sqlite handle) that didn't have its
      # `stmt` param widened from the body's call to column_int.

      module Box
        def self.read_int(p)
          p.length
        end

        def self.read_bool(p)
          read_int(p) != 0
        end
      end

      puts Box.read_int("abc")
      puts Box.read_bool("abc")
      puts Box.read_bool("")

      # Same pattern across two layers — three-deep chain.
      module Chain
        def self.head(s)
          middle(s)
        end

        def self.middle(s)
          tail(s)
        end

        def self.tail(s)
          s.length
        end
      end

      puts Chain.head("abc")
      puts Chain.middle("xyz")
      puts Chain.tail("hi")
    RUBY

    _(result).must_answer <<~'OUT'
      3
      true
      false
      3
      3
      2
    OUT
  end

  it "plain string raise is caught by an explicit runtime error rescue" do
    _(ze0(<<~'RUBY')).must_answer "caught runtime: just a string\n"
      begin
        raise "just a string"
      rescue RuntimeError => e
        puts "caught runtime: #{e.send(:message)}"
      end
    RUBY
  end

  it "raise of a plain string is an implicit runtime error" do
    result = ze0(<<~'RUBY', path: "core/string/raise_of_a_plain_string_is_an_implicit_runtime_error.rb")
      class Risky
        def check
          raise "plain string error"
        end
      end
      Risky.new.check
    RUBY

    _(result).must_answer "", stderr: "core/string/raise_of_a_plain_string_is_an_implicit_runtime_error.rb:3:in 'Risky#check': plain string error (RuntimeError)\n\tfrom core/string/raise_of_a_plain_string_is_an_implicit_runtime_error.rb:6:in '<main>'\n", status: 1
  end

  it "ruby engine name" do
    result = ze0(<<~'RUBY')
      p RUBY_ENGINE
      p RUBY_ENGINE.is_a?(String)
      p(RUBY_ENGINE == "spinel")
    RUBY

    _(result).must_answer <<~'OUT'
      "ruby"
      true
      false
    OUT
  end

  it "str count multi arg" do
    result = ze0(<<~'RUBY')
      # String#count with multiple args computes intersection of charsets
      # Each additional arg further restricts which chars to count.

      # single arg
      puts "hello world".count("lo")
      # two args (intersection of "lo" and "o" = just "o")
      puts "hello world".count("lo", "o")
      # two args with no intersection
      puts "hello world".count("l", "o")
      # two args with negation
      puts "hello world".count("^l", "lo")
    RUBY

    _(result).must_answer <<~'OUT'
      5
      2
      0
      2
    OUT
  end

  it "str oct prefix" do
    result = ze0(<<~'RUBY')
      # String#oct with prefix auto-detection.
      # CRuby's oct handles 0x (hex), 0b (binary), 0o (explicit octal),
      # 0 (implicit octal), and bare digits (base 8). Previously spinel
      # used strtoll(base=8) unconditionally, so "0xff".oct returned 0
      # instead of 255.

      p "0xff".oct      # hex prefix: 255
      p "0b101".oct     # binary prefix: 5
      p "0o77".oct      # explicit octal: 63
      p "77".oct        # bare digits base-8: 63
      p "010".oct       # implicit octal: 8
    RUBY

    _(result).must_answer <<~'OUT'
      255
      5
      63
      63
      8
    OUT
  end

  it "str ord empty" do
    result = ze0(<<~'RUBY')
      # String#ord on empty string should raise ArgumentError, not return 0.
      begin
        "".ord
        puts "BUG: no raise"
      rescue ArgumentError => e
        puts "ArgumentError: " + e.message
      end

      # Normal ord still works
      p "A".ord
      p "a".ord
    RUBY

    _(result).must_answer <<~'OUT'
      ArgumentError: empty string
      65
      97
    OUT
  end

  it "string clamp ranges" do
    result = ze0(<<~'RUBY')
      p("z".clamp(.."c"))
      p("a".clamp("b"..))
      r001 = ("b".clamp("a"..."c") rescue $!.class); p r001
      r002 = ("b".clamp("c", "a") rescue $!.class); p r002
      p("b".clamp("a", "c"))
      p("z".clamp("b", "d"))
      p("b".clamp("a".."c"))
    RUBY

    _(result).must_answer <<~'OUT'
      "c"
      "b"
      ArgumentError
      ArgumentError
      "b"
      "d"
      "b"
    OUT
  end

  it "string embedded nul compare" do
    result = ze0(<<~'RUBY')
      # A NUL is an ordinary byte in a Ruby String, and the representation records
      # the real length -- but comparison went through strcmp, which stops at the
      # first one. Two strings differing only after a NUL compared equal, so they
      # also sorted equal, deduplicated into one, and collapsed as Hash keys. #3471,
      # #3472.
      s = "a\0b"
      t = "a\0c"
      p(s == t)
      p(s.casecmp(t))
      p(s.casecmp?(t))
      p([t, s].sort.map(&:bytes))
      p([s, t].max.bytes)
      p([s, t].min.bytes)
      p([s, t].uniq.size)
      p([s, t].count(t))
      p([s, t].index(t))
      p([s, t].include?(t))
      p(([s, t] - [s]).map(&:bytes))
      p(([s, t] & [t]).map(&:bytes))
      p(([s] | [t]).map(&:bytes))
      p([s, t].group_by { |x| x }.size)
      p({ s => 1, t => 2 }.size)
      # The comparison operators themselves went through strcmp too, so `<=>` said 0
      # where `==` said false, and the relational four ordered by the shared prefix.
      p(s <=> t)
      p(s < t)
      p(s > t)
      p(s <= t)
      p(s >= t)
      p(s.between?("a\0a", "a\0d"))
      p(s.clamp("a\0c", "a\0d").bytes)
      p((s.."a\0d").include?(t))
      u = "a" + 0.chr + "b"
      p(u <=> "a\0c")
      p(u < "a\0c")
      case t
      when s.."a\0d" then puts "in"
      else puts "out"
      end
    RUBY

    _(result).must_answer <<~'OUT'
      false
      -1
      false
      [[97, 0, 98], [97, 0, 99]]
      [97, 0, 99]
      [97, 0, 98]
      2
      1
      1
      true
      [[97, 0, 99]]
      [[97, 0, 99]]
      [[97, 0, 98], [97, 0, 99]]
      2
      2
      -1
      true
      false
      true
      false
      true
      [97, 0, 99]
      true
      -1
      true
      in
    OUT
  end

  it "string equal identity" do
    result = ze0(<<~'RUBY')
      # String#equal? is pointer identity; each literal occurrence is a distinct
      # object (matching plain CRuby), while aliases and self-comparison hold.
      a = "abc"
      b = "abc"
      p a.equal?(b)        # two occurrences: distinct objects
      p a.equal?(a)
      c = a
      p a.equal?(c)        # alias preserves identity
      d = "ab" + "c"
      e = "ab" + "c"
      p d.equal?(e)        # heap strings are always distinct
      p a == b             # content equality unaffected
      h = { "k" => 1 }
      p h["k"]             # hash keys compare by content, unaffected
      p "".equal?("")      # empty literals are distinct occurrences too
      # value-embedded types: identity IS the value (flonum-style immediates)
      x = Complex(2, 3)
      p x.equal?(x)
      p 1.0.equal?(1.0)
      p 1.0.equal?(2.0)
      r = Rational(1, 2)
      p r.equal?(r)
    RUBY

    _(result).must_answer <<~'OUT'
      false
      true
      true
      false
      true
      1
      false
      true
      true
      false
      true
    OUT
  end

  it "string freeze identity" do
    result = ze0(<<~'RUBY')
      # String#freeze marks in place and returns the SAME object:
      # s.freeze.equal?(s) is true and s.frozen? flips. equal? on two string
      # expressions compares pointers (identical literals share storage, like
      # the frozen-string-literal world, so that case is out of scope here).
      s = "hi"
      p s.frozen?
      p s.freeze.equal?(s)
      p s.frozen?
      t = "ab"
      p t.equal?(t)
    RUBY

    _(result).must_answer <<~'OUT'
      false
      true
      true
      true
    OUT
  end

  it "string identity tap then" do
    result = ze0(<<~'RUBY')
      s = "hello"
      puts s.itself.equal?(s)
      puts s.tap { |x| x }.equal?(s)
      puts s.then { |x| x }.equal?(s)
    RUBY

    _(result).must_answer <<~'OUT'
      true
      true
      true
    OUT
  end

  it "string literal" do
    result = ze0(<<~'RUBY')
      name = "world"
      greeting = "hello #{name}, #{1 + 2} times"
      puts(greeting)
      puts(greeting.length)
      puts(greeting[0])
      puts(greeting[-1])
      s = "cat"
      s[0] = "b"
      puts(s)
    RUBY

    _(result).must_answer <<~'OUT'
      hello world, 3 times
      20
      h
      s
      bat
    OUT
  end

  it "string nil float batch" do
    result = ze0(<<~'RUBY')
      # String#bytesplice with Range / #append_as_bytes / #crypt,
      # Float#=== against non-float operands, and nil & / | / ^ boolean ops
      # on a receiver that widened to poly.

      # bytesplice: integer start/length and Range forms
      s = "hello"
      s.bytesplice(0, 2, "HE")
      p s
      s = "hello"
      s.bytesplice(1..3, "___")
      p s

      # append_as_bytes
      s = "abc"
      s.append_as_bytes("de")
      p s

      # crypt(3): real libc DES with a two-character salt
      p "hello".crypt("ab")
      p "password".crypt("sa")

      # Float#=== : nil / Rational / Complex / Integer / Float operands
      p(1.0 === nil)
      p(1.0 === Rational(1, 2))
      p(1.0 === Complex(1, 0))
      p(0.5 === Rational(1, 2))
      p(1.0 === 1)
      p(1.0 === 1.0)
      p(1.0 == nil)
      p(1.0 == Rational(1, 2))

      # nil & / | / ^ stay boolean even when the local widens to poly
      n = nil
      p(n | 0)
      p(n & 0)
      p(n ^ 0)
      n = nil
      p(n | "x")
      p(n & "x")
      p(n ^ false)
    RUBY

    _(result).must_answer <<~'OUT'
      "HEllo"
      "h___o"
      "abcde"
      "abl0JrMf6tlhw"
      "sa3tHJ3/KuYvI"
      false
      false
      true
      true
      true
      true
      false
      false
      true
      false
      true
      true
      false
      false
    OUT
  end

  it "string pattern joins with its receiver" do
    result = ze0(<<~'RUBY')
      # A String argument at a search or a substitution site must join with
      # the receiver -- CRuby's rb_enc_check, the same test `+` makes. Without
      # it the argument's bytes are read under the receiver's encoding, so the
      # search quietly fails (or matches) where ruby raises.
      s = "日".encode("Shift_JIS")
      pat = "日".encode("EUC-JP")

      def show(name)
        p [name, yield]
      rescue Exception => e
        puts "#{name}: #{e.class}: #{e.message}"
      end

      show("gsub") { s.gsub(pat, "x") }
      show("sub") { s.sub(pat, "x") }
      show("index") { s.index(pat) }
      show("rindex") { s.rindex(pat) }
      show("byteindex") { s.byteindex(pat) }
      show("include?") { s.include?(pat) }
      show("start_with?") { s.start_with?(pat) }
      show("end_with?") { s.end_with?(pat) }
      show("split") { s.split(pat) }
      show("partition") { s.partition(pat) }
      show("rpartition") { s.rpartition(pat) }
      show("slice") { s[pat] }
      show("count") { s.count(pat) }
      show("delete") { s.delete(pat) }
      show("squeeze") { s.squeeze(pat) }
      show("tr") { s.tr(pat, "x") }
      show("plus") { s + pat }

      # Comparison makes no such test: two strings of different encodings are
      # simply unequal, and they still order.
      show("eq") { s == pat }
      show("eql") { s.eql?(pat) }
      show("cmp") { s <=> pat }

      # An ASCII-only argument joins with any ASCII-compatible receiver, so
      # these read the bytes and answer.
      show("ascii index") { s.index("x".encode("EUC-JP")) }
      show("ascii include?") { s.include?("x".encode("EUC-JP")) }
      show("ascii gsub") { s.gsub("x".encode("EUC-JP"), "y") }

    RUBY

    _(result).must_answer <<~'OUT'
      gsub: Encoding::CompatibilityError: incompatible character encodings: Shift_JIS and EUC-JP
      sub: Encoding::CompatibilityError: incompatible character encodings: Shift_JIS and EUC-JP
      index: Encoding::CompatibilityError: incompatible character encodings: Shift_JIS and EUC-JP
      rindex: Encoding::CompatibilityError: incompatible character encodings: Shift_JIS and EUC-JP
      byteindex: Encoding::CompatibilityError: incompatible character encodings: Shift_JIS and EUC-JP
      include?: Encoding::CompatibilityError: incompatible character encodings: Shift_JIS and EUC-JP
      start_with?: Encoding::CompatibilityError: incompatible character encodings: Shift_JIS and EUC-JP
      end_with?: Encoding::CompatibilityError: incompatible character encodings: Shift_JIS and EUC-JP
      split: Encoding::CompatibilityError: incompatible character encodings: Shift_JIS and EUC-JP
      partition: Encoding::CompatibilityError: incompatible character encodings: Shift_JIS and EUC-JP
      rpartition: Encoding::CompatibilityError: incompatible character encodings: Shift_JIS and EUC-JP
      slice: Encoding::CompatibilityError: incompatible character encodings: Shift_JIS and EUC-JP
      count: Encoding::CompatibilityError: incompatible character encodings: Shift_JIS and EUC-JP
      delete: Encoding::CompatibilityError: incompatible character encodings: Shift_JIS and EUC-JP
      squeeze: Encoding::CompatibilityError: incompatible character encodings: Shift_JIS and EUC-JP
      tr: Encoding::CompatibilityError: incompatible character encodings: Shift_JIS and EUC-JP
      plus: Encoding::CompatibilityError: incompatible character encodings: Shift_JIS and EUC-JP
      ["eq", false]
      ["eql", false]
      ["cmp", -1]
      ["ascii index", nil]
      ["ascii include?", false]
      ["ascii gsub", "\x{93FA}"]
    OUT
  end

  it "string shl identity" do
    result = ze0(<<~'RUBY')
      # String#<< returns the receiver itself (identity), not a copy (KieranP #2307).
      # The mutable-buffer receiver appends in place; the expression value and a
      # subsequent read of the variable are the same object.
      s = "a"
      p((s << "b").equal?(s))
      p s
      p((s.concat("e")).equal?(s))
      p s
      t = "x"
      u = "y"
      t << "z"
      p t.equal?(u)          # distinct buffers stay distinct
      p s.upcase.equal?(s)   # a non-mutating transform is a new object
    RUBY

    _(result).must_answer <<~'OUT'
      true
      "ab"
      true
      "abe"
      false
      false
    OUT
  end

  it "string to c" do
    result = ze0(<<~'RUBY')
      # String#to_c: lenient leading-substring parse into a Complex.

      # Rectangular forms.
      p "3+4i".to_c
      p "-3-4i".to_c
      p "5+i".to_c
      p "1.5+2.5i".to_c

      # Pure real and pure imaginary.
      p "1.5".to_c
      p "7".to_c
      p "3i".to_c
      p "3.0e2i".to_c

      # Bare imaginary unit, with optional sign.
      p "i".to_c
      p "+i".to_c
      p "-i".to_c

      # Rational components.
      p "2/3".to_c
      p "2/3+1/4i".to_c
      p "1.5/2".to_c

      # Polar (magnitude@angle); a zero angle keeps the exact magnitude.
      p "1@2".to_c
      p "1@0".to_c

      # Whitespace is trimmed; junk and empty strings parse to (0+0i).
      p "  3+4i  ".to_c
      p "foo".to_c
      p "".to_c

      # Digit-group underscores; a trailing '.' and an unterminated tail stop the parse.
      p "1_000".to_c
      p "5.".to_c
      p "3+4".to_c

      # A zero denominator raises, matching Rational parsing.
      begin
        "1/0".to_c
      rescue ZeroDivisionError => e
        puts "raised: #{e.message}"
      end
    RUBY

    _(result).must_answer <<~'OUT'
      (3+4i)
      (-3-4i)
      (5+1i)
      (1.5+2.5i)
      (1.5+0i)
      (7+0i)
      (0+3i)
      (0+300.0i)
      (0+1i)
      (0+1i)
      (0-1i)
      ((2/3)+0i)
      ((2/3)+(1/4)*i)
      ((3/4)+0i)
      (-0.4161468365471424+0.9092974268256817i)
      (1+0.0i)
      (3+4i)
      (0+0i)
      (0+0i)
      (1000+0i)
      (5+0i)
      (3+0i)
      raised: divided by 0
    OUT
  end

  it "struct string member gc root" do
    result = ze0(<<~'RUBY')
      # A single fresh-string struct member must survive the struct's own allocation
      # (SP_POOL_NEW can trigger a GC before the member is stored). The constructor
      # roots its heap arguments so the collector cannot sweep the name before it is
      # assigned, nor read a freed name when it later marks the (live) struct.
      Entry = Struct.new(:name)
      entries = []
      8000.times do |i|
        entries << Entry.new("item#{i}".upcase)
      end
      GC.start
      bad = 0
      entries.each_with_index { |e, i| bad += 1 unless e.name == "ITEM#{i}" }
      puts "count=#{entries.size} bad=#{bad}"
      puts entries[0].name
      puts entries[4000].name
      puts entries.last.name

      # Non-string heap members must be rooted too. A bigint member is a heap object
      # but is neither string/poly/object/array/hash, so the old rooting predicate
      # skipped it: a fresh bigint temporary could be swept across SP_POOL_NEW's GC.
      Big = Struct.new(:n)
      bigs = []
      8000.times do |i|
        bigs << Big.new(2 ** 70 + i)
      end
      GC.start
      bbad = 0
      bigs.each_with_index { |x, i| bbad += 1 unless x.n == 2 ** 70 + i }
      puts "bcount=#{bigs.size} bbad=#{bbad}"
      puts bigs[0].n
      puts bigs.last.n
    RUBY

    _(result).must_answer <<~'OUT'
      count=8000 bad=0
      ITEM0
      ITEM4000
      ITEM7999
      bcount=8000 bbad=0
      1180591620717411303424
      1180591620717411311423
    OUT
  end

  it "subclass sees only the calls ruby makes" do
    result = ze0(<<~'RUBY')
      # Which of String's own methods its methods call on a subclass: every
      # method String defines is wrapped to log a call made from inside another,
      # and each is then called once on a fresh receiver. CRuby calls one by
      # dispatch only where it means to, and ze0's core, written in Ruby, has
      # to call no more and no fewer. Written by `rake gen:dispatch`.

      class Probe < String
        CALLING = []
        LOG = []
        [:%, :*, :+, :+@, :-@, :<, :<<, :<=, :<=>, :==, :===, :=~, :>, :>=, :[], :[]=, :append_as_bytes, :ascii_only?, :b, :between?, :byteindex, :byterindex, :bytes, :bytesize, :byteslice, :bytesplice, :capitalize, :capitalize!, :casecmp, :casecmp?, :center, :chars, :chomp, :chomp!, :chop, :chop!, :chr, :clamp, :clear, :codepoints, :concat, :count, :crypt, :dedup, :delete, :delete!, :delete_prefix, :delete_prefix!, :delete_suffix, :delete_suffix!, :downcase, :downcase!, :dump, :dup, :each_byte, :each_char, :each_codepoint, :each_grapheme_cluster, :each_line, :empty?, :encode, :encode!, :encoding, :end_with?, :eql?, :force_encoding, :freeze, :getbyte, :grapheme_clusters, :gsub, :gsub!, :hash, :hex, :include?, :index, :initialize_copy, :insert, :inspect, :intern, :length, :lines, :ljust, :lstrip, :lstrip!, :match, :match?, :next, :next!, :oct, :ord, :partition, :prepend, :replace, :reverse, :reverse!, :rindex, :rjust, :rpartition, :rstrip, :rstrip!, :scan, :scrub, :scrub!, :setbyte, :size, :slice, :slice!, :split, :squeeze, :squeeze!, :start_with?, :strip, :strip!, :sub, :sub!, :succ, :succ!, :sum, :swapcase, :swapcase!, :to_c, :to_f, :to_i, :to_r, :to_s, :to_str, :to_sym, :tr, :tr!, :tr_s, :tr_s!, :undump, :unicode_normalize, :unicode_normalize!, :unicode_normalized?, :unpack, :unpack1, :upcase, :upcase!, :upto, :valid_encoding?].each do |m|
          define_method(m) do |*args, &blk|
            LOG << "#{CALLING.last}->#{m}" unless CALLING.empty?
            CALLING << m
            begin
              super(*args, &blk)
            ensure
              CALLING.pop
            end
          end
          ruby2_keywords(m)
        end
      end

      def call(name)
        r = Probe.new(+"hello world")
        Probe::LOG.clear
        begin
          yield r
        rescue StandardError => e
          Probe::LOG << "raised #{e.class}"
        end
        puts "#{name}: #{Probe::LOG.join(" ")}" unless Probe::LOG.empty?
      end

      call("%") { |r| r.__send__(:%, 1) { |*x| x.first } }
      call("*") { |r| r.__send__(:*, 1) { |*x| x.first } }
      call("+") { |r| r.__send__(:+, "l") { |*x| x.first } }
      call("+@") { |r| r.__send__(:+@) { |*x| x.first } }
      call("-@") { |r| r.__send__(:-@) { |*x| x.first } }
      call("<") { |r| r.__send__(:<, "l") { |*x| x.first } }
      call("<<") { |r| r.__send__(:<<, 1) { |*x| x.first } }
      call("<=") { |r| r.__send__(:<=, "l") { |*x| x.first } }
      call("<=>") { |r| r.__send__(:<=>, 1) { |*x| x.first } }
      call("==") { |r| r.__send__(:==, 1) { |*x| x.first } }
      call("===") { |r| r.__send__(:===, 1) { |*x| x.first } }
      call("=~") { |r| r.__send__(:=~, /l/) { |*x| x.first } }
      call(">") { |r| r.__send__(:>, "l") { |*x| x.first } }
      call(">=") { |r| r.__send__(:>=, "l") { |*x| x.first } }
      call("[]") { |r| r.__send__(:[], 1) { |*x| x.first } }
      call("[]=") { |r| r.__send__(:[]=, "l", "L") { |*x| x.first } }
      call("append_as_bytes") { |r| r.append_as_bytes() { |*x| x.first } }
      call("ascii_only?") { |r| r.ascii_only?() { |*x| x.first } }
      call("b") { |r| r.b() { |*x| x.first } }
      call("between?") { |r| r.between?("l", "L") { |*x| x.first } }
      call("byteindex") { |r| r.byteindex("l") { |*x| x.first } }
      call("byterindex") { |r| r.byterindex("l") { |*x| x.first } }
      call("bytes") { |r| r.bytes() { |*x| x.first } }
      call("bytesize") { |r| r.bytesize() { |*x| x.first } }
      call("byteslice") { |r| r.byteslice(1) { |*x| x.first } }
      call("capitalize") { |r| r.capitalize() { |*x| x.first } }
      call("capitalize!") { |r| r.capitalize!() { |*x| x.first } }
      call("casecmp") { |r| r.casecmp(1) { |*x| x.first } }
      call("casecmp?") { |r| r.casecmp?(1) { |*x| x.first } }
      call("center") { |r| r.center(1) { |*x| x.first } }
      call("chars") { |r| r.chars() { |*x| x.first } }
      call("chomp") { |r| r.chomp() { |*x| x.first } }
      call("chomp!") { |r| r.chomp!() { |*x| x.first } }
      call("chop") { |r| r.chop() { |*x| x.first } }
      call("chop!") { |r| r.chop!() { |*x| x.first } }
      call("chr") { |r| r.chr() { |*x| x.first } }
      call("clear") { |r| r.clear() { |*x| x.first } }
      call("codepoints") { |r| r.codepoints() { |*x| x.first } }
      call("concat") { |r| r.concat() { |*x| x.first } }
      call("count") { |r| r.count("l") { |*x| x.first } }
      call("dedup") { |r| r.dedup() { |*x| x.first } }
      call("delete") { |r| r.delete("l") { |*x| x.first } }
      call("delete!") { |r| r.delete!("l") { |*x| x.first } }
      call("delete_prefix") { |r| r.delete_prefix("l") { |*x| x.first } }
      call("delete_prefix!") { |r| r.delete_prefix!("l") { |*x| x.first } }
      call("delete_suffix") { |r| r.delete_suffix("l") { |*x| x.first } }
      call("delete_suffix!") { |r| r.delete_suffix!("l") { |*x| x.first } }
      call("downcase") { |r| r.downcase() { |*x| x.first } }
      call("downcase!") { |r| r.downcase!() { |*x| x.first } }
      call("dump") { |r| r.dump() { |*x| x.first } }
      call("dup") { |r| r.dup() { |*x| x.first } }
      call("each_byte") { |r| r.each_byte() { |*x| x.first } }
      call("each_char") { |r| r.each_char() { |*x| x.first } }
      call("each_codepoint") { |r| r.each_codepoint() { |*x| x.first } }
      call("each_grapheme_cluster") { |r| r.each_grapheme_cluster() { |*x| x.first } }
      call("each_line") { |r| r.each_line() { |*x| x.first } }
      call("empty?") { |r| r.empty?() { |*x| x.first } }
      call("encode") { |r| r.encode() { |*x| x.first } }
      call("encode!") { |r| r.encode!() { |*x| x.first } }
      call("encoding") { |r| r.encoding() { |*x| x.first } }
      call("end_with?") { |r| r.end_with?() { |*x| x.first } }
      call("eql?") { |r| r.eql?(1) { |*x| x.first } }
      call("getbyte") { |r| r.getbyte(1) { |*x| x.first } }
      call("grapheme_clusters") { |r| r.grapheme_clusters() { |*x| x.first } }
      call("gsub") { |r| r.gsub(1) }
      call("gsub!") { |r| r.gsub!(1) }
      call("hash") { |r| r.hash() { |*x| x.first } }
      call("hex") { |r| r.hex() { |*x| x.first } }
      call("include?") { |r| r.include?("l") { |*x| x.first } }
      call("index") { |r| r.index("l") { |*x| x.first } }
      call("initialize_copy") { |r| r.initialize_copy("l") { |*x| x.first } }
      call("inspect") { |r| r.inspect() { |*x| x.first } }
      call("intern") { |r| r.intern() { |*x| x.first } }
      call("length") { |r| r.length() { |*x| x.first } }
      call("lines") { |r| r.lines() { |*x| x.first } }
      call("ljust") { |r| r.ljust(1) { |*x| x.first } }
      call("lstrip") { |r| r.lstrip() { |*x| x.first } }
      call("lstrip!") { |r| r.lstrip!() { |*x| x.first } }
      call("match") { |r| r.match("l") { |*x| x.first } }
      call("match?") { |r| r.match?("l") { |*x| x.first } }
      call("next") { |r| r.next() { |*x| x.first } }
      call("next!") { |r| r.next!() { |*x| x.first } }
      call("oct") { |r| r.oct() { |*x| x.first } }
      call("ord") { |r| r.ord() { |*x| x.first } }
      call("partition") { |r| r.partition("l") { |*x| x.first } }
      call("prepend") { |r| r.prepend() { |*x| x.first } }
      call("replace") { |r| r.replace("l") { |*x| x.first } }
      call("reverse") { |r| r.reverse() { |*x| x.first } }
      call("reverse!") { |r| r.reverse!() { |*x| x.first } }
      call("rindex") { |r| r.rindex("l") { |*x| x.first } }
      call("rjust") { |r| r.rjust(1) { |*x| x.first } }
      call("rpartition") { |r| r.rpartition("l") { |*x| x.first } }
      call("rstrip") { |r| r.rstrip() { |*x| x.first } }
      call("rstrip!") { |r| r.rstrip!() { |*x| x.first } }
      call("scan") { |r| r.scan("l") { |*x| x.first } }
      call("scrub") { |r| r.scrub() { |*x| x.first } }
      call("scrub!") { |r| r.scrub!() { |*x| x.first } }
      call("setbyte") { |r| r.setbyte(0, 1) { |*x| x.first } }
      call("size") { |r| r.size() { |*x| x.first } }
      call("slice") { |r| r.slice(1) { |*x| x.first } }
      call("slice!") { |r| r.slice!(1) { |*x| x.first } }
      call("split") { |r| r.split() { |*x| x.first } }
      call("squeeze") { |r| r.squeeze() { |*x| x.first } }
      call("squeeze!") { |r| r.squeeze!() { |*x| x.first } }
      call("start_with?") { |r| r.start_with?() { |*x| x.first } }
      call("strip") { |r| r.strip() { |*x| x.first } }
      call("strip!") { |r| r.strip!() { |*x| x.first } }
      call("sub") { |r| r.sub("l") { |*x| x.first } }
      call("sub!") { |r| r.sub!("l") { |*x| x.first } }
      call("succ") { |r| r.succ() { |*x| x.first } }
      call("succ!") { |r| r.succ!() { |*x| x.first } }
      call("sum") { |r| r.sum() { |*x| x.first } }
      call("swapcase") { |r| r.swapcase() { |*x| x.first } }
      call("swapcase!") { |r| r.swapcase!() { |*x| x.first } }
      call("to_c") { |r| r.to_c() { |*x| x.first } }
      call("to_f") { |r| r.to_f() { |*x| x.first } }
      call("to_i") { |r| r.to_i() { |*x| x.first } }
      call("to_r") { |r| r.to_r() { |*x| x.first } }
      call("to_s") { |r| r.to_s() { |*x| x.first } }
      call("to_str") { |r| r.to_str() { |*x| x.first } }
      call("to_sym") { |r| r.to_sym() { |*x| x.first } }
      call("tr") { |r| r.tr("l", "L") { |*x| x.first } }
      call("tr!") { |r| r.tr!("l", "L") { |*x| x.first } }
      call("tr_s") { |r| r.tr_s("l", "L") { |*x| x.first } }
      call("tr_s!") { |r| r.tr_s!("l", "L") { |*x| x.first } }
      call("unicode_normalize") { |r| r.unicode_normalize() { |*x| x.first } }
      call("unicode_normalize!") { |r| r.unicode_normalize!() { |*x| x.first } }
      call("unicode_normalized?") { |r| r.unicode_normalized?() { |*x| x.first } }
      call("unpack") { |r| r.unpack("l") { |*x| x.first } }
      call("unpack1") { |r| r.unpack1("l") { |*x| x.first } }
      call("upcase") { |r| r.upcase() { |*x| x.first } }
      call("upcase!") { |r| r.upcase!() { |*x| x.first } }
      call("upto") { |r| r.upto(1) }
      call("valid_encoding?") { |r| r.valid_encoding?() { |*x| x.first } }

    RUBY

    _(result).must_answer <<~'OUT'
      <: <-><=>
      <=: <=-><=>
      >: >-><=>
      >=: >=-><=>
      between?: between?-><=>
      dup: dup->initialize_copy
      initialize_copy: raised NoMethodError
      unicode_normalize: unicode_normalize->encoding unicode_normalize->gsub
      unicode_normalize!: unicode_normalize!->encoding unicode_normalize!->gsub
      unicode_normalized?: unicode_normalized?->encoding unicode_normalized?->scan
    OUT
  end

  it "symbol nil truthiness" do
    result = ze0(<<~'RUBY')
      # A nilable symbol slot stores (sp_sym)-1 as its nil sentinel. Truthiness
      # in conditions and in the value form of && / || must test the sentinel;
      # it used to read always-true, so `if @exit_triggered` fired on nil.

      class Level
        def initialize
          @exit_triggered = nil
        end

        def trigger(kind)
          @exit_triggered = kind
        end

        def check
          if @exit_triggered
            "exit:#{@exit_triggered}"
          else
            "playing"
          end
        end

        def check_and(intermission)
          # value-form && with a symbol left arm
          (@exit_triggered && !intermission) ? "finish" : "continue"
        end

        def sym_or_default
          @exit_triggered || :none
        end
      end

      lvl = Level.new
      puts lvl.check
      puts lvl.check_and(false)
      p lvl.sym_or_default
      lvl.trigger(:normal)
      puts lvl.check
      puts lvl.check_and(false)
      puts lvl.check_and(true)
      p lvl.sym_or_default

      # ||= / &&= on nilable symbol slots (ivar and local, statement and value form)
      class Cache
        def initialize
          @mode = nil
        end
        def mode_or_default
          @mode ||= :easy
        end
        def try_upgrade
          @mode &&= :hard
          @mode
        end
        def reset
          @mode = nil
        end
      end

      c = Cache.new
      p c.mode_or_default
      p c.mode_or_default
      p c.try_upgrade
      c.reset
      p c.try_upgrade

      def lsym(start)
        s = start ? :given : nil
        s ||= :fallback
        got = (s &&= :promoted)
        [s, got]
      end
      p lsym(true)
      p lsym(false)
    RUBY

    _(result).must_answer <<~'OUT'
      playing
      continue
      :none
      exit:normal
      finish
      continue
      :normal
      :easy
      :easy
      :hard
      nil
      [:promoted, :promoted]
      [:promoted, :promoted]
    OUT
  end

  it "value subclass of string equality and hashing" do
    result = ze0(<<~'RUBY')
      # A `String` subclass (D3): inherited `String` methods, a `super`-free custom
      # method, `dup` independence, and payload-based equality/`Hash`-key identity
      # (`Tag.new("k")` is the same key as `"k"`, symmetric `==`).

      class Tag < String
        def shout; upcase + "!"; end
      end
      t = Tag.new("hi")
      puts t.shout
      puts t.class
      puts(t == "hi")
      puts("hi" == t)
      puts(Tag.new("x").hash == "x".hash)
      h = { "key" => 1 }
      puts h[Tag.new("key")].inspect
      d = Tag.new("a")
      d2 = d.dup
      d2 << "b"
      puts d
      puts d2
    RUBY

    _(result).must_answer <<~'OUT'
      HI!
      Tag
      true
      true
      true
      1
      a
      ab
    OUT
  end
end
