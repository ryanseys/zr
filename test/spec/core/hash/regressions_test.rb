# frozen_string_literal: true

require "spec_helper"

describe "Hash: regressions" do
  it "empty hash promote" do
    result = ze0(<<~'RUBY')
      # Empty hash literal whose first []= write pins a different key/value
      # type pair than the str_int_hash default. Pre-fix: declaration ran
      # before any []= so `h = {}; h[1] = "one"` got declared as
      # sp_StrIntHash and the int-keyed []= failed to compile.

      # Empty -> string keys, int values (matches str_int_hash default; works pre-fix)
      h1 = {}
      h1["k"] = 1
      h1["m"] = 2
      puts h1["k"]
      puts h1["m"]
      puts h1.length

      # Empty -> string keys, string values
      h2 = {}
      h2["x"] = "alpha"
      h2["y"] = "beta"
      puts h2["x"]
      puts h2["y"]
      puts h2.length

      # Empty -> int keys, string values
      h3 = {}
      h3[1] = "one"
      h3[2] = "two"
      puts h3[1]
      puts h3[2]
      puts h3.length

      # Empty -> sym keys, int values
      h4 = {}
      h4[:a] = 10
      h4[:b] = 20
      puts h4[:a]
      puts h4[:b]
      puts h4.length

      # Empty -> sym keys, string values
      h5 = {}
      h5[:name] = "ada"
      h5[:role] = "scientist"
      puts h5[:name]
      puts h5[:role]
      puts h5.length
    RUBY

    _(result).must_answer <<~'OUT'
      1
      2
      2
      alpha
      beta
      2
      one
      two
      2
      10
      20
      2
      ada
      scientist
      2
    OUT
  end

  it "hash" do
    result = ze0(<<~'RUBY')
      # Test Hash support

      # Hash literal
      h = {}
      h["one"] = 1
      h["two"] = 2
      h["three"] = 3
      puts h["two"]    # 2
      puts h.length    # 3

      # Iteration
      h.each do |k, v|
        puts k
      end

      # keys
      puts h.keys.length  # 3

      # has_key?
      if h.has_key?("two")
        puts "found"
      end

      # delete
      h.delete("two")
      puts h.length  # 2
    RUBY

    _(result).must_answer <<~'OUT'
      2
      3
      one
      two
      three
      3
      found
      2
    OUT
  end

  it "hash delete order" do
    result = ze0(<<~'RUBY')
      # Regression test: Hash#delete must compact the insertion-order array
      # so that subsequent #keys / #values / each iteration skip the deleted
      # entry. The Robin Hood backing array was being repaired correctly on
      # delete but the parallel `order[]` array was not, so #keys returned the
      # stale key and #values returned a zero / NULL slot for it.

      # String keys
      sh = {"a" => 1, "b" => 2, "c" => 3}
      sh.delete("b")
      puts sh.keys.inspect          # ["a", "c"]
      puts sh.values.inspect        # [1, 3]
      puts sh.length                # 2

      # Symbol keys (the path that exposed the bug via PR #246)
      yh = {a: 1, b: 2, c: 3}
      yh.delete(:b)
      puts yh.keys.inspect          # [:a, :c]
      puts yh.values.inspect        # [1, 3]

      # Delete first / last entries (boundary cases for the shift loop)
      fh = {a: 1, b: 2, c: 3}
      fh.delete(:a)
      puts fh.keys.inspect          # [:b, :c]

      lh = {a: 1, b: 2, c: 3}
      lh.delete(:c)
      puts lh.keys.inspect          # [:a, :b]
    RUBY

    _(result).must_answer <<~'OUT'
      ["a", "c"]
      [1, 3]
      2
      [:a, :c]
      [1, 3]
      [:b, :c]
      [:a, :b]
    OUT
  end

  it "hash keys each" do
    result = ze0(<<~'RUBY')
      # Test hash.keys.each fusion for all hash types

      # int_str_hash: integer keys
      h1 = {3 => "Fizz", 5 => "Buzz", 7 => "Bazz"}
      h1.keys.each do |ki|
        puts ki
      end
      # => 3 5 7

      # str_str_hash: string keys
      h2 = {"a" => "apple", "b" => "banana", "c" => "cherry"}
      h2.keys.each do |ks|
        puts ks
      end
      # => a b c

      # str_int_hash: string keys, integer values
      h3 = {"x" => 10, "y" => 20, "z" => 30}
      h3.keys.each do |ks2|
        puts ks2
      end
      # => x y z

      # body reads value via lookup
      total = 0
      {10 => "ten", 20 => "twenty", 30 => "thirty"}.keys.each do |n|
        total = total + n
      end
      puts total
      # => 60

      # common pattern: conditional accumulation
      map = {3 => "Fizz", 5 => "Buzz"}
      output = ""
      map.keys.each do |d|
        if 15 % d == 0
          output = output + map[d]
        end
      end
      puts output
      # => FizzBuzz

      # no block param
      count = 0
      {"a" => 1, "b" => 2}.keys.each do
        count = count + 1
      end
      puts count
      # => 2
    RUBY

    _(result).must_answer <<~'OUT'
      3
      5
      7
      a
      b
      c
      x
      y
      z
      60
      FizzBuzz
      2
    OUT
  end

  it "hash transform keys" do
    result = ze0(<<~'RUBY')
      # Hash#transform_keys for str_int_hash. The block runs once per key,
      # its return value becomes the new key. Mirrors transform_values'
      # shape (which already shipped) but on the key axis.

      # Identity transform — keys unchanged
      h1 = {"alpha" => 1, "beta" => 2}
      puts h1.transform_keys { |k| k }["alpha"]
      puts h1.transform_keys { |k| k }["beta"]

      # Upcase keys
      h2 = {"hello" => 10, "world" => 20}
      upper = h2.transform_keys { |k| k.upcase }
      puts upper["HELLO"]
      puts upper["WORLD"]
      puts upper.has_key?("hello")
      puts upper.has_key?("HELLO")

      # Concat suffix
      h3 = {"a" => 100, "b" => 200}
      suff = h3.transform_keys { |k| k + "_x" }
      puts suff["a_x"]
      puts suff["b_x"]

      # Empty hash transform
      empty = {}
      empty["k"] = 1
      empty.delete("k")
      puts empty.transform_keys { |k| k.upcase }.length

      # Length preserved
      big = {"one" => 1, "two" => 2, "three" => 3}
      puts big.transform_keys { |k| k + "!" }.length
    RUBY

    _(result).must_answer <<~'OUT'
      1
      2
      10
      20
      false
      true
      100
      200
      0
      3
    OUT
  end

  it "hash transform values" do
    result = ze0(<<~'RUBY')
      # Hash#transform_values across hash variants. The block runs once
      # per value, its return becomes the new value, keys and order
      # preserved. str_int_hash already shipped; this covers int_str_hash
      # and sym_int_hash.

      # === sym_int_hash variant ===
      # `{a: 1, b: 2}` parses as sym→int. transform_values keeps the
      # key set and feeds each value through the block. p on the result
      # uses the new sp_SymIntHash_inspect helper to print the hash in
      # Ruby's `{a: V, b: V, ...}` form.
      p({a: 1, b: 2}.transform_values { |v| v * 10 })
      p({x: 5, y: 10, z: 15}.transform_values { |v| v + 100 })
      puts({a: 1, b: 2, c: 3}.transform_values { |v| v * v }[:c])
      puts({foo: 7}.transform_values { |v| v - 2 }[:foo])

      # Non-destructive — original hash retains its values; result is a
      # fresh hash. transform_values must not mutate the receiver.
      hh = {a: 1, b: 2}
      hh2 = hh.transform_values { |v| v * 100 }
      p hh         # {a: 1, b: 2}
      p hh2        # {a: 100, b: 200}

      # === int_str_hash variant ===

      # Identity transform — values unchanged
      h1 = {1 => "alpha", 2 => "beta"}
      puts h1.transform_values { |v| v }[1]
      puts h1.transform_values { |v| v }[2]

      # Upcase values
      h2 = {1 => "hello", 2 => "world"}
      upper = h2.transform_values { |v| v.upcase }
      puts upper[1]
      puts upper[2]

      # String concat
      h3 = {1 => "a", 2 => "b", 3 => "c"}
      suff = h3.transform_values { |v| v + "!" }
      puts suff[1]
      puts suff[2]
      puts suff[3]

      # Length preserved across transform
      big = {10 => "one", 20 => "two", 30 => "three"}
      puts big.transform_values { |v| v + "?" }.length

      # Empty block maps every value to nil (CRuby parity).
      # For int_str_hash the value type is `const char *`; nil → NULL.
      empty = {1 => "alpha", 2 => "beta"}.transform_values { }
      puts empty[1].nil?
      puts empty[2].nil?
      puts empty.length
    RUBY

    _(result).must_answer <<~'OUT'
      {a: 10, b: 20}
      {x: 105, y: 110, z: 115}
      9
      5
      {a: 1, b: 2}
      {a: 100, b: 200}
      alpha
      beta
      HELLO
      WORLD
      a!
      b!
      c!
      3
      true
      true
      2
    OUT
  end

  it "int str hash" do
    result = ze0(<<~'RUBY')
      # Test integer-keyed string-valued hash (sp_IntStrHash)
      # Regression: previously segfaulted — codegen emitted sp_StrStrHash,
      # causing sp_str_hash() to dereference integer keys as pointers.

      # Literal creation and lookup
      h = {3 => "Fizz", 5 => "Buzz", 7 => "Bazz"}
      puts h[3]          # Fizz
      puts h[5]          # Buzz
      puts h[7]          # Bazz
      puts h[1]          # (empty)

      # has_key?
      puts h.has_key?(3)   # true
      puts h.has_key?(4)   # false

      # length
      puts h.length        # 3

      # keys returns int array
      puts h.keys.length   # 3
      puts h.keys[0]       # 3

      # values
      puts h.values[0]     # Fizz

      # keys.each iteration
      h.keys.each do |k|
        puts k
      end

      # each iteration (key, value)
      h.each do |k, v|
        puts "#{k}:#{v}"
      end

      # []= assignment
      h[15] = "FizzBuzz"
      puts h[15]           # FizzBuzz
      puts h.length        # 4

      # fetch with default
      puts h.fetch(3, "none")   # Fizz
      puts h.fetch(99, "none")  # none

      # FizzBuzz pattern — the original failing case
      map = {3 => "Fizz", 5 => "Buzz"}
      (1..15).each do |x|
        out = ""
        map.keys.each do |k|
          out += map[k] if x % k == 0
        end
        out = x.to_s if out.empty?
        puts out
      end
    RUBY

    _(result).must_answer <<~'OUT'
      Fizz
      Buzz
      Bazz

      true
      false
      3
      3
      3
      Fizz
      3
      5
      7
      3:Fizz
      5:Buzz
      7:Bazz
      FizzBuzz
      4
      Fizz
      none
      1
      2
      Fizz
      4
      Buzz
      Fizz
      7
      8
      Fizz
      Buzz
      11
      Fizz
      13
      14
      FizzBuzz
    OUT
  end

  it "hash dup str int str" do
    result = ze0(<<~'RUBY')
      # Hash#dup was missing from the str_str_hash and int_str_hash codegen
      # dispatch tables -- the runtime helpers exist (sp_StrStrHash_dup,
      # sp_IntStrHash_dup) but the codegen arms didn't dispatch to them, so
      # `m = h.dup` lowered to `cannot resolve call to 'dup' on str_str_hash
      # (emitting 0)` and subsequent `.length` / `[]=` / `.each` calls on
      # the int-typed `0` segfaulted at runtime.
      #
      # Sibling Hash variants (sym_int / sym_str / sym_poly / str_int /
      # str_poly) already had dup arms; this closes the coverage gap.
      # Issue #592.

      # str_str_hash
      h1 = {"a" => "1", "b" => "2"}
      m1 = h1.dup
      m1["c"] = "3"
      puts h1.length          # 2
      puts m1.length          # 3
      puts m1["a"]            # 1
      puts m1["c"]            # 3

      # int_str_hash
      h2 = {1 => "one", 2 => "two"}
      m2 = h2.dup
      m2[3] = "three"
      puts h2.length          # 2
      puts m2.length          # 3
      puts m2[1]              # one
      puts m2[3]              # three

      # Verify the dup is independent (original unchanged).
      puts h1.has_key?("c")   # false
      puts h2.has_key?(3)     # false
    RUBY

    _(result).must_answer <<~'OUT'
      2
      3
      1
      3
      2
      3
      one
      three
      false
      false
    OUT
  end

  it "hash each block param types" do
    result = ze0(<<~'RUBY')
      # `h.each do |k, v|` previously had its block params typed via
      # elem_type_of_array(recv_type), which only knows about typed
      # arrays — for a hash receiver it fell back to "int" for both
      # `k` and `v`. Code inside the block like `puts k + ": " + v.to_s`
      # then had analyze cache (and codegen's infer_type fallback)
      # return "int" for the chained `+`, lowering `puts` to
      # `printf("%lld", (long long)(string_concat + int_to_s))` — both
      # the cast and the raw `+` between pointers fail C compile.
      #
      # Fix: block_param_type_at now branches on is_hash_type for the
      # `each` family and returns the hash's key part for pi==0 and the
      # value part for pi==1, expanded to full names (str→string,
      # sym→symbol). Codegen's infer_type CallNode cache-miss path also
      # learned `+` on string recv returns string and `.to_s` returns
      # string, covering nodes inside block bodies that walk_and_cache
      # doesn't cache.

      h = { "a" => 1, "b" => 2 }
      h.each do |k, v|
        puts k + ": " + v.to_s
      end
    RUBY

    _(result).must_answer <<~'OUT'
      a: 1
      b: 2
    OUT
  end

  it "hash merge cross variant" do
    result = ze0(<<~'RUBY')
      # Issue #661: Hash#merge across hash variants with different value
      # types. Previously the codegen used the receiver's prefix
      # unconditionally (sp_SymIntHash_merge(h1, h2) where h2 was
      # sp_SymStrHash *), failing C compile.
      #
      # Fix: when recv and arg are both sym-keyed (or both str-keyed) but
      # their value types differ, the analyzer pulls the call's return
      # type up to sym_poly_hash / str_poly_hash, and codegen promotes
      # both sides via the existing *_to_sym_poly / *_from_str_int_hash
      # converters before dispatching sp_*PolyHash_merge.

      # Sym + Sym with mixed value types.
      h1 = { a: 1, b: 2 }
      h2 = { c: "x", d: "y" }
      h3 = h1.merge(h2)
      puts h3[:a].inspect
      puts h3[:c].inspect

      # Str + Str with mixed value types.
      s1 = { "a" => 1, "b" => 2 }
      s2 = { "c" => "x", "d" => "y" }
      s3 = s1.merge(s2)
      puts s3["a"].inspect
      puts s3["c"].inspect

      puts "ok"
    RUBY

    _(result).must_answer <<~'OUT'
      1
      "x"
      1
      "x"
      ok
    OUT
  end

  it "hash new default value" do
    result = ze0(<<~'RUBY')
      # `Hash.new(default_value)` per-instance default support.
      #
      # Each hash variant struct (StrIntHash / StrStrHash / IntStrHash /
      # SymIntHash / SymStrHash / StrPolyHash / SymPolyHash / PolyPolyHash)
      # gains a `default_v` field. `_new` initializes it to the variant's
      # sentinel zero (so legacy `{}` literals unchanged); `_new_with_default`
      # is a new constructor that sets the field. `_get` returns
      # `default_v` on miss; `_dup` / `_merge` propagate (merge inherits
      # the LEFT receiver's default per CRuby).
      #
      # Codegen routes `Hash.new(N)` through `_new_with_default` and
      # adds `Hash#default` / `Hash#default=` accessor arms to each
      # variant. The analyzer's `infer_call_type` arm picks the right
      # variant from the default's type (string → str_str_hash, int
      # / nil / bool → str_int_hash) and types `h.default` as the
      # value-slot type so `puts h.default` dispatches correctly.
      #
      # Block form `Hash.new { |h, k| ... }` (proc default) remains
      # deferred -- separate feature.
      #
      # Issue #600 puzzle 2.

      # Int default
      h = Hash.new(5)
      puts h[:a]              # 5
      puts h["x"]             # 5
      puts h.length           # 0
      puts h.key?(:a)         # false
      puts h.default          # 5

      # Modify default; existing key unaffected
      h.default = 99
      puts h["missing"]       # 99
      h["b"] = 10
      puts h["b"]             # 10
      puts h["c"]             # 99

      # String default
      s = Hash.new("none")
      puts s["x"]             # none
      puts s.default          # none

      # dup propagates default
      h2 = Hash.new(42)
      h2["a"] = 1
      d = h2.dup
      puts d.default          # 42
      puts d["never_set"]     # 42
      puts d.length           # 1
      puts d["a"]             # 1

      # merge inherits left default
      m = h2.merge({"x" => 100})
      puts m.default          # 42
      puts m["not_there"]     # 42

      # Hash.new(0) -- pre-existing lrama_features shape, default ==
      # sentinel, behaviour unchanged.
      counter = Hash.new(0)
      counter["x"] = counter["x"] + 1
      puts counter["x"]       # 1
      puts counter["z"]       # 0

      # Float default with int keys -- lands on the PolyPoly variant, which
      # previously had no default_v / _new_with_default at all, so
      # `Hash.new(0.0)` emitted `sp_PolyPolyHash_new_with_default(0.0)` and
      # failed C compilation (int-to-pointer conversion).
      f = Hash.new(0.0)
      f[1] += 2.5
      p f[1]                  # 2.5
      p f[7]                  # 0.0 (default for a missing key)
      p f.default             # 0.0
      f.default = 1.5
      p f[9]                  # 1.5
      fd = f.dup
      p fd[42]                # 1.5 (dup propagates default)
      fm = f.merge({2 => 3.5})
      p fm[2]                 # 3.5
      p fm[99]                # 1.5 (merge inherits left default)
    RUBY

    _(result).must_answer <<~'OUT'
      5
      5
      0
      false
      5
      99
      10
      99
      none
      none
      42
      42
      1
      1
      42
      42
      1
      0
      2.5
      0.0
      0.0
      1.5
      1.5
      3.5
      1.5
    OUT
  end

  it "hash or fallback missing key" do
    result = ze0(<<~'RUBY')
      # Issue #660: `hash[k] || rhs` on a typed-hash receiver must return
      # rhs when the key is missing -- not the value-type zero (0 / "").
      #
      # Background: typed hash variants (sp_StrIntHash, sp_StrStrHash, ...)
      # materialize the value type's zero as the missing-key default. Combined
      # with the `||` truthy-lhs ternary lowering, the rhs arm was unreachable:
      # 0 / "" are truthy in Ruby, so the always-present zero short-circuited
      # the fallback.
      #
      # Fix: compile_or detects `hash[k]` on a typed-hash recv and rewrites
      # to `has_key(h, k) ? get(h, k) : rhs`. Poly-hash variants already
      # return sp_box_nil on miss, so they keep the legacy truthy lowering.

      # Empty hash, no writes (inferred str_int_hash).
      h1 = {}
      puts (h1[:missing] || "fallback")

      # String-valued hash via prior write.
      h2 = {}
      h2[:set_key] = "value"
      puts (h2[:missing] || "fallback")

      # Int-valued hash via prior write -- the missing-key 0 used to win.
      h3 = {}
      h3[:set] = 1
      puts (h3[:missing] || -1)

      # Present key returns the value, not the fallback.
      h4 = {}
      h4[:found] = "got it"
      puts (h4[:found] || "fallback")
    RUBY

    _(result).must_answer <<~'OUT'
      fallback
      fallback
      -1
      got it
    OUT
  end

  it "comparable clamp string" do
    result = ze0(<<~'RUBY')
      # Issue #899: Comparable#clamp on a string receiver via strcmp.
      puts "b".clamp("a", "c")
      puts "z".clamp("a", "c")
      puts "a".clamp("b", "c")
    RUBY

    _(result).must_answer <<~'OUT'
      b
      c
      b
    OUT
  end

  it "file separator constants" do
    result = ze0(<<~'RUBY')
      # Issue #891: File::SEPARATOR / PATH_SEPARATOR / ALT_SEPARATOR
      # resolved at compile time as string literals.
      puts File::SEPARATOR
      puts File::PATH_SEPARATOR
      puts "a" + File::SEPARATOR + "b"
    RUBY

    _(result).must_answer <<~'OUT'
      /
      :
      a/b
    OUT
  end

  it "hash fetch int int" do
    result = ze0(<<~'RUBY')
      # Hash#fetch on an int->int specialized hash: plain lookup and the 2-arg
      # default form (the int->int variant previously had #[] but not #fetch).
      h = { 1 => 10, 2 => 20 }
      puts h.fetch(1)
      puts h.fetch(2)
      puts h.fetch(9, -1)
      puts h.fetch(0, 42)
      puts "done"
    RUBY

    _(result).must_answer <<~'OUT'
      10
      20
      -1
      42
      done
    OUT
  end

  it "a lazy select or reject over an endless range answers its first n" do
    result = ze0(<<~'RUBY')
      puts (1..Float::INFINITY).lazy.select { |x| x.odd? }.first(5).inspect
      puts (1..Float::INFINITY).lazy.select { |x| x % 3 == 0 }.first(4).inspect
      puts (1..Float::INFINITY).lazy.reject { |x| x.even? }.first(5).inspect
      puts (1..Float::INFINITY).lazy.first(3).inspect
      puts (10..Float::INFINITY).lazy.select { |x| x.even? }.first(3).inspect
      puts (1..100).lazy.select { |x| x % 7 == 0 }.first(3).inspect
      puts (1..Float::INFINITY).lazy.select { |x| x > 5 }.first
    RUBY

    _(result).must_answer <<~'OUT'
      [1, 3, 5, 7, 9]
      [3, 6, 9, 12]
      [1, 3, 5, 7, 9]
      [1, 2, 3]
      [10, 12, 14]
      [7, 14, 21]
      6
    OUT
  end

  it "Hash#to_proc answers a proc that looks a key up" do
    result = ze0(<<~'RUBY')
      h = {a: 1, b: 2}
      p = h.to_proc
      puts p.call(:a)
      puts p.call(:b)

      g = {"x" => 10, "y" => 20}.to_proc
      puts g.call("x")
      puts g.call("y")
    RUBY

    _(result).must_answer <<~'OUT'
      1
      2
      10
      20
    OUT
  end

  it "a proc fills its missing parameters with nil" do
    result = ze0(<<~'RUBY')
      p = Proc.new { |a, b| puts "a=#{a.inspect} b=#{b.inspect}" }
      p.call(1)
      p.call(1, 2)

      q = Proc.new { |x, y, z| puts "x=#{x} y=#{y} z=#{z}" }
      q.call(10)
      q.call(10, 20)
      q.call(10, 20, 30)
    RUBY

    _(result).must_answer <<~'OUT'
      a=1 b=nil
      a=1 b=2
      x=10 y= z=
      x=10 y=20 z=
      x=10 y=20 z=30
    OUT
  end

  it "a String range enumerates by succ, carrying into the next letter" do
    result = ze0(<<~'RUBY')
      puts ("a".."c").to_a.inspect
      puts ("A".."D").to_a.inspect
      puts ("aa".."ac").to_a.inspect
      puts ("az".."bb").to_a.inspect
      puts (1..3).to_a.inspect
    RUBY

    _(result).must_answer <<~'OUT'
      ["a", "b", "c"]
      ["A", "B", "C", "D"]
      ["aa", "ab", "ac"]
      ["az", "ba", "bb"]
      [1, 2, 3]
    OUT
  end

  it "kernel rand no arg float" do
    result = ze0(<<~'RUBY')
      # Kernel#rand without args returns Float in [0.0, 1.0).
      puts rand.class
      puts rand(100).class
      v = rand
      puts v >= 0.0 && v < 1.0
    RUBY

    _(result).must_answer <<~'OUT'
      Float
      Integer
      true
    OUT
  end

  it "kernel string coercion" do
    result = ze0(<<~'RUBY')
      # Issue #879: Kernel#String() coercion routes through .to_s for
      # each primitive type. nil -> "". Pre-fix: silently emitted 0.
      puts String(42)
      puts String(nil).inspect
      puts String(true)
      puts String("hi")
      puts String(:sym)
      puts String(3.14)
    RUBY

    _(result).must_answer <<~'OUT'
      42
      ""
      true
      hi
      sym
      3.14
    OUT
  end

  it "nil coercion" do
    result = ze0(<<~'RUBY')
      # Issue #871: NilClass coercion methods. v1 covers to_i / to_f /
      # to_a. to_c, to_r, to_h deferred (Complex, Rational unsupported;
      # typed-Hash empty needs element-type judgement).
      puts nil.to_i
      puts nil.to_f
      puts nil.to_a.inspect
    RUBY

    _(result).must_answer <<~'OUT'
      0
      0.0
      []
    OUT
  end

  it "nil to h" do
    result = ze0(<<~'RUBY')
      # NilClass#to_h returns an empty hash.
      p nil.to_h
      p nil.to_h.length
      p nil.to_h.empty?
    RUBY

    _(result).must_answer <<~'OUT'
      {}
      0
      true
    OUT
  end

  it "ruby version constants" do
    result = ze0(<<~'RUBY')
      # Issue #890: RUBY_VERSION / RUBY_PLATFORM / RUBY_ENGINE built-in
      # string constants. Format-only check so the test stays stable
      # across platforms — the actual values are runtime-detected.
      puts RUBY_VERSION.is_a?(String)
      puts RUBY_PLATFORM.is_a?(String)
      puts RUBY_ENGINE.is_a?(String)
      puts RUBY_PLATFORM.length > 0
    RUBY

    _(result).must_answer <<~'OUT'
      true
      true
      true
      true
    OUT
  end

  it "sym int hash key value" do
    result = ze0(<<~'RUBY')
      # Hash#key(value) / #value? / #has_value? on sym_int_hash.
      # Missing-key #key returns the empty-sym sentinel since the typed
      # sym slot can't carry nil.
      h = {a: 1, b: 2, c: 3}
      puts h.key(2).inspect
      puts h.has_value?(2)
      puts h.has_value?(99)
      puts h.value?(3)
    RUBY

    _(result).must_answer <<~'OUT'
      :b
      true
      false
      true
    OUT
  end

  it "symbol name" do
    result = ze0(<<~'RUBY')
      # Symbol#name returns the symbol's name as a string (not a pointer
      # value cast as int).
      puts :hello.name
      puts :foo.name.length
    RUBY

    _(result).must_answer <<~'OUT'
      hello
      3
    OUT
  end

  it "time subtraction returns float" do
    result = ze0(<<~'RUBY')
      # Issue #901: Time - Time returns Float (elapsed seconds). LV
      # slot inferred as sp_Time on pass 1, refined to float on pass 2
      # once the rhs LV was declared as time. merge_refined_local_type
      # now accepts time -> float refinement.
      start = Time.now
      diff = Time.now - start
      puts diff >= 0
      puts diff.class
    RUBY

    _(result).must_answer <<~'OUT'
      true
      Float
    OUT
  end

  it "hash conformance batch7" do
    result = ze0(<<~'RUBY')
      # Hash conformance (KieranP #2399,#2406-#2410,#2416,#2417)
      p({} < { a: 1 })
      p({ a: 1 } > {})
      p({} <= {})
      p({} >= { a: 1 })
      p({}.min)
      p({}.max)
      p({}.minmax)
      p({ a: 1, b: 2 }.invert.invert)
      p({ a: 1 }.values_at)
      p(Hash.new(0).values_at(:x, :y))
      p(Hash.new(7).default(:x))
      h = Hash.new(9)
      p h.default(:zz)
      p({}.to_h)
      p({}.sum)
      p({}.sum(5))
      r = { a: 1, b: 2 }.each_with_index { |_pair, _i| nil }
      p r
    RUBY

    _(result).must_answer <<~'OUT'
      true
      true
      true
      false
      nil
      nil
      [nil, nil]
      {a: 1, b: 2}
      []
      [0, 0]
      7
      9
      {}
      0
      5
      {a: 1, b: 2}
    OUT
  end

  it "hash numeric wave11" do
    result = ze0(<<~'RUBY')
      # Hash#any?/none?/one?/count with a pair argument; blockless none? on {} local
      p({ a: 1 }.any?([:a, 1]))
      p({ a: 1 }.any?([:a, 2]))
      b11 = {}; p(b11.none?)
      c11 = {}; p(c11.any?)
      h11 = { x: 5 }
      p h11.count([:x, 5])
      p h11.one?([:x, 5])
      # hash literal as block arg
      p([:a, :b].map(&{ a: 1, b: 2 }))
      # Range#size: INFINITY bound, float begin TypeError, finite float end
      p((1..Float::INFINITY).size)
      r11 = ((1.0..10.0).size rescue "TypeError"); p r11
      r12 = ((0.5..Float::INFINITY).size rescue "TypeError"); p r12
      p((1..2.5).size)
      p((1...2.5).size)
      p((1...3.0).size)
      # Integer modulo/remainder/divmod with Float and Rational divisors
      p(7.remainder(2.5))
      p(-7.remainder(2.5))
      p(7.modulo(2.5))
      p(10.divmod(3r))
      p(10 % Rational(3, 1))
      p(10.modulo(Rational(3, 1)))
      p(1.5 % Rational(1, 2))
      # Float#clamp: range keeps bound classes, mixed 2-arg boxed
      p(5.5.clamp(1.0..3.0))
      p(2.0.clamp(1.0..3.0))
      p(0.5.clamp(1.0..3.0))
      p(0.5.clamp(1, 3))
      p(5.5.clamp(1, 3))
      p(2.5.clamp(1, 3.5))
    RUBY

    _(result).must_answer <<~'OUT'
      true
      false
      true
      false
      1
      true
      [1, 2]
      Infinity
      "TypeError"
      "TypeError"
      2
      2
      2
      2.0
      -2.0
      2.0
      [3, (1/1)]
      (1/1)
      (1/1)
      0.0
      3.0
      2.0
      1.0
      1
      3
      2.5
    OUT
  end

  it "hash predicates merge minby wave10" do
    result = ze0(<<~'RUBY')
      # Hash: blockless any?/all?/none?, Hash[kwargs], deconstruct_keys,
      # multi-arg merge with a conflict block, min_by(n)/max_by(n) (hash receivers),
      # compact!, and &hash as a block argument.
      p({ a: 1 }.any?)
      p({}.any?)
      p({ a: 1 }.all?)
      p({}.all?)
      p({ a: 1 }.none?)
      p({}.none?)
      p Hash[a: 1, b: 2]
      h0 = { name: "x", age: 3 }
      p h0.deconstruct_keys([:name])
      p h0.deconstruct_keys(nil)

      h1 = { a: 1 }
      p h1.merge({ a: 10 }, { a: 20 }) { |k, o, n| o + n }
      p h1.merge({ b: 2 }, { c: 3 })
      g1 = { "x" => 1 }
      p g1.merge({ "x" => 5 }) { |k, o, n| o * n }

      h2 = { a: 1, b: 2 }
      p [:a, :b].map(&h2)
      g2 = { "x" => 10 }
      p %w[x y].map(&g2)

      h3 = { a: 3, b: 1, c: 2 }
      p h3.min_by(2) { |_k, v| v }
      p h3.max_by(2) { |_k, v| v }
      p [5, 1, 4].min_by(2) { |x| x }
      p [5, 1, 4].max_by(2) { |x| x }

      h4 = { a: 1, b: nil, c: 3 }
      p h4.compact!
      p h4
      g4 = { a: 1 }
      p g4.compact!
      p g4
    RUBY

    _(result).must_answer <<~'OUT'
      true
      false
      true
      true
      false
      true
      {a: 1, b: 2}
      {name: "x", age: 3}
      {name: "x", age: 3}
      {a: 31}
      {a: 1, b: 2, c: 3}
      {"x" => 5}
      [1, 2]
      [10, nil]
      [[:b, 1], [:c, 2]]
      [[:a, 3], [:c, 2]]
      [1, 4]
      [5, 4]
      {a: 1, c: 3}
      {a: 1, c: 3}
      nil
      {a: 1}
    OUT
  end

  it "a Hash literal whose values are all empty arrays still takes writes" do
    result = ze0(<<~'RUBY')
      # Hash literal whose only values are empty array literals (element kind
      # unresolved) must still type to a concrete poly-valued hash variant.
      p({ "empty" => [] })
      h = { "a" => [1], "empty" => [] }
      p h
      p({ 1 => [] })
      g = { "x" => [], "y" => [] }
      g["x"] << 5
      p g
    RUBY

    _(result).must_answer <<~'OUT'
      {"empty" => []}
      {"a" => [1], "empty" => []}
      {1 => []}
      {"x" => [5], "y" => []}
    OUT
  end

  it "sort, min, max and sort_by answer for a Hash read out of a container" do
    result = ze0(<<~'RUBY')
      # A Hash read out of a container keeps #sort / #min / #max / #sort_by --
      # the poly receiver must materialize its pairs, not degrade to NoMethodError/nil.
      h = [{ 20 => 2, 3 => 1 }].first
      p h.sort
      p h.min
      p h.max
      p h.sort_by { |k, v| v }
      p h.sort_by { |k, v| k }
    RUBY

    _(result).must_answer <<~'OUT'
      [[3, 1], [20, 2]]
      [3, 1]
      [20, 2]
      [[3, 1], [20, 2]]
      [[3, 1], [20, 2]]
    OUT
  end

  it "ENV.update and #merge! take a conflict block, and #delete a not-found block" do
    result = ze0(<<~'RUBY')
      ENV["SP_A"] = "1"
      ENV.update({ "SP_A" => "2", "SP_B" => "9" }) { |k, o, n| o + n }
      p ENV["SP_A"]
      p ENV["SP_B"]
      ENV.merge!({ "SP_B" => "0" }) { |k, o, n| "#{k}!" }
      p ENV["SP_B"]
      r = ENV.delete("SP_NOPE_X") { |k| "missing #{k}" }
      p r
      ENV["SP_C"] = "cc"
      p(ENV.delete("SP_C") { |k| "nope" })
      p ENV["SP_C"]
    RUBY

    _(result).must_answer <<~'OUT'
      "12"
      "9"
      "SP_B!"
      "missing SP_NOPE_X"
      "cc"
      nil
    OUT
  end

  it "nil.to_h is an empty Hash and compares equal to one" do
    result = ze0(<<~'RUBY')
      p(nil.to_h == {})
      p({} == nil.to_h)
      p({} == {})
      h = {"a" => 1}
      p(h == {})
      p({} == h)
      p({}.eql?(nil.to_h))
      p({} != nil.to_h)
    RUBY

    _(result).must_answer <<~'OUT'
      true
      true
      true
      false
      false
      true
      false
    OUT
  end

  it "bsearch_index answers the index of the first element the block accepts" do
    result = ze0(<<~'RUBY')
      def ins(arr, v) = arr.insert(0, v)
      sorted = []
      ins(sorted, 5)
      p sorted.bsearch_index { |x| x >= 4 }

      def build(a, v); a.push(v); a; end
      xs = []
      build(xs, 1); build(xs, 3); build(xs, 5); build(xs, 7)
      p xs.bsearch_index { |x| x >= 4 }
      p xs.bsearch_index { |x| x >= 100 }
      p xs.bsearch_index { |x| 5 <=> x }

      a = [1, 3, 5, 7, 9]
      p a.bsearch_index { |x| x >= 6 }
    RUBY

    _(result).must_answer <<~'OUT'
      0
      2
      nil
      2
      3
    OUT
  end

  it "transform_values answers a Hash in whatever type the block returns" do
    result = ze0(<<~'RUBY')
      p({ "a" => 85 }.transform_values { |v| v / 10.0 })
      p({ "a" => 1, "b" => 2 }.transform_values { |v| v.to_s })
      p({ "a" => 1 }.transform_values { |v| v * 2 })
      p({ "a" => 1 }.transform_values { |v| [v, v] })
      p({ 1 => 5 }.transform_values { |v| v / 2.0 })
    RUBY

    _(result).must_answer <<~'OUT'
      {"a" => 8.5}
      {"a" => "1", "b" => "2"}
      {"a" => 2}
      {"a" => [1, 1]}
      {1 => 2.5}
    OUT
  end

  it "a string mutated through a container read shows through, and a Hash key does not" do
    result = ze0(<<~'RUBY')
      # Mutation THROUGH a container read: the element is the shared handle, so
      # the container (and any source local) observes it.
      arr = ["hello", "world"]
      arr[0].upcase!
      arr[1] << "!"
      p arr
      h = { k: "value" }
      h[:k].gsub!("l", "L")
      p h[:k]
      s = "shared"
      box = ["x"]
      box << s
      box[1].reverse!
      p s
      p box
      box[0].succ!
      p box[0]
      # hash string keys stay snapshots (CRuby dups+freezes stored keys)
      k = "key"
      hs = { k => 1 }
      k << "-mut"
      p hs.keys
      p k
    RUBY

    _(result).must_answer <<~'OUT'
      ["HELLO", "world!"]
      "vaLue"
      "derahs"
      ["x", "derahs"]
      "y"
      ["key"]
      "key-mut"
    OUT
  end
end
