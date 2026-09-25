# frozen_string_literal: true

require "spec_helper"

describe "String: dispatch" do
  it "boxed nil string identity" do
    result = zr(<<~'RUBY')
      # A NULL string is Ruby nil (the nullable-string invariant); boxing must
      # preserve it, or a boxed nil-string carries the string tag and fails
      # tag-keyed comparisons and nil?.
      x = defined?(no_such_thing)
      p x == nil
      arr = [defined?(nope), 1]
      p arr[0].nil?
      p arr[0] == nil
      h = { k: defined?(zilch) }
      p h[:k].inspect
    RUBY

    _(result).must_answer <<~'OUT'
      true
      true
      true
      "nil"
    OUT
  end

  it "empty array write over string" do
    result = zr(<<~'RUBY')
      # An empty array literal carries no type of its own, so the union of a local's
      # writes kept the other write's type and the array was emitted into a slot
      # shaped for it: `a = ""; a = []` assigned an sp_IntArray to a const char *.
      # A non-empty literal already widened the slot to the boxed one.
      a = ""
      a = []
      a.each { |b| b }
      p a

      b = ""
      b = [1]
      p b

      c = 1
      c = []
      p c

      d = []
      d = ""
      p d

      e = []
      e << 1
      p e

      f = []
      p f
      p f.size

      g = {}
      g = []
      p g
    RUBY

    _(result).must_answer <<~'OUT'
      []
      [1]
      []
      ""
      [1]
      []
      0
      []
    OUT
  end

  it "poly array concat unshift rindex" do
    result = zr(<<~'RUBY')
      # Poly (heterogeneous) array methods: concat (in-place append, incl. typed-array
      # arg), unshift/prepend (front insert), rindex (last match or nil).
      def cat(a, b); a.concat(b); end
      p cat([1, "x"], [:y, 2])
      def cat_typed(a); a.concat([9, 8]); end
      p cat_typed([1, "x"])
      def un(a); a.unshift(:z, 0); end
      p un([1, "x"])
      def ri(a, v); a.rindex(v); end
      p ri([1, "x", 1, "x"], "x")
      p ri([1, "x"], :nope)
      def mut; a = [1, "x"]; a.concat([:y]); a; end
      p mut
      # self-concat must not corrupt when the receiver reallocs mid-copy
      def selfcat(a); a.concat(a); end
      p selfcat([1, "x", 2.0, :q, 5, 6, 7, 8, 9, 10, 11])
      # multiple concat args (incl. a typed-array arg) are all evaluated before appending
      def cat3(a, b); a.concat(b, [9, 8]); end
      p cat3([1, "x"], [:y])
    RUBY

    _(result).must_answer <<~'OUT'
      [1, "x", :y, 2]
      [1, "x", 9, 8]
      [:z, 0, 1, "x"]
      3
      nil
      [1, "x", :y]
      [1, "x", 2.0, :q, 5, 6, 7, 8, 9, 10, 11, 1, "x", 2.0, :q, 5, 6, 7, 8, 9, 10, 11]
      [1, "x", :y, 9, 8]
    OUT
  end

  it "poly array plus concat" do
    result = zr(<<~'RUBY')
      # `Array#+` on an array value of unknown type concatenates. When a record
      # field's only initializer is an empty `[]`, its element type is unresolvable,
      # so it is stored as a boxed value and `+` goes through the dynamic `+`
      # dispatcher. That dispatcher concatenates when both operands are arrays.
      M = Data.define(:xs)

      m = M.new(xs: [])
      m2 = m.with(xs: m.xs + ["a", "b"])
      p m2.xs
      p m2.xs.size

      n = M.new(xs: [])
      p (n.xs + [1, 2]).size          # poly array + int array
      p (n.xs + [[1], [2]]).length    # poly array + nested array
    RUBY

    _(result).must_answer <<~'OUT'
      ["a", "b"]
      2
      2
      2
    OUT
  end

  it "poly dispatch attr reader" do
    result = zr(<<~'RUBY')
      # An attr_reader-defined accessor on a polymorphic receiver works the
      # same as an explicit `def v; @v; end`.

      class C
        def initialize(v); @v = v; end
        attr_reader :v
      end

      class D
        def initialize(v); @v = v; end
        attr_reader :v
      end

      # Same return type per class (string) — result temp stays
      # `const char *`, no boxing.
      def make(flag)
        flag ? C.new("c-val") : D.new("d-val")
      end

      puts make(true).v
      puts make(false).v

      # Mixing an explicit `def v` on one class with attr_reader on
      # others. The dispatcher must cover both shapes.
      class F
        def initialize(v); @v = v; end
        def v; @v; end
      end

      def mix(flag)
        flag ? C.new("from-attr") : F.new("from-def")
      end

      puts mix(true).v
      puts mix(false).v
    RUBY

    _(result).must_answer <<~'OUT'
      c-val
      d-val
      from-attr
      from-def
    OUT
  end

  it "poly dispatch inherited attr reader" do
    result = zr(<<~'RUBY')
      # Parent defines attr_reader :val, SubHolder inherits it.
      # Reading .val via a poly-typed parameter must dispatch
      # correctly for both parent and subclass instances.

      class Holder
        def initialize(v)
          @val = v
        end
        attr_reader :val
      end

      class SubHolder < Holder
      end

      def read_val(e)
        e.val
      end

      puts read_val(Holder.new("a"))
      puts read_val(SubHolder.new("b"))
    RUBY

    _(result).must_answer "a\nb\n"
  end

  it "poly dispatch ptr array" do
    result = zr(<<~'RUBY')
      # Polymorphic `[]` and `length` dispatch must reach an array of user
      # objects. Such an array must not be read as an Integer array.
      #
      # `lenof([Foo.new(1), Foo.new(2)])` prints 2.

      class Foo
        def initialize(n)
          @n = n
        end
        attr_reader :n
      end

      class Bar
        def length
          99
        end

        def [](_)
          77
        end
      end

      def lenof(a)
        a.length
      end

      def first(a)
        a[0]
      end

      # `length` over mixed call sites — IntArray, PtrArray<Foo>, and a
      # user class. The PtrArray branch is the new one for this PR.
      puts lenof([1, 2, 3])                  # 3
      puts lenof([Foo.new(1), Foo.new(2)])   # 2
      puts lenof(Bar.new)                    # 99

      # `[]` over the same shapes.
      puts first([10, 20, 30])               # 10
      foo = first([Foo.new(42)])
      puts foo.n                             # 42
      puts first(Bar.new)                    # 77
    RUBY

    _(result).must_answer <<~'OUT'
      3
      2
      99
      10
      42
      77
    OUT
  end

  it "poly dispatch string receiver split" do
    result = zr(<<~'RUBY')
      # A poly receiver whose method name a user class also owns.
      #
      # Any class can define `split` -- the bundled Pathname does. A genuine String
      # must still take String#split, so `str.split.join(" ")` works. A receiver
      # that matches no class raises, and does not give back a zero value.

      class Path
        attr_reader :s

        def initialize(s)
          @s = s
        end

        def split
          [Path.new("a"), Path.new("b")]
        end

        def bytes
          [1, 2]
        end
      end

      module Util
        module_function

        def wrap(str) = str.split.join(" ")
        def widen(str) = str.length
      end

      # `help` comes off a rest-array pop, so the parameter is poly, not String
      class Flag
        attr_reader :help

        def initialize(*opts)
          @help = opts.pop
        end
      end

      p Util.wrap("Usage:  slap   [options]")
      p Util.wrap(Flag.new("-h", "some  help").help)
      p Util.widen("abcd")

      # the user's own method still wins for its own receiver
      p Path.new("x").split.map { |q| q.s }

      # a value that answers neither raises, rather than reading back as empty
      def poly_split(v) = v.split
      holder = [1, "a b"]
      p poly_split(holder[1])
      begin
        poly_split(holder[0])
        p "no raise"
      rescue NoMethodError
        p "NoMethodError"
      end
    RUBY

    _(result).must_answer <<~'OUT'
      "Usage: slap [options]"
      "some help"
      4
      ["a", "b"]
      ["a", "b"]
      "NoMethodError"
    OUT
  end

  it "poly keyed hash method dedup" do
    result = zr(<<~'RUBY')
      # Hash with Method-typed keys — the optcarrot @peeks/@pokes dedup
      # pattern. Two `obj.method(:foo)` calls produce distinct Method
      # instances but eql? as keys (same bound receiver + fn_ptr), so the
      # `@cache[k] ||= k` cache stores only one entry for them.

      class Cache
        def initialize
          @h = {}
        end
        def add(k)
          @h[k] ||= k
        end
        def has?(k)
          !@h[k].nil?
        end
        def size
          @h.size
        end
      end

      class M
        def self.foo; end
        def self.bar; end
      end

      c = Cache.new
      m1 = M.method(:foo)
      c.add(m1)
      puts c.has?(m1)             # true (same instance round-trips)
      puts c.has?(M.method(:bar)) # false (different fn_ptr)

      # Two distinct Method instances for the same (receiver, fn_ptr)
      # hash and eql? identically, so the cache stays at size 1.
      c.add(M.method(:foo))
      puts c.size                 # 1
      puts c.has?(M.method(:foo)) # true via eql? (m1 returned for the
                                  # query Method instance)
    RUBY

    _(result).must_answer <<~'OUT'
      true
      false
      1
      true
    OUT
  end

  it "poly length string tag" do
    result = zr(<<~'RUBY')
      # `.length` / `.size` on a receiver of unknown type that holds a String
      # at run time gives the String's length. This matters when an
      # is_a?(String) guard appears alongside a length check:
      #   if v.is_a?(String) && v.length > 0; ... end

      class C; def x; 1; end; end

      arr = ["hello", C.new]
      v = arr[0]
      if v.is_a?(String) && v.length > 0
        puts v
      end
      if v.is_a?(String)
        puts v.size.to_s
      end
      puts "done"
    RUBY

    _(result).must_answer <<~'OUT'
      hello
      5
      done
    OUT
  end

  it "poly receiver string method" do
    result = zr(<<~'RUBY')
      # A String method called on a POLY receiver. The receiver is only known at run
      # time (a container read, a yield). A receiver that is not a String must not
      # get the String method applied to its #to_s RENDERING:
      #
      #   [1, Bare.new][1].upcase   # not "#<BARE:0X0000560F...>"
      #
      # CRuby has no such method on the object and raises NoMethodError. Implicit
      # conversion does NOT rescue it either: #to_str converts an ARGUMENT into a
      # String slot and never a receiver, so a class defining #to_str still raises
      # here -- which is why this is not the conversion protocol's business.
      class Bare
      end

      class WithToStr
        def to_str
          "CONV"
        end

        def to_s
          "SHOW"
        end
      end

      def try(label)
        yield
      rescue NoMethodError => e
        p [label, e.class, e.message]
      end

      o = [1, Bare.new][1]
      try("upcase")  { p o.upcase }
      try("strip")   { p o.strip }
      try("reverse") { p o.reverse }
      try("chars")   { p o.chars }

      # #to_str does not make the receiver a String
      w = [1, WithToStr.new][1]
      try("to_str upcase") { p w.upcase }

      # every receiver kind that IS a string still answers, and the ones CRuby
      # refuses are refused: a Symbol has its own case conversion but no #strip,
      # and a shared-mutable string is a builtin box rather than a bare tag.
      p [1, "Ab c"][1].upcase
      p [1, String.new("Ab c")][1].upcase
      p [1, String.new("Ab c")][1].chars
      p [1, :ab][1].upcase
      try("sym strip") { p [1, :ab][1].strip }
      try("int upcase") { p [1, 5][1].upcase }
      try("nil strip")  { p [1, nil][1].strip }

      # a user class that owns the name keeps its own arm
      class Owns
        def upcase
          "MINE"
        end
      end
      p [1, Owns.new][1].upcase
    RUBY

    _(result).must_answer <<~'OUT'
      ["upcase", NoMethodError, "undefined method 'upcase' for an instance of Bare"]
      ["strip", NoMethodError, "undefined method 'strip' for an instance of Bare"]
      ["reverse", NoMethodError, "undefined method 'reverse' for an instance of Bare"]
      ["chars", NoMethodError, "undefined method 'chars' for an instance of Bare"]
      ["to_str upcase", NoMethodError, "undefined method 'upcase' for an instance of WithToStr"]
      "AB C"
      "AB C"
      ["A", "b", " ", "c"]
      :AB
      ["sym strip", NoMethodError, "undefined method 'strip' for an instance of Symbol"]
      ["int upcase", NoMethodError, "undefined method 'upcase' for an instance of Integer"]
      ["nil strip", NoMethodError, "undefined method 'strip' for nil"]
      "MINE"
    OUT
  end

  it "poly recv aref str key" do
    result = zr(<<~'RUBY')
      # A user-defined `def [](k)` takes its parameter type from the
      # caller's arguments. Here the receiver's type is only known at run
      # time (a method param that accepts more than one user class), and
      # callers pass a String key. Each class's `[]` gets the String key.
      # Integer#[] (bit reference) and the Array#[] forms do not apply to
      # a String key.

      class A
        def [](k)
          "from-A:" + k
        end
      end

      class B
        def [](k)
          "from-B:" + k
        end
      end

      def lookup(receiver, key)
        receiver[key]
      end

      puts lookup(A.new, "alpha")
      puts lookup(B.new, "beta")
    RUBY

    _(result).must_answer "from-A:alpha\nfrom-B:beta\n"
  end

  it "poly recv two arg slice" do
    result = zr(<<~'RUBY')
      # 2-arg `recv[start, length]` on a receiver of unknown type. A String
      # value gives a substring, and an Array value gives a length-N slice,
      # not only element 0.
      #
      # Also: `puts arr` prints one element per line, as in MRI, not the
      # array's inspect form.

      def tr(s, length: 30)
        s[0, length]
      end

      puts tr("Hello world this is a long string")
      puts tr([1, 2, 3, 4, 5])
      puts tr([10.5, 20.5, 30.5])
      puts tr(["a", "b", "c"])
    RUBY

    _(result).must_answer <<~'OUT'
      Hello world this is a long str
      1
      2
      3
      4
      5
      10.5
      20.5
      30.5
      a
      b
      c
    OUT
  end

  it "poly str append" do
    result = zr(<<~'RUBY')
      # A value of unknown type flowing into `String#<<` on a mutable String.
      # The canonical shape: a module-level method that returns
      # `@hash[k] || ""` over a heterogeneously-valued hash, so its return
      # type is only known at run time. `io << M.get(:t)` appends the String.

      module M
        @data = {}

        def self.set(k, v)
          @data[k] = v
        end

        def self.get(k)
          @data[k] || ""
        end
      end

      # Mixed value types make the hash values' type known only at run time.
      M.set(:n, 42)
      M.set(:t, "hello")

      io = String.new
      io << M.get(:t)
      puts io                # hello

      # Also exercise the expression-context << path via chained append.
      io2 = String.new
      (io2 << M.get(:t)) << M.get(:t)
      puts io2               # hellohello
    RUBY

    _(result).must_answer "hello\nhellohello\n"
  end

  it "poly str delete chain" do
    result = zr(<<~'RUBY')
      class Wad
        def initialize(blob)
          @blob = blob
        end

        def read_lump(name)
          return nil unless name == "PNAMES"

          @blob
        end
      end

      class Texture
        attr_reader :name

        def initialize(name)
          @name = name
        end

        def self.parse_texture(data, offset)
          name = data[offset, 8].delete("\x00").upcase
          new(name)
        end

        def self.load_all(wad)
          data = wad.read_lump("PNAMES")
          return [] unless data

          [parse_texture(data, 0), parse_texture(data, 8)]
        end
      end

      w = Wad.new("abcd\x00\x00\x00\x00tail\x00\x00\x00\x00rest")
      Texture.load_all(w).each { |t| puts t.name }

      # the plain string form keeps working
      puts "hi\x00\x00\x00".delete("\x00")
      puts Texture.load_all(Wad.new("x\x00\x00\x00\x00\x00\x00\x00")).map(&:name).inspect
    RUBY

    _(result).must_answer <<~'OUT'
      ABCD
      TAIL
      hi
      ["X", ""]
    OUT
  end

  it "poly string append integer" do
    result = zr(<<~'RUBY')
      # `str << int` appends that CODEPOINT, and one outside the range is a
      # RangeError. A String reached through a POLY slot -- the same local also
      # assigned from a container read, so its type is the union -- fell past the
      # String arms of the boxed `<<`, not the Integer shift: `a << -1` raises, as in
      # CRuby.
      a = +"a"
      r = (a << -1 rescue $!.class)
      p r
      h = { k: +"abc" }
      a = h[:k]
      a << "Z"
      p h

      # the same local, both directions
      b = { k: +"abc" }
      c = b[:k]
      p (c << -1 rescue $!.class)
      p (c << 66 rescue $!.class)
      p (c << 0x3042 rescue $!.class)
      p (c << 2**40 rescue $!.class)
      p b

      # through an Array element
      f = [+"q"]
      g = f[0]
      p (g << -5 rescue $!.class)
      p (g << 33 rescue $!.class)
      p f

      # a shared handle appends to a shared handle
      i = [+"x"]
      j = [+"y"]
      k = i[0]
      k << j[0]
      p i

      # and the typed route keeps answering what it answered
      m = +"a"
      p (m << 66 rescue $!.class)
      p (m << -1 rescue $!.class)
    RUBY

    _(result).must_answer <<~'OUT'
      RangeError
      {k: "abcZ"}
      RangeError
      "abcB"
      "abcBあ"
      RangeError
      {k: "abcBあ"}
      RangeError
      "q!"
      ["q!"]
      ["xy"]
      "aB"
      RangeError
    OUT
  end

  it "poly string arm" do
    result = zr(<<~'RUBY')
      # A String reaching the dispatch through a poly slot -- an element of a nested
      # array, where inference does not narrow past the first level -- answers the
      # String methods. `strip` and its one-sided siblings are the shape of most of
      # these.
      #
      # `to_str` is the one that matters beyond convenience: it is the implicit
      # conversion protocol, so a poly slot holding a String has to answer it.
      #
      # The argument-taking ones are here too.
      nested = [["k", "  Vv\tz  "]]
      s = nested[0][1]
      p s.lstrip
      p s.rstrip
      p s.to_str
      p s.ascii_only?
      p s.valid_encoding?
      p s.scrub
      p s.encode

      # above ASCII, where ascii_only? has something to say
      u = [["k", "日本"]]
      p u[0][1].ascii_only?
      p u[0][1].to_str
      p u[0][1].lstrip
      p u[0][1].valid_encoding?

      # the whole point is that these agree with the same call on a plain String
      plain = "  Vv\tz  "
      p [s.lstrip == plain.lstrip, s.rstrip == plain.rstrip, s.to_str == plain.to_str]
      p [s.ascii_only? == plain.ascii_only?, s.valid_encoding? == plain.valid_encoding?]

      # the argument-taking shapes, whose arm lives outside the argc==0 block
      p s.unpack("C*")
      p s.unpack("C3")
      p s.byteslice(2)
      p s.byteslice(2, 2)
      p s.scrub("?")
      p s.encode("UTF-8")
      p u[0][1].unpack("C*").length
      p u[0][1].byteslice(0, 3)

      # a poly slot holding something that is not a String still raises
      mixed = [1, "s"]
      def at(a, i); a[i]; end
      begin
        at(mixed, 0).lstrip
      rescue NoMethodError => e
        puts "NoMethodError"
      end
    RUBY

    _(result).must_answer <<~'OUT'
      "Vv\tz  "
      "  Vv\tz"
      "  Vv\tz  "
      true
      true
      "  Vv\tz  "
      "  Vv\tz  "
      false
      "日本"
      "日本"
      true
      [true, true, true]
      [true, true]
      [32, 32, 86, 118, 9, 122, 32, 32]
      [32, 32, 86]
      "V"
      "Vv"
      "  Vv\tz  "
      "  Vv\tz  "
      6
      "日"
      NoMethodError
    OUT
  end

  it "poly string at path slot" do
    result = zr(<<~'RUBY')
      # A String of unknown static type used as a path argument. The File / Dir / IO
      # surface takes a String ivar whose type is widened, or any untyped accessor,
      # as the path String. The test covers the same shape at different call sites.
      class Store
        def initialize(path)
          @path = path
        end

        # @path is widened to poly by the nil write below, so every use of it is a
        # boxed value rather than a const char *.
        def forget
          @path = nil
        end

        def write_it(text)
          File.open(@path, "w") { |f| f.write(text) }
        end

        # an empty block: the call's value still has to fit the slot it is typed into
        def touch
          File.open(@path, "a") { |f| }
        end

        def exists = File.exist?(@path)
        def sized = File.size(@path)
        def dir = File.directory?(@path)
        def base = File.basename(@path)
        def full = File.expand_path(@path)
        def read_it = File.read(@path)
        def drop = File.delete(@path)
      end

      path = "spinel_pathslot_#{Process.pid}.tmp"
      s = Store.new(path)
      s.write_it("hello")
      p s.exists
      p s.sized
      p s.dir
      p s.base == path
      p s.full.end_with?(path)
      p s.read_it
      s.touch
      p s.sized
      s.drop
      p s.exists
    RUBY

    _(result).must_answer <<~'OUT'
      true
      5
      false
      true
      true
      "hello"
      5
      false
    OUT
  end

  it "poly string char index" do
    result = zr(<<~'RUBY')
      # String#[int] on a value that widened to poly (a method with multiple return
      # paths) must return the single character, not nil.
      def poly_str
        return @c if @c
        s = "ABCDEF"
        @c = s
        s
      end
      d = poly_str
      puts d[0]
      puts d[3]
      puts d[-1]
      puts d[99].inspect
      puts d[0].ord
    RUBY

    _(result).must_answer <<~'OUT'
      A
      D
      F
      nil
      65
    OUT
  end

  it "poly string method vs class method" do
    result = zr(<<~'RUBY')
      # A class method of the same name is reached only through a Class-valued
      # receiver: it must not capture a String instance call in a poly union.
      class Foo
        def self.downcase(s)
          s + "!"
        end

        def self.upcase(s, n)
          s * n
        end
      end

      def pick(n)
        if n > 0
          "HeLLo"
        else
          Foo
        end
      end

      k = pick(1)
      p k.downcase
      p k.upcase
      p k.reverse
      p k.chars.first(2)

      # the class method still answers through the class itself
      p Foo.downcase("x")
      p Foo.upcase("y", 3)

      # and an instance member of the name still wins over the String method
      Row = Struct.new(:upcase)
      def pick2(n)
        n > 0 ? Row.new(7) : "text"
      end
      p pick2(1).upcase
      p pick2(0).upcase
    RUBY

    _(result).must_answer <<~'OUT'
      "hello"
      "HELLO"
      "oLLeH"
      ["H", "e"]
      "x!"
      "yyy"
      7
      "TEXT"
    OUT
  end

  it "poly string transforms" do
    result = zr(<<~'RUBY')
      # sub / gsub / tr / squeeze on a String that arrives boxed (a Fiber#resume
      # value, a container read), alongside the arms that already worked.
      f = Fiber.new { Fiber.yield("t=1.5"); nil }
      v = f.resume
      p (v.sub("t=", "") rescue $!.class)
      p (v.gsub("=", ":") rescue $!.class)
      p (v.tr("=", "-") rescue $!.class)
      p (v.squeeze("1") rescue $!.class)
      p v.delete_prefix("t=")
      p v.upcase
      p v.split("=")
    RUBY

    _(result).must_answer <<~'OUT'
      "1.5"
      "t:1.5"
      "t-1.5"
      "t=1.5"
      "1.5"
      "T=1.5"
      ["t", "1.5"]
    OUT
  end

  it "poly to f via str poly hash" do
    result = zr(<<~'RUBY')
      # `.to_f` on a String value whose type is only known at run time parses
      # the number, the same as on a receiver that is statically a String.
      #
      # Shape from a JSON-ish Hash[String, untyped]: read a string
      # value out of a heterogeneous hash and call .to_f on it.

      class C
        def initialize
          @h = { "w" => "900", "h" => "600.5", "pad" => " 2.5", "junk" => "abc", "blank" => "", "n" => 7, "f" => 1.25 }
        end

        def at(k)
          (@h[k]).to_f
        end
      end

      c = C.new
      puts c.at("w")
      puts c.at("h")
      puts c.at("pad")
      puts c.at("junk")
      puts c.at("blank")
      puts c.at("n")
      puts c.at("f")
    RUBY

    _(result).must_answer <<~'OUT'
      900.0
      600.5
      2.5
      0.0
      0.0
      7.0
      1.25
    OUT
  end

  it "poly to i base" do
    result = zr(<<~'RUBY')
      # `to_i(base)` on a POLY receiver (a value whose static type widened to a union --
      # e.g. an array element that may be Integer or String, or a `case v` result that
      # returns the un-narrowed scrutinee) raised NoMethodError at runtime: the
      # poly-receiver method block is gated on argc == 0, so the one-arg radix form was
      # never handled. It now parses the string with the given base, like
      # String#to_i(base). No-arg to_i (base 10) is unchanged.
      vals = ["ff", 42]        # heterogeneous literal -> poly element type
      p vals[0].to_i(16)       # 255
      p vals[0].to_i           # base 10: "ff" -> 0

      bins = ["101", 0]
      p bins[0].to_i(2)        # 5

      octs = ["17", 0]
      p octs[0].to_i(8)        # 15

      def widen(v)
        case v
        when Integer then v
        when String then v
        else 0
        end
      end
      p widen("2a").to_i(16)   # 42 -- the motivating case/when-dispatch shape

      # A radix only applies to String#to_i; when the poly value is a non-String at
      # runtime (here the Integer 42), CRuby raises ArgumentError rather than parsing
      # the value's string form -- so `42.to_i(16)` is NOT a silent 66.
      begin
        p vals[1].to_i(16)
      rescue ArgumentError => e
        puts "ArgumentError: #{e.message}"
      end
    RUBY

    _(result).must_answer <<~'OUT'
      255
      0
      5
      15
      42
      ArgumentError: wrong number of arguments (given 1, expected 0)
    OUT
  end

  it "poly to i via str poly hash" do
    result = zr(<<~'RUBY')
      # `.to_i` on a receiver whose type is only known at run time gives
      # the Integer value, not 0.
      #
      # Shape: a heterogeneous Hash returns a value of unknown type;
      # `.to_i` on that.

      class C
        def initialize
          @h = { "a" => 42, "b" => "hello" }
        end
        def at(k)
          (@h[k]).to_i
        end
      end

      c = C.new
      puts c.at("a")
    RUBY

    _(result).must_answer "42\n"
  end

  it "poly to s into string slot" do
    result = zr(<<~'RUBY')
      # `to_s` on a receiver of unknown type, where a user class's `to_s` return is
      # untyped, so the result type is only known at run time. The result lands in
      # a String slot and must still read as that String.

      class Cand
        attr_accessor :id

        def initialize(id)
          self.id = id
        end

        def to_s
          id
        end
      end

      class Req
        attr_accessor :verb
      end

      def build(v)
        r = Req.new
        r.verb = (v || "GET").to_s
        r
      end

      p build(nil).verb
      p build("POST").verb
      p Cand.new("z").to_s

      # the same through a local rather than a writer
      def label(v)
        s = (v || "none").to_s
        s
      end
      p label(nil)
      p label("x")
      p label(Cand.new("c"))

      # and into an interpolation, where the slot is a string too
      def show(v) = "[#{(v || 'd').to_s}]"
      p show(nil)
      p show("e")
    RUBY

    _(result).must_answer <<~'OUT'
      "GET"
      "POST"
      "z"
      "none"
      "x"
      "c"
      "[d]"
      "[e]"
    OUT
  end

  it "poly value into str str hash" do
    result = zr(<<~'RUBY')
      # An ivar that can be nil or a String, because a `kwarg: nil`
      # default makes the writer's param nullable. The ivar is then
      # stored as a value in a Hash of String keys and String values.
      #
      # action_controller/base.rb has this pattern:
      # `@location = location` (location is a `location: nil` kwarg)
      # followed by `res.headers["Location"] = controller.location`
      # at the Tep::Server entry. Same pattern, minimized here.

      class C
        attr_reader :loc

        def initialize
          @loc = nil
        end

        def render(loc: nil)
          @loc = loc
        end
      end

      class Bag
        attr_reader :h

        def initialize
          @h = {}
          @h["k"] = "v"
        end
      end

      c = C.new
      c.render(loc: "/b")
      b = Bag.new
      b.h["k2"] = c.loc
      puts b.h["k"]
      puts b.h["k2"]
    RUBY

    _(result).must_answer "v\n/b\n"
  end

  it "ptr array to poly array at call" do
    result = zr(<<~'RUBY')
      # A method param that takes a mixed array, because one caller
      # passes a heterogeneous literal `[A.new, "x"]`. Another caller
      # passes a homogeneous `[A.new, A.new]`. Both calls must work, and
      # the elements of the homogeneous array must stay A instances.

      class A
        attr_reader :tag
        def initialize(t = "default"); @tag = t; end
      end

      def take(arr)
        arr.first
      end

      a_arr = [A.new("homogeneous"), A.new("entry2")]
      mixed = [A.new("mixed_a"), "x"]
      r1 = take(a_arr)
      r2 = take(mixed)
      # r1 should be an A instance.
      # Verify by reading back the tag after a runtime is_a? check.
      if r1.is_a?(A)
        puts r1.tag
      else
        puts "NOT_A"
      end
      if r2.is_a?(A)
        puts r2.tag
      else
        puts "NOT_A"
      end
    RUBY

    _(result).must_answer "homogeneous\nmixed_a\n"
  end

  it "str poly hash dup widen" do
    result = zr(<<~'RUBY')
      # A local initialized from `.dup` of a Hash with String values, where
      # later writes put values of other types into it. Reads of the copied
      # String values must give those values, not 0 or nil. The test reads
      # the values, not only `.length`.

      class Match
        attr_reader :path_params
        def initialize(pp); @path_params = pp; end
      end

      m = Match.new({ "article_id" => "1", "format" => "html" })
      merged = m.path_params.dup
      merged["x"] = 1        # int value forces analyzer-side widening to str_poly_hash
      puts merged["article_id"]   # round-trips the original str value
      puts merged["format"]
      puts merged["x"]
      puts merged.length
    RUBY

    _(result).must_answer <<~'OUT'
      1
      html
      1
      3
    OUT
  end

  it "str poly hash dup widen from int" do
    result = zr(<<~'RUBY')
      # Sibling case to "str poly hash dup widen": here the source Hash has
      # Integer values. Reads from the copy give the original Integers.

      class Counter
        attr_reader :counts
        def initialize(h); @counts = h; end
      end

      c = Counter.new({ "a" => 1, "b" => 2 })
      merged = c.counts.dup
      merged["x"] = "label"   # str value forces analyzer-side widening
      puts merged["a"]
      puts merged["b"]
      puts merged["x"]
    RUBY

    _(result).must_answer <<~'OUT'
      1
      2
      label
    OUT
  end

  it "String.new takes an argument read boxed out of a nested array, and refuses nil" do
    result = zr(<<~'RUBY')
      # String.new(x) where x is a value of unknown type -- an element read out of
      # a nested array, rather than a flat array, a local, or a literal. The
      # argument must be unboxed to its String.
      nested = [["class", "x"]]
      p String.new(nested[0][1])             # "x"

      # A flat array element, covered alongside the nested case.
      flat = ["class", "y"]
      p String.new(flat[1])                  # "y"

      # The copy is independent of the source.
      def mutable_from_nested(pairs)
        s = String.new(pairs[0][1])
        s << "!"
        s
      end
      p mutable_from_nested([["k", "z"]])    # "z!"
      p [["k", "z"]][0][1]                   # "z" (unchanged)

      # A poly value that cannot convert to a String still raises TypeError, same as
      # a plain String.new(nil) / String.new(5). A variable index into a
      # heterogeneous array keeps the element poly-typed rather than narrowed.
      mixed = [nil, 5, "z"]
      def poly_at(arr, i); arr[i]; end
      begin
        String.new(poly_at(mixed, 0))
      rescue TypeError => e
        puts e.message
      end
      begin
        String.new(poly_at(mixed, 1))
      rescue TypeError => e
        puts e.message
      end
    RUBY

    _(result).must_answer <<~'OUT'
      "x"
      "y"
      "z!"
      "z"
      no implicit conversion of nil into String
      no implicit conversion of Integer into String
    OUT
  end
end
