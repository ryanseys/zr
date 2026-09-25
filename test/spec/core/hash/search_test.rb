# frozen_string_literal: true

require "spec_helper"

describe "Hash: searching and matching" do
  it "empty hash enumerable" do
    result = zr(<<~'RUBY')
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

  it "map.with_index and each.with_index ride the pair array, and a nil-tailed block keeps its side effects" do
    result = zr(<<~'RUBY')
      # hash.map.with_index / hash.each.with_index iterate the [key, value]
      # pairs. A block that ends in puts still runs puts for each pair.
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

  it "(h[k] = v) mutates the hash and answers the assigned value" do
    result = zr(<<~'RUBY')
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

  it "h[k] ||= a container picks the hash variant from the key, a parameter key included" do
    result = zr(<<~'RUBY')
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

  it "nil is an ordinary key that no lookup finds until something stores it" do
    result = zr(<<~'RUBY')
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

  it "a callee that widened its hash slot to poly widens its caller's slot to the same variant" do
    result = zr(<<~'RUBY')
      # A hash goes from `parse` to `assign`. `assign` stores both a String
      # and a Hash as values in it. The caller passes the same hash object,
      # so the caller must also accept values of mixed types.
      #
      # This is the shape of a form parser in a blog app: the parser calls
      # a helper that stores `into[k] = val` (a String) and `into[k] = {}`
      # (a Hash) in the same hash.

      module Form
        # The body stores a String AND a Hash as values of `into`.
        def self.assign(into, k, v)
          if k.include?("[")
            into[k] = {}
          else
            into[k] = v
          end
        end

        # This passes `into` on to `assign`, so it holds mixed values too.
        def self.parse(input, into)
          input.split("&").each { |pair| assign(into, pair, "v") }
        end

        # The driver starts with a literal that holds a String value and
        # a Hash value, then passes it through the chain.
        def self.run
          h = { "x" => "v", "nested" => {} }
          parse("a=1&b=2", h)
          h.length
        end
      end

      puts Form.run
    RUBY

    _(result).must_answer "4\n"
  end

  it "to_a and entries answer the pairs in insertion order, for every typed-hash variant" do
    result = zr(<<~'RUBY')
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
    result = zr(<<~'RUBY')
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
    result = zr(<<~'RUBY')
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
