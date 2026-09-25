# frozen_string_literal: true

require "spec_helper"

describe "String: defining and naming methods" do
  it "alias supports the symbol spelling of both names" do
    result = zr(<<~'RUBY')
      class Greeter
        def hello
          "hi"
        end
        alias :bonjour :hello
      end
      puts Greeter.new.bonjour
    RUBY

    _(result).must_answer "hi\n"
  end

  it "define method with a symbol to proc block" do
    result = zr(<<~'RUBY')
      # `define_method(:name, &:other)`. In CRuby the `&` conversion happens at
      # the CALL SITE, before rb_mod_define_method runs (proc.c:2872, which
      # rejects a bare Symbol as its second positional arg), so the body is the
      # symbol proc `->(recv, *rest) { recv.other(*rest) }` -- which is why the
      # defined method takes its RECEIVER as the first argument.

      class Widget
        define_method(:as_str, &:to_s)
      end
      class Gadget
        define_method :label, &:to_s
      end
      puts Widget.new.as_str(7)
      puts Gadget.new.label(8)
      p [1, 2, 3].map(&:to_s)
      p [10, 20, 30].inject(0, &:+)
    RUBY

    _(result).must_answer <<~'OUT'
      7
      8
      ["1", "2", "3"]
      60
    OUT
  end

  it "int element alias not string" do
    result = zr(<<~'RUBY')
      # `b0 = bytes[i]` where bytes holds Integers, in a method that also appends to a
      # String: `b0 << 4` is an Integer shift, not a String append, and `b0` stays
      # an Integer.
      ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"

      def encode(s)
        bytes = s.bytes
        n = bytes.length
        out = +""
        i = 0
        while i + 3 <= n
          b0 = bytes[i]
          b1 = bytes[i + 1]
          b2 = bytes[i + 2]
          out << ALPHABET[(b0 >> 2) & 0x3F].to_s
          out << ALPHABET[((b0 << 4) | (b1 >> 4)) & 0x3F].to_s
          out << ALPHABET[((b1 << 2) | (b2 >> 6)) & 0x3F].to_s
          out << ALPHABET[b2 & 0x3F].to_s
          i = i + 3
        end
        out
      end

      p encode("Man")
      p encode("any carnal pleasure")

      # the string alias through a container still works
      rows = [+"abc"]
      r = rows[0]
      r.upcase!
      p [rows, r.equal?(rows[0])]
    RUBY

    _(result).must_answer <<~'OUT'
      "TWFu"
      "YW55IGNhcm5hbCBwbGVhc3Vy"
      [["ABC"], true]
    OUT
  end

  it "interpolated undef is a runtime tombstone" do
    result = zr(<<~'RUBY')
      # `undef :"#{name}"` (immutable_struct_ex strips Struct writers in a loop)
      # has no compile-time spelling: it desugars to a runtime `undef_method` on
      # the default definee, in class-body order.
      class Wardrobe
        def hat; "hat"; end
        def hat=(_v); end
        def coat; "coat"; end
        def coat=(_v); end

        %w[hat coat].each do |piece|
          undef :"#{piece}="
        end
      end

      w = Wardrobe.new
      p w.hat
      p w.coat
      begin
        w.hat = 1
      rescue NoMethodError => e
        puts "writer gone: #{e.class}"
      end
      p w.respond_to?(:coat=)

      # Inside instance_eval on a singleton (the immutable_struct_ex shape), and
      # mixed with a plain name in one statement.
      class Locker
        def a; :a; end
        def b; :b; end
        def c; :c; end
        gone = "b"
        undef :a, :"#{gone}"
      end
      l = Locker.new
      p l.c
      p l.respond_to?(:a)
      p l.respond_to?(:b)
      puts "still running"
    RUBY

    _(result).must_answer <<~'OUT'
      "hat"
      "coat"
      writer gone: NoMethodError
      false
      :c
      false
      false
      still running
    OUT
  end

  it "mutable str alias uaf" do
    result = zr(<<~'RUBY')
      # A mutable String (String.new + <<) owns its internal buffer, freed by
      # the object's finalizer. Boxing/coercing/returning that buffer as an
      # immutable string must copy it, not alias it: otherwise a GC that
      # collects the unreferenced builder frees the buffer out from under the
      # still-referenced string (a use-after-free). Each path below captures
      # the converted value, then churns the heap and forces a GC so a freed
      # buffer would be reused before it is read back.

      def build_io(n)
        io = String.new
        i = 0
        while i < n
          io << i.to_s
          io << ","
          i += 1
        end
        io
      end

      def hold(x)                 # the param takes values of any class
        GC.start
        i = 0
        t = ""
        while i < 4000
          t = t + i.to_s
          i += 1
        end
        x
      end

      def via_to_s(n)             # mutable.to_s returned across a fn boundary
        build_io(n).to_s
      end

      def via_gsub(n)             # gsub with no match returns the receiver
        build_io(n).gsub("ZZZ", "x")
      end

      hold(42)                    # an Integer call lets hold take any class

      a = hold(build_io(6))       # pass through a param of any class
      b = via_to_s(6)             # to_s conversion
      c = String(build_io(6))     # Kernel#String conversion
      d = via_gsub(6)             # no-op gsub returning the receiver

      i = 0
      t = ""
      while i < 8000
        t = t + i.to_s
        i += 1
      end
      GC.start
      i = 0
      while i < 8000
        t = t + i.to_s
        i += 1
      end

      puts a
      puts b
      puts c
      puts d
    RUBY

    _(result).must_answer <<~'OUT'
      0,1,2,3,4,5,
      0,1,2,3,4,5,
      0,1,2,3,4,5,
      0,1,2,3,4,5,
    OUT
  end

  it "send with a non literal target binds keyword args" do
    result = zr(<<~'RUBY')
      # The G2 trailing-kwargs-hash convention: `send`'s truly-dynamic
      # fallback (non-literal target name) carries kwargs as one trailing
      # Hash; the callee's trampoline pops and binds it.

      class Foo
        def bar(x:)
          x
        end
      end
      name = :bar
      puts Foo.new.send(name, x: 41) + 1
    RUBY

    _(result).must_answer "42\n"
  end

  it "shared string reference links" do
    result = zr(<<~'RUBY')
      # The same String written twice is a `@`-link the second time, so a
      # mutation through one alias is visible through the other after load.

      s = "ab"
      g = Marshal.load(Marshal.dump([s, s]))
      g[0] << "z"
      p g[1]
    RUBY

    _(result).must_answer "\"abz\"\n"
  end

  it "a String reached through an accessor is the object the container holds, as through [] it is" do
    result = zr(<<~'RUBY')
      # A String reached through an ACCESSOR call is the same object the container
      # holds, exactly as one reached through `[]` is. An index assignment or an
      # in-place mutator on it changes the String in the container.
      b = [+"xyz"]
      b.first[1] = "*"
      p b

      b = [+"xyz"]
      b.last[1] = "*"
      p b

      b = [+"xyz"]
      b.fetch(0)[1] = "*"
      p b

      b = [+"abc"]
      b.first.replace("zzz")
      p b

      b = [+"abc"]
      b.first << "Z"
      p b

      h = { k: +"abc" }
      h.dig(:k) << "Z"
      p h

      # bound to a local first, which is the same alias
      b = [+"abc"]
      a = b.first
      a << "Z"
      p b

      b = [+"abc"]
      a = b.last
      a.replace("zzz")
      p b

      # the COUNT forms answer a new Array and are untouched by any of this
      b = [+"abc", +"def"]
      p b.first(1)
      p b.last(2)

      # and the ordinary reads keep their values
      p [1, 2, 3].first
      p [1, 2, 3].last
      p [].first
      p [].last
      p({ a: 1 }.first)
      p (1..3).first
      p [1, 2, 3].send(:first)
    RUBY

    _(result).must_answer <<~'OUT'
      ["x*z"]
      ["x*z"]
      ["x*z"]
      ["zzz"]
      ["abcZ"]
      {k: "abcZ"}
      ["abcZ"]
      ["zzz"]
      ["abc"]
      ["abc", "def"]
      1
      3
      nil
      nil
      [:a, 1]
      1
      1
    OUT
  end

  it "a String read out of a container into a local aliases the element, so a mutation shows in both" do
    result = zr(<<~'RUBY')
      # Reading a mutable String out of a container into a local aliases the
      # element: an in-place mutation through the local must show in the container,
      # and `equal?` must answer true. The local does not hold a COPY.
      rows = [+"abc"]
      r = rows[0]
      r.upcase!
      p [rows, r, r.equal?(rows[0])]
      r << "Z"
      p rows
      r.sub!("A", "q")
      p rows
      r.replace("new")
      p rows

      h = { a: +"abc" }
      v = h[:a]
      v << "Z"
      p [h, v.equal?(h[:a])]
      v.upcase!
      p h

      n = { 1 => +"one" }
      w = n[1]
      w << "!"
      p n

      # unrelated: a copy is still a copy when nothing mutates
      plain = ["abc"]
      q = plain[0]
      p [q, plain]

      # a store then an alias

      store = {}
      store[:k] = +"v"
      sv = store[:k]
      sv << "2"
      p store
    RUBY

    _(result).must_answer <<~'OUT'
      [["ABC"], "ABC", true]
      ["ABCZ"]
      ["qBCZ"]
      ["new"]
      [{a: "abcZ"}, true]
      {a: "ABCZ"}
      {1 => "one!"}
      ["abc", ["abc"]]
      {k: "v2"}
    OUT
  end
end
