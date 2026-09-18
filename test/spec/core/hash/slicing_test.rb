# frozen_string_literal: true

require "spec_helper"

describe "Hash: slicing" do
  it "chained aset on poly hash recv" do
    result = ze0(<<~'RUBY')
      # #456: `outer[k1][k2] = v` where outer's value type is sp_RbVal
      # (StrPolyHash). The inner `[]=` recv is poly; with no
      # `is_a?(Hash)` narrowing, the dispatch needs to enumerate Hash-
      # storage arms, not only Array-storage ones. Prior to this fix
      # the poly-recv `[]=` codegen emitted PolyArray / PtrArray /
      # IntArray arms only and the call failed C compile with
      # "passing argument 2 of sp_PolyArray_set makes integer from
      # pointer without a cast" when the index was a string literal.
      #
      # Surfaced in the canonical form-decoder shape
      # `into[outer][inner] = val` inside `CgiIo.assign_form_pair`.

      def assign(into)
        into["x"]["y"] = "z"
        into["x"]["y"]
      end

      box = { "x" => { "y" => "old" } }
      puts assign(box)
    RUBY

    _(result).must_answer "z\n"
  end

  it "enumerable hash range receiver" do
    result = ze0(<<~'RUBY')
      # Enumerable methods whose only arm is the Array one were refused outright on a
      # Hash or a Range receiver. Every one of them answers what the same call on
      # `receiver.to_a` answers -- Enumerable over a Hash walks its pairs, over a
      # Range its elements -- so that is where they go.
      h = { a: 1, b: 2, c: 3 }
      r = (1..5)

      out = []
      h.each_slice(2) { |s| out << s }
      p out
      p h.each_cons(2).to_a
      p h.take_while { |k, v| v < 3 }
      p h.drop_while { |k, v| v < 3 }
      p h.grep(Array)
      p h.grep_v(Array)
      p h.sort
      p h.minmax_by { |k, v| v }
      p h.each_entry { |e| e }

      p r.sort
      p r.sort { |a, b| b <=> a }
      p r.grep(2..4)
      p r.grep_v(2..4)
      p r.each_slice(2).to_a
      p r.each_cons(2).to_a
      p r.minmax_by { |x| -x }
      p r.reverse_each.to_a
      p r.uniq
      p r.find_index(3)
      p r.zip([9, 8, 7, 6, 5])
      p r.flat_map { |x| [x, x] }

      # the Hash-returning members keep their own answers
      p h.select { |k, v| v > 1 }
      p h.reject { |k, v| v > 1 }
      p h.map { |k, v| v }
      p h.to_a
      p r.to_a
    RUBY

    _(result).must_answer <<~'OUT'
      [[[:a, 1], [:b, 2]], [[:c, 3]]]
      [[[:a, 1], [:b, 2]], [[:b, 2], [:c, 3]]]
      [[:a, 1], [:b, 2]]
      [[:c, 3]]
      [[:a, 1], [:b, 2], [:c, 3]]
      []
      [[:a, 1], [:b, 2], [:c, 3]]
      [[:a, 1], [:c, 3]]
      {a: 1, b: 2, c: 3}
      [1, 2, 3, 4, 5]
      [5, 4, 3, 2, 1]
      [2, 3, 4]
      [1, 5]
      [[1, 2], [3, 4], [5]]
      [[1, 2], [2, 3], [3, 4], [4, 5]]
      [5, 1]
      [5, 4, 3, 2, 1]
      [1, 2, 3, 4, 5]
      2
      [[1, 9], [2, 8], [3, 7], [4, 6], [5, 5]]
      [1, 1, 2, 2, 3, 3, 4, 4, 5, 5]
      {b: 2, c: 3}
      {a: 1}
      [1, 2, 3]
      [[:a, 1], [:b, 2], [:c, 3]]
      [1, 2, 3, 4, 5]
    OUT
  end

  it "hash const into defaulted param" do
    result = ze0(<<~'RUBY')
      # A Hash constant passed to a parameter that defaults to `{}`. Two faults, both
      # silent: the loop ran zero times, and then its writes went nowhere (#4041).
      #
      # The poly `each` asked sp_poly_arr_len_ex for the receiver's length, and that
      # knew only the three poly-VALUED hash variants -- a String-keyed one answered
      # 0 and the block simply never ran.
      #
      # With it running, the `@units = {}` literal was symbol-keyed while the keys
      # written into it were Strings, so every entry was dropped. The key sites can
      # disagree across fixpoint rounds (a block parameter of a poly iteration reads
      # as poly on one round and as the default literal's own kind on another); the
      # poly-keyed hash is the only representation that holds both, so it now wins
      # over a narrower mark rather than losing to whichever landed first.
      class Quantity
        attr_reader :units
        def initialize(units = {})
          @units = {}
          units.each { |u, e| @units[u] = e }
        end
      end
      KILO = { 'kg' => 1 }
      p Quantity.new(KILO).units
      p Quantity.new({ 'g' => 2, 'mg' => 3 }).units
      p Quantity.new.units

      SYMS = { a: 1 }
      p Quantity.new(SYMS).units

      INTS = { 1 => 'one' }
      p Quantity.new(INTS).units

      # the plain function shape, and the iteration count itself
      def count(src = {})
        n = 0
        src.each { |k, v| n += 1 }
        n
      end
      p count(KILO)
      p count(SYMS)
      p count(INTS)
      p count({ 'x' => 1, 'y' => 2 })
      p count

      # every hash kind through a poly each
      def keys_of(src = {})
        out = []
        src.each { |k, v| out << k }
        out
      end
      p keys_of({ 'a' => 'b' })
      p keys_of({ 1 => 2 })
      p keys_of({ 1 => 'x' })
      p keys_of({ a: [1] })
    RUBY

    _(result).must_answer <<~'OUT'
      {"kg" => 1}
      {"g" => 2, "mg" => 3}
      {}
      {a: 1}
      {1 => "one"}
      1
      1
      1
      2
      0
      ["a"]
      [1]
      [1]
      [:a]
    OUT
  end

  it "hash double splat" do
    result = ze0(<<~'RUBY')
      # A hash literal with a double-splat (`{ **h, k: v }`) must merge the spread
      # source instead of erasing the literal's type to UNKNOWN and rejecting.
      #
      # Type inference bailed the moment it saw a non-AssocNode element, so `**h`
      # gave the literal no inferrable key/value type. Merge the spread source's
      # key/value types (a concrete hash) -- or, for a source reached through a poly
      # binding, iterate its boxed pairs at runtime into a poly hash.

      # 1. The gap: a poly spread source (h flows through a poly array via map) plus
      #    an explicit key computed from it.
      def bump(h)
        { **h, x: h[:x] + 1 }
      end
      rows = (0...3).map { |i| { x: i.to_f, y: 0.0 } }
      p rows.map { |h| bump(h) }         #=> [{x: 1.0, y: 0.0}, {x: 2.0, y: 0.0}, {x: 3.0, y: 0.0}]

      # 2. A concretely-typed spread source with an overriding key.
      def upd(h) = { **h, a: 99 }
      p upd({ a: 1, b: 2 })              #=> {a: 99, b: 2}

      # 3. Splat last: the spread overrides an earlier explicit key.
      def upd2(h) = { a: 1, **h }
      p upd2({ a: 5, c: 3 })             #=> {a: 5, c: 3}

      # 4. Two spreads.
      def merge2(a, b) = { **a, **b }
      p merge2({ x: 1 }, { y: 2 })       #=> {x: 1, y: 2}

      # 5. String-keyed spread + an added string key.
      def strh(h) = { **h, "z" => 9 }
      p strh({ "a" => 1 })               #=> {"a" => 1, "z" => 9}

      # 6. Direct local spread source (concrete type).
      h = { x: 1.0, y: 2.0 }
      p({ **h, z: 3.0 })                 #=> {x: 1.0, y: 2.0, z: 3.0}

      puts "done"
    RUBY

    _(result).must_answer <<~'OUT'
      [{x: 1.0, y: 0.0}, {x: 2.0, y: 0.0}, {x: 3.0, y: 0.0}]
      {a: 99, b: 2}
      {a: 5, c: 3}
      {x: 1, y: 2}
      {"a" => 1, "z" => 9}
      {x: 1.0, y: 2.0, z: 3.0}
      done
    OUT
  end

  it "hash enumerable batch" do
    result = ze0(<<~'RUBY')
      # Hash Enumerable conformance (KieranP #2339,#2341,#2350,#2352)
      h = { a: 1, b: 2 }
      p h.first                                  # #2350 first pair
      p h.first(1)
      p h.take(1)
      p h.drop(1)
      p({}.first)
      p h.sort { |x, y| y[1] <=> x[1] }          # #2341 sort with comparator block
      p h.sort { |x, y| x[1] <=> y[1] }
      p({ "a" => 1, "b" => 2 }.key(2))           # #2352 key on a String-keyed hash
      p({ 1 => "x", 2 => "y" }.key("y"))
      p({ "a" => 1 }.key(9))
      p h.any? { |pair| pair[1] > 1 }            # #2339 solo param is the pair
      p h.count { |pair| pair[1] > 1 }
      p h.all? { |pair| pair[1] > 0 }
      p h.any? { |k, v| v > 1 }                   # two params still bind k, v
    RUBY

    _(result).must_answer <<~'OUT'
      [:a, 1]
      [[:a, 1]]
      [[:a, 1]]
      [[:b, 2]]
      nil
      [[:b, 2], [:a, 1]]
      [[:a, 1], [:b, 2]]
      "b"
      2
      nil
      true
      1
      true
      true
    OUT
  end

  it "hash except" do
    result = ze0(<<~'RUBY')
      # Hash#except returns a copy of the hash without the given keys.

      # 1. Symbol-keyed, drop one / several / a missing key.
      p({ a: 1, b: 2, c: 3 }.except(:b))    #=> {a: 1, c: 3}
      p({ a: 1, b: 2, c: 3 }.except(:a, :c))#=> {b: 2}
      p({ a: 1, b: 2 }.except(:z))          #=> {a: 1, b: 2}
      p({ a: 1 }.except)                    #=> {a: 1}

      # 2. String-keyed.
      p({ "x" => 1, "y" => 2 }.except("x")) #=> {"y" => 2}
      h = { "a" => 1, "b" => 2, "c" => 3 }
      p h.except("b")                       #=> {"a" => 1, "c" => 3}

      # 3. Through a method param (defeats constant-folding).
      def drop(h) = h.except(:b)
      p drop({ a: 1, b: 2, c: 3 })          #=> {a: 1, c: 3}

      # 4. The receiver is not mutated.
      orig = { a: 1, b: 2 }
      orig.except(:a)
      p orig                                #=> {a: 1, b: 2}

      # 5. Key supplied as a poly method param (coerced, not a literal).
      def drop_sym(k) = { a: 1, b: 2, c: 3 }.except(k)
      p drop_sym(:b)                        #=> {a: 1, c: 3}
      def drop_str(k) = { "a" => 1, "b" => 2 }.except(k)
      p drop_str("a")                       #=> {"b" => 2}

      puts "done"
    RUBY

    _(result).must_answer <<~'OUT'
      {a: 1, c: 3}
      {b: 2}
      {a: 1, b: 2}
      {a: 1}
      {"y" => 2}
      {"a" => 1, "c" => 3}
      {a: 1, c: 3}
      {a: 1, b: 2}
      {a: 1, c: 3}
      {"b" => 2}
      done
    OUT
  end

  it "hash range enum extensions" do
    result = ze0(<<~'RUBY')
      # Hash min/max/minmax_by, flat_map splicing, and each_with_object over
      # hashes and ranges (the pair/array redispatch family).
      h = { a: 1, b: 3, c: 2 }
      p h.min
      p h.max
      p h.minmax_by { |k, v| v }
      p h.min_by { |k, v| v }
      data = { a: [1, 2], b: [3, 4] }
      p data.flat_map { |k, v| v }
      p (1..5).each_with_object([]) { |i, acc| acc << i * i }
      r = { a: 1, b: 2 }.each_with_object([]) { |(k, v), arr| arr << "#{k}=#{v}" }
      p r
    RUBY

    _(result).must_answer <<~'OUT'
      [:a, 1]
      [:c, 2]
      [[:a, 1], [:b, 3]]
      [:a, 1]
      [1, 2, 3, 4]
      [1, 4, 9, 16, 25]
      ["a=1", "b=2"]
    OUT
  end

  it "hash range key" do
    result = ze0(<<~'RUBY')
      # Two Ranges with the same bounds are one Hash key. A fresh box hashed by
      # pointer, so a lookup never found the entry it had just stored.
      h = { (1..3) => :a, (4..6) => :b }
      p h[(1..3)]
      p h[(4..6)]
      p h[(7..9)]
      p h.key?(1..3)
      p h.key?(1...3)
      k = (1..3)
      p h[k]
      p h.size

      g = {}
      g[(1...4)] = :x
      p g[(1...4)]
      p g[(1..4)]
      p g.size

      # the Range value comparisons themselves are unchanged
      p((1..3) == (1..3))
      p((1..3).eql?(1..3))
      p((1..3).hash == (1..3).hash)
    RUBY

    _(result).must_answer <<~'OUT'
      :a
      :b
      nil
      true
      false
      :a
      2
      :x
      nil
      1
      true
      true
      true
    OUT
  end

  it "hash simple returns" do
    result = ze0(<<~'RUBY')
      # Hash: clear returns the emptied hash; no-arg merge is a copy; no-arg slice
      # is an empty hash; blockless one? is exactly-one-pair; to_hash is self.
      h = { a: 1, b: 2 }
      r = h.clear
      p r
      p h
      p({ a: 1, b: 2 }.merge)
      p({ a: 1, b: 2 }.slice)
      p({ a: 1 }.one?)
      p({ a: 1, b: 2 }.one?)
      p({}.one?)
      p({ a: 1 }.to_hash)
      g = { "x" => 1 }
      p g.merge
      p g.one?
    RUBY

    _(result).must_answer <<~'OUT'
      {}
      {}
      {a: 1, b: 2}
      {}
      true
      false
      false
      {a: 1}
      {"x" => 1}
      true
    OUT
  end

  it "integer hash range batch9" do
    result = ze0(<<~'RUBY')
      # Integer quo/gcdlcm/pow/digits edges, Hash compact!/update/store/merge!/
      # each_with_object(String memo), and endless Range#to_a.

      # Integer
      begin
        p(7.quo(0))
      rescue => e
        p e.class
      end
      p(7.quo(2))
      begin
        p(12.gcdlcm(2.5))
      rescue => e
        p e.class
      end
      p(12.gcdlcm(8))
      p(3.pow(-2))
      p(2.pow(-1))
      p(3.pow(2))
      p((2 ** 100).digits(1024))
      p(255.digits(16))

      # Hash
      h = { 1 => nil, 2 => "y" }
      h.compact!
      p(h)
      h2 = { a: 1 }
      h2.update({ b: 2 }, { c: 3 })
      p(h2)
      p({ "a" => 1, "b" => 2 }.each_with_object("") { |(k, _v), acc| acc << k })
      h3 = {}
      h3.store(:a, 1)
      p(h3)
      h4 = {}
      h4.merge!({ a: 1 })
      p(h4)

      # endless Range#to_a raises instead of hanging
      begin
        p((1..).to_a)
      rescue RangeError
        puts "RangeError"
      end
    RUBY

    _(result).must_answer <<~'OUT'
      ZeroDivisionError
      (7/2)
      TypeError
      [4, 24]
      (1/9)
      (1/2)
      9
      [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1]
      [15, 15]
      {2 => "y"}
      {a: 1, b: 2, c: 3}
      "ab"
      {a: 1}
      {a: 1}
      RangeError
    OUT
  end

  it "key whose hash raises raises where it is used" do
    result = ze0(<<~'RUBY')
      # A key's own `hash` or `eql?` that raises raises at the call that ran
      # it, and a key's `eql?` that grows the table under a lookup leaves the
      # table whole.
      class Bad
        def hash = raise("boom")
      end

      identity = {}.compare_by_identity
      identity[Bad.new] = 1

      begin
        {**identity}
      rescue => e
        p [:splat, e.message]
      end

      begin
        {}.update(identity)
      rescue => e
        p [:update, e.message]
      end

      begin
        {Bad.new => 1}
      rescue => e
        p [:literal, e.message]
      end

      begin
        {a: 1}[Bad.new]
      rescue => e
        p [:aref, e.message]
      end

      begin
        {a: 1}.fetch(Bad.new)
      rescue => e
        p [:fetch, e.message]
      end

      begin
        {a: 1}.key?(Bad.new)
      rescue => e
        p [:key?, e.message]
      end

      class Later
        def hash = $late ? raise("late") : 1
      end
      kept = {Later.new => 1}
      $late = true
      begin
        kept.rehash
      rescue => e
        p [:rehash, e.message]
      end

      after = {}
      after[:a] = 1
      p after

      H = {}
      class Grow
        def hash = 1
        def eql?(other) = (20.times { |i| H[i] = i }; true)
      end
      H[Grow.new] = 1
      H[Grow.new] = 2
      p H.size

    RUBY

    _(result).must_answer <<~'OUT'
      [:splat, "boom"]
      [:update, "boom"]
      [:literal, "boom"]
      [:aref, "boom"]
      [:fetch, "boom"]
      [:key?, "boom"]
      [:rehash, "late"]
      {a: 1}
      21
    OUT
  end

  it "user to hash splat" do
    result = ze0(<<~'RUBY')
      # `**obj` where obj defines #to_hash converts through to_hash, as CRuby does.
      class Opts
        def to_hash = { a: 1, b: 2 }
      end
      def take(a:, b:) = [a, b]
      p take(**Opts.new)

      # into a keyword-rest callee
      def collect(**o) = o
      p collect(**Opts.new)

      # an explicit keyword alongside the converted splat
      p collect(x: 9, **Opts.new)

      # a converter held in a local
      o = Opts.new
      p take(**o)
    RUBY

    _(result).must_answer <<~'OUT'
      [1, 2]
      {a: 1, b: 2}
      {x: 9, a: 1, b: 2}
      [1, 2]
    OUT
  end

  it "void value hash store nil" do
    result = ze0(<<~'RUBY')
      # `h[k] = nil` in value position (`return @cache[k] = nil`): the rhs is
      # nil-typed and has no C storage type; the store temp must widen to poly
      # instead of being declared `void _tN` (error: incomplete type 'void').
      class Cache
        def initialize
          @h = {}
          @last = nil
        end

        def fetch(k)
          return @h[k] = nil
        end

        def put(k)
          @last = (@h[k] = nil)
        end

        def last
          @last
        end

        def size
          @h.size
        end
      end

      c = Cache.new
      p c.fetch("a")
      p c.put("b")
      p c.last
      p c.size
    RUBY

    _(result).must_answer <<~'OUT'
      nil
      nil
      nil
      2
    OUT
  end
end
