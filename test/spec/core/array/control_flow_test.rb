# frozen_string_literal: true

require "spec_helper"

describe "Array: control flow" do
  it "select! answers nil when it removed nothing, and a frozen receiver raises whatever the kind" do
    result = zr(<<~'RUBY')
      # Array#select! / #filter! / #reject! return nil when nothing was removed and
      # self otherwise; #keep_if / #delete_if always return self. Receivers route
      # through a method param so the runtime (not a folded literal) path runs. Each
      # helper is called with a single element-kind: mixing int and poly arrays
      # through one param would widen the param to poly and bypass the typed path.
      def si(x); x; end   # int arrays only
      def sm(x); x; end   # mixed (poly) arrays only

      # --- typed int array: nil-when-unchanged for the ! forms ---
      p si([1, 2, 3]).reject! { |x| x > 99 }   # nothing removed -> nil
      p si([1, 2, 3]).reject! { |x| x > 1 }    # removed -> self
      p si([1, 2, 3]).select! { |x| x > 0 }    # all kept -> nil
      p si([1, 2, 3]).select! { |x| x > 1 }    # removed -> self
      p si([1, 2, 3]).filter! { |x| x.even? }  # removed -> self

      # --- keep_if / delete_if always return self ---
      p si([1, 2, 3]).keep_if { |x| x > 99 }   # empty, but self
      p si([1, 2, 3]).delete_if { |x| x > 0 }  # empty, but self
      p si([1, 2, 3]).keep_if { |x| x > 1 }    # self

      # --- mutation is visible on the receiver afterwards ---
      a = si([1, 2, 3, 4])
      a.reject! { |x| x.even? }
      p a

      # --- empty receiver ---
      p si([]).reject! { |x| x > 0 }           # nothing removed -> nil

      # --- poly (mixed) array: same return contract ---
      p sm([1, "two", 3]).reject! { |x| x == 99 }  # nothing removed -> nil
      p sm([1, "two", 3]).reject! { |x| x == 3 }   # removed -> self
      p sm([1, "two", 3]).select! { |x| x != 99 }  # all kept -> nil
      c = sm([1, "two", 3, 4])
      c.select! { |x| x != "two" }
      p c

      # --- frozen receiver raises FrozenError (message detail is a separate gap) ---
      fi = si([1, 2, 3].freeze)
      begin; fi.reject! { |x| x > 1 }; rescue => e; puts e.class; end
      fm = sm(["a", 1, "b"].freeze)
      begin; fm.select! { |x| x != 1 }; rescue => e; puts e.class; end
    RUBY

    _(result).must_answer <<~'OUT'
      nil
      [1]
      nil
      [2, 3]
      [2]
      []
      []
      [2, 3]
      [1, 3]
      nil
      nil
      [1, "two"]
      nil
      [1, 3, 4]
      FrozenError
      FrozenError
    OUT
  end

  it "unshift prepends its arguments in order and answers the receiver" do
    result = zr(<<~'RUBY')
      # Array#unshift prepends its arguments and returns the (mutated) receiver.
      # The return value was lost (nil) for the assigned/expression form, and the
      # float-array case did not actually prepend. Covers int, string, and float
      # arrays, multi-argument unshift (argument order preserved), the statement
      # form, and a non-literal receiver.
      x = [2, 3].unshift(1)
      p x
      a = ["x", "y"]
      p a.unshift("z")
      b = [1.0, 2.0]
      p b.unshift(0.5)
      p [2, 3].unshift(1, 0)

      q = [1, 2]
      q.unshift(0)
      p q

      def prepend9(arr)
        arr.unshift(9)
      end
      p prepend9([1, 2])

      # Multi-argument unshift evaluates its arguments left to right, even though
      # they are prepended in reverse to keep argument order.
      order = []
      mk = ->(v) { order << v; v.to_f }
      fa = [9.0]
      fa.unshift(mk.call(1), mk.call(2))
      p fa
      p order
    RUBY

    _(result).must_answer <<~'OUT'
      [1, 2, 3]
      ["z", "x", "y"]
      [0.5, 1.0, 2.0]
      [1, 0, 2, 3]
      [0, 1, 2]
      [9, 1, 2]
      [1.0, 2.0, 9.0]
      [1, 2]
    OUT
  end

  it "a push inside a loop over an empty array still grows the array" do
    result = zr(<<~'RUBY')
      # Issue #412. An empty array literal followed by a `<<` push
      # inside a loop, where the pushed value rides through an
      # intermediate variable, emitted as `sp_IntArray *` even though
      # the pushed values were class pointers:
      #
      #   def make
      #     results = []
      #     i = 0
      #     while i < 3
      #       instance = Foo.new
      #       results << instance        # ← intermediate var
      #       i += 1
      #     end
      #     results
      #   end
      #
      #   error: passing argument 2 of 'sp_IntArray_push' makes integer
      #          from pointer without a cast
      #     sp_IntArray_push(lv_results, lv_instance);
      #                                  ^~~~~~~~~~~
      #
      # Three combinations distinguished:
      #
      #   - direct push (`results << Foo.new`)            -- worked
      #   - intermediate var, no loop                     -- worked
      #   - intermediate var INSIDE loop                  -- failed
      #
      # Root cause: `scan_locals`'s `<<` push observation upgrades
      # `int_array → <typed>_array` only when `infer_type(arg)` resolves
      # to a typed value. In pass 1, the intermediate local
      # (`instance`) hadn't been declared in the scope yet, so
      # `infer_type(LocalVariableReadNode "instance")` fell back to
      # "int" via `find_var_type` returning "" — push didn't upgrade.
      # Pass 2 (with locals declared) DID resolve and DID upgrade
      # `ltypes2[results]` to `obj_Foo_ptr_array`, but
      # `refine_method_body_locals`'s pass-1↔pass-2 merge only handled
      # `int → concrete` and `nil → nullable_pointer`, not
      # `int_array → typed_array`. The pass-2 result was dropped.
      #
      # Compounding the local-decl miss: `infer_all_returns`'s
      # top-level-method branch ran a single-pass `scan_locals` before
      # calling `infer_body_return`, so the function's return type was
      # also pinned at `int_array` independently of what
      # precompute_all_scope_decls eventually computed for the local.
      # Both branches now route through `refine_method_body_locals`.
      #
      # Coverage:
      #   - the canonical Rails-style `_adapter_all` shape from the
      #     issue's repro,
      #   - a typed-array (str) variant to prove the pass-2 merge
      #     covers `int_array → str_array` too,
      #   - a baseline direct-push variant as a regression check that
      #     the previously-working path still works.

      class Foo
        attr_accessor :v
        def initialize
          @v = 0
        end
      end

      def make_with_intermediate
        results = []
        i = 0
        while i < 3
          instance = Foo.new
          results << instance
          i += 1
        end
        results
      end

      a = make_with_intermediate
      puts a.length                   # 3

    RUBY

    _(result).must_answer <<~'OUT'
      3
    OUT
  end

  it "a String built in the same shape keeps every row it pushed" do
    result = zr(<<~'RUBY')
      # Issue #412. An empty array literal followed by a `<<` push
      # inside a loop, where the pushed value rides through an
      # intermediate variable, emitted as `sp_IntArray *` even though
      # the pushed values were class pointers:
      #
      #   def make
      #     results = []
      #     i = 0
      #     while i < 3
      #       instance = Foo.new
      #       results << instance        # ← intermediate var
      #       i += 1
      #     end
      #     results
      #   end
      #
      #   error: passing argument 2 of 'sp_IntArray_push' makes integer
      #          from pointer without a cast
      #     sp_IntArray_push(lv_results, lv_instance);
      #                                  ^~~~~~~~~~~
      #
      # Three combinations distinguished:
      #
      #   - direct push (`results << Foo.new`)            -- worked
      #   - intermediate var, no loop                     -- worked
      #   - intermediate var INSIDE loop                  -- failed
      #
      # Root cause: `scan_locals`'s `<<` push observation upgrades
      # `int_array → <typed>_array` only when `infer_type(arg)` resolves
      # to a typed value. In pass 1, the intermediate local
      # (`instance`) hadn't been declared in the scope yet, so
      # `infer_type(LocalVariableReadNode "instance")` fell back to
      # "int" via `find_var_type` returning "" — push didn't upgrade.
      # Pass 2 (with locals declared) DID resolve and DID upgrade
      # `ltypes2[results]` to `obj_Foo_ptr_array`, but
      # `refine_method_body_locals`'s pass-1↔pass-2 merge only handled
      # `int → concrete` and `nil → nullable_pointer`, not
      # `int_array → typed_array`. The pass-2 result was dropped.
      #
      # Compounding the local-decl miss: `infer_all_returns`'s
      # top-level-method branch ran a single-pass `scan_locals` before
      # calling `infer_body_return`, so the function's return type was
      # also pinned at `int_array` independently of what
      # precompute_all_scope_decls eventually computed for the local.
      # Both branches now route through `refine_method_body_locals`.
      #
      # Coverage:
      #   - the canonical Rails-style `_adapter_all` shape from the
      #     issue's repro,
      #   - a typed-array (str) variant to prove the pass-2 merge
      #     covers `int_array → str_array` too,
      #   - a baseline direct-push variant as a regression check that
      #     the previously-working path still works.

      class Foo
        attr_accessor :v
        def initialize
          @v = 0
        end
      end

      def make_with_intermediate
        results = []
        i = 0
        while i < 3
          instance = Foo.new
          results << instance
          i += 1
        end
        results
      end

      def make_strs_with_intermediate
        buf = []
        i = 0
        while i < 4
          s = "row" + i.to_s
          buf << s
          i += 1
        end
        buf
      end

      s = make_strs_with_intermediate
      puts s.length                   # 4
      puts s[0]                       # row0
      puts s[3]                       # row3

    RUBY

    _(result).must_answer <<~'OUT'
      4
      row0
      row3
    OUT
  end

  it "the direct push it is measured against answers the same" do
    result = zr(<<~'RUBY')
      # Issue #412. An empty array literal followed by a `<<` push
      # inside a loop, where the pushed value rides through an
      # intermediate variable, emitted as `sp_IntArray *` even though
      # the pushed values were class pointers:
      #
      #   def make
      #     results = []
      #     i = 0
      #     while i < 3
      #       instance = Foo.new
      #       results << instance        # ← intermediate var
      #       i += 1
      #     end
      #     results
      #   end
      #
      #   error: passing argument 2 of 'sp_IntArray_push' makes integer
      #          from pointer without a cast
      #     sp_IntArray_push(lv_results, lv_instance);
      #                                  ^~~~~~~~~~~
      #
      # Three combinations distinguished:
      #
      #   - direct push (`results << Foo.new`)            -- worked
      #   - intermediate var, no loop                     -- worked
      #   - intermediate var INSIDE loop                  -- failed
      #
      # Root cause: `scan_locals`'s `<<` push observation upgrades
      # `int_array → <typed>_array` only when `infer_type(arg)` resolves
      # to a typed value. In pass 1, the intermediate local
      # (`instance`) hadn't been declared in the scope yet, so
      # `infer_type(LocalVariableReadNode "instance")` fell back to
      # "int" via `find_var_type` returning "" — push didn't upgrade.
      # Pass 2 (with locals declared) DID resolve and DID upgrade
      # `ltypes2[results]` to `obj_Foo_ptr_array`, but
      # `refine_method_body_locals`'s pass-1↔pass-2 merge only handled
      # `int → concrete` and `nil → nullable_pointer`, not
      # `int_array → typed_array`. The pass-2 result was dropped.
      #
      # Compounding the local-decl miss: `infer_all_returns`'s
      # top-level-method branch ran a single-pass `scan_locals` before
      # calling `infer_body_return`, so the function's return type was
      # also pinned at `int_array` independently of what
      # precompute_all_scope_decls eventually computed for the local.
      # Both branches now route through `refine_method_body_locals`.
      #
      # Coverage:
      #   - the canonical Rails-style `_adapter_all` shape from the
      #     issue's repro,
      #   - a typed-array (str) variant to prove the pass-2 merge
      #     covers `int_array → str_array` too,
      #   - a baseline direct-push variant as a regression check that
      #     the previously-working path still works.

      class Foo
        attr_accessor :v
        def initialize
          @v = 0
        end
      end

      def make_with_intermediate
        results = []
        i = 0
        while i < 3
          instance = Foo.new
          results << instance
          i += 1
        end
        results
      end

      # Baseline direct-push (was already working).
      def make_direct
        results = []
        i = 0
        while i < 3
          results << Foo.new
          i += 1
        end
        results
      end

      puts make_direct.length         # 3
    RUBY

    _(result).must_answer <<~'OUT'
      3
    OUT
  end

  it "empty array return via local" do
    result = zr(<<~'RUBY')
      # An empty array literal returned from a method through a LOCAL variable lost
      # its container type and settled at String: the method was emitted as
      # `sp_String *lv_a = sp_String_new_shared(sp_IntArray_new())`, and every use of
      # the result in the caller followed it -- `<<` became sp_String_append_bin, so a
      # Float or an object arrived at a `const char *` parameter.
      #
      # Returning the very same literal directly (`def make_direct; []; end`) was
      # always fine, which is what kept this hidden.

      def make
        a = []
        a
      end

      xs = make
      xs << 1.5
      p xs
      p xs.length

      def make_direct
        []
      end

      ys = make_direct
      ys << 1.5
      p ys

      # push instead of << also stayed correct: only << is ambiguous between Array
      # and String, so only << followed the mistyped literal.
      def make_push
        a = []
        a
      end

      zs = make_push
      zs.push(1.5)
      p zs

      # The shape this was found in: a generic top-K helper whose result is assigned
      # back over its argument, with the accumulator seeded from a bare [].
      class Item
        attr_reader :score
        def initialize(s)
          @score = s
        end
      end

      def top1(kept)
        trimmed = []
        trimmed << kept[0]
        trimmed
      end

      items = []
      items << Item.new(3.0)
      items << Item.new(1.0)
      items = top1(items)
      p items.length
      p items[0].score

      # The other side of the gate (#3227 P6): when the caller's slot really is a
      # String, mutating the result of a method whose tail is a local still has to
      # pull that local into the shared-handle set, so the mutation lands on the one
      # buffer and aliases of it see the change.
      def make_held
        s = +"x"
        s << "y"
        s
      end

      r = make_held
      r << "z"
      p r

      def mk2
        a = +"p"
        a
      end

      q = mk2
      q2 = q
      q << "!"
      p q
      p q2
      p q.equal?(q2)
    RUBY

    _(result).must_answer <<~'OUT'
      [1.5]
      1
      [1.5]
      [1.5]
      1
      3.0
      "xyz"
      "p!"
      "p!"
      true
    OUT
  end

  it "float to s uses fixed for fractional 16 digit values" do
    result = zr(<<~'RUBY')
      # Ruby #2593: a 16-digit-integer-part float WITH a fraction prints fixed,
      # while an integer-valued 16-digit double stays scientific.

      puts 4503599627370495.5
      puts 1234567890123456.7
      puts(-4503599627370495.5)
      puts 9007199254740992.0
      puts 1e15
      puts 1e16
    RUBY

    _(result).must_answer <<~'OUT'
      4503599627370495.5
      1234567890123456.8
      -4503599627370495.5
      9.007199254740992e+15
      1.0e+15
      1.0e+16
    OUT
  end

  it "for loop over range and array" do
    result = zr(<<~'RUBY')
      # Arithmetic on the Range case works through the emitter's numeric
      # lowering and its runtime-checked fallback; an
      # `Array`'s elements aren't tracked per-element (`Poly`), so the
      # array case just displays each value.

      sum = 0
      for i in 1..5
        sum += i
      end
      puts sum
      puts i

      arr = [10, 20, 30]
      for el in arr
        puts el
      end
    RUBY

    _(result).must_answer <<~'OUT'
      15
      5
      10
      20
      30
    OUT
  end

  it "for loop reads the live array" do
    result = zr(<<~'RUBY')
      a = [1, 2, 3]
      seen = []
      for x in a
        seen << x
        a << x + 10 if x < 3      # append during iteration
      end
      p seen
      b = [1, 2, 3, 4]
      seen2 = []
      for y in b
        seen2 << y
        b.pop if y == 1           # shrink during iteration
      end
      p seen2
      c = [1, 2, 3]
      seen3 = []
      for z in c
        seen3 << z
        c[1] = 99 if z == 1       # rewrite upcoming slot
      end
      p seen3
    RUBY

    _(result).must_answer <<~'OUT'
      [1, 2, 3, 11, 12]
      [1, 2, 3]
      [1, 99, 3]
    OUT
  end

  it "multi assign array underfill" do
    result = zr(<<~'RUBY')
      # Multiple assignment from a single array RHS with fewer elements than targets:
      # the surplus targets land nil (`a, b, c = [10, 20]` -> c is nil). Previously
      # rejected at compile time ("unsupported multiple assignment"); the surplus
      # targets now nil-fill and the affected local widens to poly so it can hold nil.
      # Receivers routed through a method param exercise the typed runtime path.
      def s(x); x; end

      # top-level under-fill: trailing target nil
      a, b, c = s([10, 20])
      p [a, b, c]

      # two missing trailing targets
      d, e, f = s([1])
      p [d, e, f]

      # string elements, nil tail
      g, h, i = s(["x", "y"])
      p [g, h, i]

      # float elements, nil tail
      j, k, l = s([1.5])
      p [j, k, l]

      # under-fill inside a method, result returned as an array literal (exercises
      # method-return inference: the array must type as poly because of the nil tail)
      def from_pair
        x, y, z = [1, 2]
        [x, y, z]
      end
      p from_pair

      # the surplus nil target is usable; the supplied ones keep their real type
      m, n = s([5])
      p m + 1
      p n.nil?

      # exact length and over-supplied forms still behave
      p1, p2, p3 = s([1, 2, 3])
      p [p1, p2, p3]
      q1, q2 = s([1, 2, 3])
      p [q1, q2]
    RUBY

    _(result).must_answer <<~'OUT'
      [10, 20, nil]
      [1, nil, nil]
      ["x", "y", nil]
      [1.5, nil, nil]
      [1, 2, nil]
      6
      true
      [1, 2, 3]
      [1, 2]
    OUT
  end

  it "return break and next with several values build an implicit array" do
    result = zr(<<~'RUBY')
      # A single SPLAT is the case a plain "one argument -> pass it through"
      # rule gets wrong: `return *a` with `a == [1]` is `[1]`, not `1`.

      def two; return 1, 2; end
      p two
      def three; return 1, 2, 3; end
      p three
      def splat_ret(a); return *a; end
      p splat_ret([1, 2])
      p splat_ret([1])
      def mixed(a); return 1, *a; end
      p mixed([2, 3])
      p([1].each { break 1, 2 })
      p([[1, 2]].map { |a, b| next a, b })
      def none; return; end
      p none
    RUBY

    _(result).must_answer <<~'OUT'
      [1, 2]
      [1, 2, 3]
      [1, 2]
      [1]
      [1, 2, 3]
      [1, 2]
      [[1, 2]]
      nil
    OUT
  end

  it "return object array across methods" do
    result = zr(<<~'RUBY')
      # A method that accumulates objects into a local and returns it: the local and
      # the method's value name one storage location, so the caller's slot has to
      # follow the callee's return type. Also covers the shapes the pass must leave
      # alone -- a returned array read back through a runtime protocol (`to_a`), and
      # one whose element classes conflict.
      class P
        attr_reader :x
        def initialize(x)
          @x = x
        end
      end

      class Q
        attr_reader :y
        def initialize(y)
          @y = y
        end
      end

      def build(n)
        out = []
        i = 0
        while i < n
          out.push(P.new(i * 2))
          i += 1
        end
        out
      end

      def total(ps)
        s = 0
        i = 0
        while i < ps.length
          s += ps[i].x
          i += 1
        end
        s
      end

      def mixed(n)
        n > 0 ? [P.new(1), Q.new(2)] : []
      end

      class Pair
        def initialize(a, b)
          @a = a
          @b = b
        end

        def to_a
          [@a, @b]
        end
      end

      ps = build(5)
      p total(ps)
      p build(3).length
      p mixed(1).length
      p Pair.new(7, "x").to_a.length
      p Pair.new(7, "x").to_a[0]
    RUBY

    _(result).must_answer <<~'OUT'
      20
      3
      2
      2
      7
    OUT
  end
end
