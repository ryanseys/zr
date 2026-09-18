# frozen_string_literal: true

require "spec_helper"

describe "Enumerable: dispatch" do
  it "poly array map" do
    result = ze0(<<~'RUBY')
      def t_poly_array_map
        # `compile_map_expr` had no `poly_array` recv branch — a
        # heterogeneous-element array (`[1, "two", :three]`) called
        # `.map { ... }` and the dispatch fell through to the `"0"`
        # placeholder. The result was typed as `sp_IntArray *` (per the
        # inferred map result), `lv_out = 0` was emitted, and any
        # `.length` / `[i]` on the accumulator dereferenced NULL,
        # crashing at runtime.

        # (1) poly_array → IntArray (int-return block).
        arr = [1, "two", :three, 4.5]
        out = arr.map { |x| x.to_s.length }
        puts out.length      # 4
        puts out[0]          # 1
        puts out[1]          # 3
        puts out[2]          # 5
        puts out[3]          # 3

        # (2) poly_array → StrArray (string-return block).
        strs = arr.map { |x| x.to_s }
        puts strs.length     # 4
        puts strs[0]         # 1
        puts strs[1]         # two
        puts strs[2]         # three
        puts strs[3]         # 4.5

        # (3) poly_array → IntArray (different int expression).
        sizes = arr.map { |x| x.to_s.length * 2 }
        puts sizes.length    # 4
        puts sizes[0]        # 2
        puts sizes[3]        # 6
      end
      t_poly_array_map
    RUBY

    _(result).must_answer <<~'OUT'
      4
      1
      3
      5
      3
      4
      1
      two
      three
      4.5
      4
      2
      6
    OUT
  end

  it "poly array push handlers" do
    result = ze0(<<~'RUBY')
      def t_poly_array_push_handlers
        # `compile_call_expr` and `compile_mutating_call_stmt` had no `<<`
        # / `push` arms for poly_array recv. The expr-context fall-through
        # produced raw C `<<` on `sp_PolyArray *` (gcc error: "invalid
        # operands to binary <<"); the stmt-context fall-through silently
        # dropped the push from generated C entirely.
        #
        # Repro: a heterogeneous literal lowers to poly_array; then both
        # `arr << v` (expr / stmt-without-receiver-rewrite) and
        # `arr.push(v)` exercise the dispatch.

        arr = [1, "two", :three]
        arr << 42
        arr.push("four")
        puts arr.length
        puts arr[0]
        puts arr[1]
        puts arr[2]
        puts arr[3]
        puts arr[4]
      end
      t_poly_array_push_handlers
    RUBY

    _(result).must_answer <<~'OUT'
      5
      1
      two
      three
      42
      four
    OUT
  end

  it "poly hash" do
    result = ze0(<<~'RUBY')
      def t_poly_hash
        # Test heterogeneous Hash

        h = {name: "Alice", age: 30, active: true}
        puts h[:name]     # Alice
        puts h[:age]      # 30
        puts h[:active]   # true
        puts h.length     # 3

        # Iteration
        h.each do |k, v|
          puts k
        end
        # name, age, active

        puts "done"
      end
      t_poly_hash
    RUBY

    _(result).must_answer <<~'OUT'
      Alice
      30
      true
      3
      name
      age
      active
      done
    OUT
  end

  it "primitive is a" do
    result = ze0(<<~'RUBY')
      def t_primitive_is_a
        # is_a? / kind_of? / instance_of? on primitive receivers — answer
        # decided at compile time based on Ruby's class hierarchy.

        # === Integer ===
        p 5.is_a?(Integer)
        p 5.is_a?(Numeric)
        p 5.is_a?(Comparable)
        p 5.is_a?(Object)
        p 5.is_a?(Float)
        p 5.is_a?(String)
        p 5.kind_of?(Integer)
        p 5.kind_of?(Numeric)
        p 5.instance_of?(Integer)
        p 5.instance_of?(Numeric)   # false — instance_of? doesn't follow superclass

        # === Float ===
        p 1.5.is_a?(Float)
        p 1.5.is_a?(Numeric)
        p 1.5.is_a?(Comparable)
        p 1.5.is_a?(Integer)
        p 1.5.kind_of?(Numeric)
        p 1.5.instance_of?(Float)
        p 1.5.instance_of?(Numeric)

        # === String ===
        p "hi".is_a?(String)
        p "hi".is_a?(Comparable)
        p "hi".is_a?(Object)
        p "hi".is_a?(Integer)
        p "hi".kind_of?(String)
        p "hi".instance_of?(String)
        p "hi".instance_of?(Comparable)

        # === Symbol ===
        p :hi.is_a?(Symbol)
        p :hi.is_a?(Comparable)
        p :hi.is_a?(String)
        p :hi.kind_of?(Symbol)
        p :hi.instance_of?(Symbol)

        # === Top-level ancestors (Kernel / BasicObject) ===
        # Every value is in the Object hierarchy, so is_a? returns true for
        # Kernel and BasicObject as well as Object. instance_of? still
        # returns false for these because they're ancestors, not the exact
        # class of the receiver.
        p 5.is_a?(Kernel)
        p 5.is_a?(BasicObject)
        p 1.5.is_a?(Kernel)
        p 1.5.is_a?(BasicObject)
        p "hi".is_a?(Kernel)
        p "hi".is_a?(BasicObject)
        p :hi.is_a?(Kernel)
        p :hi.is_a?(BasicObject)
        p 5.instance_of?(Kernel)
        p 5.instance_of?(BasicObject)
      end
      t_primitive_is_a
    RUBY

    _(result).must_answer <<~'OUT'
      true
      true
      true
      true
      false
      false
      true
      true
      true
      false
      true
      true
      true
      false
      true
      true
      false
      true
      true
      true
      false
      true
      true
      false
      true
      true
      false
      true
      true
      true
      true
      true
      true
      true
      true
      true
      true
      false
      false
    OUT
  end

  it "poly each with index" do
    result = ze0(<<~'RUBY')
      # each_with_index on a POLY receiver - an array reached as a boxed sp_RbVal (a
      # def parameter, or an element of a nested array) - went through poly dispatch
      # that lacked each_with_index and raised NoMethodError, though plain `each` had a
      # poly path (sp_poly_each_elem). It now binds the whole element + the loop index,
      # never splatting a nested-array element (unlike `each`).
      def show(cells)
        cells.each_with_index do |v, i|
          puts "#{i}:#{v}"
        end
      end
      show(["x", 1, :sym])

      def rows(data)
        data.each do |row|
          row.each_with_index { |c, i| puts "#{i}=#{c}" }
        end
      end
      rows([["a", "b"], ["c", "d"]])

      def total(xs)
        sum = 0
        xs.each_with_index { |_v, i| sum += i }
        sum
      end
      puts total([10, 20, 30, 40])

      # A boxed (sp_RbVal) poly receiver: `cond ? array : hash` gives a TY_POLY value,
      # the path this PR adds each_with_index to. The cases below exercise its block
      # param binding.
      def poly(cond)
        cond ? [10, 20, 30] : { a: 1 }
      end

      # UNUSED index param: the pruned `i` local is never declared, so the binding
      # must be skipped (not emit an assignment to an undeclared `lv_i`).
      poly(true).each_with_index { |v, i| puts v }

      # EXTRA param beyond the yielded (element, index) arity binds to nil each
      # iteration -- a reassigned extra must not leak its prior value across passes.
      poly(true).each_with_index { |v, i, x| x = 99 unless x.nil?; puts "#{v}/#{i}/#{x.inspect}" }
    RUBY

    _(result).must_answer <<~'OUT'
      0:x
      1:1
      2:sym
      0=a
      1=b
      0=c
      1=d
      6
      10
      20
      30
      10/0/nil
      20/1/nil
      30/2/nil
    OUT
  end

  it "poly element methods" do
    result = ze0(<<~'RUBY')
      # Array-reduction methods (sum / min / max / first / last / length) called on the
      # elements of a poly array whose elements are themselves arrays -- e.g. the runs
      # produced by chunk_while. The element type is erased to poly, so the method is
      # dispatched at runtime by the boxed element's class. Works through an explicit
      # block and through &:sym. Distinct per-type helpers keep each run monomorphic.
      def ii(x) = x
      def nff(x) = x
      def nss(x) = x

      runs = ii([1, 2, 4, 5, 7]).chunk_while { |a, b| b - a == 1 }.to_a  # [[1,2],[4,5],[7]]
      p runs.map { |r| r.sum }                                          # [3, 9, 7]
      p runs.map(&:sum)                                                 # [3, 9, 7]
      p runs.map { |r| r.length }                                       # [2, 2, 1]
      p runs.map(&:max)                                                 # [2, 5, 7]
      p runs.map { |r| r.min }                                          # [1, 4, 7]
      p runs.map { |r| r.first }                                        # [1, 4, 7]
      p runs.map(&:last)                                                # [2, 5, 7]
      runs.each { |r| p r.sum }                                         # 3 / 9 / 7
      p runs.select { |r| r.sum > 5 }                                   # [[4, 5], [7]]

      # float runs sum/max to floats
      fr = nff([[1.5, 2.5], [3.5]])
      p fr.map { |r| r.sum }                                            # [4.0, 3.5]
      p fr.map(&:max)                                                   # [2.5, 3.5]

      # string runs: first / last / length
      sr = nss([["a", "b"], ["c"]])
      p sr.map { |r| r.first }                                          # ["a", "c"]
      p sr.map(&:length)                                                # [2, 1]

      # direct poly-array methods are unaffected (length / first of the runs array)
      p runs.length                                                     # 3
      p runs.first                                                      # [1, 2]
    RUBY

    _(result).must_answer <<~'OUT'
      [3, 9, 7]
      [3, 9, 7]
      [2, 2, 1]
      [2, 5, 7]
      [1, 4, 7]
      [1, 4, 7]
      [2, 5, 7]
      3
      9
      7
      [[4, 5], [7]]
      [4.0, 3.5]
      [2.5, 3.5]
      ["a", "c"]
      [2, 1]
      3
      [1, 2]
    OUT
  end

  it "poly fdiv" do
    result = ze0(<<~'RUBY')
      rings = [[[[-63.1269583, 46.2338358], [-63.1260111, 46.234436]]]]
      array = rings.flat_map { |ring| ring.first.map &:first }
      p array.sum
      p 7.0.fdiv 3
      p array.sum.fdiv array.size
      vals = [1, 2.5, 3]
      p vals[0].fdiv(vals[2])
      p vals.sum.fdiv(2)
      p 7.fdiv(2)
    RUBY

    _(result).must_answer <<~'OUT'
      -126.2529694
      2.3333333333333335
      -63.1264847
      0.3333333333333333
      3.25
      3.5
    OUT
  end

  it "poly find index block" do
    result = ze0(<<~'RUBY')
      # find_index / index / rindex WITH A BLOCK on a poly receiver.
      #
      # The block form is emitted by the typed-array path, which is keyed on the
      # storage kind, so a value only known to be an array at run time never reached
      # it and the call fell through to the unresolved-call raise. Every sibling name
      # -- find, select, count, any? -- already had a poly loop of its own; this
      # family had none, on either side: analyze did not type the call either, so
      # even once it emitted, the value was discarded.

      def pick(f)
        f ? [3, 4, 5, 6] : "no"
      end

      a = pick(true)
      p a.find_index { |x| x > 4 }
      p a.index { |x| x > 4 }
      p a.rindex { |x| x > 4 }
      p a.find_index { |x| x > 99 }
      p a.rindex { |x| x > 99 }
      p a.find_index { |x| true }

      # strings, so the element rides the pointer channel
      def pick_s(f)
        f ? ["aa", "b", "ccc"] : 0
      end

      s = pick_s(true)
      p s.find_index { |x| x.length == 1 }
      p s.rindex { |x| x.length >= 2 }

      # a truthy non-boolean block value: every type but nil/false is truthy
      p a.find_index { |x| x }
      p a.find_index { |x| nil }

      # the sibling names still answer as before
      p a.find { |x| x > 4 }
      p a.count { |x| x > 4 }

      # a hash receiver: entries arrive as pairs
      def pick_h(f)
        f ? { "a" => 1, "b" => 2 } : 0
      end

      h = pick_h(true)
      p h.find_index { |k, v| v == 2 }

      # the argument form is untouched
      p a.index(5)
    RUBY

    _(result).must_answer <<~'OUT'
      2
      2
      3
      nil
      nil
      0
      1
      2
      0
      nil
      5
      2
      1
      2
    OUT
  end

  it "poly recv arg iterators" do
    result = ze0(<<~'RUBY')
      # each_slice / each_cons / zip / cycle with a block, on a receiver only known
      # to be a container at run time. The blockless forms re-dispatched as the array
      # ones; the block forms had no arm and fell to the loud NoMethodError.
      rows = [[1, 2, 4, 5], { "a" => 1, "b" => 2 }, "x"]

      a = rows[0]
      p a.each_slice(2) { |s| s }
      p a.each_cons(2) { |s| s }
      p a.zip([9]) { |s| s }
      p a.cycle(1) { |s| s }

      # each_slice and each_cons answer the RECEIVER, so a Hash answers itself and
      # not the pairs the re-dispatch materializes from it. zip and cycle answer nil.
      h = rows[1]
      p h.each_slice(1) { |s| s }
      p h.each_cons(1) { |s| s }
      p h.zip([1]) { |s| s }
      p h.cycle(1) { |s| s }

      # the blockless forms still materialize
      p a.each_slice(2).to_a
      p a.each_cons(2).to_a

      # and the guarded forms answer nil
      def pick(n) = n > 0 ? [1, 2, 4, 5] : nil
      [1, 0].each do |k|
        v = pick(k)
        p v&.zip([9]) { |s| s }
        p v&.cycle(1) { |s| s }
      end
    RUBY

    _(result).must_answer <<~'OUT'
      [1, 2, 4, 5]
      [1, 2, 4, 5]
      nil
      nil
      {"a" => 1, "b" => 2}
      {"a" => 1, "b" => 2}
      nil
      nil
      [[1, 2], [4, 5]]
      [[1, 2], [2, 4], [4, 5]]
      nil
      nil
      nil
      nil
    OUT
  end

  it "poly recv find chunk" do
    result = ze0(<<~'RUBY')
      # find / detect answer the winning ELEMENT of a receiver only known to be a
      # container at run time, and the chunk family answers an Enumerator unless a
      # .to_a terminal materializes the runs. Both had no arm for a poly receiver and
      # fell through to the last-resort Hash face, which types find as the [k, v]
      # pair -- a type the emitter never renders.
      rows = [[1, 2, 4, 5], { "a" => 1, "b" => 2 }, "x"]

      a = rows[0]
      p a.find { |x| x > 2 }
      p a.detect { |x| x > 2 }
      p a.chunk { |x| x > 2 }.to_a
      p a.slice_before { |x| x > 3 }.to_a
      p a.slice_after { |x| x > 3 }.to_a

      # a Hash answers its [k, v] pairs through the same loop
      h = rows[1]
      p h.find { |k, n| n > 1 }
      p h.detect { |k, n| n > 1 }

      def pick(n) = n > 0 ? [1, 2, 4, 5] : nil
      [1, 0].each do |k|
        v = pick(k)
        p v&.find { |x| x > 2 }
        p v&.detect { |x| x > 2 }
        r = v&.chunk { |x| x > 2 }
        p(r.nil? ? nil : r.to_a)
      end
    RUBY

    _(result).must_answer <<~'OUT'
      4
      4
      [[false, [1, 2]], [true, [4, 5]]]
      [[1, 2], [4], [5]]
      [[1, 2, 4], [5]]
      ["b", 2]
      ["b", 2]
      4
      4
      [[false, [1, 2]], [true, [4, 5]]]
      nil
      nil
      nil
    OUT
  end

  it "poly recv map join" do
    result = ze0(<<~'RUBY')
      # Issue #654: `arr.map { ... }.join(sep)` on a poly-typed
      # receiver (e.g. parameter with `= nil` default that widens to
      # sp_RbVal) silently emitted `sp_StrArray * _t = 0` for the map
      # result, then `sp_StrArray_join(NULL, sep)` returned empty in
      # the standalone repro and segfaulted on the downstream pointer
      # deref in real-blog AOT.
      #
      # Fix: compile_map_expr now has a `rt == "poly"` arm that emits
      # runtime tag dispatch on cls_id (PolyArray / IntArray / StrArray
      # / FloatArray) and routes the per-element fetch through the
      # matching `_get` helper. The block param is sp_RbVal; the
      # accumulator picks its variant (StrArray when the block returns
      # string, etc.) from the block's last expression's static type.

      def joined(arr = nil)
        return "(empty)" if arr.nil?
        arr.map { |x| "v=#{x}" }.join(",")
      end

      puts joined(["a", "b"])
      puts joined(["x"])
      puts joined([])
      puts joined(nil)

      # Heterogeneous (poly-array) elements via the same poly param.
      def joined_int(arr = nil)
        return "(none)" if arr.nil?
        arr.map { |x| "n=#{x}" }.join(";")
      end

      puts joined_int([1, 2, 3])
    RUBY

    _(result).must_answer <<~'OUT'
      v=a,v=b
      v=x

      (empty)
      n=1;n=2;n=3
    OUT
  end
end
