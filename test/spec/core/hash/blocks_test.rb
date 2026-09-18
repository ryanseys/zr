# frozen_string_literal: true

require "spec_helper"

describe "Hash: blocks and yields" do
  it "block forward hash iterators" do
    result = ze0(<<~'RUBY')
      def fwd_map(&b)   = ({ a: 1, b: 2 }).map(&b)
      def fwd_sel(&b)   = ({ a: 1, b: 2 }).select(&b)
      def fwd_rej(&b)   = ({ a: 1, b: 2 }).reject(&b)
      def fwd_sum(&b)   = ({ a: 1, b: 2 }).sum(&b)
      def fwd_cnt(&b)   = ({ a: 1, b: 2 }).count(&b)
      def fwd_find(&b)  = ({ a: 1, b: 2 }).find(&b)
      def fwd_sort(&b)  = ({ a: 1, b: 2 }).sort_by(&b)
      def fwd_min(&b)   = ({ a: 1, b: 2 }).min_by(&b)
      def fwd_grp(&b)   = ({ a: 1, b: 2 }).group_by(&b)
      def fwd_fmap(&b)  = ({ a: 1, b: 2 }).filter_map(&b)
      def fwd_part(&b)  = ({ a: 1, b: 2 }).partition(&b)

      p(fwd_map  { |k, v| v })
      p(fwd_sel  { |k, v| v > 0 })
      p(fwd_rej  { |k, v| v > 0 })
      p(fwd_sum  { |k, v| v })
      p(fwd_cnt  { |k, v| v > 1 })
      p(fwd_find { |k, v| v > 1 })
      p(fwd_sort { |k, v| -v })
      p(fwd_min  { |k, v| -v })
      p(fwd_grp  { |k, v| v.odd? })
      p(fwd_fmap { |k, v| v > 1 ? v : nil })
      p(fwd_part { |k, v| v > 1 })

    RUBY

    _(result).must_answer <<~'OUT'
      [1, 2]
      {a: 1, b: 2}
      {}
      3
      1
      [:b, 2]
      [[:b, 2], [:a, 1]]
      [:b, 2]
      {true => [[:a, 1]], false => [[:b, 2]]}
      [2]
      [[[:b, 2]], [[:a, 1]]]
    OUT
  end

  it "empty hash block result key" do
    result = ze0(<<~'RUBY')
      # An empty `{}` local whose `[]=` key is a block's return value.
      #
      # The key-context pass runs during the fixpoint, where a key that is a block
      # result has no type yet, so the local fell through to the post-fixpoint
      # backstop -- which defaulted it to StrPolyHash. Codegen reads a StrPolyHash
      # key out of the boxed value as `.v.s`, so the write handed a boxed Integer to
      # a `const char *` slot and the program segfaulted with no output.
      #
      # The backstop now checks the local's own `[]=` keys, which by then DO have a
      # type, and only keeps the String-keyed default when the key is a String (or
      # there are no writes to say otherwise).
      #
      # Only the receiver form varied: `Rel.new.group { }` was always correct,
      # `x = Rel.new; x.group { }` was the crash.

      class Rel
        def group
          out = {}
          [1, 2, 3].each do |rec|
            k = yield rec
            arr = out.fetch(k, nil)
            if arr.nil?
              arr = []
              out[k] = arr
            end
            arr << rec
          end
          out
        end

        def single
          out = {}
          k = yield 5
          out[k] = 5
          out
        end

        def str_keyed
          out = {}
          k = yield 5
          out[k.to_s] = 5
          out
        end
      end

      x = Rel.new
      p x.single { |v| v % 2 }
      p x.group { |v| v % 2 }
      p x.str_keyed { |v| v % 2 }

      # the inline-receiver form keeps its precise Hash[Integer, Integer]
      p Rel.new.single { |v| v % 2 }

      # a block result reached through an explicit block param, same shape
      class Blk
        def single(&blk)
          out = {}
          k = blk.call(5)
          out[k] = 5
          out
        end
      end
      y = Blk.new
      p y.single { |v| v % 2 }

      # the read-modify-write forms key the slot just as `[]=` does, so the variant
      # decision has to see them too (they carry the key in arguments[0] and the
      # value in a `value` ref, which is why the write index used to miss them)
      class Counter
        def tally
          out = {}
          k = yield 5
          out[k] ||= 0
          out[k] += 1
          out
        end

        def anded
          out = {}
          k = yield 4
          out[k] = 1
          out[k] &&= 9
          out
        end
      end
      p Counter.new.tally { |v| v % 3 }
      p Counter.new.anded { |v| v % 3 }

      def string_keyed_or_write
        h = {}
        h["a"] ||= 1
        h
      end
      p string_keyed_or_write
    RUBY

    _(result).must_answer <<~'OUT'
      {1 => 5}
      {1 => [1, 3], 0 => [2]}
      {"1" => 5}
      {1 => 5}
      {1 => 5}
      {2 => 1}
      {1 => 9}
      {"a" => 1}
    OUT
  end

  it "empty hash key through tap" do
    result = ze0(<<~'RUBY')
      # A `tap` / `then` block parameter is another name for the call's own receiver,
      # so a key operation written through it says the same thing about the literal
      # that one written directly on it does. The rule that gives a bare `{}` the
      # variant its key selects did not follow the parameter back, so the literal
      # kept the String-keyed default and an Array key went into a `const char *`
      # slot (#4026):
      #
      #   p( {}.tap{ |h| h[[]] } )
      #   # error: incompatible pointer types passing 'sp_IntArray *' to
      #   #        parameter of type 'const char *'
      p({}.tap { |h| h[[]] })
      p({}.then { |h| h[[]] })
      p({}.tap { |h| h[[1]] })
      p({}.tap { |h| h[1.5] })
      p({}.tap { |h| h[:a] })
      p({}.tap { |h| h["k"] })

      # the WRITE forms name their key in the same place, and were not in the rule's
      # name list at all -- so a Symbol key through tap built a String-keyed hash
      p({}.tap { |h| h[:a] = 1 })
      p({}.tap { |h| h["k"] = 1 })
      p({}.tap { |h| h[1] = 2 })
      p({}.tap { |h| h[[1, 2]] = 3 })
      p({}.tap { |h| h.store([1], 2) })
      p({}.tap { |h| h.store(:s, 4) })

      # nested, and reaching the same literal twice
      p({}.tap { |h| h[[1]] = 1 }.tap { |g| g[[2]] = 2 })

      # the direct spellings keep answering the same thing
      h = {}
      h[:a] = 1
      p h
      g = {}
      g[[1]] = 2
      p g
      p({}.fetch([], "d"))
    RUBY

    _(result).must_answer <<~'OUT'
      {}
      nil
      {}
      {}
      {}
      {}
      {a: 1}
      {"k" => 1}
      {1 => 2}
      {[1, 2] => 3}
      {[1] => 2}
      {s: 4}
      {[1] => 1, [2] => 2}
      {a: 1}
      {[1] => 2}
      "d"
    OUT
  end

  it "empty hash yield wrapper seed" do
    result = ze0(<<~'RUBY')
      # An empty {} passed as a yield-wrapper's accumulator seed: the callee builds
      # it through its block (acc = yield(acc, x)), so the param/return can't settle
      # from the wrapper body (the precise index-write widening can't reach it).
      # It must not degrade the wrapper -- and its caller -- to a void method.
      class Rel
        def initialize(a)
          @a = a
        end
        def inject(acc)
          @a.each { |x| acc = yield(acc, x) }
          acc
        end
      end

      class V
        def self.tally(flag)
          if flag
            {}
          else
            Rel.new([1, 2]).inject({}) do |memo, v|
              memo[v] = { a: v }
              memo
            end
          end
        end
      end

      puts V.tally(true).length
      puts V.tally(false).length
      h = V.tally(false)
      p h[1]
      p h.class
    RUBY

    _(result).must_answer <<~'OUT'
      0
      2
      {a: 1}
      Hash
    OUT
  end

  it "fetch block supersedes default" do
    result = ze0(<<~'RUBY')
      # CRuby warns "block supersedes default value argument" wherever a `fetch`-like
      # takes BOTH a positional default and a block, and the block is the one that
      # wins. Six sites carry the same wording (`Hash#fetch`, `Array#fetch`,
      # `Array.new`, `ENV.fetch`, `Thread#fetch`), and the warning is `rb_warn`, not
      # `rb_warning`: it prints under a plain run, not only under `-w`.

      # The block outranks the default at every site.
      p([1, 2].fetch(9, :dflt) { |i| [:blk, i] })
      p({ a: 1 }.fetch(:z, :dflt) { |k| [:blk, k] })
      p(ENV.fetch("ZEO_NO_SUCH_VAR", "dflt") { |k| "blk #{k}" })
      p(Thread.current.fetch(:nope, :dflt) { |k| [:blk, k] })
      p(Array.new(3, :fill) { |i| i })

      # A found key never reaches either, so no warning and no block call.
      p([1, 2].fetch(0, :dflt) { :blk })
      p({ a: 1 }.fetch(:a, :dflt) { :blk })

      # One argument plus a block is the ordinary form -- no warning.
      p([1, 2].fetch(9) { |i| [:blk, i] })
      p({ a: 1 }.fetch(:z) { |k| [:blk, k] })
      p(ENV.fetch("ZEO_NO_SUCH_VAR") { |k| "blk #{k}" })
      p(Thread.current.fetch(:nope) { |k| [:blk, k] })
      p(Array.new(3) { |i| i * 2 })

      # Two arguments and no block is the other ordinary form -- no warning.
      p([1, 2].fetch(9, :dflt))
      p({ a: 1 }.fetch(:z, :dflt))
      p(ENV.fetch("ZEO_NO_SUCH_VAR", "dflt"))
      p(Thread.current.fetch(:nope, :dflt))
      p(Array.new(2, :fill))

      # `$VERBOSE = nil` silences `rb_warn` entirely.
      $VERBOSE = nil
      p({ a: 1 }.fetch(:z, :dflt) { :blk })
      $VERBOSE = false
    RUBY

    _(result).must_answer <<~'OUT', stderr: <<~'ERR'
      [:blk, 9]
      [:blk, :z]
      "blk ZEO_NO_SUCH_VAR"
      [:blk, :nope]
      [0, 1, 2]
      1
      1
      [:blk, 9]
      [:blk, :z]
      "blk ZEO_NO_SUCH_VAR"
      [:blk, :nope]
      [0, 2, 4]
      :dflt
      :dflt
      "dflt"
      :dflt
      [:fill, :fill]
      :blk
    OUT
      core/hash/blocks_test.rb:8: warning: block supersedes default value argument
      core/hash/blocks_test.rb:9: warning: block supersedes default value argument
      core/hash/blocks_test.rb:10: warning: block supersedes default value argument
      core/hash/blocks_test.rb:11: warning: block supersedes default value argument
      core/hash/blocks_test.rb:12: warning: block supersedes default value argument
      core/hash/blocks_test.rb:15: warning: block supersedes default value argument
      core/hash/blocks_test.rb:16: warning: block supersedes default value argument
    ERR
  end

  it "forwarded block stored" do
    result = ze0(<<~'RUBY')
      $p007 = nil
      def store007(&b007); $p007 = b007; end
      def outer007(&b007); store007(&b007); end

      n007 = 0
      outer007 { n007 += 1 }
      $p007.call
      puts "n=#{n007}"
      $p007.call
      puts "n=#{n007}"

      def inner008(&b); b.call; end
      def outer008(&b); inner008(&b); end
      m = 0
      outer008 { m += 2 }
      puts "m=#{m}"

      def deep009(&b); $q = b; end
      def mid009(&b); deep009(&b); end
      def top009(&b); mid009(&b); end
      k = 0
      top009 { k += 5 }
      $q.call
      puts "k=#{k}"
    RUBY

    _(result).must_answer <<~'OUT'
      n=1
      n=2
      m=2
      k=5
    OUT
  end

  it "map, transform_values, select and reject take a block whatever the key and value types are" do
    result = ze0(<<~'RUBY')
      # Hash block methods (map / each_value / transform_values / select /
      # reject) across the typed-hash variants. sym_int variants already
      # worked; this fills in the str_int / sym_str / str_str arms that
      # previously fell through to the unresolved-call path.
      puts({a: 1, b: 2}.map { |k, v| v * 10 }.inspect)
      puts({a: 1, b: 2}.transform_values { |v| v * 10 }.inspect)
      puts({a: 1, b: 2, c: 3}.select { |k, v| v > 1 }.inspect)
      puts({"a" => 1, "b" => 2}.map { |k, v| v * 10 }.inspect)
      puts({"a" => 1, "b" => 2}.transform_values { |v| v * 10 }.inspect)
      puts({a: "x", b: "y"}.map { |k, v| v }.inspect)
      puts({a: "x", b: "y"}.transform_values { |v| v + "!" }.inspect)
      puts({"a" => "x", "b" => "y"}.map { |k, v| v }.inspect)
      puts({"a" => "x", "b" => "y"}.transform_values { |v| v + "!" }.inspect)
      {a: 1, b: 2}.each_value { |v| puts v }
      {"a" => 1}.each_value { |v| puts v }
    RUBY

    _(result).must_answer <<~'OUT'
      [10, 20]
      {a: 10, b: 20}
      {b: 2, c: 3}
      [10, 20]
      {"a" => 10, "b" => 20}
      ["x", "y"]
      {a: "x!", b: "y!"}
      ["x", "y"]
      {"a" => "x!", "b" => "y!"}
      1
      2
      1
    OUT
  end

  it "default_proc answers the Hash.new block as a Proc, or nil" do
    result = ze0(<<~'RUBY')
      # Hash#default_proc wraps the stored Hash.new{} block as a first-class Proc
      # (nil for a hash without one); calling it drives the original block. Proc
      # inspect carries a heap address, so the pin checks nil-ness, callability,
      # and introspection rather than the printed form.
      h = Hash.new { |hash, k| hash[k] = k.to_s }
      p h.default_proc.nil?
      dp = h.default_proc
      p dp.lambda?
      p dp.arity
      p h[:x]
      p dp.call(h, :y)
      p h[:y]
      p({ a: 1 }.default_proc)
      h2 = { b: 2 }
      p h2.default_proc
      p h2.default_proc.nil?
      hs = Hash.new { |hash, k| hash[k] = k.upcase }
      hs["ab"] = "AB0"
      p hs["cd"]
      p hs.default_proc.nil?
      p hs.default_proc.call(hs, "ef")
      hp = Hash.new { |hash, k| hash[k] = [k, k] }
      hp[1] = [9]
      p hp[2]
      p hp.default_proc.nil?
    RUBY

    _(result).must_answer <<~'OUT'
      false
      false
      2
      "x"
      "y"
      "y"
      nil
      nil
      true
      "CD"
      false
      "EF"
      [2, 2]
      false
    OUT
  end

  it "default_proc= takes a lambda and a miss then calls it" do
    result = ze0(<<~'RUBY')
      # Hash#default_proc= with a lambda literal (KieranP #2371)
      h = {}
      h.default_proc = ->(hh, k) { k.to_s }
      p h[:x]
      h2 = { a: 1 }
      h2.default_proc = ->(hh, k) { 99 }
      p h2[:zzz]
      p h2[:a]
      h3 = { "a" => 1 }
      h3.default_proc = ->(hh, k) { "miss:" + k }
      p h3["q"]
      p h3["a"]
    RUBY

    _(result).must_answer <<~'OUT'
      "x"
      99
      1
      "miss:q"
      1
    OUT
  end

  it "default_proc= answers the proc, the way any assignment answers its right side" do
    result = ze0(<<~'RUBY')
      # An assignment's value is the right-hand side: `h.default_proc = p` answers
      # the proc. Answering the hash put an sp_XHash* into a Proc* slot (#3833).
      h = {}
      r = (h.default_proc = ->(hh, k) { k.to_s })
      p r.class
      p h[:missing]
      g = {}
      g.default_proc = ->(hh, k) { 0 }
      p g[:x]
      p g.default_proc.class
    RUBY

    _(result).must_answer <<~'OUT'
      Proc
      "missing"
      0
      Proc
    OUT
  end

  it "default with a key runs the default block, and without one answers the stored default" do
    result = ze0(<<~'RUBY')
      # Hash#default(key) invokes the default_proc with (self, key) when the hash
      # was built with a block; default() with no key, or a value-default hash,
      # returns the stored default object.
      h = Hash.new { |hash, k| k.to_s }
      p h.default(:foo)
      p h.default
      g = Hash.new(99)
      p g.default(:x)
      p g.default
    RUBY

    _(result).must_answer <<~'OUT'
      "foo"
      nil
      99
      99
    OUT
  end

  it "the block methods over an empty Hash answer empty" do
    result = ze0(<<~'RUBY')
      # Block-taking methods on an empty hash (KieranP #2336)
      h = {}
      p(h.select { |k, v| true })
      p(h.reject { |k, v| false })
      h.each { |k, v| }
      p h
      p({}.select { |k, v| true })          # direct literal too
      p({}.map { |k, v| v })
      p({}.reject { |k, v| false })
      p({}.count { |k, v| true })
      # narrowing still wins over the empty-{} default
      a = {}; a[:x] = 1
      p a
      b = {}; b["y"] = 2
      p b
      c = {}; c[3] = 4
      p c
    RUBY

    _(result).must_answer <<~'OUT'
      {}
      {}
      {}
      {}
      []
      {}
      0
      {x: 1}
      {"y" => 2}
      {3 => 4}
    OUT
  end

  it "fetch runs its block only on a miss" do
    result = ze0(<<~'RUBY')
      h_si = { a: 1, b: 2 }
      puts h_si.fetch(:a) { 99 }
      puts h_si.fetch(:missing) { 99 }

      h_ss = { x: "one", y: "two" }
      puts h_ss.fetch(:x) { "fallback" }
      puts h_ss.fetch(:missing) { "fallback" }

      h_sp = { a: 1, b: "two" }
      puts h_sp.fetch(:b) { "fallback" }
      puts h_sp.fetch(:missing) { "fallback" }

      h_str_int = { "a" => 1, "b" => 2 }
      puts h_str_int.fetch("a") { 99 }
      puts h_str_int.fetch("missing") { 99 }

      h_str_str = { "x" => "one", "y" => "two" }
      puts h_str_str.fetch("x") { "fallback" }
      puts h_str_str.fetch("missing") { "fallback" }

      h_str_p = { "a" => 1, "b" => "two" }
      puts h_str_p.fetch("b") { "fallback" }
      puts h_str_p.fetch("missing") { "fallback" }

      # block can be multi-statement
      result = h_si.fetch(:missing) {
        x = 10
        y = 20
        x + y
      }
      puts result
    RUBY

    _(result).must_answer <<~'OUT'
      1
      99
      one
      fallback
      two
      fallback
      1
      99
      one
      fallback
      two
      fallback
      30
    OUT
  end

  it "fetch yields the key it looked for" do
    result = ze0(<<~'RUBY')
      # Hash#fetch(key) { |k| ... } yields the looked-up key to the block on a
      # miss; on a hit it returns the stored value and the block is not run.
      # (int-keyed hashes; the param is the int key.)
      h = { 1 => 10, 2 => 20 }
      puts h.fetch(2) { |k| k * 100 }
      puts h.fetch(99) { |k| k * 100 }
      counts = { 5 => 1 }
      puts counts.fetch(7) { |missing| missing + 1 }
      puts "done"
    RUBY

    _(result).must_answer <<~'OUT'
      20
      9900
      8
      done
    OUT
  end

  it "the key fetch yields arrives as the Hash's own key type" do
    result = ze0(<<~'RUBY')
      # Hash#fetch(key) { |k| ... } yields the missing key to the block.
      # The block param must be typed as the hash's KEY type (sym / string /
      # int), not the default int, so block-body uses like k.to_s / k + "!"
      # dispatch correctly. Top-level calls exercise block_param_type_at;
      # the in-method assignment forms exercise scan_locals.

      # Top-level (block_param_type_at), distinct param names so each block
      # gets its own scope slot.
      puts({ 1 => 10 }.fetch(99) { |ka| ka * 100 })
      puts({ a: 10 }.fetch(:zzz) { |kb| kb.to_s })
      puts({ "a" => 10 }.fetch("zzz") { |kc| kc + "!" })

      # In-method, value consumed via an assignment RHS (scan_locals).
      def m_int
        r = { 1 => 10 }.fetch(99) { |k| k * 100 }
        r
      end

      def m_sym
        r = { a: 10 }.fetch(:zzz) { |k| k.to_s }
        r
      end

      def m_str
        r = { "a" => 10 }.fetch("zzz") { |k| k + "!" }
        r
      end

      def m_sym_concat
        r = { a: 10 }.fetch(:missing) { |k| "key=" + k.to_s }
        r
      end

      puts m_int
      puts m_sym
      puts m_str
      puts m_sym_concat
    RUBY

    _(result).must_answer <<~'OUT'
      9900
      zzz
      zzz!
      9900
      zzz
      zzz!
      key=missing
    OUT
  end

  it "none? and one? take a block over an integer-keyed Hash" do
    result = ze0(<<~'RUBY')
      # Hash#none? / #one? with a block on an Integer-keyed hash (KieranP #2346)
      p({ 1 => 10, 2 => 20 }.none? { |k, _v| k > 5 })
      p({ 1 => 10, 2 => 20 }.none? { |_k, v| v > 5 })
      p({ 1 => 10, 2 => 20 }.one? { |_k, v| v > 15 })
      p({ 1 => 10, 2 => 20 }.one? { |_k, v| v > 5 })
      p({ 1 => "a", 2 => "b" }.none? { |_k, v| v == "z" })
      p({ a: 1, b: 2 }.none? { |_k, v| v > 5 })
      p({ a: 1, b: 2 }.one? { |_k, v| v > 1 })
      p({ 1 => 10, 2 => 20 }.none? { |pair| pair[0] > 5 })
    RUBY

    _(result).must_answer <<~'OUT'
      true
      false
      true
      false
      true
      true
      true
      true
    OUT
  end

  it "merge resolves a conflicting key through its block" do
    result = ze0(<<~'RUBY')
      # Hash#merge with a conflict-resolution block. For colliding keys
      # the block sees (key, this-value, other-value); spinel's int
      # variant supports it.

      h1 = {a: 1, b: 2}
      h2 = {b: 99, c: 3}
      result = h1.merge(h2) { |k, v1, v2| v1 + v2 }
      puts result[:a]
      puts result[:b]   # 2 + 99 = 101
      puts result[:c]
    RUBY

    _(result).must_answer <<~'OUT'
      1
      101
      3
    OUT
  end

  it "the conflict block sees the receiver's default for a key it does not hold" do
    result = ze0(<<~'RUBY')
      # Hash#merge with a conflict block returns a fresh hash, which must inherit
      # the receiver's default value and default proc.
      left = { "a" => 1, "b" => "left" }
      left.default = "missing"
      value_result = left.merge({ "a" => 2, "c" => "other" }) { |key, old, new| old }
      p value_result["absent"]
      p value_result["a"]

      suffix = "!"
      proc_left = { "a" => 1, "b" => "left" }
      proc_left.default_proc = proc { |hh, key| hh[key] = key + suffix }
      proc_result = proc_left.merge({ "a" => 2, "c" => "other" }) { |key, old, new| new }
      GC.start
      p proc_result["absent"]
      p proc_result["a"]
      p proc_result.length

      # Exercise the dedicated PolyPolyHash block-form merge path too.
      poly_left = Hash.new { |hh, key| "poly:" + key.to_s }
      poly_left[1] = "one"
      poly_right = Hash.new { |hh, key| "other:" + key.to_s }
      poly_right[1] = "other"
      poly_result = poly_left.merge(poly_right) { |key, old, new| old }
      p poly_result[99]
      p poly_result[1]
    RUBY

    _(result).must_answer <<~'OUT'
      "missing"
      1
      "absent!"
      2
      4
      "poly:99"
      "one"
    OUT
  end

  it "min, max, min_by, max_by and find over the pairs" do
    result = ze0(<<~'RUBY')
      # Hash#min_by / #max_by / #find / #detect yield each |key, value| pair and
      # return the winning [key, value] pair (or nil when nothing qualifies). Each
      # helper is monomorphic (one hash variant) so the runtime walk is exercised
      # without widening the parameter to poly.

      def min_v(h)     = h.min_by { |k, v| v }
      def max_v(h)     = h.max_by { |k, v| v }
      def min_v_str(h) = h.min_by { |k, v| v }
      def max_len(h)   = h.max_by { |k, v| v.length }
      def min_k_int(h) = h.min_by { |k, v| k }
      def find_v(h)    = h.find { |k, v| v == 2 }
      def find_gone(h) = h.find { |k, v| v > 99 }
      def find_k(h)    = h.find { |k, v| k == :b }
      def detect_v(h)  = h.detect { |k, v| v.even? }

      p min_v({ a: 3, b: 1, c: 2 })
      p max_v({ a: 3, b: 1, c: 2 })
      p min_v_str({ "a" => 3, "b" => 1 })
      p max_len({ a: "xx", b: "y", c: "zzz" })
      p min_k_int({ 3 => 30, 1 => 10, 2 => 20 })
      p find_v({ a: 1, b: 2, c: 3 })
      p find_gone({ a: 1, b: 2 })
      p find_k({ a: 1, b: 2 })
      p detect_v({ a: 1, b: 4, c: 3 })

      # The winning pair is a real array.
      pair = max_v({ a: 3, b: 7, c: 5 })
      p pair[0]
      p pair[1]
    RUBY

    _(result).must_answer <<~'OUT'
      [:b, 1]
      [:a, 3]
      ["b", 1]
      [:c, "zzz"]
      [1, 10]
      [:b, 2]
      nil
      [:b, 2]
      [:b, 4]
      :b
      7
    OUT
  end

  it "a default block whose value is an empty container compiles and stores" do
    result = ze0(<<~'RUBY')
      # Hash.new with a block whose body assigns a container default used to
      # miscompile: the empty `[]`/`{}` literal infers as an untyped value, so the
      # emitted default-proc declared `void _t = sp_IntArray_new()`. The value is
      # now boxed into an sp_RbVal temp, so container defaults compile and work.
      # (String/Integer keys are used so #inspect matches CRuby; a symbol-keyed
      #  Hash.new{} default still renders keys with `=>` -- tracked separately.)

      # array default
      words = Hash.new { |h, k| h[k] = [] }
      words["a"] << 1
      words["a"] << 2
      words["b"] << 3
      p words

      # integer default
      counts = Hash.new { |h, k| h[k] = 0 }
      counts["x"] += 1
      counts["x"] += 1
      counts["y"] += 5
      p counts

      # hash default (nested)
      nested = Hash.new { |h, k| h[k] = {} }
      nested["a"]["b"] = 1
      nested["a"]["c"] = 2
      p nested

      # the block value is returned (auto-vivification returns the new container)
      fresh = Hash.new { |h, k| h[k] = [] }
      fresh["z"].push(9)
      p fresh["z"]
    RUBY

    _(result).must_answer <<~'OUT'
      {"a" => [1, 2], "b" => [3]}
      {"x" => 2, "y" => 5}
      {"a" => {"b" => 1, "c" => 2}}
      [9]
    OUT
  end

  it "a default-block Hash keeps each key's own type through inspect" do
    result = ze0(<<~'RUBY')
      # Hash.new { |h,k| ... } must preserve the key type on inspect: a symbol key
      # renders as `a:`, a string key as `"a"=>`, an integer key as `1=>`. The
      # default-block hash is polymorphic by nature, so keys round-trip faithfully.
      sym = Hash.new { |h, k| h[k] = [] }
      sym[:a] << 1
      sym[:b] << 2
      sym[:a] << 3
      p sym

      str = Hash.new { |h, k| h[k] = [] }
      str["a"] << 1
      p str

      int = Hash.new { |h, k| h[k] = 0 }
      int[1] += 5
      int[2] += 7
      p int

      # accumulator idiom across many keys
      acc = Hash.new { |h, k| h[k] = [] }
      [:x, :y, :x, :z, :y, :x].each { |s| acc[s] << 1 }
      p acc

      # routed through a method param (defeats constant folding)
      def touch(h, k)
        h[k] << k.to_s
      end
      routed = Hash.new { |h, k| h[k] = [] }
      touch(routed, :a)
      touch(routed, :a)
      touch(routed, :b)
      p routed

      # mixed key types collapse to a faithful poly hash
      mix = Hash.new { |h, k| h[k] = 0 }
      mix[:a] += 1
      mix["b"] += 2
      mix[3] += 3
      p mix

      # reading a missing key runs the block and returns its value
      counts = Hash.new { |h, k| h[k] = k.to_s * 2 }
      p counts[:ab]
      p counts["cd"]
    RUBY

    _(result).must_answer <<~'OUT'
      {a: [1, 3], b: [2]}
      {"a" => [1]}
      {1 => 5, 2 => 7}
      {x: [1, 1, 1], y: [1, 1], z: [1]}
      {a: ["a", "a"], b: ["b"]}
      {a: 1, "b" => 2, 3 => 3}
      "abab"
      "cdcd"
    OUT
  end

  it "a default block ending in a write stores and answers the value" do
    result = ze0(<<~'RUBY')
      # Hash.new with a default block whose final expression is a value-producing
      # `h[k] = v` must store and return the assigned value (Ruby: `(h[k]=v)` => v).
      h = Hash.new { |hash, k| hash[k] = 0 }
      h[:a] += 1
      puts h[:a]
      puts h[:missing]

      hs = Hash.new { |hash, k| hash[k] = "missing" }
      puts hs[:x]
      puts hs[:x]

      # The explicit non-final workaround must keep working.
      hw = Hash.new { |hash, k| hash[k] = 0; 0 }
      hw[:a] += 1
      puts hw[:a]
      puts hw[:missing]
    RUBY

    _(result).must_answer <<~'OUT'
      1
      0
      missing
      missing
      1
      0
    OUT
  end

  it "default_proc is nil for a Hash built with a value rather than a block" do
    result = ze0(<<~'RUBY')
      r001 = (Hash.new(0).default_proc rescue $!.class); p r001
      p(Hash.new.default_proc)
      p(Hash.new("x").default_proc)
      h004 = Hash.new(0)
      p(h004.default_proc)
      p({}.default_proc)
      h = Hash.new { |hh, k| hh[k] = k.to_s }
      p h.default_proc.class
    RUBY

    _(result).must_answer <<~'OUT'
      nil
      nil
      nil
      nil
      nil
      Proc
    OUT
  end

  it "a value default is not stored where a block default may store" do
    result = ze0(<<~'RUBY')
      h = Hash.new(0)
      h[:a] += 1
      h[:a] += 1
      p h[:a]
      p h[:z]
      p h.size
      d = Hash.new { |hh, k| hh[k] = k.to_s }
      p d[:q]
      p d
    RUBY

    _(result).must_answer <<~'OUT'
      2
      0
      1
      "q"
      {q: "q"}
    OUT
  end

  it "select, reject and find take a block whose body is nil" do
    result = ze0(<<~'RUBY')
      # The nil-block-body family on a HASH receiver. The array arms were fixed with
      # the empty-block desugar (#4006), but a Hash reaches its own emitters, and
      # they had the same holes:
      #
      #   {a: 1}.select { nil }  # error: used struct type value where scalar is required
      #   {a: 1}.reject {}       # error: wrong type argument to unary exclamation mark
      #   {a: 1}.find { nil }    # error: used struct type value where scalar is required
      #
      # A body whose value IS nil types VOID/NIL: neither a boxed value to ask
      # sp_poly_truthy about nor a scalar to test. It is statically FALSY, so select
      # keeps nothing, reject keeps everything, and find never wins -- and the body
      # still runs, for its effects.
      h = { a: 1, b: 2 }
      p h.select { nil }
      p h.reject { nil }
      p h.select {}
      p h.reject {}
      p h.find { nil }
      p h.find {}
      p h.detect { nil }
      p h.filter { nil }

      # min_by / max_by over a hash compare through the ORDERING entry, not the
      # Comparable operator: a key that is always nil ties everywhere, so the first
      # entry wins rather than the comparison failing
      p h.min_by { nil }
      p h.max_by { nil }
      p h.min_by {}
      p h.max_by {}

      # side effects in a falsy body still happen
      seen = []
      h.select { seen << 1; nil }
      p seen

      # and the ordinary predicates keep working
      p h.select { |k, v| v > 1 }
      p h.reject { |k, v| v > 1 }
      p h.find { |k, v| v > 1 }
      p h.min_by { |k, v| -v }
      p h.max_by { |k, v| -v }
    RUBY

    _(result).must_answer <<~'OUT'
      {}
      {a: 1, b: 2}
      {}
      {a: 1, b: 2}
      nil
      nil
      nil
      {}
      [:a, 1]
      [:a, 1]
      [:a, 1]
      [:a, 1]
      [1, 1]
      {b: 2}
      {a: 1}
      [:b, 2]
      [:b, 2]
      [:a, 1]
    OUT
  end

  it "||= through a subscript does not evaluate its right side for a key already there" do
    result = ze0(<<~'RUBY')
      # The cycle this program builds on purpose, and the census it leaves
      # behind. A cycle alive at exit is not a defect: it is a ring the
      # program never broke, so the census below is recorded as an
      # observation rather than gated on.
      #
      # `f = ->(n) { memo[n] ||= f.call(...) }` -- a lambda reaching itself through a captured local.
      # At exit: cycle leak: 4 objects (cell x2, Hash x1, Proc x1)
      # `h[k] ||= rhs` must not evaluate any part of rhs when the key is present:
      # a memoizing lambda whose rhs calls itself twice otherwise recurses forever.
      memo = { 0 => 0, 1 => 1 }
      f = nil
      f = ->(n) { memo[n] ||= f.call(n - 1) + f.call(n - 2) }
      p f.call(2)
      p f.call(10)
      p memo[10]

      # &&= on the same shape
      seen = { "a" => 1 }
      g = ->(k) { seen[k] &&= seen[k] + 100 }
      p g.call("a")
      p g.call("b")
      p seen

      # a string-keyed hash, and a plain local ||= with a call on the right
      counts = {}
      def bump(h, k)
        h[k] ||= expensive(k)
      end
      def expensive(k)
        puts "computing #{k}"
        k.length
      end
      p bump(counts, "xy")
      p bump(counts, "xy")
      p counts

      arr = [nil, 2]
      arr[0] ||= 41
      p arr
    RUBY

    _(result).must_answer <<~'OUT'
      1
      55
      55
      101
      nil
      {"a" => 101}
      computing xy
      2
      2
      {"xy" => 2}
      [41, 2]
    OUT
  end

  it "a one-parameter block takes the pair, except on select and reject which take the key" do
    result = ze0(<<~'RUBY')
      # A SOLO block param on Hash Enumerables receives what CRuby yields it:
      # the [k, v] PAIR for each/each_pair/map/find/sort_by/group_by/sum (their
      # each yields one pair, auto-splat serves 2-param blocks), but the KEY for
      # Hash#select/#reject (their own iterators yield k, v). Also the blockless
      # Hash#each_with_index enumerator ([[k, v], i] pairs), and the mode-0 solo
      # key binding no longer types the slot as the VALUE (a latent compile
      # failure for select { |k| } on a sym-keyed hash).
      h = { a: 1, b: 2 }
      p h.map { |pair| pair }
      p h.each_pair.map { |pair| pair }
      p h.find { |pair| pair[1] == 2 }
      p h.sort_by { |pair| -pair[1] }
      p h.sum(0) { |pair| pair[1] }
      p h.map { |k, v| [k, v] }
      p h.select { |k| k == :a }
      p h.reject { |k| k == :a }
      p h.each_with_index.to_a
    RUBY

    _(result).must_answer <<~'OUT'
      [[:a, 1], [:b, 2]]
      [[:a, 1], [:b, 2]]
      [:b, 2]
      [[:b, 2], [:a, 1]]
      3
      [[:a, 1], [:b, 2]]
      {a: 1}
      {b: 2}
      [[[:a, 1], 0], [[:b, 2], 1]]
    OUT
  end

  it "sum with no block needs a seed the pairs can add to" do
    result = ze0(<<~'RUBY')
      # Hash#sum without a block on a variable receiver: an empty hash returns the
      # init value (0 by default); a non-empty hash raises TypeError (init + [k,v]).
      h = {}
      p h.sum
      p h.sum(5)
      g = { 1 => 2 }
      begin
        g.sum
      rescue => e
        p e.class
      end
    RUBY

    _(result).must_answer <<~'OUT'
      0
      5
      TypeError
    OUT
  end

  it "keyword params on a block bind from a trailing yielded hash" do
    result = ze0(<<~'RUBY')
      class Collector
        def emit
          yield x: 1, y: 2
        end
      end
      Collector.new.emit { |x:, y: 10| puts x + y }
    RUBY

    _(result).must_answer "3\n"
  end

  it "new forwarded block stored" do
    result = ze0(<<~'RUBY')
      # A forwarded `&proc` into a class whose `initialize` stores the block
      # (`def initialize(&blk); @blk = blk; end`) threads the proc value into the
      # constructor, and a later `@blk.call` returns the right value for every body
      # return type -- faithful now that a proc's result rides the universal boxed
      # return channel (this used to be a loud compile reject).
      class Box
        def initialize(&blk)
          @blk = blk
        end

        def has_block?
          !@blk.nil?
        end

        def run(x)
          @blk.call(x)
        end
      end

      pr = ->(n) { n * 2 }
      p Box.new(&pr).run(21)          # 42  (int return)

      # String and array returns exercise the boxed channel for non-int results.
      sr = ->(n) { "n=#{n}" }
      p Box.new(&sr).run(7)           # "n=7"

      ar = ->(n) { [n, n * 2] }
      p Box.new(&ar).run(3)           # [3, 6]

      # A lambda literal forwarded directly with &.
      p Box.new(&->(n) { n + 100 }).run(5)   # 105

      # An omitted block: the stored @blk is nil.
      p Box.new.has_block?            # false
      p Box.new(&pr).has_block?       # true

      # A proc (not lambda) forwarded.
      inc = proc { |n| n + 1 }
      p Box.new(&inc).run(9)          # 10

      # Forwarding into an initialize that also takes a positional arg.
      class Labeled
        def initialize(label, &blk)
          @label = label
          @blk = blk
        end

        def call(x)
          "#{@label}=#{@blk.call(x)}"
        end
      end

      dbl = ->(n) { n * 2 }
      puts Labeled.new("twice", &dbl).call(21)   # twice=42

      # A proc pulled from a poly slot (a container element, a to-be-erased value)
      # arrives boxed rather than as a bare sp_Proc*; forwarding it with & must unbox
      # it into the stored block, not silently thread a NULL block.
      procs = [->(n) { n * 2 }, ->(n) { n + 100 }]
      p Box.new(&procs[0]).run(21)    # 42
      p Box.new(&procs[1]).run(5)     # 105

      table = { double: ->(n) { n * 2 }, negate: ->(n) { -n } }
      p Box.new(&table[:double]).run(6)   # 12
      p Box.new(&table[:negate]).run(6)   # -6

      # A poly-carried non-lambda proc forwarded, and one alongside a positional arg.
      plain = [proc { |n| n + 1 }]
      p Box.new(&plain[0]).run(9)                    # 10
      puts Labeled.new("via", &procs[0]).call(4)     # via=8
    RUBY

    _(result).must_answer <<~'OUT'
      42
      "n=7"
      [3, 6]
      105
      false
      true
      10
      twice=42
      42
      105
      12
      -6
      10
      via=8
    OUT
  end

  it "stored block call returns value" do
    result = ze0(<<~'RUBY')
      # A block stored into an ivar (`@blk = blk`) is type-erased into a generic
      # sp_Proc*; a later `@blk.call` reads the boxed poly return slot
      # (_sp_proc_poly_ret). The block must therefore use the poly return ABI even
      # when its body yields a scalar -- otherwise the proc returns the int directly
      # and the generic call site reads a stale nil (printed 0).
      class Holder
        def store(&blk)
          @blk = blk
        end
        def fire
          @blk.call
        end
      end

      h = Holder.new
      h.store { 42 }
      puts h.fire           # 42
      h.store { 7 + 8 }
      puts h.fire           # 15
    RUBY

    _(result).must_answer "42\n15\n"
  end

  it "struct to h block" do
    result = ze0(<<~'RUBY')
      # Struct#to_h with a block yields each (member_symbol, value) pair and
      # builds a hash from the [k, v] arrays the block returns. Values are
      # asserted via key lookup rather than Hash#inspect so the test does not
      # depend on the `=>` inspect spacing, which differs across Ruby versions.
      Person = Struct.new(:name, :age)
      p = Person.new("Alice", 30)
      h = p.to_h { |name, val| [name.to_s, val] }
      puts h["name"]
      puts h["age"]
      puts h.size

      Point = Struct.new(:x, :y)
      pt = Point.new(3, 4)
      # transform the value too
      h2 = pt.to_h { |k, v| [k.to_s, v * 2] }
      puts h2["x"]
      puts h2["y"]

      # both elements stringified (block returns a str_array)
      h3 = pt.to_h { |k, v| [k.to_s, v.to_s] }
      puts h3["x"]
      puts h3["y"]

      # heterogeneous members (string, int, bool)
      Rec = Struct.new(:label, :count, :on)
      r = Rec.new("widget", 7, true)
      h4 = r.to_h { |k, v| [k.to_s, v] }
      puts h4["label"]
      puts h4["count"]
      puts h4["on"]
    RUBY

    _(result).must_answer <<~'OUT'
      Alice
      30
      2
      6
      8
      3
      4
      widget
      7
      true
    OUT
  end

  it "struct to h block composite" do
    result = ze0(<<~'RUBY')
      P001 = Struct.new(:x, :y)
      p(P001.new(1, 2).to_h { |k001, v001| [k001, [v001]] })
      P002 = Struct.new(:a)
      p(P002.new(7).to_h { |k, v| [k, {v => 1}] })
      p(P001.new(1, 2).to_h { |k, v| [k, v * 10] })
      p({x: 1}.to_h { |k, v| [k, [v]] })
      D001 = Data.define(:m, :n)
      p(D001.new(m: 1, n: 2).to_h { |k, v| [k, [v, v]] })
      S002 = Struct.new(:s)
      p(S002.new("q").to_h { |k, v| [k, [v]] })
    RUBY

    _(result).must_answer <<~'OUT'
      {x: [1], y: [2]}
      {a: {7 => 1}}
      {x: 10, y: 20}
      {x: [1]}
      {m: [1, 1], n: [2, 2]}
      {s: ["q"]}
    OUT
  end

  it "struct to h block key" do
    result = ze0(<<~'RUBY')
      # Struct#to_h { |k, v| [nk, nv] } whose new key is neither a Symbol nor a
      # String fell back to a string-keyed hash, so the key went into a const char *
      # slot and the C did not compile.
      P = Struct.new(:x, :y)
      p(P.new(1,2).to_h { |k,v| [v,k] })
      p(P.new(1,2).to_h)
      p(P.new(1,2).to_h { |k,v| [k.to_s, v] })
      p(P.new(1,2).to_h { |k,v| [k, v*2] })
    RUBY

    _(result).must_answer <<~'OUT'
      {1 => :x, 2 => :y}
      {x: 1, y: 2}
      {"x" => 1, "y" => 2}
      {x: 2, y: 4}
    OUT
  end
end
