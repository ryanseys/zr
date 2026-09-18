# frozen_string_literal: true

require "spec_helper"

describe "Array: slicing" do
  it "array enum materialize" do
    result = ze0(<<~'RUBY')
      # Blockless enumerator materialization: cycle(n), repeated_permutation,
      # slice_before/slice_after with a pattern value, and each_entry.
      a = [1, 2]
      p a.cycle(2).to_a          # [1, 2, 1, 2]
      p a.cycle(0).to_a          # []
      b = [1, 3, 2, 3, 4]
      p b.slice_before(3).to_a   # [[1], [3, 2], [3, 4]]
      p b.slice_after(3).to_a    # [[1, 3], [2, 3], [4]]
      p ["x", "y", "x"].slice_before("x").to_a  # [["x", "y"], ["x"]]
      c = [1, 2, 3]
      p c.each_entry.to_a        # [1, 2, 3]
      r = []
      a.repeated_permutation(2) { |x| r << x }
      p r                        # [[1, 1], [1, 2], [2, 1], [2, 2]]
      p [5, 6].repeated_permutation(2).to_a  # [[5, 5], [5, 6], [6, 5], [6, 6]]
      p a.repeated_permutation(0).to_a       # [[]]
    RUBY

    _(result).must_answer <<~'OUT'
      [1, 2, 1, 2]
      []
      [[1], [3, 2], [3, 4]]
      [[1, 3], [2, 3], [4]]
      [["x", "y"], ["x"]]
      [1, 2, 3]
      [[1, 1], [1, 2], [2, 1], [2, 2]]
      [[5, 5], [5, 6], [6, 5], [6, 6]]
      [[]]
    OUT
  end

  it "array fill incompatible" do
    result = ze0(<<~'RUBY')
      # Array#fill with a value incompatible with the element type rebuilds the
      # result as a poly array (CRuby just mixes the element in); positional and
      # range spans, and the compatible typed fills keep their arms.
      p [1, 2, 3, 4, 5].fill("x", 1, 2)
      p [1, 2, 3, 4, 5].fill("x", 1..3)
      p [1, 2, 3].fill(9)
      a = [1, 2, 3, 4, 5]
      a.fill("y", 2, 1)
      p a
      p %w[a b c].fill("z", 1)
    RUBY

    _(result).must_answer <<~'OUT'
      [1, "x", "x", 4, 5]
      [1, "x", "x", "x", 5]
      [9, 9, 9]
      [1, 2, "y", 4, 5]
      ["a", "z", "z"]
    OUT
  end

  it "array fill range" do
    result = ze0(<<~'RUBY')
      # fill(value, range): a negative end counts from the end and an endless one
      # runs to the last element. Unnormalized, `fill(v, 2..)` grew the array until
      # the process died and `fill(v, 1..-1)` filled nothing.
      a=[1,2,3,4,5]
      p a.fill(9, 1..-1)
      b=[1,2,3,4,5]
      p b.fill(9, 2..)
      c=[1,2,3,4,5]
      p c.fill(9, 1..2)
      d=[1,2,3,4,5]
      p d.fill(9, 2)
      e=[1,2,3,4,5]
      p e.fill(9, 1...3)
      f=[1,2,3,4,5]
      p f.fill(9, -2..)
      g=[1,2,3]
      p g.fill(9, 0..9)
      h=["a","b","c"]
      p h.fill("z", 1..-1)
    RUBY

    _(result).must_answer <<~'OUT'
      [1, 9, 9, 9, 9]
      [1, 2, 9, 9, 9]
      [1, 9, 9, 4, 5]
      [1, 2, 9, 9, 9]
      [1, 9, 9, 4, 5]
      [1, 2, 3, 9, 9]
      [9, 9, 9, 9, 9, 9, 9, 9, 9, 9]
      ["a", "z", "z"]
    OUT
  end

  it "array first last empty" do
    result = ze0(<<~'RUBY')
      # Array#first / Array#last on an empty array return nil,
      # not SP_INT_NIL printed as a huge negative number.
      # CRuby returns nil for [].first and [].last.

      puts [].first.inspect
      puts [].last.inspect
      puts [].first.nil?.inspect
      puts [].last.nil?.inspect
      puts [1, 2, 3].first.inspect
      puts [1, 2, 3].last.inspect
      puts [1, 2, 3].first(2).inspect
      puts [1, 2, 3].last(2).inspect
    RUBY

    _(result).must_answer <<~'OUT'
      nil
      nil
      true
      true
      1
      3
      [1, 2]
      [2, 3]
    OUT
  end

  it "array push multi arg" do
    result = ze0(<<~'RUBY')
      # Array#push / #append take any number of arguments and return the
      # array. Both forms previously compiled only the first argument
      # (compile_arg0), so a multi-arg push dropped every element after the
      # first and the expression-form result of int/float/ptr/poly pushes
      # returned 0 instead of the array.

      p ["a"].append("b", "c")                    #=> ["a", "b", "c"]
      p [1].push(2, 3, 4)                          #=> [1, 2, 3, 4]
      p [1.0].push(2.0, 3.0)                       #=> [1.0, 2.0, 3.0]
      p [:a].push(:b, :c)                          #=> [:a, :b, :c]
      p(["a"].append("b", "c") == ["a", "b", "c"]) #=> true

      # Statement form mutates in place.
      a = [1]
      a.push(2, 3)
      p a                                          #=> [1, 2, 3]
      a.append(4, 5, 6)
      p a                                          #=> [1, 2, 3, 4, 5, 6]

      # Single-arg push still returns the array (expression form).
      p([1].push(9) == [1, 9])                     #=> true

      # Object (ptr) arrays.
      class Box
        def initialize(v); @v = v; end
        def v; @v; end
      end
      b = [Box.new(1)]
      b.push(Box.new(2), Box.new(3))
      p b.map { |x| x.v }                          #=> [1, 2, 3]

      puts "done"
    RUBY

    _(result).must_answer <<~'OUT'
      ["a", "b", "c"]
      [1, 2, 3, 4]
      [1.0, 2.0, 3.0]
      [:a, :b, :c]
      true
      [1, 2, 3]
      [1, 2, 3, 4, 5, 6]
      true
      [1, 2, 3]
      done
    OUT
  end

  it "array values at open range" do
    result = ze0(<<~'RUBY')
      a = [1, 2, 3, 4, 5]
      p a.values_at(2..)
      p a.values_at(2...)
      p a.values_at(..2)
      p a.values_at(...2)
      p a.values_at(nil..2)
      p a.values_at(1..3)
      p a.values_at(1..9)
      p a.values_at(-2..)
      p a.values_at(7..9)
      p a.values_at(0, 2..3)
      p([1, 2, 3, 4, 5].fill(9, 2..))
      s = ["a", "b", "c"]
      p s.values_at(1..)
      p s.values_at(..1)
    RUBY

    _(result).must_answer <<~'OUT'
      [3, 4, 5]
      [3, 4, 5]
      [1, 2, 3]
      [1, 2]
      [1, 2, 3]
      [2, 3, 4]
      [2, 3, 4, 5, nil, nil, nil, nil, nil]
      [4, 5]
      [nil, nil, nil]
      [1, 3, 4]
      [1, 2, 9, 9, 9]
      ["b", "c"]
      ["a", "b"]
    OUT
  end

  it "bsearch and empty parens" do
    result = ze0(<<~'RUBY')
      # Array#bsearch / Range#bsearch support both CRuby modes, selected by the
      # block's return type. Find-minimum mode (a boolean/nil result) answers the
      # first element for which the block is true; find-any mode (a Numeric
      # comparator result) treats 0 as a hit, a negative result searches the lower
      # half and a positive one the upper half, answering nil when nothing matches.
      nums = [0, 4, 7, 10, 12]
      p nums.bsearch { |x| x >= 7 }          # find-minimum
      p nums.bsearch { |x| 10 <=> x }        # find-any hit
      p nums.bsearch_index { |x| 12 <=> x }
      p(nums.bsearch { |x| 3 <=> x })        # find-any miss -> nil
      p [1, 2, 3].bsearch { |x| 1 - x }
      p((1..1000).bsearch { |x| x >= 512 })
      p((1..1000).bsearch { |x| 777 <=> x })

      # `()` is nil: falsy as a condition, a nil value in expression position.
      p(())
      p((() && true))
      p((true || ()))
      count = 0
      while () ; count += 1 ; end
      p count

      # Array#concat copies every source before appending, so a self-aliasing
      # concat terminates instead of feeding its own growth.
      a = [1, 2]
      a.concat(a, a)
      p a
    RUBY

    _(result).must_answer <<~'OUT'
      7
      10
      4
      nil
      1
      512
      777
      nil
      nil
      true
      0
      [1, 2, 1, 2, 1, 2]
    OUT
  end

  it "builtin array method capture" do
    result = ze0(<<~'RUBY')
      # `<int_array>.method(:op)` lowered through a per-(type, op)
      # trampoline matching the Method dispatch ABI. Surfaced via
      # optcarrot's CPU memory-mapping shape
      # `add_mappings(0x0000..0x07ff, @ram, @ram.method(:[]=))` —
      # the captured Method later sits in @store and is invoked via
      # `@store[addr][addr, val]`.
      #
      # Three operators supported in the first cut: `:[]`, `:[]=`,
      # `:push`. Other (recv_type, mname) pairs still fall through to
      # the unresolved-call warning until they're added to
      # emit_builtin_array_method_adapter.

      a = [10, 20, 30, 40, 50]

      mget = a.method(:[])
      mset = a.method(:[]=)
      mpush = a.method(:push)

      # Read via captured Method: bracket-call shape.
      puts mget[0]
      puts mget[2]
      puts mget[4]

      # Write via captured Method: mutates the receiver in place.
      mset[1, 200]
      mset[3, 400]
      puts a[0]
      puts a[1]
      puts a[2]
      puts a[3]
      puts a[4]

      # Push via captured Method: extends the receiver.
      mpush[60]
      mpush[70]
      puts a.length
      puts a[5]
      puts a[6]
    RUBY

    _(result).must_answer <<~'OUT'
      10
      30
      50
      10
      200
      30
      400
      50
      7
      60
      70
    OUT
  end

  it "Top-level def, [] passed directly at call site" do
    result = ze0(<<~'RUBY')
      # Empty `[]` literal as parameter — deferred element-type resolution
      # must converge across caller / param / body. Issues #58 (top-level
      # def + instance method) and #84 (inherited dispatch). Was four
      # tests; class names don't collide so the merge is straight
      # concatenation with shared helpers.


      def push_floats(buf)
        buf.push(1.5)
        buf.push(2.5)
        buf
      end
      result_pf = push_floats([])
      puts result_pf[0]   # 1.5
      puts result_pf[1]   # 2.5
    RUBY

    _(result).must_answer <<~'OUT'
      1.5
      2.5
    OUT
  end

  it "Top-level def, [] stored in local first" do
    result = ze0(<<~'RUBY')
      # Empty `[]` literal as parameter — deferred element-type resolution
      # must converge across caller / param / body. Issues #58 (top-level
      # def + instance method) and #84 (inherited dispatch). Was four
      # tests; class names don't collide so the merge is straight
      # concatenation with shared helpers.


      def collect_names(buf)
        buf.push("alpha")
        buf.push("beta")
      end
      names = []
      collect_names(names)
      puts names[0]       # alpha
      puts names[1]       # beta
      puts names.length   # 2
    RUBY

    _(result).must_answer <<~'OUT'
      alpha
      beta
      2
    OUT
  end

  it "Instance method receiving [] — same deferred path" do
    result = ze0(<<~'RUBY')
      # Empty `[]` literal as parameter — deferred element-type resolution
      # must converge across caller / param / body. Issues #58 (top-level
      # def + instance method) and #84 (inherited dispatch). Was four
      # tests; class names don't collide so the merge is straight
      # concatenation with shared helpers.


      class Recorder
        def record(buf, name)
          buf.push(name)
          buf.push(name + "!")
        end
      end
      r = Recorder.new
      log = []
      r.record(log, "go")
      r.record(log, "stop")
      puts log.length     # 4
      puts log[0]         # go
      puts log[1]         # go!
      puts log[2]         # stop
      puts log[3]         # stop!

      # === Inherited dispatch (#84): caller-side inference must walk
      # the inheritance chain to update the *parent's* @cls_meth_ptypes
      # when cls_find_method_direct misses on the child. ===
      class Base
        def add_to(buf)
          buf.push("hi")
        end
      end
      class Child < Base
      end
      names1 = []
      Child.new.add_to(names1)
      names1.push("more")
      puts names1[0]      # hi
      puts names1[1]      # more

      # Two-deep inheritance.
      class Grandchild < Child
      end
      names2 = []
      Grandchild.new.add_to(names2)
      names2.push("again")
      puts names2[0]      # hi
      puts names2[1]      # again

      # Class that overrides the inherited slot AND inherits a different
      # defaulted method. The promotion must hit Base2's slot for the
      # inherited `also_add` call, not Mixed's.
      class Base2
        def also_add(buf)
          buf.push("base2")
        end
      end
      class Mixed < Base2
        def add_to(buf)
          buf.push(42)
        end
      end

      ints = []
      Mixed.new.add_to(ints)
      ints.push(7)
      puts ints[0]        # 42
      puts ints[1]        # 7

      strs = []
      Mixed.new.also_add(strs)
      strs.push("more")
      puts strs[0]        # base2
      puts strs[1]        # more
    RUBY

    _(result).must_answer <<~'OUT'
      4
      go
      go!
      stop
      stop!
      hi
      more
      hi
      again
      42
      7
      base2
      more
    OUT
  end

  it "flatten walks any depth" do
    result = ze0(<<~'RUBY')
      # flatten walks with a stack of its own, as CRuby's does, so an Array
      # nested far deeper than any call stack flattens; a level stops the walk
      # where it says; an element answering to_ary is asked once; a recursive
      # Array raises only when the walk would enter it again.
      def t = yield rescue [$!.class, $!.message]

      deep = [0]
      100_000.times { |i| deep = [deep, i + 1] }
      p t { deep.flatten.size }, t { deep.flatten.first(3) }, t { deep.flatten(1).size }, t { deep.flatten(2).size }

      list = Class.new { def to_ary = [:x, [:y]] }
      p t { [1, list.new, [2, [3]]].flatten }, t { [1, list.new].flatten(1) }, t { [[1, [2, [3, [4]]]]].flatten(2) }
      p t { [1, [2]].flatten(0) }, t { [1, [2]].flatten(-1) }, t { [1, [2]].flatten(nil) }, t { [1, [2]].flatten(1.9) }

      a = [1]
      a << a
      p t { a.flatten }, t { a.flatten(1).size }, t { [a].flatten(1).size }, t { [[a]].flatten(2).size }

      b = [1, 2]
      p t { b.flatten! }, t { [1, [2]].flatten! }, t { [1, [2]].flatten!(0) }, t { [[1]].freeze.flatten! }, t { [1].freeze.flatten! }
      c = [1, [2]]
      p t { c.flatten.equal?(c) }, t { [1, 2].flatten.equal?([1, 2]) }

    RUBY

    _(result).must_answer <<~'OUT'
      100001
      [0, 1, 2]
      3
      4
      [1, :x, :y, 2, 3]
      [1, :x, [:y]]
      [1, 2, [3, [4]]]
      [1, [2]]
      [1, 2]
      [1, 2]
      [1, 2]
      [ArgumentError, "tried to flatten recursive array"]
      3
      2
      2
      nil
      [1, 2]
      nil
      [FrozenError, "can't modify frozen Array: [[1]]"]
      [FrozenError, "can't modify frozen Array: [1]"]
      false
      false
    OUT
  end

  it "float array first last nil" do
    result = ze0(<<~'RUBY')
      # FloatArray#first/#last on an empty array return nil (float? nullable),
      # not 0.0. A non-empty array yields the value as a plain float, and the
      # value flows transparently through arithmetic (the float? rides as a
      # double; base_type strips the `?`).
      a = [1.5, 2.5]
      p a.first
      p a.last
      p a.first.nil?

      b = [3.0, 4.0]
      b.pop
      b.pop
      p b.first
      p b.last
      p b.first.nil?

      c = [10.5, 4.5]
      p c.last - c.first        # float? - float? -> float
      x = c.last
      p x + 1.0                 # float? flowing into bare-float arithmetic
    RUBY

    _(result).must_answer <<~'OUT'
      1.5
      2.5
      false
      nil
      nil
      true
      -6.0
      5.5
    OUT
  end

  it "hash dig" do
    result = ze0(<<~'RUBY')
      # Hash#dig: nested key traversal across hash variants.

      # 1. Single-key form on each hash variant — alias for `[]`.
      sih = {"one" => 1, "two" => 2}
      puts sih.dig("one")          # 1
      puts sih.dig("two")           # 2

      ssh = {"a" => "alpha", "b" => "beta"}
      puts ssh.dig("a")             # alpha
      puts ssh.dig("b")             # beta

      ish = {1 => "x", 2 => "y"}
      puts ish.dig(1)               # x
      puts ish.dig(2)               # y

      syih = {a: 10, b: 20}
      puts syih.dig(:a)             # 10
      puts syih.dig(:b)             # 20

      # 2. Multi-key on a sym_poly_hash with a sym_poly_hash leaf.
      nested = { user: { name: "Alice", age: 30 }, count: 7 }
      puts nested.dig(:user, :name) # Alice
      puts nested.dig(:user, :age)  # 30
      puts nested.dig(:count)       # 7

      # 3. Multi-key on a sym_poly_hash whose inner hash is sym_int_hash.
      config = { limits: { read: 100, write: 50 }, version: 2 }
      puts config.dig(:limits, :read)  # 100
      puts config.dig(:limits, :write) # 50
      puts config.dig(:version)        # 2

      # 4. Multi-key on a sym_poly_hash whose inner hash is sym_str_hash.
      labels = { en: { hello: "hi", bye: "bye" }, ja: { hello: "konnichiwa", bye: "sayonara" } }
      puts labels.dig(:en, :hello)    # hi
      puts labels.dig(:ja, :bye)      # sayonara

      # 5. Three-deep nesting.
      deep = { a: { b: { c: 42 } } }
      puts deep.dig(:a, :b, :c)       # 42

      # 6. Missing keys produce nil.
      miss = { a: { b: 1 } }
      puts miss.dig(:nope)            # (blank)
      puts miss.dig(:a, :nope)        # (blank)
      # CRuby raises TypeError on `int.dig(:c)`; spinel returns nil. Not
      # probed here so `.expected` stays comparable to CRuby.

      # 7. Same shape for str_poly_hash.
      sph = { "user" => { "name" => "Bob", "age" => 25 } }
      puts sph.dig("user", "name")    # Bob
      puts sph.dig("user", "age")     # 25
      puts sph.dig("missing")         # (blank)

      # 8. Real 0 / "" leaves vs missing keys: `p` distinguishes 0 / "" / nil.
      zh = { a: { b: 0 } }
      p zh.dig(:a, :b)                # 0
      p zh.dig(:a, :missing)          # nil
      zs = { a: { b: "" } }
      p zs.dig(:a, :b)                # ""
      p zs.dig(:a, :missing)          # nil

      # 9. str_poly_hash with str_int_hash and str_str_hash leaves.
      counts = { "a" => { "x" => 1, "y" => 2 } }
      puts counts.dig("a", "x")       # 1
      p counts.dig("a", "missing")    # nil
      labs2 = { "a" => { "x" => "hi" } }
      puts labs2.dig("a", "x")        # hi
      p labs2.dig("a", "missing")     # nil

      # 10. Mid-walk into a leaf with no #dig: a TypeError, not a quiet nil (#3567
      # corrected this expectation, which had been pinned the other way).
      flat = { a: 1 }
      r_flat = (flat.dig(:a, :b) rescue $!.class)
      p r_flat                        # TypeError

      # 11. Each key expression evaluates exactly once across the dig walk.
      def k_first
        puts "k1"
        :a
      end
      def k_second
        puts "k2"
        :b
      end
      side = { a: { b: 99 } }
      puts side.dig(k_first, k_second)

      # 12. Static key-type mismatch returns nil (CRuby compat).
      sym_h = {a: 1}
      p sym_h.dig("a")                # nil  (string key on sym hash)
      str_h = {"a" => 1}
      p str_h.dig(:a)                 # nil  (sym key on str hash)
      mismatch = { a: { b: 1 } }
      p mismatch.dig("a", :b)         # nil  (multi-key first-key mismatch)
    RUBY

    _(result).must_answer <<~'OUT'
      1
      2
      alpha
      beta
      x
      y
      10
      20
      Alice
      30
      7
      100
      50
      2
      hi
      sayonara
      42


      Bob
      25

      0
      nil
      ""
      nil
      1
      nil
      hi
      nil
      TypeError
      k1
      k2
      99
      nil
      nil
      nil
    OUT
  end

  it "integer digits base" do
    result = ze0(<<~'RUBY')
      # Integer#digits(base) returns the digits in the given base, least-significant
      # first. The base argument must reach the runtime instead of being ignored.
      p 255.digits
      p 255.digits(16)
      p 100.digits(10)
      p 1234.digits(16)
      p 0.digits(16)

      def digits_of(n, base)
        n.digits(base)
      end
      p digits_of(255, 16)
      p digits_of(1000, 2)

      # A base of polymorphic type (here an element of a mixed array) must be
      # unboxed to an integer before reaching the runtime.
      bases = [16, "x"]
      p 255.digits(bases.first)
    RUBY

    _(result).must_answer <<~'OUT'
      [5, 5, 2]
      [15, 15]
      [0, 0, 1]
      [2, 13, 4]
      [0]
      [15, 15]
      [0, 0, 0, 1, 0, 1, 1, 1, 1, 1]
      [15, 15]
    OUT
  end

  it "pointer type miscompiles" do
    result = ze0(<<~'RUBY')
      # Shapes whose generated C carried a pointer of the wrong type: each read one
      # struct through another's layout, and each was only a compiler warning before
      # (#3975's second observation -- the build now fails on one).
      x = case "foo"
          when ["foo", "foo"] then "bad"
          when "foo" then "good"
          end
      p x

      # `[].freeze.rotate`: the empty literal was built as the int-array default and
      # handed to the poly-array path
      p(-> { [].freeze.rotate }.call)
      p [2].freeze.rotate(2)
      p [1, 2, 3].freeze.rotate(-3)

      # product with a block answers self, and its empty-array argument is poly
      arr = [1, 2]
      seen = []
      p arr.product([3, 4], [5]) { |t| seen << t }.equal?(arr)
      p seen
      p arr.product([]) { }.equal?(arr)
      p arr.product([3, 4]) { }.equal?(arr)

      # a massign rest slices the SOURCE array's kind
      *a, b, c = *1
      p [a, b, c]
      *d, e = *[1, 2, 3]
      p [d, e]
      *f, g = "x", "y", "z"
      p [f, g]
    RUBY

    _(result).must_answer <<~'OUT'
      "good"
      []
      [2]
      [1, 2, 3]
      true
      [[1, 3, 5], [1, 4, 5], [2, 3, 5], [2, 4, 5]]
      true
      true
      [[], 1, nil]
      [[1, 2], 3]
      [["x", "y"], "z"]
    OUT
  end

  it "range and array range args" do
    result = ze0(<<~'RUBY')
      # Cluster of "Range struct passed where mrb_int expected" C errors:
      #   #1247 rand(range) / rand(float)
      #   #1234 Range#cover? with a Range argument
      #   #1228 Range#first(n) / #last(n) / #count
      #   #1240 Array#values_at with a Range argument
      #   #1224 Array#fill(value, range)
      # Each used to either emit a C type error (sp_Range fed to an mrb_int
      # operand) or silently return the wrong value.

      # #1247 — rand with a range / float arg. Values are nondeterministic,
      # so assert membership rather than the value.
      vi = rand(1..6)
      puts(vi >= 1 && vi <= 6)
      puts vi.class
      vf = rand(1.0..10.0)
      puts(vf >= 1.0 && vf < 10.0)
      puts vf.class

      # #1234 — cover? with a Range argument
      puts (1..10).cover?(5..8)
      puts (1..10).cover?(5..12)
      puts (1..10).cover?(5)

      # #1228 — first(n) / last(n) / count
      p (1..10).first(3)
      p (1..10).last(3)
      p (1...10).last(3)
      p (1..10).first(20)
      puts (1..10).count
      puts (1...10).count

      # #1240 — values_at with a Range argument
      p [10, 20, 30, 40, 50].values_at(1..3)
      p [10, 20, 30, 40, 50].values_at(0, 2, 4)
      p ["a", "b", "c", "d"].values_at(1..2)

      # #1224 — fill(value, range)
      a = [1, 2, 3, 4, 5]
      a.fill(0, 2..4)
      p a
      b = [1, 2, 3, 4, 5]
      b.fill(9, 1...3)
      p b
    RUBY

    _(result).must_answer <<~'OUT'
      true
      Integer
      true
      Float
      true
      false
      true
      [1, 2, 3]
      [8, 9, 10]
      [7, 8, 9]
      [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]
      10
      9
      [20, 30, 40]
      [10, 30, 50]
      ["b", "c"]
      [1, 2, 0, 0, 0]
      [1, 9, 9, 4, 5]
    OUT
  end

  it "range bsearch" do
    result = ze0(<<~'RUBY')
      # Integer Range#bsearch in find-minimum mode: the block returns truthy
      # for the upper half; bsearch returns the smallest member where it does,
      # or nil when no member qualifies.
      p (1..100).bsearch { |x| x >= 42 }
      p (1..100).bsearch { |x| x >= 1 }
      p (1..100).bsearch { |x| x >= 100 }
      p (1..100).bsearch { |x| x >= 200 }
      p (0...10).bsearch { |x| x >= 7 }
      p (0...10).bsearch { |x| x >= 9 }
      p (0...10).bsearch { |x| x >= 10 }
      p (5..5).bsearch { |x| x >= 5 }
    RUBY

    _(result).must_answer <<~'OUT'
      42
      1
      100
      nil
      7
      9
      nil
      5
    OUT
  end

  it "range bsearch float" do
    result = ze0(<<~'RUBY')
      # Range#bsearch over a float-bounded range bisects the real interval (a
      # float member, or nil) -- previously it crashed with "can't iterate from
      # Float". Integer ranges keep their index bisection.
      p((0.1...2.3).bsearch { |x| x > 1.0 })
      p((0.0..10.0).bsearch { |x| x >= 4.0 })
      p((0.1...2.3).bsearch { |x| x > 3 })
      p((-5.0..5.0).bsearch { |x| x >= 0 })
      p((1..10).bsearch { |x| x >= 4 })
      p((1..10).bsearch { |x| x > 100 })
      p((0..8).bsearch { |x| x * x >= 33 })
    RUBY

    _(result).must_answer <<~'OUT'
      1.0000000000000002
      4.0
      nil
      0.0
      4
      nil
      6
    OUT
  end

  it "range overlap array flatten depth" do
    result = ze0(<<~'RUBY')
      # Range#overlap? on two numeric ranges, plus Array#flatten(n)
      # with a depth-bounded variant.

      puts (1..5).overlap?(4..10)
      puts (1..3).overlap?(5..10)
      puts (5..10).overlap?(1..3)
      puts (1..10).overlap?(20..30)

      # Depth-bounded flatten.
      puts [[1, [2, [3, [4]]]]].flatten(1).inspect
      puts [[1, [2, [3, [4]]]]].flatten(2).inspect
      puts [[1, [2, [3, [4]]]]].flatten(3).inspect
      # Unbounded still works (no arg).
      puts [[1, [2, [3]]]].flatten.inspect

      # Depth-bounded flatten unboxes float and string sub-arrays one level too
      # (the bounded walker handles IntArray / StrArray / FloatArray / PolyArray).
      puts [[1.5, 2.5], [3.5]].flatten(1).inspect
      puts [["a", "b"], ["c"]].flatten(1).inspect
    RUBY

    _(result).must_answer <<~'OUT'
      true
      false
      false
      false
      [1, [2, [3, [4]]]]
      [1, 2, [3, [4]]]
      [1, 2, 3, [4]]
      [1, 2, 3]
      [1.5, 2.5, 3.5]
      ["a", "b", "c"]
    OUT
  end

  it "safe nav array returning" do
    result = ze0(<<~'RUBY')
      # `x&.keys` / `&.values` / `&.to_a` on a receiver that is not statically a Hash
      # typed the whole expression poly, while the guarded call itself lowers to an
      # sp_PolyArray *. The C conditional then had an sp_RbVal nil against a pointer
      # and the build aborted. An array result is a pointer whose NULL already reads
      # as nil, so the guard can stay in pointer form. #3461.
      x = nil
      p(x&.keys)
      p(x&.values)
      p(x&.to_a)
      rows = [{ "a" => 1 }]
      p(rows.first&.keys)
      p(rows.first&.values)
      p(rows.first&.to_a)
      h = { "a" => 1 }
      p(h&.keys)
      p(rows.first&.size)
      r2 = [["x", "y"]]
      p(r2.first&.reverse)
      empty = []
      p(empty.first&.keys)
    RUBY

    _(result).must_answer <<~'OUT'
      nil
      nil
      nil
      ["a"]
      [1]
      [["a", 1]]
      ["a"]
      1
      ["y", "x"]
      nil
    OUT
  end

  it "sp net poll grow" do
    result = ze0(<<~'RUBY')
      # The readiness set grows with the caller's connection count.
      #
      # It used to be a fixed 256-entry array whose overflow answered -1 -- and -1 is
      # also what a caller reads as "this fd is not in the set this round", so from
      # the 257th fd on a connection went deaf with nothing said about it. A server
      # holding one socket per user reaches 256 on its first busy minute.
      #
      # poll_add only records (fd, mode); it does not touch the fd, so the same fd
      # registered many times is a faithful test of the set's capacity.
      module Net
        ffi_func :sp_net_poll_reset, [],          :int
        ffi_func :sp_net_poll_add,   [:int, :int], :int
        ffi_func :sp_net_poll_ready, [:int],       :int
      end

      Net.sp_net_poll_reset

      # Slots are handed out in order, and keep being handed out well past the old
      # 256 ceiling.
      slots = []
      1000.times { slots << Net.sp_net_poll_add(0, 1) }

      puts "first: #{slots[0]}"
      puts "at old cap: #{slots[255]}"
      puts "past old cap: #{slots[256]}"
      puts "last: #{slots[999]}"
      puts "any refused: #{slots.any? { |s| s < 0 }}"
      puts "all in order: #{slots.each_with_index.all? { |s, i| s == i }}"

      # A slot past the registered count reads as "nothing fired" rather than
      # walking off the set.
      puts "beyond set: #{Net.sp_net_poll_ready(5000)}"
      puts "negative: #{Net.sp_net_poll_ready(-1)}"

      # reset re-uses the same storage: the next add starts at slot 0 again.
      Net.sp_net_poll_reset
      puts "after reset: #{Net.sp_net_poll_add(0, 1)}"
    RUBY

    _(result).must_answer "", stderr: <<~'ERR', status: 1
      core/array/slicing_test.rb:11:in '<module:Net>': undefined method 'ffi_func' for module Net (NoMethodError)

        ffi_func :sp_net_poll_reset, [],          :int
        ^^^^^^^^
      	from core/array/slicing_test.rb:10:in '<main>'
    ERR
  end

  it "stack operations take a count in the kernel" do
    result = ze0(<<~'RUBY')
      # pop, shift and unshift are kernel entries with the count of `pop(n)`
      # and `shift(n)` read there, and first and last stay ruby's own Ruby:
      # the same answers, errors in the same order, plain Arrays from a
      # subclass, and a queue that shifts and unshifts in place.
      a = [1, 2, 3, 4, 5]
      p a.first, a.last, a.first(2), a.last(2), a.first(0), a.last(9), a.first(2.9)
      p a.pop, a.pop(2), a, a.shift, a.shift(3), a, a.shift, a.pop, a.shift(2), a.pop(1)
      b = [3, 4]
      p b.unshift(1, 2), b.unshift, b.prepend(0), b.shift(2), b.unshift(:x), b
      p (b.first(-1) rescue $!.class), (b.pop(-1) rescue $!.message), (b.shift("x") rescue $!.class), (b.first(1, 2) rescue $!.message)
      f = [1].freeze
      p (f.pop rescue $!.class), (f.pop(-1) rescue $!.class), (f.shift(0) rescue $!.class), (f.unshift rescue $!.class), f.first(1), f.last(0)
      class Stack < Array; end
      s = Stack.new([1, 2, 3])
      p s.first(2).class, s.last(2).class, s.pop(1).class, s.shift(1).class, s.class
      q = []
      20_000.times { |i| q.push(i); q.unshift(-i) }
      sum = 0
      sum += q.shift while q.size > 10
      p sum, q.size, q.first(3), q.last(3)
      p [].method(:pop).arity, [].method(:first).parameters, [].method(:shift).owner, [].method(:unshift).source_location
      p %w[a b c].method(:first).unbind.bind_call([7, 8], 1), [[1, 2]].first.first(1)

    RUBY

    _(result).must_answer <<~'OUT'
      1
      5
      [1, 2]
      [4, 5]
      []
      [1, 2, 3, 4, 5]
      [1, 2]
      5
      [3, 4]
      []
      1
      [2]
      []
      nil
      nil
      []
      []
      [:x, 2, 3, 4]
      [:x, 2, 3, 4]
      [:x, 2, 3, 4]
      [0, 1]
      [:x, 2, 3, 4]
      [:x, 2, 3, 4]
      ArgumentError
      "negative array size"
      TypeError
      "wrong number of arguments (given 2, expected 0..1)"
      FrozenError
      FrozenError
      FrozenError
      FrozenError
      [1]
      []
      Array
      Array
      Array
      Array
      Stack
      -199945
      10
      [19990, 19991, 19992]
      [19997, 19998, 19999]
      -1
      [[:opt, :n]]
      Array
      nil
      [7]
      [1]
    OUT
  end

  it "struct dig" do
    result = ze0(<<~'RUBY')
      # Struct#dig is variadic. The first key is member access (by symbol /
      # string name or integer position); any further keys dig recursively
      # into the member's value. Previously dig fell through to an unresolved
      # nil and emitted a C type error.
      Person = Struct.new(:name, :age)
      p = Person.new("Alice", 30)
      puts p.dig(:name)
      puts p.dig(:age)
      puts p.dig(0)
      puts p.dig(1)

      # nested dig: a member holding a hash is dug recursively
      Config = Struct.new(:name, :address)
      c = Config.new("server", { "country" => "JP", "city" => "Tokyo" })
      puts c.dig(:address, "country")
      puts c.dig(:address, "city")
    RUBY

    _(result).must_answer <<~'OUT'
      Alice
      30
      Alice
      30
      JP
      Tokyo
    OUT
  end
end
