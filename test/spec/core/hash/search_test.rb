# frozen_string_literal: true

require "spec_helper"

describe "Hash: searching and matching" do
  it "empty hash enumerable" do
    result = ze0(<<~'RUBY')
      a005 = {}
      o005 = []
      a005.each_entry { |e005| o005 << e005 }
      p o005
      a = {}
      p a.each_cons(2) { |s| }
      b = {}
      p b.each_slice(2) { |s| }
      c = {}
      p c.cycle(1) { |x| }
      d = {}
      p d.grep(Array)
      e = {}
      p e.take_while { true }
      f = {}
      p f.sort
      g = {}
      p g.inject(0) { |acc, _| acc }
      h = { a: 1 }
      o = []
      h.each_entry { |x| o << x }
      p o
      i = {}
      i[:k] = 1
      p i
    RUBY

    _(result).must_answer <<~'OUT'
      []
      {}
      {}
      nil
      []
      []
      []
      0
      [[:a, 1]]
      {k: 1}
    OUT
  end

  it "hash enum with index chain" do
    result = ze0(<<~'RUBY')
      # hash.map.with_index / hash.each.with_index interpose to_a and ride the
      # pair-array chain; a nil-typed block tail (puts) keeps its side effects
      # through the boxed collect (it used to be folded to a bare nil).
      h = { a: 1, b: 2 }
      h.map.with_index { |(k, v), i| puts "#{i}:#{k}" }
      h.each.with_index { |(k, v), i| puts "#{i}=#{v}" }
      [10, 20].map.with_index { |v, i| puts "#{i}->#{v}" }
    RUBY

    _(result).must_answer <<~'OUT'
      0:a
      1:b
      0=1
      1=2
      0->10
      1->20
    OUT
  end

  it "hash index assign expression" do
    result = ze0(<<~'RUBY')
      # Expression-form hash `[]=`: Ruby's `(h[k] = v)` mutates the hash and
      # evaluates to the assigned value. Covers str / sym keys and int / string
      # values, including a poly-valued hash where the result keeps its scalar type.

      h = {}
      x = (h["a"] = 1)
      puts x
      puts h["a"]

      hp = {"a" => 1, "b" => "x"}
      y = (hp["c"] = 2)
      puts y
      puts hp["c"]
      z = (hp["d"] = "added")
      puts z
      puts hp["d"]

      hs = {a: 1}
      w = (hs[:b] = 2)
      puts w
      puts hs[:b]
    RUBY

    _(result).must_answer <<~'OUT'
      1
      1
      2
      2
      added
      added
      2
      2
    OUT
  end

  it "hash index or write key variant" do
    result = ze0(<<~'RUBY')
      # h[k] ||= <container> picks the hash variant from the key, param keys included
      def build(k)
        h = {}
        h[k] ||= []
        h[k] << 1
        h
      end
      p build(0)
      p build("a")
      p build(:s)

      def lit; h = {}; h[0] ||= []; h[0] << 1; h; end
      p lit
      def bh(k); h = {}; h[k] ||= {}; h[k]["x"] = 1; h; end
      p bh(0)
      def sc(k); h = {}; h[k] ||= 0; h[k] += 1; h; end
      p sc(0)

      class K
        def initialize; @h = {}; end
        def add(k); @h[k] ||= []; @h[k] << 1; self; end
        def to_h; @h; end
      end
      p K.new.add(0).to_h
    RUBY

    _(result).must_answer <<~'OUT'
      {0 => [1]}
      {"a" => [1]}
      {s: [1]}
      {0 => [1]}
      {0 => {"x" => 1}}
      {0 => 1}
      {0 => [1]}
    OUT
  end

  it "hash nil key lookup" do
    result = ze0(<<~'RUBY')
      NAMED = { "navy" => "#000080", "red" => "#ff0000" }

      def valid?(color)
        NAMED.key?(color)
      end

      p valid?("navy")
      p valid?(nil)
      p NAMED[nil]
      p NAMED.fetch(nil, "none")
      p NAMED.include?(nil)
      p NAMED.member?(nil)
      p NAMED.size

      counts = Hash.new(0)
      counts["a"] += 1
      p counts[nil]
      p counts.key?(nil)

      mixed = { "k" => 1 }
      p mixed.key?(nil)
      p mixed.size

      vals = { "k" => [1, 2] }
      p vals[nil]
      p vals.key?(nil)
    RUBY

    _(result).must_answer <<~'OUT'
      true
      false
      nil
      "none"
      false
      false
      2
      0
      false
      false
      1
      nil
      false
    OUT
  end

  it "hash param widen from callee slot" do
    _(ze0(<<~'RUBY')).must_answer "4\n"
      # Hash-typed parameter back-propagation from callee slot:
      # `def outer(into); inner(into); end` where `inner` already
      # widened its `into` slot to a poly variant (via body
      # heterogeneous writes) should widen `outer`'s `into` slot to
      # the same poly variant. Symmetric extension of #453's ptr-back-
      # prop applied to hash types.
      #
      # Surfaces in real-blog's
      # `CgiIo.parse_form_into(into) -> CgiIo.assign_form_pair(into, ...)`
      # chain where assign_form_pair widens to str_poly_hash via its
      # body's mixed `into[k] = val` (string) + `into[k] = {}` (hash)
      # writes; pre-fix the outer parse_form_into kept `into` typed
      # str_int_hash and the C call passed it into a str_poly_hash *
      # slot.

      module Form
        # Heterogeneous body — into[k] = string AND into[k] = {} —
        # widens `into` to str_poly_hash via narrow_param_hash.
        def self.assign(into, k, v)
          if k.include?("[")
            into[k] = {}
          else
            into[k] = v
          end
        end

        # Bare-call forward of `into` — outer's `into` should widen
        # to the same str_poly_hash via callee-slot back-prop.
        def self.parse(input, into)
          input.split("&").each { |pair| assign(into, pair, "v") }
        end

        # Driver that creates a properly-typed sym_poly_hash and
        # widens through the chain. Using a heterogeneous initial
        # literal pins the LV at str_poly_hash from the start.
        def self.run
          h = { "x" => "v", "nested" => {} }
          parse("a=1&b=2", h)
          h.length
        end
      end

      puts Form.run
    RUBY
  end

  it "hash to a entries" do
    result = ze0(<<~'RUBY')
      # Hash#to_a / #entries materialize entries as an array of [key, value] pairs,
      # preserving insertion order, across every typed-hash variant. Each receiver
      # goes through a monomorphic method parameter so the runtime path is exercised
      # (not constant-folded) without widening any one helper's parameter to poly.

      def sym_int(h)  = h.to_a
      def str_int(h)  = h.to_a
      def str_str(h)  = h.to_a
      def int_str(h)  = h.to_a
      def int_int(h)  = h.to_a
      def sym_poly(h) = h.to_a
      def poly_poly(h) = h.to_a
      def sym_int_ents(h) = h.entries

      p sym_int({ a: 1, b: 2, c: 3 })
      p str_int({ "a" => 1, "b" => 2 })
      p str_str({ "a" => "x", "b" => "y" })
      p int_str({ 1 => "one", 2 => "two" })
      p int_int({ 10 => 100, 20 => 200 })
      p sym_poly({ a: 1, b: "two" })
      p poly_poly({ 1 => 2, "a" => "b" })
      p sym_int_ents({ a: 1 })

      # Pairs are real arrays: index them and read back keys and values.
      ps = sym_int({ x: 10, y: 20, z: 30 })
      p ps.length
      p ps.map { |pair| pair[0] }
      p ps.map { |pair| pair[1] }
      p ps.first[0]
      p ps.first[1]
    RUBY

    _(result).must_answer <<~'OUT'
      [[:a, 1], [:b, 2], [:c, 3]]
      [["a", 1], ["b", 2]]
      [["a", "x"], ["b", "y"]]
      [[1, "one"], [2, "two"]]
      [[10, 100], [20, 200]]
      [[:a, 1], [:b, "two"]]
      [[1, 2], ["a", "b"]]
      [[:a, 1]]
      3
      [:x, :y, :z]
      [10, 20, 30]
      :x
      10
    OUT
  end

  it "index or write empty hash" do
    result = ze0(<<~'RUBY')
      # h[k] ||= v / &&= / op= on a hash parameter passed in empty ({} infers as an
      # unresolved element type): the index-or-write usage now seeds the parameter's
      # hash variant from the key and value types, so the method's return type
      # resolves instead of degrading to poly.
      def fill(h, k)
        h[k] ||= "default"
        h[k]
      end
      puts fill({}, "name")
      puts fill({ "name" => "set" }, "name")   # existing key: ||= keeps it

      def tally(h, k)
        h[k] ||= 0
        h[k] += 1
        h[k]
      end
      puts tally({}, "x")

      def memo(h, k)
        h[k] &&= "present"
        h[k].inspect
      end
      puts memo({}, "y")                       # &&= on a missing key stays nil

      def symfill(h, k)
        h[k] ||= "sym"
        h[k]
      end
      puts symfill({}, :a)                     # symbol-keyed hash
    RUBY

    _(result).must_answer <<~'OUT'
      default
      set
      1
      nil
      sym
    OUT
  end

  it "user hash that collides" do
    result = ze0(<<~'RUBY')
      # A user `hash` is a BUCKET, not an identity. Ruby does not require it to
      # be unique -- two distinct keys may collide -- so a table that keys on it
      # alone loses entries and reads back the wrong value.
      #
      # This one did: two colliding keys stored as ONE, `h[a]` answered `"b"`,
      # `uniq` collapsed them, and a `Set` held one member. Silent, with a clean
      # exit, on the conventional way to write a value object.

      class K
        attr_reader :n

        def initialize(n) = @n = n
        def hash = 42
        def eql?(o) = o.is_a?(K) && o.n == @n
        def ==(o) = eql?(o)
      end

      a = K.new(1)
      b = K.new(2)
      a2 = K.new(1)

      h = {}
      h[a] = "a"
      h[b] = "b"
      p h.size
      p h[a]
      p h[b]
      # A DIFFERENT object that is `eql?` to a stored key still finds it -- the
      # other half of the rule, and the reason identity alone is not the answer.
      p h[a2]
      p h.key?(b)
      h[a2] = "a again"
      p h.size
      p h[a]

      h.delete(a)
      p h.size
      p h[b]

      p [a, b, a2].uniq.size

      require "set"
      s = Set.new([a, b, a2])
      p s.size
      p s.include?(b)

      # A class defining `hash` but NO `eql?` keeps ruby's default identity, so
      # two colliding instances stay two keys.
      class OnlyHash
        def hash = 7
      end
      g = {}
      g[OnlyHash.new] = 1
      g[OnlyHash.new] = 2
      p g.size

      # `compare_by_identity` ignores both methods.
      i = {}.compare_by_identity
      i[a] = "a"
      i[a2] = "a2"
      p i.size
    RUBY

    _(result).must_answer <<~'OUT'
      2
      "a"
      "b"
      "a"
      true
      2
      "a again"
      1
      "b"
      2
      2
      true
      2
      2
    OUT
  end
end
