# frozen_string_literal: true

require "spec_helper"

describe "Marshal programs" do
  it "carries an array s ivars" do
    result = ze0(<<~'RUBY')
      a = [1]
      a.instance_variable_set(:@meta, 7)
      back = Marshal.load(Marshal.dump(a))
      p back
      p back.instance_variable_get(:@meta)
    RUBY

    _(result).must_answer <<~'OUT'
      [1]
      7
    OUT
  end

  it "data value and the numeric values round trip" do
    result = ze0(<<~'RUBY')
      # Marshal writes a Data value as the Struct record CRuby writes, reads it
      # back frozen, and builds a Rational or a Complex without calling their
      # `allocate`, which Ruby cannot call. A class is written by its name
      # alone, whatever it holds in its own instance variables.
      Point = Data.define(:x, :y)
      Pair = Struct.new(:a, :b)

      [Point.new(x: 1, y: [2]), Pair.new(3, "four"), 3r, Complex(1, 2), Thread, Point].each do |value|
        dumped = Marshal.dump(value)
        back = Marshal.load(dumped)
        p [dumped, back, back == value, back.frozen?]
      end

    RUBY

    _(result).must_answer <<~'OUT'
      ["\x04\bS:\nPoint\a:\x06xi\x06:\x06y[\x06i\a", #<data Point x=1, y=[2]>, true, true]
      ["\x04\bS:\tPair\a:\x06ai\b:\x06bI\"\tfour\x06:\x06ET", #<struct Pair a=3, b="four">, true, false]
      ["\x04\bU:\rRational[\ai\bi\x06", (3/1), true, true]
      ["\x04\bU:\fComplex[\ai\x06i\a", (1+2i), true, true]
      ["\x04\bc\vThread", Thread, true, false]
      ["\x04\bc\nPoint", Point, true, false]
    OUT
  end

  it "an anonymous class is refused, because a dump names the class load must find" do
    result = ze0(<<~'RUBY')
      # A dump names the class so `Marshal.load` can find it again, which an
      # ANONYMOUS class has no way to be -- so it is refused rather than written as a
      # reference nothing can resolve.
      def scrub(s) = s.sub(/0x[0-9a-f]+/, "ADDR")
      def err
        yield
        :no_raise
      rescue TypeError => e
        [e.class, scrub(e.message)]
      end

      klass = Struct.new(:x)
      p err { Marshal.dump(klass.new(42)) }
      p err { Marshal.dump(klass) }
      p err { Marshal.dump(Class.new) }
      p err { Marshal.dump(Module.new) }
      p err { Marshal.dump(Class.new.new) }
      p err { Marshal.dump(String.singleton_class) }

      # A NAMED one still round-trips, however it was minted.
      Point = Struct.new(:x, :y)
      p Marshal.load(Marshal.dump(Point.new(1, 2))).to_a
      Minted = Class.new do
        attr_accessor :v
      end
      m = Minted.new
      m.v = 7
      p Marshal.load(Marshal.dump(m)).v
      p Marshal.load(Marshal.dump(Point)).name
      p Marshal.load(Marshal.dump([1, "two", :three, {a: 1}]))

      # An anonymous class nested inside an otherwise fine structure still refuses.
      p err { Marshal.dump([1, Class.new.new]) }
      p err { Marshal.dump({k: Struct.new(:z).new(1)}) }
    RUBY

    _(result).must_answer <<~'OUT'
      [TypeError, "can't dump anonymous class #<Class:ADDR>"]
      [TypeError, "can't dump anonymous class #<Class:ADDR>"]
      [TypeError, "can't dump anonymous class #<Class:ADDR>"]
      [TypeError, "can't dump anonymous module #<Module:ADDR>"]
      [TypeError, "can't dump anonymous class #<Class:ADDR>"]
      [TypeError, "singleton class can't be dumped"]
      [1, 2]
      7
      "Point"
      [1, "two", :three, {a: 1}]
      [TypeError, "can't dump anonymous class #<Class:ADDR>"]
      [TypeError, "can't dump anonymous class #<Class:ADDR>"]
    OUT
  end

  it "the value tower round-trips, and symbols and floats write CRuby's exact bytes" do
    result = ze0(<<~'RUBY')
      # Marshal round-trips the value tower (primitives, bignum, array, hash,
      # Rational, shared refs and cycles) and writes CRuby's exact wire bytes for
      # symbols (with ;-symlinks) and floats.
      #
      # The cycle it round-trips, and the copy that came back: both alive at exit.
      # At exit: cycle leak: 2 objects (Array x2)

      def rt(x) = Marshal.load(Marshal.dump(x))
      p rt(42)
      p rt(-987654321)
      p rt(3.14)
      p rt("hi")
      p rt(:sym)
      p rt([1, "x", :y, nil, true])
      p rt(2 ** 200)
      p rt(Rational(3, 4))
      p [rt(Rational(1, 3)), rt(Rational(2, 5))]
      shared = [1, 2]
      sg = rt([shared, shared])
      sg[0] << 99
      p sg[1]
      cyc = [10]
      cyc << cyc
      dc = rt(cyc)
      p dc[1][1][0]
      puts Marshal.dump([:ab, :cd, :ab]).bytes.join(",")
      puts Marshal.dump(100.0).bytes.join(",")
    RUBY

    _(result).must_answer <<~'OUT'
      42
      -987654321
      3.14
      "hi"
      :sym
      [1, "x", :y, nil, true]
      1606938044258990275541962092341162602522202993782792835301376
      (3/4)
      [(1/3), (2/5)]
      [1, 2, 99]
      10
      4,8,91,8,58,7,97,98,58,7,99,100,59,0
      4,8,102,8,49,101,50
    OUT
  end

  it "dump takes an IO and a depth limit, and load takes an IO, freeze: and a proc" do
    result = ze0(<<~'RUBY')
      # Marshal's entry surface beyond the byte format (which matches
      # exactly): `dump(obj, io)` WRITES to the IO (zeo writes nothing),
      # `load` accepts an IO source, `freeze: true` freezes the graph, the
      # proc argument visits every object, the depth-limit argument raises
      # ArgumentError past the limit, and the incompatible-format TypeError
      # carries its detail line ("format version 4.8 required; 9.8 given").
      # (Found by the 2026-08-24 probe sweep.)
      require "stringio"
      def show
        p yield
      rescue Exception => e
        puts "#{e.class}: #{e.message}"
      end
      show { io = StringIO.new(+"".b); Marshal.dump([1], io); io.string.bytes.first(2) }
      show { Marshal.load(StringIO.new(Marshal.dump(:sym))) }
      show { r = Marshal.load(Marshal.dump(["s"]), freeze: true); [r.frozen?, r.first.frozen?] }
      show do
        seen = []
        Marshal.load(Marshal.dump([1, "a"]), ->(o) { seen << o.class; o })
        seen.map(&:to_s).sort
      end
      show { Marshal.dump([[1]], 1) }
      show { Marshal.load("\x09\x08T") }
    RUBY

    _(result).must_answer <<~'OUT'
      [4, 8]
      :sym
      [true, true]
      ["Array", "Integer", "String", "TrueClass"]
      ArgumentError: exceed depth limit
      TypeError: incompatible marshal file format (can't be read)
      	format version 4.8 required; 9.8 given
    OUT
  end

  it "an exception loads back, and an extended module travels with the object" do
    result = ze0(<<~'RUBY')
      # A dumped exception loads back. `marshal_allocate` has no Exception arm,
      # so it reports "allocator undefined" for a class `rclass.rs` already knows
      # how to allocate.
      begin
        e = Marshal.load(Marshal.dump(Errno::EINTR.new))
        p e.class
        p e.message
      rescue Exception => ex
        puts "errno\t#{ex.class}: #{ex.message}"
      end

      begin
        r = Marshal.load(Marshal.dump(RuntimeError.new("boom")))
        p [r.class, r.message]
      rescue Exception => ex
        puts "runtime\t#{ex.class}: #{ex.message}"
      end

      # `extend`ed modules travel: CRuby writes an `e` record per module and
      # re-extends on load.
      module Tag
        def tagged? = true
      end

      o = Object.new
      o.extend(Tag)
      r = Marshal.load(Marshal.dump(o))
      p r.singleton_class.ancestors.include?(Tag)
      p r.tagged?
    RUBY

    _(result).must_answer <<~'OUT'
      Errno::EINTR
      "Interrupted system call"
      [RuntimeError, "boom"]
      true
      true
    OUT
  end

  it "dump writes a NUL-heavy payload to an IO, and load reads one back" do
    result = ze0(<<~'RUBY')
      # Marshal.load takes either the serialized bytes or an IO to read them from,
      # and Marshal.dump writes to an IO when it is given one. Only the String forms
      # were compiled: `Marshal.load(f)` handed the sp_File* over as though the
      # handle itself were the bytes, and the C build stopped on the pointer type.
      # `Marshal.dump(obj, f)` matched no arm at all and came out as a NameError on
      # the Marshal constant. (matz/spinel#4112)
      path = "/tmp/sp_marshal_io_stream_#{Process.pid}.bin"

      # The round trip through a stream, with the value carrying a NUL-heavy dump:
      # the write is binary, so the bytes are sized from the header rather than by
      # strlen, which would stop at the first NUL inside the payload.
      File.open(path, "wb") { |f| Marshal.dump({ "a" => [1, 2.5, nil, true] }, f) }
      p File.size(path) > 0
      p File.open(path) { |f| Marshal.load(f) }

      # The shape it was reduced from: the block's value is untyped, and the result
      # lands in an ivar.
      class Store
        def load_from(p)
          @table = File.open(p) { |f| Marshal.load(f) }
        end
        attr_reader :table
      end
      s = Store.new
      p s.load_from(path)
      p s.table.is_a?(Hash)

      # dump answers the stream it wrote to, as CRuby does.
      File.open(path, "wb") { |f| p Marshal.dump("x", f).is_a?(File) }

      # The String forms are untouched.
      bytes = Marshal.dump([1, "two", :three])
      p bytes.is_a?(String)
      p Marshal.load(bytes)

      # A handle held in a local, rather than a block parameter, reaches the same arm.
      f = File.open(path, "rb")
      p Marshal.load(f)
      f.close

      File.unlink(path)
    RUBY

    _(result).must_answer <<~'OUT'
      true
      {"a" => [1, 2.5, nil, true]}
      {"a" => [1, 2.5, nil, true]}
      true
      true
      true
      [1, "two", :three]
      "x"
    OUT
  end

  it "Rational, Complex and a plain user object round-trip, sharing what was shared" do
    result = ze0(<<~'RUBY')
      # The cycle this program builds on purpose, and the census it leaves
      # behind. A cycle alive at exit is not a defect: it is a ring the
      # program never broke, so the census below is recorded as an
      # observation rather than gated on.
      #
      # Marshal's object-link table needs shared references and cycles to exercise it.
      # At exit: cycle leak: 2 objects (Array x2)
      # Marshal.dump / Marshal.load round-trip (Phase 1): primitives, Array, Hash.
      def rt(x) = Marshal.load(Marshal.dump(x))
      p rt(42)
      p rt(-7)
      p rt(0)
      p rt(122)
      p rt(123)
      p rt(1234567890)
      p rt(-987654321)
      p rt(3.14)
      p rt(-2.5)
      p rt(nil)
      p rt(true)
      p rt(false)
      p rt("hello")
      p rt("")
      p rt(:a_symbol)
      p rt([1, 2, 3])
      p rt(["a", "b", "c"])
      p rt([1, "x", :y, nil, true, [2, 3]])
      p rt([])
      # Hashes are loaded as a general hash; verify via element access (Hash#inspect
      # of a polymorphic hash is a separate, pre-existing gap).
      h = rt({"a" => 1, "b" => 2})
      puts h["a"]
      puts h["b"]
      g = rt({x: [1, 2], y: "z"})
      puts g[:x].inspect
      puts g[:y]
      # Bignum.
      p rt(123456789012345678901234567890)
      p rt(-99999999999999999999999999999999)
      p rt(2 ** 200)
      p rt([1, 100000000000000000000, "z"])
      # Shared references and cycles (CRuby's object-link table).
      shared = [1, 2]
      sg = rt([shared, shared])
      sg[0] << 99
      p sg[1]
      cyc = [10]
      cyc << cyc
      dc = rt(cyc)
      p dc[0]
      p dc.length
      p dc[1][1][0]
      sh = {n: 1}
      eh = rt([sh, sh])
      eh[0][:m] = 5
      p eh[1][:m]
      # Complex and Rational (CRuby `U` user-marshal form). Zeo's Complex is
      # float-only, so its components round-trip as Floats.
      p rt(Rational(3, 4))
      p rt(Rational(-1, 2))
      p rt(Rational(5, 1))
      p rt(Complex(1.5, -2.5))
      p rt([Rational(1, 3), Rational(2, 5)])
      rc = rt({r: Rational(7, 8), c: Complex(1.5, -2.5)})
      puts rc[:r]
      puts rc[:c]
      # Plain user objects (CRuby `o` form). Verified via attribute access, since an
      # object's #inspect carries a non-deterministic address.
      class MPoint
        def initialize(x, y, label)
          @x = x
          @y = y
          @label = label
        end
        attr_reader :x, :y, :label
      end
      mp = rt(MPoint.new(3, 4, "pt"))
      puts mp.x
      puts mp.y
      puts mp.label
      # nil ivar round-trips as nil
      class MNil
        def initialize(a); @a = a; end
        attr_reader :a, :b
      end
      mn = rt(MNil.new(10))
      p mn.a
      p mn.b
      # nested user object + poly ivar holding mixed values
      class MInner
        def initialize(v); @v = v; end
        attr_reader :v
      end
      class MOuter
        def initialize(inner, item); @inner = inner; @item = item; end
        attr_reader :inner, :item
      end
      mo = rt(MOuter.new(MInner.new(42), "tag"))
      puts mo.inner.v
      puts mo.item
      mo2 = rt(MOuter.new(MInner.new(7), [1, 2]))
      puts mo2.inner.v
      p mo2.item
      # shared object reference round-trips as a shared object
      mshared = MInner.new(99)
      mpair = rt([mshared, mshared])
      p mpair[0].v
      p mpair[1].v
    RUBY

    _(result).must_answer <<~'OUT'
      42
      -7
      0
      122
      123
      1234567890
      -987654321
      3.14
      -2.5
      nil
      true
      false
      "hello"
      ""
      :a_symbol
      [1, 2, 3]
      ["a", "b", "c"]
      [1, "x", :y, nil, true, [2, 3]]
      []
      1
      2
      [1, 2]
      z
      123456789012345678901234567890
      -99999999999999999999999999999999
      1606938044258990275541962092341162602522202993782792835301376
      [1, 100000000000000000000, "z"]
      [1, 2, 99]
      10
      2
      10
      5
      (3/4)
      (-1/2)
      (5/1)
      (1.5-2.5i)
      [(1/3), (2/5)]
      7/8
      1.5-2.5i
      3
      4
      pt
      10
      nil
      42
      tag
      7
      [1, 2]
      99
      99
    OUT
  end

  it "a graph of hashes, arrays and a Struct comes back == to what went in" do
    result = ze0(<<~'RUBY')
      # Marshal writes and reads a graph of core objects inside the binary.
      Point = Struct.new(:x, :y)
      data = { list: [1, 2.5, "three", :four], point: Point.new(6, 7), set: (1..3).to_a }
      bytes = Marshal.dump(data)
      back = Marshal.load(bytes)
      p back[:list]
      p back[:point].to_a
      p back == data
      puts bytes.encoding
    RUBY

    _(result).must_answer <<~'OUT'
      [1, 2.5, "three", :four]
      [6, 7]
      true
      ASCII-8BIT
    OUT
  end

  it "an instance variable on a String survives the round trip" do
    result = ze0(<<~'RUBY')
      # Instance variables on a STRING survive a Marshal round-trip (the I
      # prefix carries them); zeo drops them silently -- object ivars already
      # round-trip. Data loss, not a missing error. (Found by the 2026-08-24
      # probe sweep.)
      s = +"payload"
      s.instance_variable_set(:@tag, :iv)
      r = Marshal.load(Marshal.dump(s))
      p r
      p r.instance_variable_get(:@tag)
    RUBY

    _(result).must_answer <<~'OUT'
      "payload"
      :iv
    OUT
  end

  it "a repeated symbol writes a link, and a float writes CRuby's shortest round-tripping text" do
    result = ze0(<<~'RUBY')
      # Marshal writer: a repeated symbol emits a `;<index>` link (CRuby writes each
      # symbol in full once), and floats use CRuby's Marshal text -- the shortest
      # round-tripping %g with the exponent normalized (0.0 -> "0", 100.0 -> "1e2",
      # 1e-9 -> "1e-9") -- not Ruby's to_s. Compared as raw bytes.
      d = Marshal.dump([:ab, :cd, :ab])
      puts d.bytes.join(",")
      puts Marshal.dump(100.0).bytes.join(",")
      p Marshal.load(Marshal.dump([:a, :a]))
      p Marshal.load(Marshal.dump([100.0, 1e-9, 0.0]))
      h = Marshal.load(Marshal.dump({a: 1, b: 2}))
      p h[:a] + h[:b]
    RUBY

    _(result).must_answer <<~'OUT'
      4,8,91,8,58,7,97,98,58,7,99,100,59,0
      4,8,102,8,49,101,50
      [:a, :a]
      [100.0, 1.0e-09, 0.0]
      3
    OUT
  end

  it "a Range and a hash default survive the round trip" do
    result = ze0(<<~'RUBY')
      # The cycle this program builds on purpose, and the census it leaves
      # behind. A cycle alive at exit is not a defect: it is a ring the
      # program never broke, so the census below is recorded as an
      # observation rather than gated on.
      #
      # Marshal's object-link table needs shared references and cycles to exercise it.
      # At exit: cycle leak: 2 objects (Array x2)
      # `Marshal` must round-trip a value to something `==` to it. Two shapes come
      # back wrong:
      #
      #   * a `Range` cannot be dumped at all -- `TypeError: no _dump_data is defined
      #     for class Range` -- so any structure CONTAINING one fails with it;
      #   * a `Hash`'s default value is dropped, so `Hash.new(0)` loads back with a
      #     nil default and the first `h[k] += 1` against it raises.
      #
      # Ruby marshals a Range as an ordinary object with three ivars (`@begin`,
      # `@end`, `@excl`) and writes a hash's default alongside its entries
      # (`marshal.c`'s `w_object` has a dedicated `TYPE_HASH_DEF`). zeo's dumper
      # reaches neither, and the Range case surfaces as an error about a C-extension
      # hook that has nothing to do with what the caller wrote.
      #
      # Marshal is how a value crosses a process or a cache boundary, so a silently
      # dropped default is the worse of the two: it fails later, somewhere else.

      p Marshal.load(Marshal.dump(1..2))
      p Marshal.load(Marshal.dump([1, (1...5), :x]))

      p Marshal.load(Marshal.dump({a: 1, b: [2, 3]}))

      h = Hash.new(0)
      h[:seen] = 1
      loaded = Marshal.load(Marshal.dump(h))
      p loaded
      p loaded[:missing]

      # These already round-trip, so a fix must keep them.
      p Marshal.load(Marshal.dump([1, "a", :b, nil, true, 1.5]))
      s = +"shared"
      pair = Marshal.load(Marshal.dump([s, s]))
      p pair[0].equal?(pair[1])
      cyc = [1]
      cyc << cyc
      p Marshal.load(Marshal.dump(cyc))[1].class
    RUBY

    _(result).must_answer <<~'OUT'
      1..2
      [1, 1...5, :x]
      {a: 1, b: [2, 3]}
      {seen: 1}
      0
      [1, "a", :b, nil, true, 1.5]
      true
      Array
    OUT
  end

  it "the I, /, c, m, S, U and u records each match CRuby byte for byte" do
    result = ze0(<<~'RUBY')
      # Marshal wire format: the `I` encoding wrapper, `/` Regexp, `c`/`m` class and
      # module references, `S` Struct, and the `U`/`u` user hooks -- all byte-checked
      # against CRuby and round-tripped.
      def wire(x) = Marshal.dump(x).bytes.join(",")
      def rt(x) = Marshal.load(Marshal.dump(x))

      # A string's encoding rides an `I` wrapper: E=true (UTF-8), E=false (US-ASCII),
      # encoding="<name>" (other), no wrapper for ASCII-8BIT.
      puts wire("abc")
      puts wire("abc".b)
      puts wire("café")
      puts wire("abc".encode("Shift_JIS"))
      puts rt("café").encoding.name
      puts rt("abc".b).encoding.name
      puts rt("abc".encode("Shift_JIS")).encoding.name

      # Shared strings link the second time, so a mutation is visible through both.
      s = "ab"
      g = rt([s, s])
      g[0] << "z"
      p g[1]

      # Regexp: source bytes + an option byte (i=1, x=2, m=4), I-wrapped.
      puts wire(/ab.c/im)
      r = rt(/a\d+b/i)
      puts "#{r.source} #{r.options}"

      # Class / module references.
      puts wire(String)
      p rt(String)
      p rt(Comparable)

      # Struct: class symbol, member count, member/value pairs.
      Point = Struct.new(:x, :y)
      puts wire(Point.new(1, 2))
      pt = rt(Point.new(10, "east"))
      p [pt.x, pt.y]

      # `U`: marshal_dump / marshal_load.
      class Temp
        def initialize(c = 0) = (@celsius = c)
        attr_reader :celsius
        def marshal_dump = [@celsius]
        def marshal_load(a) = (@celsius = a[0])
      end
      puts wire(Temp.new(21))
      p rt(Temp.new(100)).celsius

      # `u`: _dump / self._load, with a binary payload.
      class Version
        def initialize(n = 0) = (@n = n)
        attr_reader :n
        def _dump(depth) = [@n].pack("N")
        def self._load(s) = new(s.unpack1("N"))
      end
      puts wire(Version.new(258))
      p rt(Version.new(65535)).n

      # `C`: a subclass of a value builtin marshals the inherited body inline.
      class Tag < String; end
      puts wire(Tag.new("v1"))
      t = rt(Tag.new("v1"))
      puts "#{t.class} #{t.upcase}"
    RUBY

    _(result).must_answer <<~'OUT'
      4,8,73,34,8,97,98,99,6,58,6,69,84
      4,8,34,8,97,98,99
      4,8,73,34,10,99,97,102,195,169,6,58,6,69,84
      4,8,73,34,8,97,98,99,6,58,13,101,110,99,111,100,105,110,103,34,14,83,104,105,102,116,95,74,73,83
      UTF-8
      ASCII-8BIT
      Shift_JIS
      "abz"
      4,8,73,47,9,97,98,46,99,5,6,58,6,69,70
      a\d+b 1
      4,8,99,11,83,116,114,105,110,103
      String
      Comparable
      4,8,83,58,10,80,111,105,110,116,7,58,6,120,105,6,58,6,121,105,7
      [10, "east"]
      4,8,85,58,9,84,101,109,112,91,6,105,26
      100
      4,8,117,58,12,86,101,114,115,105,111,110,9,0,0,1,2
      65535
      4,8,73,67,58,8,84,97,103,34,7,118,49,6,58,6,69,84
      Tag V1
    OUT
  end

  it "plain object keeps its ivar order and marshals" do
    result = ze0(<<~'RUBY')
      # Two divergences on the same storage, both on a BARE `Object` and neither on a
      # user class, which is why the corpus never saw them.
      #
      # `Object.new`'s ivars were a plain `HashMap`, so `instance_variables` and
      # `inspect` reported them in hash order rather than FIRST-ASSIGNMENT order.
      # The store's own doc called that "limited to the name-keyed main object";
      # the emitter folds every `Object.new` to the same type, so it was every one
      # of them. `DynObject` -- an instance of a class minted at run time -- already
      # used an insertion-ordered map, and says why.
      #
      # `Marshal.load` allocated through `dispatch::allocate_of`, which is documented
      # to answer `None` for a BUILTIN because a builtin's blank instance lives with
      # `Class#allocate`. `Object` is a builtin, so a dumped plain object could not
      # be loaded back at all: `TypeError: allocator undefined for Object`.
      o = Object.new
      o.instance_variable_set(:@b, "two")
      o.instance_variable_set(:@a, [1, 2])
      r = Marshal.load(Marshal.dump(o))
      p r.class, r.instance_variables, r.instance_variable_get(:@a), r.instance_variable_get(:@b)
      p r.equal?(o)

      n = Object.new
      n.instance_variable_set(:@inner, o)
      p Marshal.load(Marshal.dump(n)).instance_variable_get(:@inner).instance_variable_get(:@b)

      # The order is the OBJECT's, not the class's, and every route reports the same
      # one -- including a removal, which leaves no hole for a later name to fill.
      q = Object.new
      q.instance_variable_set(:@z, 1)
      q.instance_variable_set(:@m, 2)
      q.instance_variable_set(:@a, 3)
      p q.instance_variables
      p q.inspect.sub(/0x[0-9a-f]+/, "0xADDR")
      p q.dup.instance_variables
      p q.clone.instance_variables
      q.remove_instance_variable(:@m)
      p q.instance_variables
      q.instance_variable_set(:@m, 9)
      p q.instance_variables
      p Marshal.load(Marshal.dump(q)).instance_variables

      f = Object.new
      f.instance_variable_set(:@x, 1)
      f.freeze
      p f.frozen?, f.dup.frozen?, f.clone.frozen?
      p Marshal.load(Marshal.dump(f)).frozen?
    RUBY

    _(result).must_answer <<~'OUT'
      Object
      [:@b, :@a]
      [1, 2]
      "two"
      false
      "two"
      [:@z, :@m, :@a]
      "#<Object:0xADDR @z=1, @m=2, @a=3>"
      [:@z, :@m, :@a]
      [:@z, :@m, :@a]
      [:@z, :@a]
      [:@z, :@a, :@m]
      [:@z, :@a, :@m]
      true
      false
      true
      false
    OUT
  end

  it "refuses the undumpable" do
    result = ze0(<<~'RUBY')
      # `Marshal.dump` refuses what cannot round-trip: an object with a singleton
      # ("singleton can't be dumped") and an IO ("can't dump IO"). zeo dumps both
      # happily, silently losing the singleton and the stream -- wrong DATA, not
      # just a missing error. (Found by the 2026-08-24 probe sweep.)
      o = Object.new
      def o.only_mine = 1
      begin
        Marshal.dump(o)
        puts "singleton dumped"
      rescue TypeError => e
        puts e.message
      end
      begin
        Marshal.dump($stdout)
        puts "io dumped"
      rescue TypeError => e
        puts e.message
      end
    RUBY

    _(result).must_answer <<~'OUT'
      singleton can't be dumped
      can't dump IO
    OUT
  end

  it "stream holds one value after another" do
    result = ze0(<<~'RUBY')
      # A load takes one value from a stream and leaves the rest, so a stream
      # holds value after value. A hash whose default is a block cannot be
      # written at all, and neither can a module with no name.
      require "stringio"
      require "tmpdir"

      def t = yield rescue [$!.class, $!.message]

      io = StringIO.new(+"".b)
      Marshal.dump(1, io)
      Marshal.dump("two", io)
      Marshal.dump([:three], io)
      io.rewind
      p Marshal.load(io)
      p Marshal.load(io)
      p Marshal.load(io)
      p t { Marshal.load(io) }

      path = File.join(Dir.tmpdir, "ze0_marshal_stream_#{Process.pid}.bin")
      File.open(path, "wb") { |f| Marshal.dump({ "a" => 1 }, f); Marshal.dump("b", f) }
      File.open(path, "rb") do |f|
        p Marshal.load(f)
        p Marshal.load(f)
        p f.eof?
      end
      File.unlink(path)

      # A stream that stops in the middle of a value has reached its end;
      # bytes that stop there are a dump that was cut short.
      full = Marshal.dump("hello")
      p t { Marshal.load(StringIO.new(full.byteslice(0, 4))) }
      p t { Marshal.load(StringIO.new(full.byteslice(0, 2))) }
      p t { Marshal.load(full.byteslice(0, 4)) }
      p t { Marshal.load(+"".b) }

      p t { Marshal.dump(Hash.new { |h, k| k }) }
      p t { Marshal.dump(Hash.new(5)).bytes.last }
      p t { Marshal.dump(Object.new.extend(Module.new)) }
      p t { Marshal.dump(Class.new.new) }


    RUBY

    _(result).must_answer <<~'OUT'
      1
      "two"
      [:three]
      [EOFError, "end of file reached"]
      {"a" => 1}
      "b"
      true
      [EOFError, "end of file reached"]
      [EOFError, "end of file reached"]
      [ArgumentError, "marshal data too short"]
      [ArgumentError, "marshal data too short"]
      [TypeError, "can't dump hash with default proc"]
      10
      [TypeError, "can't dump anonymous class #<Module:0xADDR>"]
      [TypeError, "can't dump anonymous class #<Class:0xADDR>"]
    OUT
  end

  it "symbol round trips with its encoding" do
    result = ze0(<<~'RUBY')
      # A Symbol is its bytes and the encoding they are in, and Marshal keeps
      # both: a binary name is plain bytes, a UTF-8 one names its encoding. An
      # Encoding's own _load answers the name it was handed; Marshal's loader
      # turns that into the encoding.
      p Marshal.restore(Marshal.dump([1, "two", :three]))
      p Marshal.load(Marshal.dump(Encoding::UTF_8)), Encoding._load("UTF-8").class
      p Marshal.load(Marshal.dump("é".b.to_sym)), Marshal.load(Marshal.dump("é".b.to_sym)).encoding
      p Marshal.load(Marshal.dump(:"é")), Marshal.load(Marshal.dump(:"é")).encoding
      p Marshal.load(Marshal.dump([:"é", :"é", "é".b.to_sym]))
      p Marshal.dump(:"é").bytes, Marshal.dump("é".b.to_sym).bytes

    RUBY

    _(result).must_answer <<~'OUT'
      [1, "two", :three]
      #<Encoding:UTF-8>
      String
      :"\xC3\xA9"
      #<Encoding:BINARY (ASCII-8BIT)>
      :é
      #<Encoding:UTF-8>
      [:é, :é, :"\xC3\xA9"]
      [4, 8, 73, 58, 7, 195, 169, 6, 58, 6, 69, 84]
      [4, 8, 58, 7, 195, 169]
    OUT
  end

  it "user marshal and userdef hooks" do
    result = ze0(<<~'RUBY')
      # `U` (marshal_dump/marshal_load) and `u` (_dump/self._load) drive
      # serialization through user methods; both round-trip through allocate +
      # the hook.

      def wire(x) = Marshal.dump(x).bytes.join(",")
      def rt(x) = Marshal.load(Marshal.dump(x))
      class UBox
        def initialize(v = nil) = (@v = v)
        attr_reader :v
        def marshal_dump = [@v, 7]
        def marshal_load(a) = (@v = a[0])
      end
      puts wire(UBox.new(5))
      p rt(UBox.new("payload")).v
      class LilEndian
        def initialize(n = 0) = (@n = n)
        attr_reader :n
        def _dump(depth) = [@n].pack("N")
        def self._load(s) = new(s.unpack1("N"))
      end
      puts wire(LilEndian.new(258))
      p rt(LilEndian.new(65535)).n
    RUBY

    _(result).must_answer <<~'OUT'
      4,8,85,58,9,85,66,111,120,91,7,105,10,105,12
      "payload"
      4,8,117,58,14,76,105,108,69,110,100,105,97,110,9,0,0,1,2
      65535
    OUT
  end
end
