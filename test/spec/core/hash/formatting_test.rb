# frozen_string_literal: true

require "spec_helper"

describe "Hash: formatting and inspection" do
  it "empty hash arg param widen" do
    result = ze0(<<~'RUBY')
      # Issue #397. `def store(receiver); receiver["k"] = "v"; end; store({})`
      # previously emitted `sp_StrIntHash_set(receiver, "k", "v")` -- a const
      # char* into the int-valued slot of `sp_StrIntHash`, fails C-compile.
      # `{}` literal defaulted to str_int_hash, the param widened to that
      # from the caller, and the body's String store didn't fit.
      #
      # Fix: narrow_param_hash_types_from_body_writes scans the body for
      # `lv_<param>[k] = v` writes and widens the param's hash variant from
      # the observed value type. Then compile_call_args_with_defaults's new
      # empty_hash_coerce arm rewrites the caller's empty `{}` to emit the
      # matching `sp_<HashType>_new()`. detect_poly_params also gets an
      # empty-hash carve-out so it doesn't fold the body-widened concrete
      # type back to poly.

      def store_str(receiver)
        receiver["k"] = "v"
        receiver["k2"] = "v2"
        receiver
      end

      h = store_str({})
      puts h["k"]                # v
      puts h["k2"]               # v2

      def store_sym_int(h)
        h[:a] = 1
        h[:b] = 2
        h
      end

      s = store_sym_int({})
      puts s[:a].to_s            # 1
      puts s[:b].to_s            # 2

      # Mixed values widens to str_poly_hash.
      def store_mixed(r)
        r["i"] = 7
        r["s"] = "x"
        r
      end

      m = store_mixed({})
      puts m["i"].to_s           # 7
      puts m["s"]                # x
    RUBY

    _(result).must_answer <<~'OUT'
      v
      v2
      1
      2
      7
      x
    OUT
  end

  it "empty hash int int promote" do
    result = ze0(<<~'RUBY')
      # An empty `{}` hash that then receives an integer-literal key must
      # promote from the str_int_hash empty-default to int_int_hash.
      # Otherwise the integer key is passed to sp_StrIntHash_set/_get as a
      # `const char *` and dereferenced, segfaulting. Gated on Integer
      # *literal* keys (an unresolved/variable key whose type is the "int"
      # first-pass fallback must NOT promote, or a later-resolved String key
      # would be stored into an int_int_hash).

      h = {}
      h[1] = 10
      h[2] = 20
      puts h[1].to_s
      puts h[2].to_s
      puts h.size.to_s

      # present-key arithmetic and has_key? guard
      puts (h[1] + h[2]).to_s
      puts h.has_key?(5).to_s
      puts h.has_key?(1).to_s

      # overwrite an existing key
      h[1] = 11
      puts h[1].to_s

      # method scope
      def build_counts
        m = {}
        m[100] = 1
        m[200] = 2
        m[100] + m[200]
      end
      puts build_counts.to_s
    RUBY

    _(result).must_answer <<~'OUT'
      10
      20
      2
      30
      false
      true
      11
      3
    OUT
  end

  it "hash and regexp as hash keys" do
    result = ze0(<<~'RUBY')
      # A Hash used as a Hash KEY was keyed by identity, not by value: two equal
      # literals were two different keys, and `#hash` disagreed between them.
      #
      # `HashKey` projects every other key structurally, but a Hash fell through to
      # `Identity(pointer)`. The obstacle was that ruby's `Hash#hash`/`#eql?` are
      # order INSENSITIVE while a derived `PartialEq` over a `Vec` is order
      # SENSITIVE -- so the pairs are put in a canonical order when the KEY is built
      # instead of being compared as a multiset. That keeps the derived `PartialEq`
      # correct and leaves the hottest equality surface in the collections layer
      # untouched.
      #
      # The REGEXP half stays as the control; it used to fail the same way.

      def show(label)
        puts "#{label}: #{yield.inspect}"
      rescue Exception => e # rubocop:disable Lint/RescueException
        puts "#{label}: #{e.class}: #{e.message}"
      end

      h = { { a: 1 } => "hash key", /re/ => "regexp key", [1, 2] => "array key" }
      show("hash key") { h[{ a: 1 }] }
      show("regexp key") { h[/re/] }
      show("array key") { h[[1, 2]] }

      show("Hash#hash agrees") { { a: 1 }.hash == { a: 1 }.hash }
      show("Regexp#hash agrees") { /re/.hash == /re/.hash }
      show("Array#hash agrees") { [1, 2].hash == [1, 2].hash }

      # Order does not matter to `Hash#hash` in ruby, and must not matter to lookup.
      show("Hash#hash ignores order") { { a: 1, b: 2 }.hash == { b: 2, a: 1 }.hash }

      g = { { a: 1 } => "one", { a: 1, b: 2 } => "two", {} => "empty" }
      show("two keys") { g[{ a: 1, b: 2 }] }
      show("reordered") { g[{ b: 2, a: 1 }] }
      show("empty hash key") { g[{}] }
      show("miss") { g[{ a: 2 }] }
      show("size") { g.size }

      # Nested, and with mixed key/value types inside the key.
      n = { { a: { b: 1 } } => "nested" }
      show("nested") { n[{ a: { b: 1 } }] }
      show("nested miss") { n[{ a: { b: 2 } }] }
      m = { { 1 => "a", :s => [1, 2], "str" => 1.5 } => "mixed" }
      show("mixed") { m[{ "str" => 1.5, :s => [1, 2], 1 => "a" }] }

      show("eql?") { { a: 1 }.eql?({ a: 1 }) }
      show("uniq") { [{ a: 1 }, { a: 1 }, { b: 2 }].uniq.size }
      require "set"
      show("as a set member") { Set[{ a: 1 }, { a: 1 }].size }

      # A key mutated after insertion is filed under a digest that no longer
      # describes it, and `rehash` is what re-derives them. It was a no-op, on the
      # belief that lookups digest afresh -- they do not, the map IS keyed by the
      # digest. Broken for an Array key too, which is why both are checked.
      k = { a: 1 }
      hash_keyed = { k => "v" }
      k[:b] = 2
      show("stale hash key") { hash_keyed[{ a: 1, b: 2 }] }
      show("rehashed hash key") { hash_keyed.rehash[{ a: 1, b: 2 }] }

      arr = [1]
      arr_keyed = { arr => "v" }
      arr << 2
      show("stale array key") { arr_keyed[[1, 2]] }
      show("rehashed array key") { arr_keyed.rehash[[1, 2]] }
      show("rehash returns self") { arr_keyed.rehash.equal?(arr_keyed) }
      show("keys survive rehash") { arr_keyed.keys }
    RUBY

    _(result).must_answer <<~'OUT'
      hash key: "hash key"
      regexp key: "regexp key"
      array key: "array key"
      Hash#hash agrees: true
      Regexp#hash agrees: true
      Array#hash agrees: true
      Hash#hash ignores order: true
      two keys: "two"
      reordered: "two"
      empty hash key: "empty"
      miss: nil
      size: 3
      nested: "nested"
      nested miss: nil
      mixed: "mixed"
      eql?: true
      uniq: 2
      as a set member: 1
      stale hash key: nil
      rehashed hash key: "v"
      stale array key: nil
      rehashed array key: "v"
      rehash returns self: true
      keys survive rehash: [[1, 2]]
    OUT
  end

  it "hash default through derived hashes" do
    result = ze0(<<~'RUBY')
      g = Hash.new { |hh, k| hh[k] = k * 2 }
      g["a"] = "x"
      p g.dup["yy"], g.clone["xx"], g.merge({})["ss"], g.compact["qq"]
      p g.merge({ "b" => "y" }).size

      s = Hash.new { |hh, k| hh[k] = k.to_s }
      s[:a] = "x"
      p s.dup[:b], s.clone[:c], s.compact[:d], s.merge({})[:e]

      m = Hash.new { |hh, k| hh[k] = [k] }
      m[1] = "one"
      m["s"] = 2
      p m.dup[9], m.clone[8], m.compact[7], m.merge({})[6]

      h = Hash.new(7)
      h["a"] = 1
      p h.dup["z"], h.clone["z"], h.merge({})["z"], h.compact["z"]

      p h.except("a")["zz"]
      c = Hash.new(0)
      c["a"] = 2
      p c.except("a")["z"]
      d = Hash.new("dflt")
      d["q"] = "v"
      p d.except("q")["nope"]
      p g.except("a")["ww"]
      p s.except(:a)[:ww]
      p m.except(1)[42]
      p g.size, s.size, m.size
    RUBY

    _(result).must_answer <<~'OUT'
      "yyyy"
      "xxxx"
      "ssss"
      "qqqq"
      2
      "b"
      "c"
      "d"
      "e"
      [9]
      [8]
      [7]
      [6]
      7
      7
      7
      7
      nil
      nil
      nil
      nil
      nil
      nil
      1
      1
      2
    OUT
  end

  it "hash enumerable eql batch" do
    result = ze0(<<~'RUBY')
      # Hash Enumerable wiring, eql?, replace widening (KieranP #2361,#2372,#2373,#2374)
      p({ a: 1 }.eql?({ a: 1 }))
      p({ a: 1 }.eql?({ a: 2 }))
      class NoEql
        def initialize(x); @x = x; end
      end
      n = NoEql.new(1)
      p n.eql?(n)
      p(/ab/ == /ab/)
      a = /ab/
      v = a.dup
      p(v == a)
      d = [1, 2, 3].each
      w = d.dup
      p(w == d)
      p w.next
      p({ a: 1, b: 2 }.find_index([:b, 2]))         # #2372
      p({ a: 1, b: 2 }.uniq)
      p({ a: 1 }.zip([9]))
      p({ a: 1, b: 2 }.tally)
      r = []
      { a: 1, b: 2 }.reverse_each { |k, v2| r << k }
      p r
      p({ 1 => 1.5, 2 => 2.5 }.value?(2.5))          # #2373
      p({ 1 => 1.5, 2 => 2.5 }.has_value?(3.5))
      h = { a: 1, b: 2 }                              # #2374 (used to hang)
      res = h.transform_keys!(&:to_s)
      p res
      p h
      h2 = { a: 1 }
      r2 = h2.replace({ "x" => 2 })
      p r2
      p h2
    RUBY

    _(result).must_answer <<~'OUT'
      true
      false
      true
      true
      true
      false
      1
      1
      [[:a, 1], [:b, 2]]
      [[[:a, 1], 9]]
      {[:a, 1] => 1, [:b, 2] => 1}
      [:b, :a]
      true
      false
      {"a" => 1, "b" => 2}
      {"a" => 1, "b" => 2}
      {"x" => 2}
      {"x" => 2}
    OUT
  end

  it "hash fetch keyerror message" do
    result = ze0(<<~'RUBY')
      # Hash#fetch's KeyError must carry the missing key: "key not found: <key.inspect>".
      # The suffix was dropped, so the message was a bare "key not found". Each key type
      # inspects differently (:sym, "str", 99), so the key is boxed and inspected.
      def fs(h, k); h.fetch(k); end
      begin; fs({a: 1, b: 2}, :zzz); rescue KeyError => e; puts e.message; end   # key not found: :zzz

      def fstr(h, k); h.fetch(k); end
      begin; fstr({"x" => 1}, "yy"); rescue KeyError => e; puts e.message; end   # key not found: "yy"

      def fi(h, k); h.fetch(k); end
      begin; fi({1 => "a"}, 99); rescue KeyError => e; puts e.message; end       # key not found: 99

      # fetch_values reports the first missing key.
      def fv(h, a, b); h.fetch_values(a, b); end
      begin; fv({a: 1}, :a, :nope); rescue KeyError => e; puts e.message; end     # key not found: :nope

      # A hash held in a poly slot (mixed value types) dispatches through the poly
      # fetch path, which shared the same bare message.
      def poly_h; { one: 1, two: "second" }; end
      def pf(h, k); h.fetch(k); end
      begin; pf(poly_h, :three); rescue KeyError => e; puts e.message; end        # key not found: :three

      # A present key still returns its value, and fetch with a default is unaffected.
      p fs({a: 1, b: 2}, :b)                                                       # 2
      def fd(h, k); h.fetch(k, -1); end
      p fd({a: 1}, :missing)                                                       # -1
    RUBY

    _(result).must_answer <<~'OUT'
      key not found: :zzz
      key not found: "yy"
      key not found: 99
      key not found: :nope
      key not found: :three
      2
      -1
    OUT
  end

  it "hash inspect poly" do
    result = ze0(<<~'RUBY')
      h_sym_poly = { a: "x", b: 1, c: :sym }
      p h_sym_poly
      puts h_sym_poly.inspect

      h_str_poly = { "a" => "x", "b" => 1, "c" => :sym }
      p h_str_poly
      puts h_str_poly.inspect

      h_sym_poly2 = { a: nil, b: 1 }
      p h_sym_poly2

      h_str_poly2 = { "k" => nil, "n" => 1 }
      p h_str_poly2
    RUBY

    _(result).must_answer <<~'OUT'
      {a: "x", b: 1, c: :sym}
      {a: "x", b: 1, c: :sym}
      {"a" => "x", "b" => 1, "c" => :sym}
      {"a" => "x", "b" => 1, "c" => :sym}
      {a: nil, b: 1}
      {"k" => nil, "n" => 1}
    OUT
  end

  it "hash many composite keys" do
    result = ze0(<<~'RUBY')
      # The bucket index takes the low bits of a key's hash, and several key kinds
      # leave their information out of those (a Float's mantissa bits are zero for a
      # whole number, an array of small coordinates folds to h*31+x). Those keys
      # landed on a handful of slots however large the table grew, and lookups
      # degenerated into linear scans. This only shows as time, so what the test
      # holds is that the entries are all there and answer correctly.
      n = 4000
      h = {}
      i = 0
      while i < n
        h[[i % 40, i / 40]] = i
        i += 1
      end
      p [h.size, h[[7, 3]], h[[39, 99]], h[[40, 0]]]

      fh = {}
      i = 0
      while i < n
        fh[i.to_f] = i
        i += 1
      end
      p [fh.size, fh[7.0], fh[3999.0], fh[4000.0]]

      st = Struct.new :a, :b
      sh = {}
      i = 0
      while i < n
        sh[st.new(i % 40, i / 40)] = i
        i += 1
      end
      p [sh.size, sh[st.new(7, 3)], sh[st.new(39, 99)]]

      rh = {}
      i = 0
      while i < 500
        rh[(i..i + 1)] = i
        i += 1
      end
      p [rh.size, rh[(7..8)], rh[(499..500)]]

      g = (0...n).group_by { |v| [v % 40, v / 40] }
      p [g.size, g[[7, 3]], g[[0, 0]].size]

      # the same keys still compare and enumerate in insertion order
      p h.keys.first(3)
      p h.to_a.last
    RUBY

    _(result).must_answer <<~'OUT'
      [4000, 127, 3999, nil]
      [4000, 7, 3999, nil]
      [4000, 127, 3999]
      [500, 7, 499]
      [4000, [127], 1]
      [[0, 0], [1, 0], [2, 0]]
      [[39, 99], 3999]
    OUT
  end

  it "hash new default empty" do
    result = ze0(<<~'RUBY')
      # An empty Hash.new(default) is a real hash: size/inspect/p work before any
      # key is inserted (it used to raise "uninitialized constant Hash"), and the
      # default is served for missing keys.
      h = Hash.new(0)
      puts h.size
      puts h.inspect
      puts h[:missing]
      h[:a] += 1
      puts h.inspect
      p Hash.new(0)
      g = Hash.new("d")
      puts g["nope"]
      puts g.size
      e = Hash.new
      puts e.size
    RUBY

    _(result).must_answer <<~'OUT'
      0
      {}
      0
      {a: 1}
      {}
      d
      0
      0
    OUT
  end

  it "hash new direct receiver" do
    result = ze0(<<~'RUBY')
      # A Hash.new called on directly has no key usage to decide its variant, and
      # staying unknown made every method on it an unresolved call (#3823).
      begin
        p Hash.new(0).fetch(:z)
      rescue KeyError => e
        p e.class
      end
      p Hash.new(0)[:z]
      p Hash.new(0).size
      p Hash.new(0).empty?
      p Hash.new { |h, k| k.to_s }[:abc]
      h = Hash.new(0)
      h[:a] += 1
      p h[:a]
      p h[:b]
      # values_at answers the default for a missing key
      p Hash.new(0).values_at(:x, :y)
      p({ a: 1 }.values_at(:a, :b))
    RUBY

    _(result).must_answer <<~'OUT'
      KeyError
      0
      0
      true
      "abc"
      1
      0
      [0, 0]
      [1, nil]
    OUT
  end

  it "hash that holds itself compares and inspects" do
    result = ze0(<<~'RUBY')
      # A Hash, an Array or an object that holds itself ends its walk where
      # CRuby does: the same two objects compared again inside their own
      # comparison are equal, and an object inspected again inside its own
      # inspect shows `...`.
      h = {}
      h[:a] = h
      g = {}
      g[:a] = g
      p h == g, h.eql?(h), h.eql?(g), h == h.dup

      a = []
      a << a
      b = []
      b << b
      p({a => 1}[b])
      p a == b, a.eql?(b)

      o = Object.new
      o.instance_variable_set(:@a, o)
      puts o.inspect.gsub(/0x\h+/, "0xXX")

      s = Struct.new(:x)
      v = s.new
      v.x = v
      puts v.inspect.gsub(/0x\h+/, "0xXX")
      Point = Struct.new(:x)
      w = Point.new
      w.x = w
      puts w.inspect
    RUBY

    _(result).must_answer <<~'OUT'
      true
      true
      true
      true
      1
      true
      true
      #<Object:0xXX @a=#<Object:0xXX ...>>
      #<struct x=#<struct #<Class:0xXX>:...>>
      #<struct Point x=#<struct Point:...>>
    OUT
  end

  it "hash transform keys accepts a mapping" do
    result = ze0(<<~'RUBY')
      p({ a: 1, b: 2 }.transform_keys(a: :x))
      p({ a: 1, b: 2 }.transform_keys(a: :x) { |k| k.to_s })
      h = { a: 1, b: 2 }
      h.transform_keys!(b: :y)
      p h
    RUBY

    _(result).must_answer <<~'OUT'
      {x: 1, b: 2}
      {x: 1, "b" => 2}
      {a: 1, y: 2}
    OUT
  end

  it "hash transform keys cross" do
    result = ze0(<<~'RUBY')
      # Hash#transform_keys with a sym → string block: result is a
      # str_*_hash (key-type swap). Same-type blocks preserve the variant.
      h = {a: 1, b: 2}
      r1 = h.transform_keys { |k| k.to_s }
      puts r1.inspect
      puts r1["a"]
      puts r1["b"]

      # Same-type block: sym → sym keeps sym_int_hash
      r2 = {a: 1, b: 2}.transform_keys { |k| k }
      puts r2.inspect
      puts r2[:a]
    RUBY

    _(result).must_answer <<~'OUT'
      {"a" => 1, "b" => 2}
      1
      2
      {a: 1, b: 2}
      1
    OUT
  end

  it "hash variant call boundary sym" do
    result = ze0(<<~'RUBY')
      # #690: Symbol-keyed hash literal passed to a sym_poly_hash-typed
      # callee param must convert at the call boundary; the post-#676
      # kwargs-bind path no longer covered this shape.
      #
      # Mirrors the failing roundhouse pattern: render_attrs takes
      # Hash[Symbol, untyped] (sym_poly_hash), callers pass a literal
      # {key: val} (sym_str_hash). The value types diverge, so the call
      # needs sp_SymStrHash_to_sym_poly to bridge.

      def render_attrs(attrs)
        pairs = []
        attrs.each do |k, v|
          pairs << k.to_s + "=" + v.to_s
        end
        pairs.join(" ")
      end

      # Calling with a Symbol-keyed string-valued literal.
      puts render_attrs({ class: "primary", id: "go" })

      # Calling with the merged form: literal SymStr + LV SymStr.
      def build_attrs
        inner = { id: "foo" }
        render_attrs({ class: "btn" }.merge(inner))
      end

      puts build_attrs
    RUBY

    _(result).must_answer <<~'OUT'
      class=primary id=go
      class=btn id=foo
    OUT
  end

  it "hash variant unify" do
    result = ze0(<<~'RUBY')
      # Hash variants (SymPolyHash, StrPolyHash, PolyPolyHash, ...) have different
      # struct layouts. Type inference must not let a local and the ivar backing it
      # settle on DIFFERENT variants, or codegen casts the pointer across layouts
      # and reads garbage / corrupts the heap.

      # Shape (a): `opts = @menu.options`. The ivar behind the reader is a
      # SymPolyHash, but a second (dead-branch) assignment with string keys widens
      # the LOCAL to a different variant. Reads through the local then walk the
      # wrong struct layout.
      class Menu
        attr_reader :options
        def initialize
          @options = {
            new_game: ["Start new game", 1],
            quit:     ["Quit to DOS", 9]
          }
        end
      end

      class Game
        def initialize
          @menu = Menu.new
        end

        def run
          opts = @menu.options
          if @menu.nil?
            opts = { "fallback" => ["none", 0] }
          end
          puts opts[:new_game][0]
          puts opts[:quit][1]
          opts[:load_game] = ["Load saved game", 3]
          puts opts[:load_game][0]
          puts opts.size
        end
      end

      Game.new.run

      # Shape (b): `@cache ||= {}` where other writes (poly keys) make @cache a
      # PolyPolyHash, but the empty literal keeps its default variant. The literal's
      # constructor then disagrees with the ivar's declared C type.
      class LineCache
        def store(key, val)
          @cache ||= {}
          @cache[key] = val
        end

        def load(key)
          @cache ||= {}
          @cache[key]
        end

        def count
          @cache ||= {}
          @cache.size
        end
      end

      lc = LineCache.new
      lc.store(:alpha, [10, 20])
      lc.store("beta", [30, 40])
      lc.store(7, [50, 60])
      puts lc.load(:alpha).inspect
      puts lc.load("beta").inspect
      puts lc.load(7).inspect
      puts lc.count
    RUBY

    _(result).must_answer <<~'OUT'
      Start new game
      9
      Load saved game
      3
      [10, 20]
      [30, 40]
      [50, 60]
      3
    OUT
  end

  it "int int hash missing key nil" do
    result = ze0(<<~'RUBY')
      h = {1 => 10, 2 => 20}
      p h[99]
      p h[99].nil?
      p h[99].inspect
      p(h[99] || 42)
      v = h[99]
      p v.nil?
      p(v || 7)
      p h[1]
      p(h[1] + 1)
    RUBY

    _(result).must_answer <<~'OUT'
      nil
      true
      "nil"
      42
      true
      7
      10
      11
    OUT
  end

  it "kwargs merge default hash" do
    result = ze0(<<~'RUBY')
      # `CONST.merge(opts)` where CONST is a Symbol-keyed hash and `opts`
      # is a method parameter with an empty-hash default (`def m(opts = {})`).
      # CRuby folds trailing keyword arguments into a Symbol-keyed positional
      # Hash when the callee declares no keyword params, so the kwargs reach
      # `opts` and `merge` dispatches sym-keyed. The empty default must also
      # merge cleanly (returning the receiver's defaults).
      #
      # Output is per-key (not hash#inspect) so it is independent of the
      # reference Ruby's hash formatting (3.2 `{:k=>v}` vs 3.4+ `{k: v}`).

      DEFAULTS = { timeout: 30, host: "localhost" }

      def configure(opts = {})
        DEFAULTS.merge(opts)
      end

      # Keyword-call form: kwargs collapse into the positional hash.
      c1 = configure(timeout: 5)
      puts c1[:timeout]                 # 5  (override applied)
      puts c1[:host]                    # localhost (default kept)

      # No-arg form: the empty `{}` default merges to just the defaults.
      c2 = configure
      puts c2[:timeout]                 # 30
      puts c2[:host]                    # localhost

      # The same idiom inside a constructor, the shape the spinelgems
      # harvest cluster (rack-health, stream-chat-ruby, ...) uses.
      class Client
        def initialize(opts = {})
          @config = DEFAULTS.merge(opts)
        end
        def config; @config; end
      end

      c3 = Client.new(host: "example.com", timeout: 5).config
      puts c3[:timeout]                 # 5
      puts c3[:host]                    # example.com

      c4 = Client.new.config
      puts c4[:timeout]                 # 30
      puts c4[:host]                    # localhost

      # A method that genuinely declares keyword params must NOT collapse:
      # named kwargs bind to their own slots, and `**h` double-splat forwards.
      def greet(name:, greeting: "hi")
        "#{greeting}, #{name}"
      end
      puts greet(name: "Ada")           # hi, Ada
      opts = { name: "Bob", greeting: "yo" }
      puts greet(**opts)                # yo, Bob
    RUBY

    _(result).must_answer <<~'OUT'
      5
      localhost
      30
      localhost
      5
      example.com
      30
      localhost
      hi, Ada
      yo, Bob
    OUT
  end

  it "param body hash inference" do
    result = ze0(<<~'RUBY')
      # #542. Method param defaulted to int when no caller passed a
      # concretely-typed argument. The body's `row["id"]` then emitted
      # the literal 0 with a "cannot resolve" warning and the method
      # silently produced wrong output -- `id=0` for the repro,
      # all-default-value Article rows in the roundhouse real-blog.
      # Sam Ruby ran 30 lines of type_seeds.rb to work around this.
      #
      # Fix (Option 2 + cast + NULL-guard, per the issue's design
      # discussion):
      #
      # 1. analyze: new `infer_hash_param_from_body` pass scans each
      #    method body for `param[StringNode/SymbolNode]` access. When
      #    found and the param's slot is still at the int/nil default,
      #    widen to `str_poly_hash` (string keys) or `sym_poly_hash`
      #    (symbol keys). Runs in the inference fixpoint alongside
      #    `infer_string_param_from_body`.
      #
      # 2. codegen: `compile_call_args_with_defaults` adds a hash-typed
      #    param cast arm. When the param's static type is a hash and
      #    the arg's inferred type is int/nil/poly, cast at the call
      #    site so the C signature accepts the call without an
      #    "incompatible integer to pointer conversion" error.
      #
      # 3. runtime: NULL-guards in the hash getters
      #    (`sp_StrPolyHash_get`, `sp_SymPolyHash_get`,
      #    `sp_StrIntHash_get`, `sp_StrStrHash_get`,
      #    `sp_IntStrHash_get`, `sp_SymIntHash_get`,
      #    `sp_SymStrHash_get`, `sp_PolyPolyHash_get`) return the
      #    slot's default sentinel (`sp_box_nil`, `0`, `sp_str_empty`)
      #    instead of dereferencing a NULL hash header.
      #
      # The combination addresses Sam's composition concern: typed
      # callers continue to build the right hash variant; untyped
      # callers cast their nil/int values to NULL of the param's
      # pointer type, the body's `row["k"]` safely returns nil, and
      # the consumer gets `nil.to_s -> ""` (CRuby raises NoMethodError
      # on nil[:k] -- we don't match the raise, but the silent
      # emit-0 is gone).

      # Single untyped caller: param widens from body usage alone, no
      # type_seeds.rb seeding required.
      def consume(row)
        puts "id=" + row["id"].to_s
      end

      class Box
        attr_accessor :contents
      end

      b = Box.new
      consume(b.contents)  # untyped (uninit ivar = nil); body inference widens param

      # Mixed callers: typed hash literal + untyped value -- previously
      # the typed caller's widening would lock the param at sp_StrPolyHash*
      # and the untyped caller would fail C compile. Now the call-site
      # cast lets the untyped caller through.
      def fetch(row)
        puts "title=" + row["title"].to_s
      end

      fetch({"title" => "Real Hash"})
      fetch(b.contents)
      fetch({"title" => "Another Real"})

      # Symbol-keyed lookup widens to sym_poly_hash via the same
      # inference path.
      def grab(opts)
        puts "name=" + opts[:name].to_s
      end

      grab({name: "Sym Hash"})
      grab(b.contents)
    RUBY

    _(result).must_answer "", stderr: "core/hash/formatting_test.rb:43:in 'Object#consume': undefined method '[]' for nil (NoMethodError)\n\n  puts \"id=\" + row[\"id\"].to_s\n                  ^^^^^^\n\tfrom core/hash/formatting_test.rb:51:in '<main>'\n", status: 1
  end

  it "raising hash reaches the caller" do
    result = ze0(<<~'RUBY')
      # A user `hash` that raises is an ordinary exception, not a crash.
      #
      # zeo projects a Hash key through an infallible `hash_key`, reached from
      # ~40 places, so a raise from the user's `hash` had no return channel and
      # was a `panic!` -- which a `extern "C"` boundary cannot unwind out of, so
      # it ENDED THE PROCESS. The exception is parked instead and the enclosing
      # builtin row reports it.
      #
      # The backtrace shape is the other half: `Hash#[]` and `Array#[]` are
      # `opt_aref`, a VM instruction with no control frame, so ruby names the
      # raising method and the caller and nothing between. `String#[]` is NOT
      # specialized and keeps its frame.
      class Boom
        def hash = raise("from hash")
        def eql?(_other) = true
      end

      h = { 1 => :one }
      begin
        h[Boom.new]
      rescue RuntimeError => e
        p [e.class.to_s, e.message, e.backtrace.first.include?("Hash#[]")]
      end
      begin
        h[Boom.new] = :two
      rescue RuntimeError => e
        p e.message
      end
      begin
        [Boom.new].uniq
      rescue RuntimeError => e
        p e.message
      end
      begin
        built = { Boom.new => 1 }
        p built
      rescue RuntimeError => e
        p e.message
      end
      p h.size
    RUBY

    _(result).must_answer <<~'OUT'
      ["RuntimeError", "from hash", false]
      "from hash"
      "from hash"
      1
    OUT
  end

  it "small hash keeps no bins" do
    result = ze0(<<~'RUBY')
      # A Hash of eight entries or fewer scans its entries; past eight it
      # indexes them. Every operation agrees across the border, with
      # deletes, a rehash, compare_by_identity, a copy and keys whose eql?
      # adds to the table on the way.
      h = {}
      (1..12).each { |i| h["k#{i}"] = i; p [h.size, h["k1"], h["k#{i}"], h.key?("k0")] if [1, 8, 9, 12].include?(i) }
      9.times { |i| h.delete("k#{i + 1}") }
      p h, h["k10"], h.key?("k3")
      h["a"] = 1
      h.rehash
      p h.keys, h.to_a.last
      c = h.dup
      c["z"] = 26
      p h.size, c.size, c["z"], h["z"]
      s = { 1 => :a, 2.0 => :b, :c => 3, "d" => 4, [5] => 5, nil => 6, true => 7 }
      p s[1], s[2.0], s[2], s[:c], s["d"], s[[5]], s[nil], s[true], s.size
      s.compare_by_identity
      k = "d"
      s[k] = 8
      p s[k], s["d"], s.size
      class Adder
        attr_reader :n
        def initialize(n, h) = (@n = n; @h = h)
        def hash = n.hash
        def eql?(o) = (@h[Object.new] = 1; o.is_a?(Adder) && o.n == n)
      end
      t = {}
      t[Adder.new(1, t)] = :one
      p t[Adder.new(1, t)], t.size > 1
      u = {}
      3.times { |i| u[i] = i }
      u.delete(1)
      u[1] = :back
      p u, u.first, u.min_by { |k, v| k.to_s }
      p({ a: 1 }.merge(b: 2).select { |k, v| v > 1 }, { x: 1 }.compare_by_identity.key?(:x))

    RUBY

    _(result).must_answer <<~'OUT'
      [1, 1, 1, false]
      [8, 1, 8, false]
      [9, 1, 9, false]
      [12, 1, 12, false]
      {"k10" => 10, "k11" => 11, "k12" => 12}
      10
      false
      ["k10", "k11", "k12", "a"]
      ["a", 1]
      4
      5
      26
      nil
      :a
      :b
      nil
      3
      4
      5
      6
      7
      7
      8
      nil
      8
      :one
      true
      {0 => 0, 2 => 2, 1 => :back}
      [0, 0]
      [0, 0]
      {b: 2}
      true
    OUT
  end

  it "sym int hash missing key nil" do
    result = ze0(<<~'RUBY')
      h = {a: 1, b: 2}
      p h[:miss]
      p h[:miss].nil?
      p h[:miss].inspect
      p(h[:miss] || 42)
      v = h[:miss]
      p v.nil?
      p(v || 7)
      p h[:a]
      p(h[:a] + 1)
      # Hash.new(N) keeps its explicit default; {} default is nil.
      c = Hash.new(0)
      p c[:z]
      p({}.default)
      p c.default
    RUBY

    _(result).must_answer <<~'OUT'
      nil
      true
      "nil"
      42
      true
      7
      1
      2
      0
      nil
      0
    OUT
  end

  it "user hash protocol keys hashes by value" do
    result = ze0(<<~'RUBY')
      class Key
        attr_reader :k

        def initialize(k)
          @k = k
        end

        def hash
          k.hash
        end

        def eql?(other)
          other.is_a?(Key) && k == other.k
        end
      end

      h = {}
      h[Key.new("a")] = 1
      puts h[Key.new("a")]
      puts h[Key.new("b")].inspect
    RUBY

    _(result).must_answer <<~'OUT'
      1
      nil
    OUT
  end
end
