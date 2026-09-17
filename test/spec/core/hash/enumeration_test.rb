# frozen_string_literal: true

require "spec_helper"

describe "Hash: enumeration" do
  it "each with index to h" do
    result = ze0(<<~'RUBY')
      # Materializing an each_with_index enumerator with to_h builds {element => index}.
      def si(x); x; end
      def ss(x); x; end
      def sp(x); x; end
      p si([10, 20, 30]).each_with_index.to_h
      p ss(["a", "b", "c"]).each_with_index.to_h
      p si([10, 20, 30]).each.with_index(1).to_h
      # A mixed poly-array receiver keeps a poly key, so the elements box into the hash.
      p sp([:x, "y", 3]).each_with_index.to_h
    RUBY

    _(result).must_answer <<~'OUT'
      {10 => 0, 20 => 1, 30 => 2}
      {"a" => 0, "b" => 1, "c" => 2}
      {10 => 1, 20 => 2, 30 => 3}
      {x: 0, "y" => 1, 3 => 2}
    OUT
  end

  it "each with object hash seed" do
    result = ze0(<<~'RUBY')
      # Array#each_with_object with an empty `{}` memo builds a general (boxed
      # key/value) hash. The memo param is typed as that hash, so `h[k] = v` inside
      # the block mutates it, and the populated hash is returned. Receivers are routed
      # through monomorphic per-type helpers to exercise the runtime path.
      def ints(x); x; end
      def strs(x); x; end
      def syms(x); x; end

      p ints([1, 2]).each_with_object({}) { |x, h| h[x] = x }
      p strs(["a", "bb"]).each_with_object({}) { |w, h| h[w] = w.length }
      p syms([:a, :b]).each_with_object({}) { |k, h| h[k] = k.to_s }
      p ints([1, 2, 3, 4]).each_with_object({}) { |n, h| h[n.even?] = n }

      # the result is an ordinary hash
      p ints([1, 2]).each_with_object({}) { |x, h| h[x] = x }.keys

      # an empty receiver yields the empty memo
      a = [1]
      a.pop
      p a.each_with_object({}) { |x, h| h[x] = x }

      # the `[]` array-seed form is unaffected
      p ints([1, 2, 3]).each_with_object([]) { |x, a| a << x * 2 }
    RUBY

    _(result).must_answer <<~'OUT'
      {1 => 1, 2 => 2}
      {"a" => 1, "bb" => 2}
      {a: "a", b: "b"}
      {false => 3, true => 4}
      [1, 2]
      {}
      [2, 4, 6]
    OUT
  end

  it "empty hash blockless enumerator" do
    result = ze0(<<~'RUBY')
      r = ({}.each_slice(2).to_a rescue $!.class)
      p r
      r2 = ({ a: 1 }.each_slice(2).to_a rescue $!.class); p r2
      r3 = ({}.chunk_while { |x, y| x == y }.to_a rescue $!.class); p r3
      r4 = ({}.each_cons(2).to_a rescue $!.class); p r4
    RUBY

    _(result).must_answer <<~'OUT'
      []
      [[[:a, 1]]]
      []
      []
    OUT
  end

  it "empty hash param default" do
    result = ze0(<<~'RUBY')
      def memo_get(n001, memo001 = {})
        memo001[n001] = n001 * 2
        memo001[n001]
      end
      p memo_get(3)

      def probe(n002, memo002 = {})
        memo002[n002] = n002 * 2
        p memo002.key?(n002)   # Ruby: true   Spinel: false
        p memo002.size         # both: 1
        memo002[n002]
      end
      p probe(3)

      def depth(name003, edges003, memo003 = {})
        return memo003[name003] if memo003.key?(name003)
        d003 = edges003[name003] || []
        memo003[name003] = d003.empty? ? 0 : 1 + d003.map { |x003| depth(x003, edges003, memo003) }.max
        memo003[name003]
      end
      p depth("a", { "a" => ["b"], "b" => ["c"], "c" => [] })

      def arr_val(s004, memo004 = {})
        memo004[s004] = [1]
        memo004[s004]
      end
      p arr_val("s")   # Ruby: [1]

      def with_arg(n005, memo005)
        memo005[n005] = n005 * 2
        memo005[n005]
      end
      p with_arg(3, {})     # => 6

      def sym_key(s006, memo006 = {})
        memo006[s006] = 1
        memo006[s006]
      end
      p sym_key(:a)         # => 1

      def acc_push(n007, acc007 = [])
        acc007 << n007
        acc007.size
      end
      p acc_push(3)         # => 1
    RUBY

    _(result).must_answer <<~'OUT'
      6
      true
      1
      6
      2
      [1]
      6
      1
      1
    OUT
  end

  it "hash blockless enumerator" do
    result = ze0(<<~'RUBY')
      # Blockless Hash Enumerable methods yield an Enumerator (KieranP #2337)
      p({ a: 1, b: 2 }.map.class)
      p({ a: 1, b: 2 }.select.class)
      p({ a: 1, b: 2 }.reject.class)
      p({ a: 1, b: 2 }.find.class)
      p({ a: 1, b: 2 }.flat_map.class)
      p({ a: 1, b: 2 }.map.to_a)
      p({ a: 1, b: 2 }.map { |k, v| v })
      p({ a: 1, b: 2 }.select { |k, v| v > 1 })
    RUBY

    _(result).must_answer <<~'OUT'
      Enumerator
      Enumerator
      Enumerator
      Enumerator
      Enumerator
      [[:a, 1], [:b, 2]]
      [1, 2]
      {b: 2}
    OUT
  end

  it "hash each entry literal" do
    result = ze0(<<~'RUBY')
      p({}.each_entry { |e| e })

      p({ a: 1, b: 2 }.each_entry { |e| e })    # Ruby: {a: 1, b: 2}   Spinel: no output
      p({ "a" => 1 }.each_entry { |e| e })      # Ruby: {"a" => 1}     Spinel: no output

      h = { a: 1, b: 2 }
      o = []; h.each_entry { |e| o << e }; p o   # => [[:a, 1], [:b, 2]]
      c = (h.each_entry { |e| e }); p c          # Ruby: {a: 1, b: 2}   Spinel: {a: 1, b: 2}
      h2 = {}; o2 = []; h2.each_entry { |e| o2 << e }; p o2   # => []
      p([1, 2].each_entry { |e| e })             # => [1, 2]
    RUBY

    _(result).must_answer <<~'OUT'
      {}
      {a: 1, b: 2}
      {"a" => 1}
      [[:a, 1], [:b, 2]]
      {a: 1, b: 2}
      []
      [1, 2]
    OUT
  end

  it "hash each enumerator" do
    result = ze0(<<~'RUBY')
      # Blockless Hash#each / Hash#each_pair return a materialized Enumerator over the
      # hash's [key, value] pairs (insertion order), a first-class value supporting
      # to_a / next / peek / size / class. The block form must keep working too.

      # --- blockless: a first-class Enumerator over [k, v] pairs ---
      e = { a: 1, b: 2, c: 3 }.each
      p e.class
      p e.to_a
      p e.size
      p e.next
      p e.next
      p e.peek
      p e.next

      p({ a: 1, b: 2 }.each_pair.to_a)

      # --- across the key/value storage variants ---
      p({ "x" => 1, "y" => 2 }.each.to_a)          # string keys, int values
      p({ "a" => "b", "c" => "d" }.each.to_a)      # string keys, string values
      p({ 1 => "one", 2 => "two" }.each.to_a)      # int keys, string values
      p({ [1] => :a, [2] => :b }.each.to_a)        # poly keys and values
      p({ a: [1, 2], b: [3, 4] }.each.to_a)        # symbol keys, array values

      # --- built-up local hash ---
      h = {}
      h[:x] = 10
      h[:y] = 20
      p h.each.to_a
      p h.each.size

      # --- assigned enumerator, materialized ---
      pairs = { one: 1, two: 2, three: 3 }.each_pair
      arr = pairs.to_a
      p arr.length
      p arr

      # --- direct block form (yields |k, v|, returns the receiver) ---
      seen = []
      { a: 1, b: 2 }.each { |k, v| seen << [k, v] }
      p seen
      sum = 0
      { a: 1, b: 2, c: 3 }.each_pair { |_k, v| sum += v }
      p sum
    RUBY

    _(result).must_answer <<~'OUT'
      Enumerator
      [[:a, 1], [:b, 2], [:c, 3]]
      3
      [:a, 1]
      [:b, 2]
      [:c, 3]
      [:c, 3]
      [[:a, 1], [:b, 2]]
      [["x", 1], ["y", 2]]
      [["a", "b"], ["c", "d"]]
      [[1, "one"], [2, "two"]]
      [[[1], :a], [[2], :b]]
      [[:a, [1, 2]], [:b, [3, 4]]]
      [[:x, 10], [:y, 20]]
      2
      3
      [[:one, 1], [:two, 2], [:three, 3]]
      [[:a, 1], [:b, 2]]
      6
    OUT
  end

  it "hash each key value" do
    result = ze0(<<~'RUBY')
      # Hash#each_key / #each_value with a block across every typed-hash
      # variant spinel offers. Keys and values are yielded in insertion
      # order. Poly (boxed-object) slots are printed via to_s so array
      # payloads render on a single line.

      # sym_int_hash
      h_sym_int = { a: 1, b: 2, c: 3 }
      h_sym_int.each_key { |k| puts k }
      puts "-"
      h_sym_int.each_value { |v| puts v }
      puts "=="

      # sym_str_hash
      h_sym_str = { x: "one", y: "two" }
      h_sym_str.each_key { |k| puts k }
      puts "-"
      h_sym_str.each_value { |v| puts v }
      puts "=="

      # sym_poly_hash (mixed scalar values box to sp_RbVal)
      h_sym_poly = { a: 1, b: "two" }
      h_sym_poly.each_key { |k| puts k }
      puts "-"
      h_sym_poly.each_value { |v| puts v.to_s }
      puts "=="

      # sym_poly_hash (object values)
      h_sym_poly_obj = { a: [1], b: [2, 3] }
      h_sym_poly_obj.each_key { |k| puts k }
      puts "-"
      h_sym_poly_obj.each_value { |v| puts v.to_s }
      puts "=="

      # str_int_hash
      h_str_int = { "a" => 1, "b" => 2 }
      h_str_int.each_key { |k| puts k }
      puts "-"
      h_str_int.each_value { |v| puts v }
      puts "=="

      # str_str_hash
      h_str_str = { "a" => "x", "b" => "y" }
      h_str_str.each_key { |k| puts k }
      puts "-"
      h_str_str.each_value { |v| puts v }
      puts "=="

      # str_poly_hash (mixed scalar values)
      h_str_poly = { "a" => 1, "b" => "two" }
      h_str_poly.each_key { |k| puts k }
      puts "-"
      h_str_poly.each_value { |v| puts v.to_s }
      puts "=="

      # str_poly_hash (object values)
      h_str_poly_obj = { "a" => [1], "b" => [2, 3] }
      h_str_poly_obj.each_key { |k| puts k }
      puts "-"
      h_str_poly_obj.each_value { |v| puts v.to_s }
      puts "=="

      # int_str_hash
      h_int_str = { 1 => "one", 2 => "two" }
      h_int_str.each_key { |k| puts k }
      puts "-"
      h_int_str.each_value { |v| puts v }
      puts "=="

      # int_int_hash
      h_int_int = { 1 => 10, 2 => 20 }
      h_int_int.each_key { |k| puts k }
      puts "-"
      h_int_int.each_value { |v| puts v }
      puts "=="

      # poly_poly_hash (heterogeneous object keys and values)
      h_poly_poly = {}
      h_poly_poly[[1, 2]] = "ab"
      h_poly_poly[[3, 4]] = "cd"
      h_poly_poly["s"] = 99
      h_poly_poly[5] = [10, 20]
      h_poly_poly.each_key { |k| puts k.to_s }
      puts "-"
      h_poly_poly.each_value { |v| puts v.to_s }
      puts "=="
    RUBY

    _(result).must_answer <<~'OUT'
      a
      b
      c
      -
      1
      2
      3
      ==
      x
      y
      -
      one
      two
      ==
      a
      b
      -
      1
      two
      ==
      a
      b
      -
      [1]
      [2, 3]
      ==
      a
      b
      -
      1
      2
      ==
      a
      b
      -
      x
      y
      ==
      a
      b
      -
      1
      two
      ==
      a
      b
      -
      [1]
      [2, 3]
      ==
      1
      2
      -
      one
      two
      ==
      1
      2
      -
      10
      20
      ==
      [1, 2]
      [3, 4]
      s
      5
      -
      ab
      cd
      99
      [10, 20]
      ==
    OUT
  end

  it "hash each next" do
    result = ze0(<<~'RUBY')
      { a: 1 }.each do |k, v|
        next
        puts "unreachable"
      end
      puts "ok"

      h = { a: 1, b: 2, c: 3 }
      seen = []
      h.each { |k, v| next if k == :b; seen << k }
      p seen

      h.each_pair { |k, v| next if v == 1; seen << v }
      p seen

      sums = 0
      { "x" => 1, "y" => 2 }.each { |k, v| next if k == "x"; sums += v }
      p sums

      d = { a: 1, b: 2, c: 3 }
      d.each { |k, v| d.delete(k) if k == :a }
      p d

      r = ({ a: 1, b: 2 }.each { |k, v| break k if v == 2 })
      p r
    RUBY

    _(result).must_answer <<~'OUT'
      ok
      [:a, :c]
      [:a, :c, 2, 3]
      2
      {b: 2, c: 3}
      :b
    OUT
  end

  it "hash each value key enumerator" do
    result = ze0(<<~'RUBY')
      # Blockless Hash#each_value / #each_key return an Enumerator, so .to_a and
      # .map chains compose (each/each_pair already did).
      h = { a: 1, b: 2 }
      p h.each_value.to_a
      p h.each_key.to_a
      p h.each_value.map { |v| v * 2 }
      p h.each_key.map { |k| k.to_s }
      sh = { "x" => 10 }
      p sh.each_value.to_a
      p sh.each_key.to_a
    RUBY

    _(result).must_answer <<~'OUT'
      [1, 2]
      [:a, :b]
      [2, 4]
      ["a", "b"]
      [10]
      ["x"]
    OUT
  end

  it "hash each with object" do
    result = ze0(<<~'RUBY', path: "core/hash/hash_each_with_object.rb")
      # Hash#each_with_object — iterates k,v pairs and threads `memo`
      # through the block. The destructured form `|(k,v), memo|` matches
      # the MultiTargetNode containing the two names; the flat 3-param
      # shape `|k, v, memo|` is also accepted.
      #
      # Note: an empty `[]` seed is typed as int_array, so a block that
      # pushes strings widens incorrectly. Use a typed seed
      # (\`[""]\`-style or pop after) when the block produces non-int values.

      h = {a: 1, b: 2, c: 3}
      result = h.each_with_object([]) { |(k,v), memo| memo << v * 10 }
      puts result.inspect

      # Flat 3-param form
      result2 = h.each_with_object([]) { |k, v, memo| memo << v * 100 }
      puts result2.inspect
    RUBY

    _(result).must_answer "[10, 20, 30]\n", stderr: "core/hash/hash_each_with_object.rb:15:in 'block in <main>': undefined method '<<' for nil (NoMethodError)\n\nresult2 = h.each_with_object([]) { |k, v, memo| memo << v * 100 }\n                                                     ^^\n\tfrom core/hash/hash_each_with_object.rb:15:in 'Hash#each'\n\tfrom core/hash/hash_each_with_object.rb:15:in 'Enumerable#each_with_object'\n\tfrom core/hash/hash_each_with_object.rb:15:in '<main>'\n", status: 1
  end

  it "hash empty literal and map" do
    result = ze0(<<~'RUBY')
      # Hash conformance (KieranP #2335,#2342,#2343)
      p({}.nil?)                          # #2335 object query on empty hash literal
      p({}.frozen?)
      p({}.empty?)
      p({}.is_a?(Hash))
      p({}.is_a?(Array))
      p(Hash[])                           # #2342 Hash[] with no arguments
      p({ a: 1, b: 2 }.map { |k, v| nil })       # #2343 all-nil block map
      p({ a: 1, b: 2 }.collect { |k, v| nil })
      p({ a: 1, b: 2 }.map { |k, v| k })
    RUBY

    _(result).must_answer <<~'OUT'
      false
      false
      true
      true
      false
      {}
      [nil, nil]
      [nil, nil]
      [:a, :b]
    OUT
  end

  it "hash keys each shadow" do
    result = ze0(<<~'RUBY')
      # Follow-up to PR #120: the hash.keys.each fusion path emitted the
      # block param as a bare assignment (`lv_k = hash->order[i]`), so a
      # block param that shadowed an outer same-named local of a different
      # type re-used the outer local's C declaration and the assignment
      # warned / produced wrong values. Mirror PR #115's pattern: declare
      # `lv_<bp>` inline with the key's C type and wrap the body in
      # push_scope / declare_var / pop_scope.

      # 1. Outer string `k`, inner int key (int_str_hash).
      def f1
        k = "outer-string"
        h = {1 => "a", 2 => "b"}
        h.keys.each do |k|
          puts k * 10
        end
        puts k
      end
      f1

      # 2. Outer int `s`, inner string key (str_int_hash).
      def f2
        s = 42
        h = {"x" => 1, "y" => 2}
        h.keys.each do |s|
          puts s + "!"
        end
        puts s
      end
      f2

      # 3. Outer string `n`, inner sym key (sym_int_hash).
      def f3
        n = "outer"
        h = {a: 10, b: 20}
        h.keys.each do |n|
          puts n
        end
        puts n
      end
      f3
    RUBY

    _(result).must_answer <<~'OUT'
      10
      20
      outer-string
      x!
      y!
      42
      a
      b
      outer
    OUT
  end

  it "hash map block" do
    result = ze0(<<~'RUBY')
      # Hash#map on sym_int_hash with a block. Pre-fix the receiver
      # fell through to a stale `_t = 0` IntArray pointer and crashed
      # on .inspect.
      h = {a: 1, b: 2}
      puts h.map { |k, v| v * 10 }.inspect
      puts h.map { |k, v| "#{k}=#{v}" }.inspect
    RUBY

    _(result).must_answer <<~'OUT'
      [10, 20]
      ["a=1", "b=2"]
    OUT
  end

  it "hash merge cross layout" do
    result = ze0(<<~'RUBY')
      # Hash#merge between incompatible specialized layouts folds through the
      # universal PolyPoly merge instead of reading the argument through the
      # wrong struct (#3261).
      merged = { 14 => nil }.merge({ 39 => 1 })
      p merged.keys.sort
      p merged[14]
      p merged[39]
      p({ 1 => 2 }.merge({ "a" => "b" }))
      p({ a: 1 }.merge({ "x" => 2 }))
      p({ 1 => 2 }.merge({ 3 => "s" }))
    RUBY

    _(result).must_answer <<~'OUT'
      [14, 39]
      nil
      1
      {1 => 2, "a" => "b"}
      {a: 1, "x" => 2}
      {1 => 2, 3 => "s"}
    OUT
  end

  it "hash param each kv inference" do
    result = ze0(<<~'RUBY')
      # Issue #408 (followup to #397). Hash params iterated solely via
      # `each do |k, v|` got no signal through the existing
      # `narrow_param_hash_types_from_body_writes` pass -- that one only
      # fires for `pname[k] = v` write-back patterns. A formatter that
      # read-only-iterates the hash, like the canonical
      # `Tep::Json.encode_object` shape:
      #
      #   def self.encode(h)
      #     out = ""
      #     h.each do |k, v|
      #       out = out + k + "=" + v
      #     end
      #     out
      #   end
      #
      # left h widened to whichever poly variant an earlier call site
      # pinned, so subsequent string-concat sites tripped the C compiler
      # with `passing 'sp_RbVal' to const char *`.
      #
      # Fix: extend `infer_param_hash_from_writes` with a parallel
      # collector that walks `pname.each do |k, v|` block bodies and
      # harvests type signals from how `k` and `v` participate in
      # `+`-chains. A chain with both a string literal leaf and a
      # k_pname / v_pname leaf is treated as evidence the corresponding
      # side is string-typed, narrowing the hash variant accordingly.
      #
      # The test exercises two shapes:
      #   - module class method with str_str_hash inputs at two
      #     differently-keyed call sites (the canonical Tep shape),
      #   - class instance method with the same body shape (the path
      #     that already worked, kept for parity).

      module Joiner
        def self.encode(h)
          out = ""
          first = true
          h.each do |k, v|
            if !first
              out = out + ","
            end
            first = false
            out = out + k + "=" + v
          end
          out
        end
      end

      puts Joiner.encode({"a" => "1", "b" => "2"})    # a=1,b=2
      puts Joiner.encode({"x" => "y"})                # x=y

      class Cookie
        def serialize(opts)
          out = ""
          first = true
          opts.each do |k, v|
            if !first
              out = out + ";"
            end
            first = false
            out = out + k + "=" + v
          end
          out
        end
      end

      c = Cookie.new
      puts c.serialize({"path" => "/", "domain" => "example.com"})
    RUBY

    _(result).must_answer <<~'OUT'
      a=1,b=2
      x=y
      path=/;domain=example.com
    OUT
  end

  it "hash reduce inject ewi" do
    result = ze0(<<~'RUBY')
      # Hash#reduce / #inject / #each_with_index materialize the [k, v] pairs once
      # and re-dispatch through the array emitters (the same shape the range
      # redispatch uses). The |acc, (k, v)| destructure binds the pair's leaves.
      h = { a: 1, b: 2, c: 3 }
      p h.reduce(0) { |sum, (k, v)| sum + v }
      p h.inject(0) { |sum, (k, v)| sum + v }
      p h.inject(100) { |sum, (k, v)| sum + v }
      h.each_with_index { |(k, v), i| puts "#{i}:#{k}=#{v}" }
      sh = { "x" => 5, "y" => 7 }
      p sh.reduce(0) { |s, (k, v)| s + v }
      p(({ a: 2 }).reduce(10) { |s, (k, v)| s * v })
      p [[:a, 1], [:b, 2]].reduce(0) { |s, (k, v)| s + v }
    RUBY

    _(result).must_answer <<~'OUT'
      6
      6
      106
      0:a=1
      1:b=2
      2:c=3
      12
      20
      3
    OUT
  end

  it "hash reduce predicate" do
    result = ze0(<<~'RUBY')
      # Hash#sum / #count / #all? / #any? with a block reduce the entries to a scalar:
      # sum accumulates the block value, count tallies truthy results, all?/any?
      # short-circuit to a boolean. Helpers are monomorphic so the runtime walk is
      # exercised without widening the parameter to poly.

      def sum_v(h)     = h.sum { |k, v| v }
      def sum_init(h)  = h.sum(10) { |k, v| v }
      def sum_float(h) = h.sum { |k, v| v * 1.0 }
      def count_gt(h)  = h.count { |k, v| v > 1 }
      def count_key(h) = h.count { |k, v| k == :a }
      def all_pos(h)   = h.all? { |k, v| v > 0 }
      def all_big(h)   = h.all? { |k, v| v > 1 }
      def any_big(h)   = h.any? { |k, v| v > 2 }
      def any_mid(h)   = h.any? { |k, v| v > 1 }

      p sum_v({ a: 1, b: 2, c: 3 })
      p sum_init({ a: 1, b: 2 })
      p sum_float({ a: 1, b: 2 })
      p count_gt({ a: 1, b: 2, c: 3 })
      p count_key({ a: 1, b: 2 })
      p all_pos({ a: 1, b: 2 })
      p all_big({ a: 1, b: 2 })
      p any_big({ a: 1, b: 2 })
      p any_mid({ a: 1, b: 2 })
    RUBY

    _(result).must_answer <<~'OUT'
      6
      13
      3.0
      2
      1
      true
      false
      false
      true
    OUT
  end

  it "hash sort by" do
    result = ze0(<<~'RUBY')
      # Hash#sort_by yields each |key, value| pair and returns the [key, value] pairs
      # ordered by the block's value. Each helper is monomorphic so the runtime walk
      # is exercised without widening the parameter to poly.

      def by_v(h)      = h.sort_by { |k, v| v }
      def by_neg_v(h)  = h.sort_by { |k, v| -v }
      def by_len(h)    = h.sort_by { |k, v| v.length }
      def by_key(h)    = h.sort_by { |k, v| k }
      def by_key_s(h)  = h.sort_by { |k, v| k.to_s }
      def by_v_str(h)  = h.sort_by { |k, v| v }

      p by_v({ a: 3, b: 1, c: 2 })
      p by_neg_v({ a: 3, b: 1, c: 2 })
      p by_len({ a: "xx", b: "y", c: "zzz" })
      p by_key({ 3 => 30, 1 => 10, 2 => 20 })
      p by_key_s({ c: 1, a: 2, b: 3 })
      p by_v_str({ "a" => 3, "b" => 1 })

      # The result is a plain array of pairs.
      ps = by_v({ x: 30, y: 10, z: 20 })
      p ps.length
      p ps.first[0]
      p ps.last[0]
    RUBY

    _(result).must_answer <<~'OUT'
      [[:b, 1], [:c, 2], [:a, 3]]
      [[:a, 3], [:c, 2], [:b, 1]]
      [[:b, "y"], [:a, "xx"], [:c, "zzz"]]
      [[1, 10], [2, 20], [3, 30]]
      [[:a, 2], [:b, 3], [:c, 1]]
      [["b", 1], ["a", 3]]
      3
      :y
      :x
    OUT
  end

  it "hash sort pairs" do
    result = ze0(<<~'RUBY', path: "core/hash/hash_sort_pairs.rb")
      # Hash#sort returns the entries as an array of [key, value] pairs ordered by
      # Array#<=> (key first, then value). Each receiver goes through a monomorphic
      # method parameter so the runtime path is exercised, not constant-folded.

      def sym_keyed(h)  = h.sort
      def str_keyed(h)  = h.sort
      def int_keyed(h)  = h.sort
      def int_int(h)    = h.sort

      p sym_keyed({ b: 2, a: 1, c: 3 })
      p str_keyed({ "d" => 1, "a" => 3, "c" => 2 })
      p int_keyed({ 3 => "x", 1 => "z", 2 => "y" })
      p int_int({ 30 => 1, 10 => 3, 20 => 2 })

      # Equal first elements fall back to comparing the second.
      p int_int({ 10 => 5, 5 => 9, 10 => 2 })

      # Result is a plain array of pairs.
      ps = sym_keyed({ z: 1, a: 2 })
      p ps.length
      p ps.first[0]
      p ps.last[0]
    RUBY

    _(result).must_answer <<~'OUT', stderr: "core/hash/hash_sort_pairs.rb:16: warning: key 10 is duplicated and overwritten on line 16\n"
      [[:a, 1], [:b, 2], [:c, 3]]
      [["a", 3], ["c", 2], ["d", 1]]
      [[1, "z"], [2, "y"], [3, "x"]]
      [[10, 3], [20, 2], [30, 1]]
      [[5, 9], [10, 2]]
      2
      :a
      :z
    OUT
  end

  it "hash values inject sym" do
    result = ze0(<<~'RUBY')
      # inject/reduce(:sym) folds a poly (boxed-element) array -- Hash#values,
      # Hash#map results -- via the tag-dispatching operators.
      h = { a: 1, b: 2, c: 3 }
      p h.values.inject(:+)
      p h.values.reduce(:+)
      p h.map { |k, v| v }.inject(:+)
      p h.values.inject { |a, b| a + b }
      p h.keys.length
    RUBY

    _(result).must_answer <<~'OUT'
      6
      6
      6
      6
      3
    OUT
  end

  it "map to heap objects" do
    result = ze0(<<~'RUBY')
      # `arr.map { Obj.new }` over a typed-array receiver collects the
      # constructed heap objects into a pointer array (previously the
      # accumulator defaulted to IntArray and the sp_<C>* push failed to
      # compile). Node is heap (it has a subclass, so not value-typed).
      class Node
        attr_reader :tag
        def initialize(t = 0); @tag = t; end
      end
      class Sub < Node; end
      ks = [10, 20, 30].map { |t| Node.new(t) }
      puts ks.size
      puts ks[0].tag
      puts ks[2].tag
      total = 0
      ks.each { |n| total += n.tag }
      puts total
    RUBY

    _(result).must_answer <<~'OUT'
      3
      10
      30
      60
    OUT
  end

  it "reduce no init hash merge" do
    result = ze0(<<~'RUBY')
      # reduce / inject with no initial value seeds the accumulator with the first
      # element, so a block whose value has a different shape than that element --
      # a Hash coming back out of #merge over a boxed element -- folds boxed.
      p [{ a: 1 }, { a: 2 }].reduce { |x, y| x.merge(y) }
      p [{ a: 1 }, { b: 2 }].inject { |x, y| x.merge(y) }
      p [{ a: 1 }, { a: 2 }].reduce { |x, y| x.merge(y) { |_k, l, r| l + r } }
      p [{ a: 1 }, { a: 2 }].reduce({}) { |x, y| x.merge(y) }

      rows = [{ "n" => 1 }, { "n" => 2 }, { "m" => 3 }]
      p rows.reduce { |x, y| x.merge(y) }
      p rows.size

      # an each-loop fold and a fold with an explicit seed still agree
      acc = {}
      rows.each { |r| acc = acc.merge(r) }
      p acc

      # arrays fold the same way
      p [[1], [2], [3]].reduce { |x, y| x + y }
      p [1, 2, 3].reduce { |x, y| x + y }
    RUBY

    _(result).must_answer <<~'OUT'
      {a: 2}
      {a: 1, b: 2}
      {a: 3}
      {a: 2}
      {"n" => 2, "m" => 3}
      3
      {"n" => 2, "m" => 3}
      [1, 2, 3]
      6
    OUT
  end
end
