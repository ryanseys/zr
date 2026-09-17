# frozen_string_literal: true

require "spec_helper"

describe "Methods: regressions" do
  it "bundle int a" do
    result = ze0(<<~'RUBY')
      # Bundled tests:
      #   - int_array_literal_lshift_heterogeneous
      #   - int_array_replace_expr
      #   - int_eq_nil_strict

      # === int_array_literal_lshift_heterogeneous ===
      def t_int_array_literal_lshift_heterogeneous
        # `<int_array literal> << <non-int>` shape (`[1, 2] << "c"`).
        # Pushing a non-int element onto a literal int_array previously
        # emitted sp_IntArray_push with a pointer-from-int-conversion
        # warning and produced a broken array. The contextual lift
        # rebuilds the recv as a poly_array of box_int(...) elements and
        # pushes the boxed arg, matching CRuby's heterogeneous-array
        # semantic.
        #
        # Scoped to direct ArrayNode literals on the LHS, so a stored
        # ivar / local (`@slots = [nil] * N; @slots << ...`) keeps the
        # existing observation-widening path. Issue #619 puzzle 7.
        p ([1, 2] << "c") == [1, 2, "c"]       # true
        p ([1, 2] << nil) == [1, 2, nil]       # true
        p ([1, 2] << 3) == [1, 2, 3]           # true (int <<, no lift)
      end
      t_int_array_literal_lshift_heterogeneous

      # === int_array_replace_expr ===
      def t_int_array_replace_expr
        # `Array#replace` in *expression* position on an int_array.
        # The stmt-form arm has long supported this; the expr-form was
        # missing — unresolved-call warning + literal `0` emitted.
        # Surfaced via optcarrot's `def load_battery; ...; @wrk.replace(sav.bytes); end`,
        # where the call sits at the tail of the method (its value is
        # the implicit return).
        
        a = [1, 2, 3]
        b = [10, 20, 30, 40]
        
        # Expression position: assigned. Should yield the (mutated) `a`.
        c = a.replace(b)
        
        # `a` mutated in place
        puts a[0]
        puts a[1]
        puts a[2]
        puts a[3]
        puts a.length
        
        # `c` is the same array (replace returns the receiver)
        puts c[0]
        puts c.length
      end
      t_int_array_replace_expr

      # === int_eq_nil_strict ===
      def t_int_eq_nil_strict
        # Partial fix for #521. In CRuby `0 == nil` is false -- only nil
        # equals nil. Spinel used to emit `(lc op rc)` for `int == nil`,
        # where `rc` was "0" (compile_expr of NilNode); since unboxed ints
        # share the C representation with the nil sentinel, this conflated
        # stored 0 with nil and made `0 == nil` return true.
        #
        # Fix: compile_eq has explicit value-type-vs-nil arms that
        # constant-fold to FALSE (or TRUE for `!=`). This does NOT solve
        # the deeper #521 problem -- Hash<String,Int> still returns 0 for
        # missing keys -- but it does fix the categorical bug that made a
        # *stored* 0 in the hash indistinguishable from "the value is
        # nil." With this fix, `v != nil` reflects the static type
        # honestly, so users who need to distinguish missing-vs-stored
        # zero have to reach for `Hash#has_key?` / `Hash#fetch`, as
        # documented in the issue comment.
        
        # Pure int (no hash)
        v = 0
        puts (v == nil).inspect   # false
        puts (v != nil).inspect   # true
        
        w = 5
        puts (w == nil).inspect   # false
        puts (w != nil).inspect   # true
        
        # Float / bool same.
        f = 0.0
        puts (f == nil).inspect   # false
        puts (f != nil).inspect   # true
        
        b = false
        puts (b == nil).inspect   # false
        
        # Hash<String,Int> stored 0 case now reports != nil correctly.
        h = {}
        h["x"] = 0
        h["y"] = 5
        vx = h["x"]
        vy = h["y"]
        puts (vx == nil).inspect  # false (was true)
        puts (vx != nil).inspect  # true  (was false)
        puts (vy == nil).inspect  # false
        puts (vy != nil).inspect  # true
        
        # Symmetric: nil == int is also false.
        puts (nil == 0).inspect   # false
        puts (nil != 0).inspect   # true
      end
      t_int_eq_nil_strict

    RUBY

    _(result).must_answer <<~'OUT'
      true
      true
      true
      10
      20
      30
      40
      4
      10
      4
      false
      true
      false
      true
      false
      true
      false
      false
      true
      false
      true
      false
      true
    OUT
  end

  it "bundle misc b" do
    _(ze0(<<~'RUBY')).must_answer "10\n10\n6\nnil\n7\n7\n6\n6\n1\n2\n3\n4\n10\nhello\nworld\n20\n1\n2\n3\n20\n40\n2\n4\n6\n20\n40\n60\n3\n4\nalice\nbob\n1=10\n2=20\n3=30\n1-2-3\n10-20-30\n606\n54\n56\n2\n2\n5\n5\n13\n13\n1\n10\n1\n10\n55\n55\n3628800\n55\n20000\nkept-string-value-0\n999\n20000\n0\n39998\n20000\nout-src-0\n999\n20000\n5\n9\n3001\npadded\next\n3000\n0\n5998\n3000\nkept-0-with-extra-padding-text\next\n3000\n1\n3000\n1024\n8\n3100\n8023\n5\n5\n15\n5\nあ\nい\nう\nえ\nお\nおえういあ\nあ\nい\nお\nお\nいう\nいうえ\nうえ\n5\n2\n3\nあXう\n3\n3\nあああ\nあいう\nあ****\n****あ\n  あ  \n5\nぃ\nba\ntrue\ntrue\ntrue\n[日][本][語]\nあ\nい\nう\n3\n"
      # Bundled tests:
      #   - local_or_and_write
      #   - multi_target_nested
      #   - numbered_block_params
      #   - numbered_params_destructure
      #   - parens_multi_stmt_and_local_write_expr
      #   - sort_reduce
      #   - gc_root_map_accumulator
      #   - gc_root_range_and_times_map
      #   - transpose_gc_root
      #   - utf8

      # === local_or_and_write ===
      def t_local_or_and_write
        # `LocalVariableOrWriteNode` (`a ||= b`) and
        # `LocalVariableAndWriteNode` (`a &&= b`) parse as their own
        # AST nodes — distinct from `LocalVariableOperatorWriteNode`
        # (which carries `+`, `-`, `*`, etc. via a binary_operator field).
        # Without dedicated parser cases the prism nodes were dropped on
        # the floor, so `a ||= b` produced no C output.
        
        # (1) Statement-form ||=
        a = nil
        a ||= 10
        puts a       # 10
        a ||= 99     # already truthy → no-op
        puts a       # 10
        
        # (2) Statement-form &&=
        b = 5
        b &&= b + 1
        puts b       # 6
        c = nil
        c &&= 99     # nil → no-op
        puts c.nil? ? "nil" : c.to_s   # nil
        
        # (3) Expression-form ||=
        x = nil
        y = (x ||= 7)
        puts x       # 7
        puts y       # 7
        
        # (4) Expression-form &&=
        p = 3
        q = (p &&= p * 2)
        puts p       # 6
        puts q       # 6
      end
      t_local_or_and_write

      # === multi_target_nested ===
      def t_multi_target_nested
        # MultiTargetNode -- nested LHS in destructuring multi-assign.
        #
        #   a, (b, c), d = 1, [2, 3], 4
        #
        # Each parenthesized group on the LHS is a MultiTargetNode that
        # recursively unpacks its slot of the RHS. Spinel routes through
        # emit_multi_write_target which dispatches on the target node type.
        # The inner-array RHS slot must be a typed-array (int_array, str_array,
        # or float_array). Two-level nesting where intermediate slots are
        # heterogeneous (poly_array) is out of scope -- documented inline.
        
        a, (b, c), d = 1, [2, 3], 4
        puts a    # 1
        puts b    # 2
        puts c    # 3
        puts d    # 4
        
        # String-typed inner array
        x, (s, t), y = 10, ["hello", "world"], 20
        puts x    # 10
        puts s    # hello
        puts t    # world
        puts y    # 20
      end
      t_multi_target_nested

      # === numbered_block_params ===
      def t_numbered_block_params
        # Numbered block params (`_1`) and Ruby 3.4 implicit `it`.
        #
        # `_1` was already supported via Prism's NumberedParametersNode + a
        # regular LocalVariableReadNode at the use site. Implicit `it` (Ruby
        # 3.4) was emitted as PM_IT_PARAMETERS_NODE / PM_IT_LOCAL_VARIABLE_READ_NODE
        # which the codegen had no handler for. spinel_parse now lowers both
        # to their `_1` equivalents so the codegen reuses the existing path.
        
        # 1. `_1` over an int array — each.
        [1, 2, 3].each { puts _1 }
        # 1
        # 2
        # 3
        
        # 2. `_1` over a map+each chain.
        [10, 20].map { _1 * 2 }.each { puts _1 }
        # 20
        # 40
        
        # 3. `it` over an int array — each with arithmetic.
        [1, 2, 3].each { puts it * 2 }
        # 2
        # 4
        # 6
        
        # 4. `it` over a map+each chain.
        [10, 20, 30].map { it * 2 }.each { puts it }
        # 20
        # 40
        # 60
        
        # 5. `it` mixed with arithmetic and comparison.
        [1, 2, 3, 4].select { it > 2 }.each { puts it }
        # 3
        # 4
        
        # 6. `it` over a string array.
        ["alice", "bob"].each { puts it }
        # alice
        # bob
      end
      t_numbered_block_params

      # === numbered_params_destructure ===
      def t_numbered_params_destructure
        # Multi-arg numbered block params (`_1`, `_2`, ...) should destructure
        # the yielded sub-array. Pre-fix: `_1` binds to the whole element
        # (the sp_IntArray pointer) and `_2` is uninitialized -> "<ptr>=0".
        # CRuby ref: arity-N blocks over a single Array argument auto-destructure.
        
        # Plain int-tuple sub-arrays - max=2 destructure
        [[1, 10], [2, 20], [3, 30]].each { puts "#{_1}=#{_2}" }
        
        # Three-element sub-arrays exercise _3
        [[1, 2, 3], [10, 20, 30]].each { puts "#{_1}-#{_2}-#{_3}" }
        
        # Sum of paired elements via destructured slots in `.each`
        total = 0
        [[1, 100], [2, 200], [3, 300]].each { total = total + _1 + _2 }
        puts total
        
        # Two-stage: outer each with _1+_2, inner reuse outside the block
        running = 0
        [[10, 1], [20, 2], [30, 3]].each { running = running + _1 - _2 }
        puts running
        
        # Short sub-array regression — pre-fix the destructure read past the
        # sub-array's data buffer (OOB) when the yielded element was shorter
        # than the block's max numbered param. The fix bounds-checks each slot
        # read and pads with 0 (typed-nil analogue). This test computes the
        # sum of `_1 + _2` only when `_2` is not nil (so CRuby gets the same
        # numbers as Spinel — Spinel's typed-zero already passes the .nil?
        # false branch). `_2` is mentioned in the block so destruct_n >= 2.
        short_total = 0
        [[1], [2, 20], [3, 30]].each { short_total = short_total + _1 + (_2.nil? ? 0 : _2) }
        puts short_total
      end
      t_numbered_params_destructure

      # === parens_multi_stmt_and_local_write_expr ===
      def t_parens_multi_stmt_and_local_write_expr
        # Verify two expression-context constructs:
        # - `(stmt1; stmt2; ...; expr)` — leading statements run for
        #   side effects; the value of the parens is the last expression.
        # - `local = expr` and `local OP= expr` used as expressions —
        #   they assign and yield the new value of the local.
        
        # (1) Multi-stmt parens — leading side effects must run.
        x = 0
        y = (x = x + 1; x = x + 1; x)
        puts x      # 2
        puts y      # 2
        
        # (2) `local = expr` as the value of an outer expression.
        a = 0
        b = (a = 5)
        puts a      # 5
        puts b      # 5
        
        # (3) `local OP= expr` as the value of an outer expression.
        c = 10
        d = (c += 3)
        puts c      # 13
        puts d      # 13
      end
      t_parens_multi_stmt_and_local_write_expr

      # === sort_reduce ===
      def t_sort_reduce
        # Test Array#sort, reduce, min, max, sum
        
        arr = (1..10).to_a
        arr.reverse!
        
        # sort
        sorted = arr.sort
        puts sorted.first  # 1
        puts sorted.last   # 10
        
        # min/max/sum
        puts arr.min   # 1
        puts arr.max   # 10
        puts arr.sum   # 55
        
        # reduce
        puts arr.reduce(0) { |sum, x| sum + x }   # 55
        puts arr.reduce(1) { |prod, x| prod * x } # 3628800
        
        # inject (alias)
        puts arr.inject(0) { |s, x| s + x }  # 55
      end
      t_sort_reduce

      # === gc_root_map_accumulator ===
      def t_gc_root_map_accumulator
        # A nested map block — outer iteration allocates plenty of inner
        # objects via sp_*_new — can trigger a GC pass between pushes
        # into the outer accumulator. Without rooting the accumulator,
        # GC frees it as unreachable; the next push then writes into
        # freed memory and corrupts malloc bookkeeping, surfacing as a
        # SIGSEGV in _int_malloc on the next allocation.
        #
        # Each .map below crosses spinel's 256KB GC threshold mid-loop
        # (each block iteration allocates a discarded scratch string
        # alongside the kept result), so the outer accumulator must be
        # rooted to survive a collection.
        
        # (1) int_array recv → StrArray accumulator (string-return block).
        ints = []
        i = 0
        while i < 20000
          ints << i
          i += 1
        end
        
        r1 = ints.map do |x|
          _scratch = "scratch-#{x}-discarded-inner-allocation-padding"
          "kept-string-value-#{x}"
        end
        puts r1.length            # 20000
        puts r1[0]                # kept-string-value-0
        puts r1[19999][-3, 3]     # 999
        
        # (2) int_array recv → IntArray accumulator (int-return block).
        r2 = ints.map do |x|
          _scratch = "scratch-#{x}-discarded-inner-allocation-padding"
          x * 2
        end
        puts r2.length            # 20000
        puts r2[0]                # 0
        puts r2[19999]            # 39998
        
        # (3) str_array recv → StrArray accumulator (string-return block).
        strs = []
        i = 0
        while i < 20000
          strs << "src-#{i}"
          i += 1
        end
        
        r3 = strs.map do |s|
          _scratch = "scratch-#{s}-discarded-inner-allocation-padding"
          "out-#{s}"
        end
        puts r3.length            # 20000
        puts r3[0]                # out-src-0
        puts r3[19999][-3, 3]     # 999
        
        # (4) str_array recv → IntArray accumulator (int-return block).
        r4 = strs.map do |s|
          _scratch = "scratch-#{s}-discarded-inner-allocation-padding"
          s.length
        end
        puts r4.length            # 20000
        puts r4[0]                # 5  (out-0 → "src-0")
        puts r4[19999]            # 9  ("src-19999")
      end
      t_gc_root_map_accumulator

      # === gc_root_range_and_times_map ===
      def t_gc_root_range_and_times_map
        # `Range#map` and `N.times.map` build a fresh accumulator
        # (IntArray / StrArray / FloatArray) and push each block result.
        # When the block allocates inside (e.g. string interpolation), a
        # GC pass triggered mid-loop frees the unrooted accumulator and
        # the next push corrupts malloc bookkeeping — typically surfaces
        # as a SIGSEGV in `_int_malloc` on the next allocation.
        #
        # `int_array` / `str_array` recv branches already root the
        # accumulator (PR #198). This covers the missing branches:
        # `Range#map` and `N.times.map`.
        
        # (1) Range#map with string-allocating block.
        r1 = (0..3000).map { |i| "padded-string-#{i}-with-some-extra-text" }
        puts r1.length          # 3001
        puts r1[0][0, 6]        # padded
        puts r1[3000][-3, 3]    # ext
        
        # (2) Range#map with int block (heap pressure from inner allocations).
        r2 = (0...3000).map do |i|
          _scratch = "scratch-#{i}-discarded-inner-allocation-padding"
          i * 2
        end
        puts r2.length          # 3000
        puts r2[0]              # 0
        puts r2[2999]           # 5998
        
        # (3) N.times.map.
        r3 = 3000.times.map { |i| "kept-#{i}-with-extra-padding-text" }
        puts r3.length          # 3000
        puts r3[0]              # kept-0-with-extra-padding-text
        puts r3[2999][-3, 3]    # ext
        
        # (4) N.times.map with int block + scratch allocations.
        r4 = 3000.times.map do |i|
          _scratch = "scratch-#{i}-discarded-inner-allocation-padding"
          i + 1
        end
        puts r4.length          # 3000
        puts r4[0]              # 1
        puts r4[2999]           # 3000
      end
      t_gc_root_range_and_times_map

      # === transpose_gc_root ===
      def t_transpose_gc_root
        # `Array#transpose` codegen creates the result `sp_PtrArray` and
        # inner `sp_IntArray` columns without `SP_GC_ROOT`. With many
        # allocations across the loop, an `sp_gc_collect` triggered by
        # the next column's `sp_IntArray_new()` reclaims the unrooted
        # result PtrArray. The next `sp_PtrArray_push(result, col)`
        # dereferences a freed pointer.
        #
        # Trigger: a transpose of a large array-of-arrays. Optcarrot's
        # `(0..7).map { (0...0x10000).map {...} }.transpose` allocates
        # 8 outer + 65536 × 8 inner ints in close succession.
        
        big = (0..7).map { |a| (0..1023).map { |b| a * 1000 + b } }.transpose
        puts big.length        # 1024
        puts big[0].length     # 8
        puts big[100][3]       # 3*1000 + 100 = 3100
        puts big[1023][7]      # 7*1000 + 1023 = 8023
      end
      t_transpose_gc_root

      # === utf8 ===
      def t_utf8
        s = "あいうえお"
        
        puts s.length          # 5
        puts s.size            # 5
        puts s.bytesize        # 15
        
        puts s.chars.length    # 5
        s.chars.each { |c| puts c }
        
        puts s.reverse         # おえういあ
        
        puts s[0]              # あ
        puts s[1]              # い
        puts s[4]              # お
        puts s[-1]             # お
        puts s[1, 2]           # いう
        puts s[1..3]           # いうえ
        puts s.slice(2, 2)     # うえ
        
        puts "hello#{s}world".index(s)   # 5  (char index, not byte)
        puts s.index("う")               # 2
        puts "あいあい".rindex("い")    # 3
        
        puts "あいう".tr("い", "X")     # あXう
        puts "ababab".count("a")        # 3
        puts "あいあいあ".count("あ")   # 3
        puts "あいあいあ".delete("い")  # あああ
        puts "ああいいうう".squeeze     # あいう
        
        puts "あ".ljust(5, "*")          # あ****
        puts "あ".rjust(5, "*")          # ****あ
        puts "あ".center(5)              # _あ__   (with spaces)
        puts "あ".ljust(5).length        # 5   (chars, including padding)
        
        puts "あ".succ                  # ぃ
        puts "az".succ                  # ba
        
        puts s.include?("うえ")          # true
        puts s.start_with?("あい")       # true
        puts s.end_with?("えお")         # true
        
        # each_char with non-ASCII
        out = ""
        "日本語".each_char { |c| out = out + "[" + c + "]" }
        puts out                          # [日][本][語]
        
        # split on empty separator
        "あいう".split("").each { |c| puts c }   # あ\nい\nう
        
        # bytes is still byte-based
        puts "あ".bytes.length            # 3
      end
      t_utf8

    RUBY
  end

  it "bundle misc c 30" do
    result = ze0(<<~'RUBY')
      # Bundled tests:
      #   - str_nul_bound_slice_bytes
      #   - str_poly_hash_merge

      # === str_nul_bound_slice_bytes ===
      def t_str_nul_bound_slice_bytes
        # Issue #657: a string with embedded NUL bytes had two surviving
        # truncation paths:
        #
        #   - s[a, n] slice walks the result range via sp_utf8_byte_offset
        #     applied to (s + boff, n). The inner call fell back to strlen
        #     on a mid-string pointer (no 0xfe/0xfc marker visible at [-1])
        #     and stopped at the first NUL after boff.
        #
        #   - s.bytes[i] (via sp_str_bytes) used `for (i=0; s[i]; i++)` which
        #     terminates at the first NUL byte.
        #
        # Fix:
        #   - sp_utf8_byte_offset bounds the walk on sp_str_byte_len(s)
        #     (which honours the heap-string hdr marker) instead of "*p".
        #   - sp_str_sub_range / sp_str_sub_range_len compute the end byte
        #     position inline against sp_str_byte_len(s) instead of recursing
        #     into sp_utf8_byte_offset(s+boff, len).
        #   - sp_str_bytes walks 0..sp_str_byte_len(s) instead of 0..NUL.
        #
        # Concat already round-trips NULs correctly (sp_str_concat uses
        # sp_str_byte_len for both inputs).
        
        nul = 0.chr
        s = "abc" + nul + "def"
        puts "len=#{s.length}"
        puts "slice_full=#{s[0, 7].length}"
        puts "slice_after_nul=#{s[4, 3].length}"
        puts "slice_around_nul=#{s[2, 3].length}"
        puts "b0=#{s.bytes[0]}"
        puts "b3=#{s.bytes[3]}"
        puts "b4=#{s.bytes[4]}"
        puts "b6=#{s.bytes[6]}"
        puts "bytes_len=#{s.bytes.length}"
      end
      t_str_nul_bound_slice_bytes

      # === str_poly_hash_merge ===
      def t_str_poly_hash_merge
        # Issue #426. `Hash#merge` was unresolved on a `str_poly_hash`
        # (mixed-value-type hash literal) -- emit produced `0` and the
        # downstream `m.length` cascaded through int. Same shape on
        # monomorphic-value hashes (`str_int_hash`, `str_str_hash`)
        # worked; the gap was just the polymorphic-value specialization.
        #
        # Fix:
        #   - Runtime: sp_StrPolyHash_merge(a, b) in lib/sp_runtime.h,
        #     same shape as the existing sp_StrIntHash_merge /
        #     sp_SymPolyHash_merge helpers.
        #   - Codegen: `compile_hash_method_expr`'s str_poly_hash arm
        #     gains a `merge` case. Dispatches by arg type:
        #       * str_poly_hash arg -> sp_StrPolyHash_merge direct.
        #       * str_str_hash arg -> inline copy with sp_box_str on
        #         each value to land in poly slots.
        #       * str_int_hash arg -> inline copy with sp_box_int.
        #
        # Out of scope: poly-typed args (sp_RbVal whose runtime hash
        # variant is unknown statically) -- needs the runtime-dispatch
        # pattern from sym_poly_hash's poly-arg branch, not in this
        # minimal fix.
        #
        # Coverage:
        #   - canonical mixed-value seed + str_int_hash override (the
        #     repro from #426).
        #   - mixed-value seed + str_str_hash override (forces the
        #     box_str copy path).
        #   - mixed-value seed + str_poly_hash override (the direct
        #     merge path; verifies it's still reachable post-fix).
        
        h = { "a" => 1, "b" => "two" }  # str_poly_hash
        m = h.merge({ "c" => 3 })       # str_int_hash arg
        puts m.length                    # 3
        puts m["a"] == 1 ? "a-ok" : "a-bad"
        puts m["c"] == 3 ? "c-ok" : "c-bad"
        
        # str_str_hash override of a str_poly_hash recv.
        h2 = { "x" => 1, "y" => "two" }
        m2 = h2.merge({ "z" => "three" })
        puts m2.length                   # 3
        puts m2["z"] == "three" ? "z-ok" : "z-bad"
        
        # str_poly_hash override of a str_poly_hash recv.
        h3 = { "p" => 1, "q" => "two" }
        extra = { "r" => 3, "s" => "four" }
        m3 = h3.merge(extra)
        puts m3.length                   # 4
      end
      t_str_poly_hash_merge

    RUBY

    _(result).must_answer <<~'OUT'
      len=7
      slice_full=7
      slice_after_nul=3
      slice_around_nul=3
      b0=97
      b3=0
      b4=100
      b6=102
      bytes_len=7
      3
      a-ok
      c-ok
      3
      z-ok
      4
    OUT
  end

  it "bundle misc c 37" do
    result = ze0(<<~'RUBY')
      # Bundled tests:
      #   - kw_nil_default_string_call (show -> t_kw_show)
      #   - optional_string_param_method (parse -> t_osp_parse)
      #   - poly_box_int_array (kind_of -> t_pbia_kind_of)
      #   - poly_or_returns_value (pick / pick_int -> t_porv_*)
      #   - each_with_object_seed_shadow (f -> t_ewoss_f)
      #   - fetch_nil_default_int_lv (f -> t_fndi_f)
      #   - no_keywords_param (add -> t_nkp_add)
      #   - sym_case (classify -> t_sc_classify)
      #
      # Each inner top-level def is renamed with a per-test prefix to
      # avoid cross-test collisions when the bundle is compiled.

      # === kw_nil_default_string_call ===
      def t_kw_show(x: nil)
        puts x
      end

      def t_kw_nil_default_string_call
        t_kw_show(x: "hi")
        t_kw_show(x: nil)
      end
      t_kw_nil_default_string_call

      # === optional_string_param_method ===
      def t_osp_parse(source, file_path = nil)
        if file_path
          puts file_path.length
        else
          puts source.length
        end
      end

      def t_optional_string_param_method
        t_osp_parse("abc", "name.rb")
        t_osp_parse("abc")
        t_osp_parse("longer", "another_name.rb")
      end
      t_optional_string_param_method

      # === poly_box_int_array ===
      def t_pbia_kind_of(a)
        a.nil? ? "nil" : "something"
      end

      def t_poly_box_int_array
        puts t_pbia_kind_of(Object.new)
        puts t_pbia_kind_of([1, 2, 3])
      end
      t_poly_box_int_array

      # === poly_or_returns_value ===
      def t_porv_pick(a, b)
        a || b
      end

      def t_porv_pick_int(a, b)
        a || b
      end

      def t_poly_or_returns_value
        puts t_porv_pick(nil, "fallback")
        puts t_porv_pick("actual", "fallback")
        puts t_porv_pick_int(0, 5)
        puts(nil || "direct")
      end
      t_poly_or_returns_value

      # === each_with_object_seed_shadow ===
      def t_ewoss_f
        obj = 42
        out = [1, 2, 3].each_with_object([]) { |x, obj| obj.push(x * 2) }
        puts out[0]   # 2
        puts out[1]   # 4
        puts out[2]   # 6
        puts obj      # 42
      end
      t_ewoss_f

      # === fetch_nil_default_int_lv ===
      def t_fndi_f(opts = {})
        v = opts.fetch(:k, nil)
        v.nil? ? "missing" : "found"
      end

      def t_fetch_nil_default_int_lv
        puts t_fndi_f
      end
      t_fetch_nil_default_int_lv

      # === no_keywords_param ===
      def t_nkp_add(a, b, **nil)
        a + b
      end

      def t_no_keywords_param
        puts t_nkp_add(1, 2)
        puts t_nkp_add(10, 20)
      end
      t_no_keywords_param

      # === sym_case ===
      def t_sc_classify(sym)
        case sym
        when :red then "warm"
        when :orange then "warm"
        when :blue then "cool"
        when :green then "cool"
        else "unknown"
        end
      end

      def t_sym_case
        puts t_sc_classify(:red)
        puts t_sc_classify(:orange)
        puts t_sc_classify(:blue)
        puts t_sc_classify(:purple)
      end
      t_sym_case
    RUBY

    _(result).must_answer <<~'OUT'
      hi

      7
      3
      15
      something
      something
      fallback
      actual
      0
      direct
      2
      4
      6
      42
      missing
      3
      30
      warm
      warm
      cool
      unknown
    OUT
  end

  it "issue 266 def length inference" do
    _(ze0(<<~'RUBY')).must_answer "0.0\n"
      # Issue #266 regression: defining `def length` on a class flipped
      # Spinel's inference for IntArray params on unrelated class methods to
      # poly. Cause was `infer_cls_meth_param_from_body` committing a param
      # to `obj_<C>` whenever the only methods called on it (here `.length`)
      # matched a user class — even though IntArray (and every other built-in
      # container) also has `.length`. The body signal is too weak to commit;
      # the gate added in this fix skips the pre-typing when the called set
      # is satisfied by built-in container types, leaving call-site
      # unification to decide.

      class Mat
        attr_accessor :flat, :nrows, :ncols
        def initialize(nrows, ncols)
          @nrows = nrows
          @ncols = ncols
          @flat  = Array.new(nrows * ncols, 0.0)
        end
      end

      class Net
        def backward(input_ids, logits)
          n_pred = input_ids.length - 1
          if n_pred <= 0
            return 0.0
          end
          self.cross_entropy_grad(logits, input_ids)
        end

        def cross_entropy_grad(logits, token_ids)
          n     = token_ids.length - 1
          total = 0.0
          i = 0
          while i < n
            target = token_ids[i + 1]
            total += logits.flat[target]
            i += 1
          end
          total
        end
      end

      def make_ids(s)
        parts = s.split(" ")
        ids   = [parts[0].to_i]
        k = 1
        while k < parts.length
          ids.push(parts[k].to_i)
          k += 1
        end
        ids
      end

      # The class with `def length` is the trigger — pre-fix this caused
      # Net#backward and Net#cross_entropy_grad to be inferred with poly
      # `input_ids` / `token_ids` params and then mis-compile.
      class Bag
        attr_accessor :data
        def initialize(data); @data = data; end
        def length;           0;             end
      end

      prompt = make_ids("0 1 2")
      puts Net.new.backward(prompt, Mat.new(3, 4))
    RUBY
  end

  it "issue 2871" do
    result = ze0(<<~'RUBY')
      def fill(h)
        h[1] = 100
      end
      h = {}
      fill(h)
      p h
      # also symbol key + direct-arg form
      def fill2(m)
        m[:x] = 9
        m[:y] = 8
      end
      g = {}
      fill2(g)
      p g
    RUBY

    _(result).must_answer <<~'OUT'
      {1 => 100}
      {x: 9, y: 8}
    OUT
  end

  it "issue 2884" do
    result = ze0(<<~'RUBY')
      class Point
        attr_reader :x
        def initialize(x) = @x = x
        def ==(o) = o.is_a?(Point) && @x == o.x
      end
      pts = [Point.new(1), Point.new(2), Point.new(3)]
      p pts.include?(Point.new(2))
      p pts.include?(Point.new(9))
      p pts.index(Point.new(3))
      p pts.index(Point.new(9))
      # uniq / Hash keys use eql? (identity for a class defining only ==), not ==
      p [Point.new(1), Point.new(1), Point.new(2)].uniq.map(&:x)
    RUBY

    _(result).must_answer <<~'OUT'
      true
      false
      2
      nil
      [1, 1, 2]
    OUT
  end

  it "issue 2886" do
    result = ze0(<<~'RUBY')
      class Money
        attr_reader :cents
        def initialize(c) = @cents = c
        def +(o) = Money.new(@cents + o.cents)
        def to_s = "$#{@cents}"
      end
      xs = [Money.new(1), Money.new(2), Money.new(4)]
      p xs.reduce(Money.new(0)) { |a, x| a + x }.to_s
      p [1r, 2r].reduce(0r) { |a, x| a + x }
      p [1, 2, 3].reduce(0) { |a, x| a + x }
      p [Complex(1, 1), Complex(2, -1)].reduce(Complex(0, 0)) { |a, x| a + x }
    RUBY

    _(result).must_answer <<~'OUT'
      "$7"
      (3/1)
      6
      (3+0i)
    OUT
  end

  it "issue 2894" do
    result = ze0(<<~'RUBY')
      def mark(h, k)
        h[k] = true
      end
      h = {}
      mark(h, :a)
      mark(h, :b)
      p h
      def put(m, k, v)
        m[k] = v
      end
      n = {}
      put(n, 7, "x")
      p n
    RUBY

    _(result).must_answer <<~'OUT'
      {a: true, b: true}
      {7 => "x"}
    OUT
  end

  it "issue 2917" do
    result = ze0(<<~'RUBY')
      # Set membership uses #eql?/#hash (like CRuby's Hash-backed Set), so an
      # equal-but-distinct value object is found, and 1 / 1.0 are distinct members.
      require "set"

      class Point
        attr_reader :x, :y
        def initialize(x, y); @x = x; @y = y; end
        def hash = [x, y].hash
        def eql?(other) = other.is_a?(Point) && x == other.x && y == other.y
      end

      s = Set.new
      s << Point.new(3, 4)
      p s.include?(Point.new(3, 4))
      p s.add?(Point.new(3, 4))
      p s.size
      s.delete(Point.new(3, 4))
      p s.include?(Point.new(3, 4))

      n = Set.new
      n << 1
      p n.include?(1.0)
      p n.include?(1)
    RUBY

    _(result).must_answer <<~'OUT'
      true
      nil
      1
      false
      false
      true
    OUT
  end

  it "issue 3042b" do
    result = ze0(<<~'RUBY')
      p NoMethodError.new("m", :nm, [1, 2]).args
      p NoMethodError.new("m", :nm, [1], true).private_call?
      p NoMethodError.new("m", :nm, [1]).private_call?
    RUBY

    _(result).must_answer <<~'OUT'
      [1, 2]
      true
      false
    OUT
  end

  it "issue 3114" do
    result = ze0(<<~'RUBY')
      def f(*a, foo: nil); p a; p foo; end
      f("xyz", "bar")
      f("xyz", "bar", foo: 9)
      def g(a, foo: 1); p [a, foo]; end
      g(10)
      g(10, foo: 2)
      def h(*a, foo: 5, bar: 6); p [a, foo, bar]; end
      h(1, 2, 3)
      h(1, bar: 9)
    RUBY

    _(result).must_answer <<~'OUT'
      ["xyz", "bar"]
      nil
      ["xyz", "bar"]
      9
      [10, 1]
      [10, 2]
      [[1, 2, 3], 5, 6]
      [[1], 5, 9]
    OUT
  end

  it "issue 3136" do
    result = ze0(<<~'RUBY')
      class A
        attr_accessor :b, :i
        def initialize
          @i = 5
        end
        def setb = @b = true
      end
      a = A.new
      p a.b.nil?
      p a.i
      p a.i.nil?
      class C
        attr_accessor :flag
        def initialize
          @flag = false
        end
      end
      p C.new.flag
      p C.new.flag.nil?
    RUBY

    _(result).must_answer <<~'OUT'
      true
      5
      false
      false
      false
    OUT
  end

  it "issue 3139" do
    result = ze0(<<~'RUBY')
      class C
        attr_reader :arr, :nums
        def initialize
          @arr = []
          @nums = []
          arr << "a"
          arr << "b"
          nums << 1
        end
      end
      c = C.new
      p c.arr
      p c.nums
      class D
        attr_accessor :mix
        def initialize
          @mix = []
          mix << 1
          mix << "s"
        end
      end
      p D.new.mix
    RUBY

    _(result).must_answer <<~'OUT'
      ["a", "b"]
      [1]
      [1, "s"]
    OUT
  end

  it "issue 3143" do
    _(ze0(<<~'RUBY')).must_answer "nil\n"
      class Crash
        attr_accessor :foo
        def initialize = @foo = nil
      end

      Crash.new.tap { _1.foo = true }

      p Crash.new.foo
    RUBY
  end

  it "issue 3144" do
    result = ze0(<<~'RUBY')
      class Crash
        attr_reader :foo

        def initialize = @foo = []
        def add(list) = list.tap { foo << _1 }
      end

      c = Crash.new
      c.add(Crash.new)
      c.add(Crash.new)
      p c.foo.size
      p c.foo.all? { |e| e.is_a?(Crash) }

      # explicit block param form
      class Box
        attr_reader :items
        def initialize = @items = []
        def push(x) = x.tap { |v| items << v }
      end
      b = Box.new
      b.push("a")
      b.push("b")
      p b.items
    RUBY

    _(result).must_answer <<~'OUT'
      2
      true
      ["a", "b"]
    OUT
  end

  it "issue 3154" do
    result = ze0(<<~'RUBY')
      class Flag ; end
      class Config
        attr_reader :flags
        def initialize = @flags = []
        def add = add_to(flags)
        def add_to(collection) = collection << Flag.new
      end
      config = Config.new
      config.add
      config.add
      p config.flags.size
      p config.flags[0].is_a?(Flag)

      # direct @ivar arg + a manual reader
      class Box
        def initialize; @items = []; end
        def push_one; fill(@items); end
        def fill(coll); coll << Flag.new; end
        def items; @items; end
      end
      b = Box.new
      b.push_one
      p b.items[0].is_a?(Flag)
    RUBY

    _(result).must_answer <<~'OUT'
      2
      true
      true
    OUT
  end

  it "issue 3158" do
    result = ze0(<<~'RUBY')
      def store(memo, n)
        memo[n] ||= n * 10
      end
      memo = {}
      store(memo, 1)
      store(memo, 2)
      store(memo, 1)
      p memo.size
      p memo
      # string-key ||= through a param
      def store_s(h, k) = h[k] ||= "v"
      hs = {}
      store_s(hs, "x"); store_s(hs, "x")
      p hs
    RUBY

    _(result).must_answer <<~'OUT'
      2
      {1 => 10, 2 => 20}
      {"x" => "v"}
    OUT
  end

  it "issue 3196" do
    result = ze0(<<~'RUBY')
      class Flag; end
      class Crash
        attr_reader :flags
        def initialize
          @flags = []
          append(["--help"], @flags)
        end
        def append(names, collection)
          available = []
          names.each { available << _1 }
          add(Flag.new).tap { collection << _1 }
        end
        def add(flag) = flag
      end
      c = Crash.new
      p c.flags.size
      p c.flags[0].is_a?(Flag)
    RUBY

    _(result).must_answer <<~'OUT'
      1
      true
    OUT
  end

  it "issue 3198" do
    result = ze0(<<~'RUBY')
      class Config
        attr_accessor :name
      end
      config = Config.new
      config.name = "app"
      p "app".sub(config.name, config.name)
      p "banana".gsub(config.name, config.name)
      class C2; attr_accessor :pat, :rep; end
      c = C2.new; c.pat = "o"; c.rep = "0"
      p "foo".sub(c.pat, c.rep)
      p "foo".gsub(c.pat, c.rep)
    RUBY

    _(result).must_answer <<~'OUT'
      "app"
      "banana"
      "f0o"
      "f00"
    OUT
  end

  it "issue 3211" do
    result = ze0(<<~'RUBY')
      def maybe_string(flag) = flag ? "foo" : nil
      def crash(value) = value.end_with?("o")
      p crash(maybe_string(true))
      def sw(v) = v.start_with?("f")
      p sw(maybe_string(true))
    RUBY

    _(result).must_answer <<~'OUT'
      true
      true
    OUT
  end

  it "issue 3227 cross method" do
    result = ze0(<<~'RUBY')
      # Shared-mutable strings across method boundaries (P5): a shared handle
      # passed into a string-mutating parameter, and aliases taken through
      # readers outside the class.
      def scream(x)
        x << "!"
      end
      def outer(y)
        scream(y)
        y << "?"
      end

      s = +"a"
      t = s
      s << +"b"
      scream(s)
      p s
      p t
      p s.equal?(t)

      u = +"plain"
      scream(u)
      p u

      v = +"deep"
      w = v
      v << "-"
      outer(v)
      p v
      p w

      scream(+"lit")

      class Doc
        attr_reader :title
        def initialize(t) = @title = t
        def bump = @title << "+"
      end
      d = Doc.new(+"aaa")
      ext = d.title
      d.bump
      p ext
      p ext.equal?(d.title)

      class Memo
        def initialize = @body = +"b"
        def body = @body
        def grow = @body << "1"
      end
      m = Memo.new
      x = m.body
      m.grow
      p x
    RUBY

    _(result).must_answer <<~'OUT'
      "ab!"
      "ab!"
      true
      "plain!"
      "deep-!?"
      "deep-!?"
      "aaa+"
      true
      "b1"
    OUT
  end

  it "issue 3227 matrix" do
    result = ze0(<<~'RUBY')
      # mutator × storage 最終確認 matrix
      puts "== local alias =="
      a1=+"x"; a2=a1; a1<<"1"; p a2
      b1=+"x"; b2=b1; b1.upcase!; p b2
      c1=+"x"; c2=c1; c1.replace("R"); p c2
      d1=+"ax"; d2=d1; d1.slice!(0); p d2
      e1=+"x"; e2=e1; e1.insert(0,">"); p e2
      f1=+"x"; f2=f1; f1[0]="Z"; p f2
      g1=+"x"; g2=g1; g1.clear; p g2
      h1=+"Ab"; h2=h1; h1.setbyte(0,97); p h2
      puts "== container =="
      s=+"x"; arr=[s]; s<<"1"; s.upcase!; arr[0].reverse!; p arr; p s
      h={k:+"v"}; h[:k]<<"1"; p h
      puts "== ivar =="
      class C1; def initialize; @s=+"x"; t=@s; @s<<"1"; p t; end; end; C1.new
      puts "== param =="
      def mm(x)=x.gsub!(+"x","G"); q=+"x"; r=q; mm(q); p r
      puts "== capture =="
      cs=+"x"; ct=cs; pr=->{ cs<<"c" }; pr.call; p ct
      puts "== return =="
      $g=[]; def mk; s=+"x"; $g<<s; s; end; rr=mk; rr<<"r"; p $g[0]
      puts "== iteration =="
      ls=[+"a",+"b"]; ls.each{|x| x<<"!"}; p ls
      puts "== frozen =="
      fz="x".freeze; fw=fz; (fz<<"!" rescue p :frozen); p fw
    RUBY

    _(result).must_answer <<~'OUT'
      == local alias ==
      "x1"
      "X"
      "R"
      "x"
      ">x"
      "Z"
      ""
      "ab"
      == container ==
      ["1X"]
      "1X"
      {k: "v1"}
      == ivar ==
      "x1"
      == param ==
      "G"
      == capture ==
      "xc"
      == return ==
      "xr"
      == iteration ==
      ["a!", "b!"]
      == frozen ==
      :frozen
      "x"
    OUT
  end

  it "issue 3227 reflection reads" do
    result = ze0(<<~'RUBY')
      # Promoted-ivar reads through reflection and formatting paths hand out safe
      # copies (never the raw handle); instance_variable_set joins the shared set.
      class W
        attr_reader :a, :b
        def initialize
          @a = +"aa"
          @b = "bb"
          t = @a
          @a << "!"
          p t
        end
      end
      w = W.new
      p w.a
      p w.instance_variable_get(:@a)
      puts "#{w.a}/#{w.b}"
      p({ x: w.a })
      p [w.a, w.b]
      p w.a.length
      p w.a == "aa!"
      s = w.a.dup
      s << "?"
      p s
      p w.a
      w.instance_variable_set(:@a, "set")
      p w.a
    RUBY

    _(result).must_answer <<~'OUT'
      "aa!"
      "aa!"
      "aa!"
      aa!/bb
      {x: "aa!"}
      ["aa!", "bb"]
      3
      true
      "aa!?"
      "aa!"
      "set"
    OUT
  end

  it "issue 3247 super method" do
    result = ze0(<<~'RUBY')
      def dbl(n) = n * 2
      p method(:dbl) === 5
      p method(:dbl).super_method

      class Base
        def greet = "base"
      end
      class Sub < Base
        def greet = "sub"
      end
      sm = Sub.new.method(:greet).super_method
      p sm.class
      p sm.call
      p sm.inspect.start_with?("#<Method: Base#greet")
      p Sub.instance_method(:greet).super_method.inspect.start_with?("#<UnboundMethod: Base#greet")
      p Base.instance_method(:greet).source_location.is_a?(Array)
    RUBY

    _(result).must_answer <<~'OUT'
      10
      nil
      Method
      "base"
      true
      true
      true
    OUT
  end

  it "issue 3251" do
    result = ze0(<<~'RUBY')
      def has_block? = iterator?
      p(has_block? { 1 })
      p(has_block?)
      def hb2
        iterator? ? "yes" : "no"
      end
      p(hb2 { })
      p(hb2)
    RUBY

    _(result).must_answer <<~'OUT'
      true
      false
      "yes"
      "no"
    OUT
  end

  it "issue 3283" do
    result = ze0(<<~'RUBY')
      module TypedStore
        def self.parse(serialized)
          h = {}
          raw = serialized.to_s
          h["k"] = if raw == "true"
          elsif raw.length >= 2
            raw[1, raw.length - 2].to_s
          else
            raw
          end
          h
        end

        def self.write(serialized)
          parse(serialized)
        end
      end

      module Seeder
        def self.seed(stream)
          stream.write("")
        end
      end

      p TypedStore.write("abc")
      p TypedStore.write("true")
      p TypedStore.write("x")
    RUBY

    _(result).must_answer <<~'OUT'
      {"k" => "b"}
      {"k" => nil}
      {"k" => "x"}
    OUT
  end

  it "issue 3289" do
    result = ze0(<<~'RUBY')
      class MyClass
        attr_reader :switches
        def initialize(opts)
          @switches = []
          @switches += opts
          @switches += []
          @more = [1]
          @more += [2, 3]
        end
        attr_reader :more
      end
      obj = MyClass.new(["--name", "-n"])
      p obj.switches
      p obj.more
    RUBY

    _(result).must_answer <<~'OUT'
      ["--name", "-n"]
      [1, 2, 3]
    OUT
  end

  it "issue 3290 method curry" do
    result = ze0(<<~'RUBY')
      def add(a, b) = a + b
      def add3(a, b, c) = a + b + c
      p(method(:add).curry[1][2])
      p(method(:add3).curry[1][2][3])
      p(method(:add3).curry[10, 20][12])

      def cat(a, b) = "#{a}-#{b}"
      c = method(:cat).curry
      p c["x"]["y"]

      class Calc
        def mul(a, b) = a * b
      end
      p(Calc.new.method(:mul).curry[6][7])
    RUBY

    _(result).must_answer <<~'OUT'
      3
      6
      42
      "x-y"
      42
    OUT
  end

  it "issue 3298" do
    result = ze0(<<~'RUBY')
      # Two bugs from the Rails-emit boot crash: a poly-array receiver had no
      # delete_at arm, and "Set-Cookie" in a string tripped the textual Set
      # auto-require, whose top-of-buffer prepend pushed this file's magic
      # comment off the scanned lines (reverting the pragma to the default).
      class R
        attr_accessor :cookies
        def initialize
          @cookies = [+""]
          @cookies.delete_at(0)
        end
        def add(line) = @cookies.push(line)
      end
      r = R.new
      r.add("a=1")
      r.add("b=2")
      head = +""
      i = 0
      while i < r.cookies.length
        head << "Set-Cookie: " + r.cookies[i] + "\r\n"
        i += 1
      end
      puts head
      p r.cookies.delete_at(0)
      p r.cookies
      p r.cookies.delete_at(5)
    RUBY

    _(result).must_answer <<~'OUT'
      Set-Cookie: a=1
      Set-Cookie: b=2
      "a=1"
      ["b=2"]
      nil
    OUT
  end

  it "issue 3303 paren write poly shift" do
    _(ze0(<<~'RUBY')).must_answer "ok\n"
      module Slap
        def self.parse(argv = ARGV) = Main.new.parse(argv)

        class Main
          def parse(argv) = Parser.new.parse(argv)
        end

        class Parser
          attr_reader :queue

          def parse(argv)
            @queue = argv
            parse_argv
          end

          def parse_argv
            (item = queue.shift)
          end
        end
      end

      argv = []
      Slap.parse(argv)
      puts "ok"
    RUBY
  end

  it "issue 3304 method reflection" do
    result = ze0(<<~'RUBY')
      # The Method/UnboundMethod reflection tail: `#box` (nil for a method in no
      # namespace), `#curry`, and `#clone`/`#dup` keeping the signature.
      def dbl(n) = n * 2
      def add(a, b) = a + b
      p(method(:dbl).box)

      c1 = method(:add).curry
      raise "FAIL" unless c1[3][4] == 7
      raise "FAIL2" unless c1.lambda?

      class Calc
        def add(n)
          n + 1
        end
      end
      p(Calc.instance_method(:add).clone.arity)
      um = Calc.instance_method(:add)
      c = um.clone
      p(c.arity)
      d = method(:dbl).dup
      p(d.arity)
      b = method(:dbl).clone
      p(b.box)
      puts "ok"
    RUBY

    _(result).must_answer <<~'OUT'
      nil
      1
      1
      1
      nil
      ok
    OUT
  end

  it "issue 3306 shared strarray insert delete at" do
    result = ze0(<<~'RUBY')
      class R
        attr_accessor :cookies
        def initialize
          @cookies = [""]
          @cookies.delete_at(0)
        end

        def add(line)
          @cookies.push(line)
        end
      end

      r = R.new
      r.add("a=1")
      r.cookies.insert(0, "z=9")
      r.cookies.insert(-1, "t=2")
      head = +""
      i = 0
      while i < r.cookies.length
        head << "Set-Cookie: " + r.cookies[i] + "\r\n"
        i += 1
      end
      puts head
      p r.cookies.delete_at(0)
      p r.cookies.delete_at(5)
      p r.cookies
    RUBY

    _(result).must_answer <<~'OUT'
      Set-Cookie: z=9
      Set-Cookie: a=1
      Set-Cookie: t=2
      "z=9"
      nil
      ["a=1", "t=2"]
    OUT
  end

  it "issue 3307 container reader mutation" do
    result = ze0(<<~'RUBY')
      class Sub
        attr_accessor :topic, :fd, :mode
        def initialize(topic, fd, mode)
          @topic = topic
          @fd = fd
          @mode = mode
        end
      end

      class App
        attr_accessor :subs
        def initialize
          @subs = [Sub.new("_", -1, 0)]
          @subs.delete_at(0)
        end

        def register(topic, fd)
          @subs << Sub.new(topic, fd, 1)
        end

        def grow_topics
          @subs[0].topic << "x" unless @subs.empty?
        end
      end

      a = App.new
      a.register(+"news", 3)
      a.grow_topics
      puts a.subs[0].topic

      subs = [Sub.new(+"local", 1, 0)]
      subs[0].topic << "!"
      subs[0].topic.upcase!
      puts subs[0].topic

      begin
        a.register("frozen-lit", 4)
        a.subs[1].topic << "x"
        puts "BUG: no raise"
      rescue FrozenError
        puts "FrozenError"
      end
    RUBY

    _(result).must_answer <<~'OUT'
      newsx
      LOCAL!
      BUG: no raise
    OUT
  end

  it "issue 3326 seeded strarray clear" do
    result = ze0(<<~'RUBY')
      class Res
        attr_accessor :cookies
        def initialize
          @cookies = [""]
          @cookies.clear
        end

        def add(name, value)
          @cookies.push(name + "=" + value)
        end
      end

      res = Res.new
      res.add("flash", "hello")
      head = +""
      res.cookies.each do |line|
        head << "Set-Cookie: " + line + "\r\n"
      end
      print head

      h = { a: 1 }
      def touch(x) = x
      v = touch(h)
      v.clear
      p h
    RUBY

    _(result).must_answer <<~'OUT'
      Set-Cookie: flash=hello
      {}
    OUT
  end

  it "issue 3328 poly int chr" do
    result = ze0(<<~'RUBY')
      def hexd(n)
        n < 10 ? ("0".getbyte(0) + n).chr : ("A".getbyte(0) + n - 10).chr
      end

      def pct(byte)
        "%" + hexd(byte >> 4) + hexd(byte & 15)
      end

      p pct("=".getbyte(0))
      p pct("&".getbyte(0))
      x = [61, "a"]
      v = x[0]
      p v.chr
      s = x[1]
      p s.chr
    RUBY

    _(result).must_answer <<~'OUT'
      "%3D"
      "%26"
      "="
      "a"
    OUT
  end

  it "probe arguments" do
    _(ze0(<<~'RUBY')).must_answer "instance_variable_get(@@x)\tNameError: '@@x' is not allowed as an instance variable name\ninstance_variable_get(x)\tNameError: 'x' is not allowed as an instance variable name\ninstance_variable_get(@1x)\tNameError: '@1x' is not allowed as an instance variable name\ninstance_variable_get(@)\tNameError: '@' is not allowed as an instance variable name\ninstance_variable_get(sym)\tok nil\ninstance_variable_set(bad)\tNameError: '@@x' is not allowed as an instance variable name\ninstance_variable_defined?(bad)\tNameError: 'x' is not allowed as an instance variable name\nremove_instance_variable(bad)\tNameError: 'x' is not allowed as an instance variable name\nremove_instance_variable(absent)\tNameError: instance variable @nope not defined\nconst_set(lower)\tNameError: wrong constant name lower\nconst_set(path)\tNameError: wrong constant name A::B\nconst_set(empty)\tNameError: wrong constant name \nconst_set(digit)\tNameError: wrong constant name 1A\nconst_get(lower)\tNameError: wrong constant name lower\nconst_get(absent)\tNameError: uninitialized constant #<Class:0xADDR>::Absent\nremove_const(absent)\tNameError: constant #<Class:0xADDR>::Absent not defined\nattr_accessor(1bad)\tNameError: invalid attribute name '1bad'\nattr_accessor(ok then bad)\tNameError: invalid attribute name '1bad'\nattr_accessor(bang)\tNameError: invalid attribute name 'x!'\nattr_accessor(int)\tTypeError: 1 is not a symbol nor a string\ndefine_method(no body)\tArgumentError: tried to create Proc object without a block\ndefine_method(int)\tTypeError: wrong argument type Integer (expected Proc/Method/UnboundMethod)\nalias_method(absent)\tNameError: undefined method 'nope' for class '#<Class:0xADDR>'\ninstance_method(absent)\tNameError: undefined method 'nope' for class '#<Class:0xADDR>'\ninclude(Class)\tTypeError: wrong argument type Class (expected Module)\ninclude(Integer)\tTypeError: wrong argument type Integer (expected Module)\ninclude(self)\tArgumentError: cyclic include detected\ninclude(frozen, bad)\tTypeError: wrong argument type Class (expected Module)\ninclude(frozen, good)\tFrozenError: can't modify frozen Class: #<Class:0xADDR>\ninclude(mod, Class)\tTypeError: wrong argument type Class (expected Module)\nprepend(Class)\tTypeError: wrong argument type Class (expected Module)\nextend(Class)\tTypeError: wrong argument type Class (expected Module)\nClass.new(Module)\tTypeError: superclass must be an instance of Class (given an instance of Module)\nClass.new(Class)\tTypeError: can't make subclass of Class\nClass.new(Integer)\tTypeError: superclass must be an instance of Class (given an instance of Integer)\nClass.new(singleton)\tTypeError: can't make subclass of singleton class\nproc >> Integer\tTypeError: callable object is expected\nproc << Integer\tTypeError: callable object is expected\nproc >> Symbol\tTypeError: callable object is expected\nproc >> proc\tok 1\nMethod#>> Integer\tTypeError: callable object is expected\ncurry(bad)\tTypeError: no implicit conversion of Symbol into Integer\nbsearch(String)\tTypeError: wrong argument type String (must be numeric, true, false or nil)\nbsearch(Float)\tok \"2\"\nbsearch(nil)\tok \"nil\"\nbsearch(NaN)\tArgumentError: comparison of Float with 0 failed\nArray#fill(bad)\tTypeError: no implicit conversion of Symbol into Integer\nArray#first(-1)\tArgumentError: negative array size\nArray#take(-1)\tArgumentError: attempt to take negative size\nArray#sample(-1)\tArgumentError: negative sample number\nArray#[]=(bad)\tTypeError: no implicit conversion of Symbol into Integer\nArray#flatten(bad)\tTypeError: no implicit conversion of Symbol into Integer\nHash#fetch(absent)\tKeyError: key not found: :x\nHash#merge(Integer)\tTypeError: no implicit conversion of Integer into Hash\nHash#dig(bad)\tTypeError: Integer does not have #dig method\nRange#new(incomparable)\tArgumentError: bad value for range\nRange#step(0)\tArgumentError: step can't be 0\nRange#step(-1)\tok []\nString#*(-1)\tArgumentError: negative argument\nString#[]=(absent)\tIndexError: string not matched\nInteger(bad)\tArgumentError: invalid value for Integer(): \"z\"\nInteger(nil)\tTypeError: can't convert nil into Integer\nFloat(bad)\tArgumentError: invalid value for Float(): \"z\"\nArray#pack(bad)\tTypeError: no implicit conversion of Integer into String\nString#unpack(bad)\tArgumentError: unknown unpack directive '-' in 'Z-'\nQueue.new(arg)\tTypeError: can't convert Integer into Array\nSizedQueue.new(0)\tArgumentError: queue size must be positive\nSizedQueue.new(-1)\tArgumentError: queue size must be positive\nQueue#pop(true) empty\tThreadError: queue empty\nQueue#pop(true, timeout:)\tArgumentError: can't set a timeout if non_block is enabled\nMarshal.dump(proc)\tTypeError: no _dump_data is defined for class Proc\nMarshal.dump(IO)\tTypeError: can't dump IO\nMarshal.dump(singleton)\tTypeError: singleton can't be dumped\nMarshal.dump(extended)\tok true\n"
      # Differential probe: ARGUMENT VALIDATION.
      #
      # Feeds deliberately-wrong arguments to the reflection and collection
      # surface and prints the exception class and message per row. A GOLDEN: the
      # `.expected` beside it is ruby 4.0.6's own answers, so every row is a
      # differential assertion and a divergence fails the suite.
      #
      # The point is to convert a long tail of one-off "zeo accepts what ruby
      # refuses" findings into a finite list. Sixteen gap files were written one
      # at a time before this existed.
      #
      # Add rows freely, then re-bless: a row that AGREES costs one line of output
      # and becomes regression cover the moment someone breaks it.

      ROWS = {}

      def probe(name, &blk) = ROWS[name] = blk

      # Rows zeo does not answer yet, each naming the gap that tracks it. A carved
      # row is left OUT of the output rather than recorded wrong -- one row cannot
      # be allowed to hold the other 74 out of the suite. When a gap is promoted,
      # delete its entry here and re-bless; the row comes back.
      SKIP = {
        "Module.new(arg)" => "tests/gaps/module_new_refuses_an_argument.rb",
      }.freeze

      # --- Names: ivars, constants, attributes, methods -------------------------
      o = Object.new
      probe("instance_variable_get(@@x)") { o.instance_variable_get("@@x") }
      probe("instance_variable_get(x)") { o.instance_variable_get("x") }
      probe("instance_variable_get(@1x)") { o.instance_variable_get("@1x") }
      probe("instance_variable_get(@)") { o.instance_variable_get("@") }
      probe("instance_variable_get(sym)") { o.instance_variable_get(:@ok) }
      probe("instance_variable_set(bad)") { o.instance_variable_set("@@x", 1) }
      probe("instance_variable_defined?(bad)") { o.instance_variable_defined?("x") }
      probe("remove_instance_variable(bad)") { o.remove_instance_variable("x") }
      probe("remove_instance_variable(absent)") { o.remove_instance_variable(:@nope) }

      k = Class.new
      probe("const_set(lower)") { k.const_set(:lower, 1) }
      probe("const_set(path)") { k.const_set("A::B", 1) }
      probe("const_set(empty)") { k.const_set("", 1) }
      probe("const_set(digit)") { k.const_set("1A", 1) }
      probe("const_get(lower)") { k.const_get(:lower) }
      probe("const_get(absent)") { k.const_get(:Absent) }
      probe("remove_const(absent)") { k.send(:remove_const, :Absent) }

      probe("attr_accessor(1bad)") { Class.new { attr_accessor :"1bad" } }
      probe("attr_accessor(ok then bad)") do
        c = Class.new { attr_accessor :ok, :"1bad" }
        c.instance_methods(false).sort.inspect
      end
      probe("attr_accessor(bang)") { Class.new { attr_accessor :"x!" } }
      probe("attr_accessor(int)") { Class.new { attr_accessor 1 } }
      probe("define_method(no body)") { Class.new { define_method(:x) } }
      probe("define_method(int)") { Class.new { define_method(:x, 1) } }
      probe("alias_method(absent)") { Class.new { alias_method :a, :nope } }
      probe("instance_method(absent)") { Class.new.instance_method(:nope) }

      # --- Modules and classes --------------------------------------------------
      probe("include(Class)") { Class.new { include String } }
      probe("include(Integer)") { Class.new { include 1 } }
      probe("include(self)") do
        m = Module.new
        m.send(:include, m)
      end
      probe("include(frozen, bad)") { Class.new.freeze.send(:include, String) }
      probe("include(frozen, good)") { Class.new.freeze.send(:include, Comparable) }
      probe("include(mod, Class)") { Class.new { include Comparable, String } }
      probe("prepend(Class)") { Class.new { prepend String } }
      probe("extend(Class)") { Object.new.extend(String) }
      probe("Class.new(Module)") { Class.new(Module.new) }
      probe("Class.new(Class)") { Class.new(Class) }
      probe("Class.new(Integer)") { Class.new(1) }
      probe("Class.new(singleton)") { Class.new(Object.new.singleton_class) }
      probe("Module.new(arg)") { Module.new(1) }

      # --- Procs and callables --------------------------------------------------
      pr = proc { |x| x }
      probe("proc >> Integer") { pr >> 7 }
      probe("proc << Integer") { pr << 7 }
      probe("proc >> Symbol") { (pr >> :to_s).call(1) }
      probe("proc >> proc") { (pr >> proc { |v| v }).call(1) }
      probe("Method#>> Integer") { 1.method(:+) >> 7 }
      probe("curry(bad)") { pr.curry(:x) }

      # --- Collections ----------------------------------------------------------
      probe("bsearch(String)") { [1, 2, 3].bsearch { "x" } }
      probe("bsearch(Float)") { [1, 2, 3].bsearch { 0.0 }.inspect }
      probe("bsearch(nil)") { [1, 2, 3].bsearch { nil }.inspect }
      probe("bsearch(NaN)") { [1, 2, 3].bsearch { Float::NAN }.inspect }
      probe("Array#fill(bad)") { [1].fill(1, :x) }
      probe("Array#first(-1)") { [1].first(-1) }
      probe("Array#take(-1)") { [1].take(-1) }
      probe("Array#sample(-1)") { [1].sample(-1) }
      probe("Array#[]=(bad)") { [1][:x] = 1 }
      probe("Array#flatten(bad)") { [1].flatten(:x) }
      probe("Hash#fetch(absent)") { {}.fetch(:x) }
      probe("Hash#merge(Integer)") { {}.merge(1) }
      probe("Hash#dig(bad)") { { a: 1 }.dig(:a, :b) }
      probe("Range#new(incomparable)") { Range.new(1, "a") }
      probe("Range#step(0)") { (1..3).step(0).to_a }
      probe("Range#step(-1)") { (1..3).step(-1).to_a }
      probe("String#*(-1)") { "a" * -1 }
      probe("String#[]=(absent)") { (+"a")["z"] = "b" }
      probe("Integer(bad)") { Integer("z") }
      probe("Integer(nil)") { Integer(nil) }
      probe("Float(bad)") { Float("z") }
      probe("Array#pack(bad)") { [1].pack("Z-") }
      probe("String#unpack(bad)") { "a".unpack("Z-") }

      # --- Queues and threads ---------------------------------------------------
      probe("Queue.new(arg)") { Thread::Queue.new(1) }
      probe("SizedQueue.new(0)") { Thread::SizedQueue.new(0) }
      probe("SizedQueue.new(-1)") { Thread::SizedQueue.new(-1) }
      probe("Queue#pop(true) empty") { Thread::Queue.new.pop(true) }
      probe("Queue#pop(true, timeout:)") { Thread::Queue.new.pop(true, timeout: 1) }

      # --- Marshal --------------------------------------------------------------
      probe("Marshal.dump(proc)") { Marshal.dump(proc {}) }
      probe("Marshal.dump(IO)") { Marshal.dump($stdout) }
      probe("Marshal.dump(singleton)") do
        s = Object.new
        def s.x = 1
        Marshal.dump(s)
      end
      probe("Marshal.dump(extended)") do
        s = Object.new
        s.extend(Comparable)
        Marshal.dump(s).bytesize.positive?
      end

      ROWS.each do |name, fn|
        next if SKIP.key?(name)

        r = begin
          v = fn.call
          "ok #{v.inspect}"
        rescue Exception => e
          "#{e.class}: #{e.message}"
        end
        puts "#{name}\t#{r}"
      end
    RUBY
  end
end
