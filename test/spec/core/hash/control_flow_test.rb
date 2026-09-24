# frozen_string_literal: true

require "spec_helper"

describe "Hash: control flow" do
  it "empty hash method return" do
    result = zr(<<~'RUBY')
      # A method whose value is an element-less hash -- a bare `{}` or `Hash.new` /
      # `Hash.new(default)` -- witnesses no element types in its body, so its return
      # inferred TY_UNKNOWN and codegen emitted a `void` C function; the caller's
      # `x = mk` then failed to compile (#1680). The caller's own use pins the concrete
      # hash variant, so back-propagate that onto the method's return.
      def mk_str;  Hash.new(""); end
      def mk_int;  Hash.new(0);  end
      def mk_bare; {};           end
      def mk_ret;  return Hash.new(""); end

      def mk_top; ::Hash.new(""); end          # top-level ::Hash (ConstantPathNode receiver)

      module Tep
        def self.str_hash; Hash.new(""); end   # the roundhouse shape: a Const.cmethod
      end

      a = mk_str
      a["k"] = "v"
      puts a["k"]
      puts a["miss"].length    # default "" preserved across the method boundary => 0

      b = mk_int
      b["n"] = 1
      puts b["n"]
      puts b["miss"]           # default 0 preserved => 0

      c = mk_bare
      c["x"] = "y"
      puts c["x"]

      d = mk_ret
      d["p"] = "q"
      puts d["p"]

      e = Tep.str_hash
      e["a"] = "b"
      puts e["a"]

      f = mk_top
      f["m"] = "n"
      puts f["m"]
    RUBY

    _(result).must_answer <<~'OUT'
      v
      0
      1
      0
      y
      q
      b
      n
    OUT
  end

  it "empty hash takes return type" do
    result = zr(<<~'RUBY')
      # An empty `{}` literal defaults to a StrPolyHash, but when a hash-returning
      # method (or a hash-typed ternary) has another branch of a different hash
      # variant, the empty branch must take that variant -- otherwise the StrPolyHash*
      # is an incompatible pointer type against e.g. a SymPolyHash return.
      def pick_sym(c)
        c ? {} : { a: 1 }            # SymPolyHash; empty branch must match
      end
      def pick_str(c)
        c ? {} : { "k" => "v" }      # str-keyed; empty branch must match
      end
      def via_local(c)
        h = c ? {} : { a: 1 }        # ternary in assignment position
        h.empty?
      end

      puts pick_sym(true).empty?     # true
      puts pick_sym(false)[:a].to_s  # 1
      puts pick_str(true).empty?     # true
      puts pick_str(false)["k"]      # v
      puts via_local(true)           # true
      puts via_local(false)          # false
    RUBY

    _(result).must_answer <<~'OUT'
      true
      1
      true
      v
      true
      false
    OUT
  end

  it "for loop destructures each pair" do
    result = zr(<<~'RUBY')
      for aa, bb in [[1, 2], [3, 4]]
        puts aa + bb
      end
    RUBY

    _(result).must_answer "3\n7\n"
  end

  it "select! answers nil when it removed nothing, and keep_if always answers self" do
    result = zr(<<~'RUBY')
      # Hash#select! / #filter! / #reject! return nil when nothing was removed and
      # self otherwise; #keep_if / #delete_if always return self. These now work in
      # expression position (as an argument to `p`), not only as a bare statement.
      # Each helper takes a single hash variant so the param type stays concrete.
      def hs(x); x; end   # sym-keyed hashes
      def hz(x); x; end   # str-keyed hashes

      # --- sym-keyed hash: nil-when-unchanged for the ! forms ---
      p hs({a: 1, b: 2}).reject! { |k, v| v > 99 }  # nothing removed -> nil
      p hs({a: 1, b: 2}).reject! { |k, v| v > 1 }   # removed -> self
      p hs({a: 1, b: 2}).select! { |k, v| v > 0 }   # all kept -> nil
      p hs({a: 1, b: 2}).select! { |k, v| v > 1 }   # removed -> self
      p hs({a: 1, b: 2}).filter! { |k, v| v == 1 }  # removed -> self

      # --- keep_if / delete_if always return self ---
      p hs({a: 1, b: 2}).keep_if { |k, v| v > 99 }  # empty, but self
      p hs({a: 1, b: 2}).delete_if { |k, v| v > 0 } # empty, but self

      # --- str-keyed hash ---
      p hz({"x" => 10, "y" => 20}).reject! { |k, v| v > 15 }  # removed -> self
      p hz({"x" => 10, "y" => 20}).reject! { |k, v| v > 99 }  # nothing removed -> nil

      # --- mutation is visible on the receiver afterwards ---
      h = hs({a: 1, b: 2, c: 3})
      h.select! { |k, v| v.odd? }
      p h

      # --- empty receiver ---
      p hs({}).reject! { |k, v| true }   # nothing removed -> nil

      # --- frozen receiver raises FrozenError (message detail is a separate gap) ---
      fh = hs({a: 1, b: 2}.freeze)
      begin; fh.reject! { |k, v| v > 1 }; rescue => e; puts e.class; end
    RUBY

    _(result).must_answer <<~'OUT'
      nil
      {a: 1}
      nil
      {b: 2}
      {a: 1}
      {}
      {}
      {"x" => 10}
      nil
      {a: 1, c: 3}
      nil
      FrozenError
    OUT
  end

  it "h[k] &&= and h[k] ||= ask has_key, so a stored 0 stays truthy" do
    result = zr(<<~'RUBY')
      # h[k] &&= and h[k] ||= on int-valued hashes must use has_key
      # for the truthy check, not the raw _get return. C treats 0 as
      # falsy but Ruby treats 0 as truthy, so the old _get guard
      # incorrectly skipped &&= on stored 0 and incorrectly fired ||=
      # on stored 0.

      h = {"a" => 0, "b" => 1}
      h["a"] &&= 99
      h["b"] &&= 99
      puts h["a"]
      puts h["b"]

      h2 = {"x" => 0, "y" => 1}
      h2["x"] ||= 99
      h2["y"] ||= 99
      puts h2["x"]
      puts h2["y"]

      # SymIntHash variant
      s = {a: 0, b: 1}
      s[:a] &&= 99
      s[:b] &&= 99
      puts s[:a]
      puts s[:b]

      s2 = {x: 0, y: 1}
      s2[:x] ||= 99
      s2[:y] ||= 99
      puts s2[:x]
      puts s2[:y]
    RUBY

    _(result).must_answer <<~'OUT'
      99
      99
      0
      1
      99
      99
      0
      1
    OUT
  end

  it "a method answering Hash.new(default) takes the int-keyed, float-valued shape its caller pins" do
    result = zr(<<~'RUBY')
      # A method returning Hash.new(default) where the caller pins the int-keyed,
      # float-valued shape (PolyPolyHash): the backprop exclusion this variant
      # needed before PolyPolyHash_new_with_default existed is gone.
      def mk; Hash.new(0.0); end
      x = mk
      x[1] += 2.5
      p x[1]
      p x[9]
      p x.default
    RUBY

    _(result).must_answer <<~'OUT'
      2.5
      0.0
      0.0
    OUT
  end

  it "int keyed hash variant" do
    result = zr(<<~'RUBY')
      # An empty hash literal takes the variant its key selects, and that mark is
      # permanent -- it only ever widens afterwards. For a String key the rule reads
      # the slot's own `h[k] = v` writes so a concrete value type is not thrown away;
      # for an Integer key it did not, because until `[]=` joined the rule's name list
      # an Integer-keyed literal never reached it. From then on a hash built only by
      # writes was boxed both ways. Correct, and one representation too wide -- which
      # is why only the infer-test property gate saw it.
      def build
        h = {}
        h[10] = 1
        h[500] = 2
        h
      end
      t = build
      t[3] = 7
      p t[10] + t[500] + t[3]
      p t.size

      def named
        n = {}
        n[1] = "one"
        n[2] = "two"
        n
      end
      p named[1] + named[2]

      # A value type the Int-keyed variants cannot hold still takes the boxed one.
      def mixed
        m = {}
        m[1] = "a"
        m[2] = 3
        m
      end
      p mixed[1]
      p mixed[2]
    RUBY

    _(result).must_answer <<~'OUT'
      10
      3
      "onetwo"
      "a"
      3
    OUT
  end

  it "next value hash" do
    result = zr(<<~'RUBY')
      # `next <value>` through hash map/select/reject: map contributes the value;
      # select/reject decide inclusion by the (next-aware) block value.
      p({ a: 1, b: 2, c: 3 }.map { |k, v| next 0 if v == 2; v * 10 })         # [10, 0, 30]
      p({ a: 1, b: 2 }.map { |k, v| "#{k}=#{v}" })                            # ["a=1", "b=2"]
      p({ a: 1, b: 2, c: 3 }.select { |k, v| next true if k == :b; v > 2 })   # {b: 2, c: 3}
      p({ a: 1, b: 2, c: 3 }.reject { |k, v| next true if k == :a; v.even? }) # {c: 3}
      p({ "x" => 1, "y" => 2 }.map { |k, v| [k, v * 2] })                     # [["x", 2], ["y", 4]]
    RUBY

    _(result).must_answer <<~'OUT'
      [10, 0, 30]
      ["a=1", "b=2"]
      {b: 2, c: 3}
      {c: 3}
      [["x", 2], ["y", 4]]
    OUT
  end

  it "nullable hash recv bracket" do
    result = zr(<<~'RUBY')
      class Router
        def self.match_pattern(s)
          return nil if s == ""
          h = {}
          h["k"] = s
          h
        end
      end

      r = Router.match_pattern("hello")
      if r
        puts r["k"]
      end

      r2 = Router.match_pattern("")
      if r2
        puts "yes"
      else
        puts "no"
      end

      # Same shape, nilable str_int_hash return
      def maybe_count(n)
        return nil if n <= 0
        h = {}
        h["x"] = n
        h
      end

      c = maybe_count(5)
      if c
        puts c["x"]
      end
    RUBY

    _(result).must_answer <<~'OUT'
      hello
      no
      5
    OUT
  end

  it "unless return path hash" do
    result = zr(<<~'RUBY')
      # #449: `unless cond; return {hash}; end; nil` — the function's
      # return type used to ignore the unless-arm's `return {hash}` and
      # infer mrb_int (the trailing nil), failing C compile. Now the
      # UnlessNode arm in collect_return_types mirrors IfNode, so both
      # the unless-body's return and the trailing nil contribute to
      # return type unification.

      def self.outer(flag)
        unless flag
          return { x: "y" }
        end
        nil
      end

      puts outer(false).nil? ? "nil" : "found"
      puts outer(true).nil? ? "nil" : "found"

      # `unless cond` with else_clause — both arms can carry returns.
      def self.classify(n)
        unless n.zero?
          return { kind: "nonzero" }
        else
          return { kind: "zero" }
        end
      end

      puts classify(0)[:kind]
      puts classify(5)[:kind]

      # Top-level def variant (non-self).
      def first_or_default(arr, default = nil)
        unless arr.empty?
          return arr[0]
        end
        default
      end

      puts first_or_default(["hi", "bye"])
      puts first_or_default([], "fallback")
    RUBY

    _(result).must_answer <<~'OUT'
      found
      nil
      zero
      nonzero
      hi
      fallback
    OUT
  end
end
