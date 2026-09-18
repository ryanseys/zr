# frozen_string_literal: true

require "spec_helper"

describe "Hash: comparison and equality" do
  it "class value hash key" do
    result = ze0(<<~'RUBY')
      # A Class used as a Hash key compares by name, the way `==` on two of them does.
      # Hashing the box itself made every occurrence a distinct key: `h[Integer] = 1;
      # h[Integer] = 2` kept both, and `group_by(&:class)` made one bucket per element.
      h = {}
      h[Integer] = 1
      h[Integer] = 2
      p h.size
      p h
      p({ Integer => 1, String => 2 }.key?(Integer))
      p [1, 2, "a"].group_by { |x| x.class }
      p [1, 2, "a"].map(&:class).tally
      p [1, 2, "a"].map(&:class).uniq
      p({ Integer => "i" }[Integer])
      p({ Integer => "i" }.fetch(String, "none"))
      counts = Hash.new(0)
      [1, "a", 2, :s].each { |v| counts[v.class] += 1 }
      p counts
    RUBY

    _(result).must_answer <<~'OUT'
      1
      {Integer => 2}
      true
      {Integer => [1, 2], String => ["a"]}
      {Integer => 2, String => 1}
      [Integer, String]
      "i"
      "none"
      {Integer => 2, String => 1, Symbol => 1}
    OUT
  end

  it "class values print and compare by identity" do
    result = ze0(<<~'RUBY')
      class Widget
      end

      module Store
        class Item
        end
      end

      puts Widget
      p Widget
      puts Store::Item
      puts Widget == Widget
      puts Widget == Store::Item
      puts Widget != Store::Item
      arr = [Widget, Store::Item]
      puts arr.include?(Widget)
    RUBY

    _(result).must_answer <<~'OUT'
      Widget
      Widget
      Store::Item
      true
      false
      true
      true
    OUT
  end

  it "compare by identity predicate" do
    result = ze0(<<~'RUBY')
      # Hash#compare_by_identity? reports false for an ordinary (value-keyed) hash.
      # The mutating Hash#compare_by_identity is rejected at compile time, since
      # spinel compares hash keys by value and cannot switch a hash to identity
      # comparison; emitting it as a no-op would silently diverge from CRuby. This
      # test pins the predicate's correct value-keyed answer.
      def s(x); x; end
      p s({}).compare_by_identity?
      p s({ "a" => 1 }).compare_by_identity?
      h = {}
      p h.compare_by_identity?
    RUBY

    _(result).must_answer <<~'OUT'
      false
      false
      false
    OUT
  end

  it "float negative zero hash" do
    result = ze0(<<~'RUBY')
      # GAP -- imported from the spinel corpus at c55d9bdb.
      # -0.0 and 0.0 hash differently from ruby's answer.
      #
      p((-0.0).eql?(0.0))
      p((-0.0).hash == (0.0).hash)
      v001 = -0.0; w001 = 0.0; c001 = (v001.hash == w001.hash); p c001
      h001 = { 0.0 => "a" }; p h001[-0.0]
      p(-0.0 == 0.0)
    RUBY

    _(result).must_answer <<~'OUT'
      true
      true
      true
      "a"
      true
    OUT
  end

  it "compare_by_identity keys by equal?, so two equal strings are two keys" do
    result = ze0(<<~'RUBY')
      # Hash#compare_by_identity — keys compared by object identity (equal?),
      # not structure (eql?/hash).

      h = {}
      p h.compare_by_identity?          # false
      r = h.compare_by_identity
      p r.equal?(h)                     # true — returns self
      p h.compare_by_identity?          # true

      # Two equal-but-distinct String objects are DISTINCT keys.
      a = "x" + ""
      b = "x" + ""
      h[a] = 1
      h[b] = 2
      p h.size                          # 2
      p h[a]                            # 1
      p h[b]                            # 2
      p h["x" + ""]                     # nil — a fresh, different object
      p h.key?(a)                       # true

      # delete uses identity too.
      h.delete(a)
      p h.size                          # 1
      p h[a]                            # nil
      p h[b]                            # 2

      # Immediates (Integer/Symbol/nil/true/Float) key by value even in identity mode.
      hi = {}.compare_by_identity
      hi[1] = "one"
      hi[1] = "ONE"
      p hi.size                         # 1
      p hi[1]                           # "ONE"
      hi[:s] = 10
      hi[:s] = 20
      p hi[:s]                          # 20
      hi[1.5] = "f"
      p hi[1.5]                         # "f"

      # Enabling on a POPULATED hash re-projects existing entries by identity:
      # the entries survive, but lookups now use identity (a fresh equal object misses).
      hp = {}
      hp["p" + ""] = 1
      hp["q" + ""] = 2
      p hp.size                         # 2
      hp.compare_by_identity
      p hp.compare_by_identity?         # true
      p hp.size                         # 2 — entries preserved
      p hp["p" + ""]                    # nil — fresh, different object

      # A frozen hash raises FrozenError.
      begin
        {}.freeze.compare_by_identity
      rescue => e
        p e.class                       # FrozenError
      end
    RUBY

    _(result).must_answer <<~'OUT'
      false
      true
      true
      2
      1
      2
      nil
      true
      1
      nil
      2
      1
      "ONE"
      20
      "f"
      2
      true
      2
      nil
      FrozenError
    OUT
  end

  it "compare_by_identity answers the receiver, and the mode holds for every later write" do
    result = ze0(<<~'RUBY')
      h = {}
      puts h.compare_by_identity?          # false
      puts h.compare_by_identity.equal?(h) # true (returns self)
      puts h.compare_by_identity?          # true
      a = "x" + ""
      b = "x" + ""
      h[a] = 1
      h[b] = 2
      puts h.size                          # 2 (distinct identities)
      puts h[a]                            # 1
      p h["x" + ""]                        # nil (fresh object)
      # immediates still key by value
      hi = {}.compare_by_identity
      hi[1] = "one"; hi[1] = "ONE"
      hi[:s] = 9; hi[:s] = 10
      puts hi.size                         # 2 (1 and :s)
      puts hi[1]                           # ONE
      # frozen raises
      begin
        {}.freeze.compare_by_identity
      rescue => e
        puts e.class                       # FrozenError
      end
    RUBY

    _(result).must_answer <<~'OUT'
      false
      true
      true
      2
      1
      nil
      2
      ONE
      FrozenError
    OUT
  end

  it "a hash inside a container compares by value, like every other container" do
    result = ze0(<<~'RUBY')
      # Boxed hashes compare by value like every other container: the poly-eq
      # object arm had no hash cases, so [h] == [same-content-h] was pointer
      # identity and always false.
      h1 = { "foo" => :bar }
      p [h1] == [{ "foo" => :bar }]
      p [{ a: 1 }] == [{ a: 1 }]
      p [{ "x" => 1 }] == [{ "x" => 2 }]
      p [{ "n" => "m" }] == [{ "n" => "m" }]
      mixed = [{ "foo" => :bar, baz: 42 }]
      p mixed == [{ "foo" => :bar, baz: 42 }]
    RUBY

    _(result).must_answer <<~'OUT'
      true
      true
      false
      true
      true
    OUT
  end

  it "to_h with no block answers the receiver itself" do
    result = ze0(<<~'RUBY')
      # Hash#to_h with no block is the identity (returns self). Verified via class,
      # length, and key access to avoid the 3.2-vs-3.4 hash-inspect spacing diff.
      h = {a: 1, b: 2}
      g = h.to_h
      puts g.class
      puts g.length
      puts g[:a]
      puts g[:b]

      s = {"x" => 10, "y" => 20}
      puts s.to_h[:x] if false   # string-keyed
      t = s.to_h
      puts t["x"]
      puts t["y"]
      puts t.length

      n = {1 => 100}.to_h
      puts n[1]
      puts "done"
    RUBY

    _(result).must_answer <<~'OUT'
      Hash
      2
      1
      2
      10
      20
      2
      100
      done
    OUT
  end

  it "update folds several hashes in order and answers the receiver" do
    result = ze0(<<~'RUBY')
      # Hash#update / #merge! with several hash arguments folds each in order and
      # returns the receiver (a value the caller can use, not nil).
      p({ a: 1 }.update({ b: 2 }, { c: 3 }))
      h = { x: 1 }
      r = h.merge!({ y: 2 }, { z: 3 })
      p r
      p h.equal?(r)
    RUBY

    _(result).must_answer <<~'OUT'
      {a: 1, b: 2, c: 3}
      {x: 1, y: 2, z: 3}
      true
    OUT
  end

  it "a user object with #hash and #eql? is a key a freshly built equal one finds" do
    result = ze0(<<~'RUBY')
      # A user object with #hash + #eql? works as a Hash key: two value-equal keys
      # collide to the same slot and compare equal, so a freshly-built key finds the
      # stored value. Previously object keys used pointer identity and always missed.

      class K
        attr_reader :v
        def initialize(v) = (@v = v)
        def hash = v.hash
        def eql?(other) = other.is_a?(K) && other.v == v
      end

      h = {}
      h[K.new(1)] = "a"
      h[K.new(2)] = "b"
      p h[K.new(1)]        # "a" — value-equal fresh key
      p h[K.new(2)]        # "b"
      p h[K.new(3)]        # nil — absent
      h[K.new(1)] = "z"    # overwrite the same logical key
      p h[K.new(1)]        # "z"
      p h.size             # 2

      # a string-backed key
      class Name
        attr_reader :s
        def initialize(s) = (@s = s)
        def hash = s.hash
        def eql?(o) = o.is_a?(Name) && o.s == s
      end
      n = {}
      n[Name.new("bob")] = 10
      n[Name.new("amy")] = 20
      p n[Name.new("bob")]
      p n[Name.new("zzz")]

      # a second key class coexists (exercises the cls_id switch arms)
      class Pt
        attr_reader :x, :y
        def initialize(x, y) = (@x, @y = x, y)
        def hash = [x, y].hash
        def eql?(o) = o.is_a?(Pt) && o.x == x && o.y == y
      end
      g = {}
      g[Pt.new(1, 2)] = "p"
      p g[Pt.new(1, 2)]
      p g[Pt.new(2, 1)]

      # primitive #hash is an Integer and stable within a run
      p 5.hash.is_a?(Integer)
      p("x".hash == "x".hash)
      p([1, 2].hash == [1, 2].hash)
    RUBY

    _(result).must_answer <<~'OUT'
      "a"
      "b"
      nil
      "z"
      2
      10
      nil
      "p"
      nil
      true
      true
      true
    OUT
  end

  it "a user #eql? is called with a poly operand, and an alias of == resolves to it" do
    result = ze0(<<~'RUBY')
      # A Hash keyed by a custom object honors user-defined #hash / #eql?: an
      # equal-but-distinct key finds the entry (sp_gen_obj_hash / sp_gen_obj_eql
      # hooks). `self == o` inside #eql? dispatches to the user #== even though
      # the operand is poly; `alias eql? ==` resolves to the target's C symbol.
      class Point
        attr_reader :x, :y
        def initialize(x, y) = (@x, @y = x, y)
        def ==(o)   = o.is_a?(Point) && x == o.x && y == o.y
        def eql?(o) = self == o
        def hash    = [x, y].hash
      end

      grid = {}
      grid[Point.new(1, 2)] = "alive"
      p grid[Point.new(1, 2)]
      p grid.key?(Point.new(1, 2))
      p grid[Point.new(9, 9)]

      a = Point.new(1, 2)
      b = Point.new(1, 2)
      c = Point.new(3, 4)
      p a == b
      p a != c
      p a != b
      boxed = [b, "x"]
      p a == boxed[0]
      p a != boxed[0]

      class Pt2
        attr_reader :x
        def initialize(x) = (@x = x)
        def ==(o) = o.is_a?(Pt2) && x == o.x
        alias eql? ==
        def hash = x.hash
      end
      g = {}
      g[Pt2.new(7)] = "yes"
      p g[Pt2.new(7)]
      p g.key?(Pt2.new(7))
    RUBY

    _(result).must_answer <<~'OUT'
      "alive"
      true
      nil
      true
      true
      false
      true
      false
      "yes"
      true
    OUT
  end

  it "value? answers whether any value equals the argument" do
    result = ze0(<<~'RUBY')
      # Issue #738 (partial -- value? / has_value?). Hash#value?(v) returns
      # true if any value in the hash equals v, else false. spinel used to
      # fall through to the unresolved-call warning.

      # sym_int_hash
      h = { a: 1, b: 2 }
      puts h.value?(2)
      puts h.value?(99)
      puts h.has_value?(1)

      # str_str_hash
      h2 = { "x" => "alpha", "y" => "beta" }
      puts h2.value?("alpha")
      puts h2.value?("zzz")

      # str_int_hash
      h3 = { "one" => 1, "two" => 2 }
      puts h3.value?(1)
      puts h3.value?(3)
    RUBY

    _(result).must_answer <<~'OUT'
      true
      false
      true
      true
      false
      true
      false
    OUT
  end

  it "rational cmp float hash" do
    result = ze0(<<~'RUBY')
      # Rational value operations against a Float and as a Hash key. Comparing a
      # Rational to a Float previously coerced the Float to a Rational (truncating
      # 1.5 -> 1/1), and a Rational's hash was pointer-based (unstable), so equal
      # Rationals neither compared nor hashed alike.
      # Each method keeps its second argument monomorphic (Float here) so the Float
      # comparison path is exercised.
      def cmpf(a, b); a <=> b; end
      p cmpf(Rational(3, 2), 1.5)    # 0
      p cmpf(Rational(3, 2), 2.0)    # -1
      p cmpf(Rational(3, 2), 1.0)    # 1

      def lt(a, b); a < b; end
      def ge(a, b); a >= b; end
      p lt(Rational(3, 2), 1.5)      # false
      p lt(Rational(3, 2), 2.0)      # true
      p ge(Rational(3, 2), 1.5)      # true

      def eqf(a, b); a == b; end
      p eqf(Rational(3, 2), 1.5)     # true
      p eqf(Rational(1, 3), 0.3)     # false

      # Comparison against another Rational / an Integer is unchanged.
      def cmpr(a, b); a <=> b; end
      p cmpr(Rational(1, 2), Rational(3, 4))  # -1
      def cmpi(a, b); a <=> b; end
      p cmpi(Rational(4, 2), 2)               # 0

      # #hash is stable and equal Rationals share a Hash slot (reduced to lowest terms).
      def stable(a); a.hash == a.hash; end
      p stable(Rational(3, 4))       # true
      p (Rational(3, 4).hash == Rational(6, 8).hash)   # true

      h = { Rational(3, 4) => "three-quarters" }
      p h[Rational(3, 4)]            # "three-quarters"
      p h[Rational(6, 8)]           # "three-quarters"  (reduces to 3/4)
      p h[Rational(1, 2)]           # nil
    RUBY

    _(result).must_answer <<~'OUT'
      0
      -1
      1
      false
      true
      true
      true
      false
      -1
      0
      true
      true
      "three-quarters"
      "three-quarters"
      nil
    OUT
  end
end
