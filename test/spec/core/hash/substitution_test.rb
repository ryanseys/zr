# frozen_string_literal: true

require "spec_helper"

describe "Hash: substitution" do
  it "env fetch default value" do
    result = ze0(<<~'RUBY')
      # ENV.fetch with a default of every kind (String, nil, Integer, Symbol,
      # Array, Hash), with a block, when the variable is set and when it is not,
      # and the KeyError of the bare form. CRuby generated the expectations.
      ENV.delete("SPINEL_ENV_FETCH_NOPE")
      p ENV.fetch("SPINEL_ENV_FETCH_NOPE", [1, 2])
      p ENV.fetch("SPINEL_ENV_FETCH_NOPE", 5)
      p ENV.fetch("SPINEL_ENV_FETCH_NOPE", nil)
      p ENV.fetch("SPINEL_ENV_FETCH_NOPE", "d")
      p ENV.fetch("SPINEL_ENV_FETCH_NOPE", :sym)
      d = { "k" => 1 }
      p ENV.fetch("SPINEL_ENV_FETCH_NOPE", d)
      p ENV.fetch("SPINEL_ENV_FETCH_NOPE") { |k| k * 2 }
      p ENV.fetch("SPINEL_ENV_FETCH_NOPE") { |k| n = k.length; n + 1 }
      ENV["SPINEL_ENV_FETCH_SET"] = "there"
      p ENV.fetch("SPINEL_ENV_FETCH_SET", 5)
      p ENV.fetch("SPINEL_ENV_FETCH_SET") { |k| k * 2 }
      x = ENV.fetch("SPINEL_ENV_FETCH_NOPE", 7)
      p x + 1
      begin
        ENV.fetch("SPINEL_ENV_FETCH_NOPE")
      rescue KeyError => e
        puts e.message
      end
      # the default is an argument: it evaluates whether or not the variable is set
      def side!; puts "side!"; 9; end
      p ENV.fetch("SPINEL_ENV_FETCH_SET", side!)
      p ENV.fetch("SPINEL_ENV_FETCH_NOPE", side!)
      p ENV.fetch("SPINEL_ENV_FETCH_NOPE") { |k| k = k.length; k * 2 }
    RUBY

    _(result).must_answer <<~'OUT'
      [1, 2]
      5
      nil
      "d"
      :sym
      {"k" => 1}
      "SPINEL_ENV_FETCH_NOPESPINEL_ENV_FETCH_NOPE"
      22
      "there"
      "there"
      8
      key not found: "SPINEL_ENV_FETCH_NOPE"
      side!
      "there"
      side!
      9
      42
    OUT
  end

  it "env is an object with hash shaped methods" do
    result = ze0(<<~'RUBY')
      # `ENV` is an Object with Hash-shaped methods, NOT a Hash (`ENV.class` is
      # `Object` -- oracle-verified), and it reads the LIVE environment.

      p ENV.class
      ENV["ZEO_E2E"] = "set"
      p ENV["ZEO_E2E"]
      p ENV.key?("ZEO_E2E")
      p ENV.fetch("ZEO_E2E")
      p ENV.fetch("ZEO_E2E_ABSENT", "default")
      p ENV.fetch("ZEO_E2E_ABSENT") { |k| "computed:#{k}" }
      p ENV["ZEO_E2E_ABSENT"]
      p ENV.delete("ZEO_E2E")
      p ENV.key?("ZEO_E2E")
      p ENV.delete("ZEO_E2E")
      p ENV.to_h.class
      p ENV.keys.class
      ENV["ZEO_E2E2"] = "x"
      ENV["ZEO_E2E2"] = nil
      p ENV["ZEO_E2E2"]
    RUBY

    _(result).must_answer <<~'OUT'
      Object
      "set"
      true
      "set"
      "default"
      "computed:ZEO_E2E_ABSENT"
      nil
      "set"
      false
      nil
      Hash
      Array
      nil
    OUT
  end

  it "delete_if, select! and reject! change the receiver in place" do
    result = ze0(<<~'RUBY')
      # Hash#delete_if / #select! / #reject! on typed hashes mutate
      # the receiver in place.

      h = {a: 1, b: 2, c: 3, d: 4}
      h.delete_if { |k, v| v % 2 == 0 }
      puts h.inspect

      h2 = {a: 1, b: 2, c: 3}
      h2.select! { |k, v| v % 2 == 0 }
      puts h2.inspect

      h3 = {a: 1, b: 2, c: 3}
      h3.reject! { |k, v| v > 1 }
      puts h3.inspect

      # str_int_hash variant.
      h4 = {"x" => 10, "y" => 20, "z" => 30}
      h4.delete_if { |k, v| v >= 20 }
      puts h4.inspect
    RUBY

    _(result).must_answer <<~'OUT'
      {a: 1, c: 3}
      {b: 2}
      {a: 1}
      {"x" => 10}
    OUT
  end

  it "delete answers the value it removed, and the element kind's zero for a miss" do
    result = ze0(<<~'RUBY')
      h_si = { a: 1, b: 2, c: 3 }
      v1 = h_si.delete(:a)
      puts v1
      puts h_si.size

      h_ss = { x: "one", y: "two" }
      v2 = h_ss.delete(:x)
      puts v2
      puts h_ss.size

      # delete missing key on sym_int_hash returns 0 (spinel int default,
      # diverges from CRuby's nil but matches existing has_key fallback)
      h2 = { a: 1 }
      puts h2.delete(:b)
      puts h2.size

      # Multi-value sym_poly_hash
      h_sp = { a: 1, b: "two", c: :sym }
      v3 = h_sp.delete(:b)
      puts v3.inspect
      puts h_sp.size
    RUBY

    _(result).must_answer <<~'OUT'
      1
      2
      one
      1

      1
      "two"
      2
    OUT
  end

  it "fetch_values and delete take a block for a miss, and the subset operators compare" do
    result = ze0(<<~'RUBY')
      # Hash#fetch_values with a block for missing keys, Hash#delete with a block,
      # hash subset/superset comparison operators, and Enumerable none?/one?/find_all
      # on a hash receiver (plus plain-array find_all).
      h = { a: 1, b: 2 }
      p h.fetch_values(:a, :b)
      p h.fetch_values(:a, :z) { |k| "missing #{k}" }

      d = { a: 1, b: 2 }
      p d.delete(:b)
      p d.delete(:z) { |k| "gone #{k}" }
      p d

      small = { a: 1 }
      big = { a: 1, b: 2 }
      same = { a: 1, b: 2 }
      p small < big
      p small <= big
      p big > small
      p big >= small
      p same < big
      p same <= big
      p big < small
      p({ a: 2 } <= big)

      n = { a: 1, b: 2 }
      p n.none? { |k, v| v > 5 }
      p n.none? { |k, v| v > 1 }
      p n.one? { |k, v| v > 1 }
      p n.one? { |k, v| v > 0 }
      p n.find_all { |k, v| v > 1 }
      p n.find_all { |k, v| v > 5 }

      p [1, 2, 3].find_all { |x| x > 1 }
      p [1, 2, 3].find_all(&:even?)
    RUBY

    _(result).must_answer <<~'OUT'
      [1, 2]
      [1, "missing z"]
      2
      "gone z"
      {a: 1}
      true
      true
      true
      true
      false
      true
      false
      false
      true
      false
      true
      false
      [[:b, 2]]
      []
      [2, 3]
      [2]
    OUT
  end

  it "the delete family and shift answer on an integer-keyed hash" do
    result = ze0(<<~'RUBY')
      # Integer-keyed Hash delete-family + Hash#shift (KieranP #2344,#2349,#2353)
      p({ 1 => "a", 2 => "b" }.delete(1))         # #2344 delete
      p({ 1 => 10, 2 => 20 }.delete(2))
      p({ 1 => 10, 2 => 20 }.slice(1))            # #2344 slice
      p({ 1 => 10, 2 => 20 }.except(1))           # #2344 except
      p({ 1 => "a", 2 => "b" }.slice(2))
      h = { a: 1, b: 2 }
      p h.shift                                    # #2349 shift
      p h
      p({ 1 => 10, 2 => 20 }.shift)
      p({}.shift) rescue p(:empty_ok)
      h2 = { 1 => 10, 2 => 20 }
      h2.delete_if { |_k, v| v > 15 }              # #2353 delete-family mutator
      p h2
      p({ 1 => 10 }.value?(10))                    # #2353 value?
      p({ 1 => 10 }.has_value?(99))
    RUBY

    _(result).must_answer <<~'OUT'
      "a"
      20
      {1 => 10}
      {2 => 20}
      {2 => "b"}
      [:a, 1]
      {b: 2}
      [1, 10]
      nil
      {1 => 10}
      true
      false
    OUT
  end

  it "a key string mutated in place has its cached hash dropped, so a later lookup still finds it" do
    result = ze0(<<~'RUBY')
      # Guards the cached-key-hash optimization: a heap string used as a hash
      # lookup key caches its hash in the string header. If the string is then
      # mutated in place, the cached hash must be invalidated, or a later lookup
      # under the new content lands in the wrong bucket and silently misses.
      h = {}
      h["bar"] = 5

      # setbyte: mutate a key whose hash was already cached by a prior lookup
      s = "AAA".dup
      _miss = (h[s] || 0)        # caches hash("AAA") into s's header
      s.setbyte(0, 66)           # s -> "BAA"; cached hash must be cleared
      h[s] = 9
      puts(h["BAA"])             # fresh hash("BAA") must find 9, not nil
      puts(h["BAA".dup])         # same, via a distinct heap pointer

      # replace: longer in-place mutation
      k = "foo".dup
      _m2 = (h[k] || 0)          # caches hash("foo")
      k.replace("longerkey")
      h[k] = 7
      puts(h["longerkey"])       # must find 7

      # basic repeated lookup (exercises the cached-hit fast path)
      env = {}
      env["alpha"] = 1
      env["beta"] = 2
      total = 0
      3.times do
        total += env["alpha"]
        total += env["beta"]
      end
      puts(total)
    RUBY

    _(result).must_answer <<~'OUT'
      9
      9
      7
      9
    OUT
  end

  it "a local widened past its initializer's hash variant is converted, not reinterpreted" do
    result = ze0(<<~'RUBY')
      # A local the analysis widened past its initializer's hash variant. The
      # variants are separate C structs, so the pointer went into the slot with no
      # conversion and the C build stopped.
      #
      # 0b3ec5fb widened the arm that reaches this -- a block over an unresolved
      # receiver has its params widened to poly -- so `sub[k] = v` widens `sub` while
      # its initializer still answers Hash[String, String]. The widening is right:
      # the receiver really can be either at run time. What was missing is the
      # conversion, which the ARGUMENT path has had since #3998.

      class A
        def each
          yield "a", "b"
        end
      end

      module Tep
        def self.str_hash
          Hash.new("")
        end
      end

      def keep
        h = Tep.str_hash
        h["k"] = "v"
        h
      end

      def nest(flat)
        sub = Tep.str_hash
        flat.each { |k, v| sub[k] = v }
        sub
      end

      puts keep.size
      puts nest({ "a" => "b" }).size
      puts nest(A.new).size
      p nest({ "a" => "b" })
      p nest(A.new)
      p nest(A.new)["a"]

      # the same shape into a symbol-keyed slot
      module Sym
        def self.sym_hash = { x: "1" }
      end

      def nest_sym(flat)
        sub = Sym.sym_hash
        flat.each { |k, v| sub[k] = v }
        sub
      end

      p nest_sym({ y: "2" }).size
      p nest_sym(A.new).size

      # a hash that is NOT widened keeps its variant, which is the control: widening
      # every one of these would box a key the whole program reads as a String
      def plain
        h = Tep.str_hash
        h["a"] = "b"
        h["a"]
      end
      p plain
    RUBY

    _(result).must_answer <<~'OUT'
      1
      1
      1
      {"a" => "b"}
      {"a" => "b"}
      "b"
      2
      2
      "b"
    OUT
  end

  it "adding a key during each raises, while deleting or rewriting one does not" do
    result = ze0(<<~'RUBY')
      h001 = { a: 1, b: 2 }
      r001 = (h001.each { |_k001, _v001| h001[:c] = 3 } rescue $!.class)
      p r001
      h002 = { a: 1, b: 2 }
      h002.each { |k, _v| h002.delete(k) }
      p h002
      h003 = { a: 1, b: 2 }
      h003.each { |k, v| h003[k] = v * 10 }
      p h003
      h4 = { "a" => 1, "b" => 2 }
      r4 = []; h4.each { |k, v| r4 << [k, v] }; p r4
      h5 = { a: 1, b: 2, c: 3 }
      r5 = []; h5.each { |k, v| r5 << k }; p r5
      p h5
    RUBY

    _(result).must_answer <<~'OUT'
      RuntimeError
      {}
      {a: 10, b: 20}
      [["a", 1], ["b", 2]]
      [:a, :b, :c]
      {a: 1, b: 2, c: 3}
    OUT
  end

  it "replace empties the receiver, copies the other's entries in order, and answers itself" do
    result = ze0(<<~'RUBY')
      # Hash#replace on the 4 common typed-hash variants — empty
      # receiver and copy entries from `other` in original-key order.
      # Returns the receiver.

      h1 = {a: 1, b: 2}; h2 = {c: 3, d: 4}; h1.replace(h2)
      puts h1.inspect
      puts h1[:c]
      puts h1[:a]

      h3 = {a: "x"}; h4 = {b: "y"}; h3.replace(h4)
      puts h3.inspect

      h5 = {"a" => 1}; h6 = {"b" => 2}; h5.replace(h6)
      puts h5.inspect

      h7 = {"a" => "x"}; h8 = {"b" => "y"}; h7.replace(h8)
      puts h7.inspect
    RUBY

    _(result).must_answer <<~'OUT'
      {c: 3, d: 4}
      3

      {b: "y"}
      {"b" => 2}
      {"b" => "y"}
    OUT
  end

  it "new hash takes cruby shape" do
    result = ze0(<<~'RUBY')
      # A new Hash takes the shape CRuby gives it. Hash[] builds the
      # receiver's class and keeps neither the identity flag nor the default;
      # select, reject, slice, except and transform_values keep the identity
      # flag and no default; compact, merge, dup and clone copy the whole
      # Hash. replace takes the other's contents, default and identity flag,
      # and leaves itself alone. A key's own hash and eql? decide, a Bignum
      # hash folded, whatever the key's class.
      def t = yield rescue [$!.class, $!.message]

      class HS < Hash; end
      h = {a: 1}
      i = {}.compare_by_identity
      d = Hash.new(3)
      d[:a] = nil
      d[:b] = 1
      p t { Hash[h].equal?(h) }, t { HS[{a: 1}].class }, t { HS[[[:a, 1]]].class }, t { Hash[i].compare_by_identity? }, t { Hash[d][:zz] }
      p t { [i.select { true }, i.reject { false }, i.slice, i.except, i.compact, i.transform_values { 1 }, i.merge({}), i.dup, i.clone].map(&:compare_by_identity?) }
      p t { [d.compact, d.select { true }, d.reject { false }, d.slice(:b), d.except(:a), d.transform_values { 1 }, d.merge({})].map { |x| x[:zz] } }
      p t { [HS[a: 1].select { true }, HS[a: 1].reject { false }, HS[a: 1].slice(:a), HS[a: 1].except, HS[a: 1].compact, HS[a: 1].transform_values { 1 }, HS[a: 1].merge({})].map(&:class) }
      p t { h.replace(h) }, t { g = {}; g.replace(Hash.new(5)); g[:x] }, t { {}.replace(i).compare_by_identity? }, t { i.dup.replace({a: 1}).compare_by_identity? }
      p t { {}.freeze.replace({}) }, t { x = {a: 1}; x.each { x.replace({}) } }, t { x = {a: 1}; x.each { x.compare_by_identity } }, t { {}.freeze.merge!({}) }

      k = Class.new { def hash = 2**70; def eql?(o) = true }
      e = Class.new(StandardError) { def hash = 1; def eql?(o) = true }
      p t { {k.new => 1}[k.new] }, t { {e.new => 1}[e.new] }, t { {Class => 1}[Class] }, t { {1..2 => :r}[1..2] }

    RUBY

    _(result).must_answer <<~'OUT'
      false
      HS
      HS
      false
      nil
      [true, true, true, true, true, true, true, true, true]
      [3, nil, nil, nil, nil, nil, 3]
      [Hash, Hash, Hash, Hash, HS, Hash, HS]
      {a: 1}
      5
      true
      false
      [FrozenError, "can't modify frozen Hash: {}"]
      [RuntimeError, "can't replace hash during iteration"]
      [RuntimeError, "compare_by_identity during iteration"]
      [FrozenError, "can't modify frozen Hash: {}"]
      1
      1
      1
      :r
    OUT
  end

  it "sym hash cross variant merge" do
    result = ze0(<<~'RUBY')
      # #515. Cross-variant Hash#merge between sym_str_hash and
      # sym_poly_hash (sibling to #510) used to fail in both directions:
      #
      # - sym_str_hash.merge(sym_poly_hash): codegen routed to
      #   sp_SymStrHash_merge and passed the poly arg as `b`, tripping
      #   -Wincompatible-pointer-types and producing runtime garbage.
      #
      # - sym_poly_hash.merge(sym_str_hash): no helper at all,
      #   "cannot resolve call to 'merge' on sym_poly_hash" warning.
      #
      # Fix: new sp_SymStrHash_to_sym_poly (codegen-emitted alongside
      # the existing sym_str_hash runtime helpers) and
      # sp_SymPolyHash_merge_str. Both directions return a fresh
      # sym_poly_hash. Analyze's merge inference returns
      # sym_poly_hash for the cross-variant pair.

      def dir1_str_recv_poly_arg(t)
        poly = { method: :delete, id: 42, text: t }
        str  = { class: "btn", role: "button" }
        str.merge(poly)
      end

      def dir2_poly_recv_str_arg(t)
        poly = { method: :delete, id: 42, text: t }
        str  = { class: "btn", role: "button" }
        poly.merge(str)
      end

      # Both directions: receiver has 2 keys, arg has 3 keys, no
      # overlap -> 5 entries in the merged hash.
      puts dir1_str_recv_poly_arg("a").length
      puts dir2_poly_recv_str_arg("a").length

      # Overlap: arg's value wins (standard Hash#merge semantics).
      def overlap_dir1
        base = { class: "btn", id: 1 }
        over = { id: 99, name: :foo }
        base.merge(over)[:id]
      end
      p overlap_dir1
    RUBY

    _(result).must_answer <<~'OUT'
      5
      5
      99
    OUT
  end

  it "sym int hash merge" do
    result = ze0(<<~'RUBY')
      # #546. Sibling of #510 -- merge / dup / delete dispatch was
      # missing on sym_int_hash (Symbol-key, Int-value). #510 fixed
      # the same surface for sym_str_hash and sym_poly_hash. Spinel
      # emitted `cannot resolve call to 'merge' on sym_int_hash
      # (emitting 0)` and the call no-op'd.
      #
      # Trigger in roundhouse: `ActionView::ViewHelpers.link_to`
      # builds an HTML-attrs hash via `.merge`; when the value type
      # was numeric (sym_int_hash variant) the merge dropped silently.
      #
      # Fix:
      # 1. spinel_codegen.rb: new `sp_SymIntHash_merge` runtime helper
      #    (mirrors the sym_str_hash version with NULL-guard on the
      #    second arg per the #542 / #546 NULL-receiver pattern).
      # 2. spinel_codegen.rb: sym_int_hash recv dispatch block gains
      #    merge / dup / delete arms.
      # 3. spinel_codegen.rb: kwarg-shorthand merge (`h.merge(c: 3)`)
      #    builds the matching sp_SymIntHash inline from the
      #    KeywordHashNode pairs, mirroring the kwarg-as-bundle path
      #    in compile_constructor_args.

      def merge_kwarg(h)
        h.merge(c: 3, d: 4)
      end

      def merge_hash(h)
        h.merge({c: 3, d: 4})
      end

      # Both forms work post-fix.
      r1 = merge_kwarg({a: 1, b: 2})
      puts r1[:a]   # 1
      puts r1[:b]   # 2
      puts r1[:c]   # 3
      puts r1[:d]   # 4

      r2 = merge_hash({a: 10, b: 20})
      puts r2[:a]   # 10
      puts r2[:c]   # 3

      # dup
      h = {x: 100, y: 200}
      h2 = h.dup
      puts h2[:x]   # 100
      puts h2[:y]   # 200

      # delete
      h3 = {p: 1, q: 2, r: 3}
      h3.delete(:q)
      puts h3[:p]   # 1
      puts h3[:q]   # 0 (missing now)
      puts h3[:r]   # 3
    RUBY

    _(result).must_answer <<~'OUT'
      1
      2
      3
      4
      10
      3
      100
      200
      1

      3
    OUT
  end
end
