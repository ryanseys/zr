# frozen_string_literal: true

require "spec_helper"

describe "Classes: regressions" do
  it "array each with object" do
    result = ze0(<<~'RUBY')
      # Array#each_with_object on poly_array and ptr_array used to silently
      # miss the type-check; the loop body never ran. Both shapes covered.

      # poly_array (heterogeneous)
      n = 0
      [1, "x"].each_with_object("") {|_e, _a| n += 1 }
      puts n

      # ptr_array (user objects)
      class T_array_each_with_object_Bar
        def initialize(x); @x = x; end
        attr_accessor :x
      end

      m = 0
      [T_array_each_with_object_Bar.new(1), T_array_each_with_object_Bar.new(2)].each_with_object("") {|_e, _a| m += 1 }
      puts m
    RUBY

    _(result).must_answer "2\n2\n"
  end

  it "array plus" do
    result = ze0(<<~'RUBY')
      # Array#+ used to fall through on poly_array / ptr_array — the result
      # temp held its default 0 because the dispatcher's type-list omitted
      # those shapes.

      # poly_array
      a = [1, "x"]
      b = [2, "y"]
      puts (a + b).length

      # ptr_array
      class T_array_plus_Bar
        def initialize(x); @x = x; end
        attr_accessor :x
      end

      c = [T_array_plus_Bar.new(1)]
      d = [T_array_plus_Bar.new(2)]
      puts (c + d).length
    RUBY

    _(result).must_answer "4\n2\n"
  end

  it "chained or assign collection poly array" do
    result = ze0(<<~'RUBY')
      # `(arr[idx] ||= []) << v` — chained `||=` over a poly_array
      # element. Pre-fix the IndexOrWriteNode expression-form returned
      # the int default for non-hash receivers, so the chain receiver
      # collapsed to literal `0` and `<<` failed T_chained_or_assign_collection_poly_array_C compile.
      # Spinel now lowers the get-then-set into an sp_RbVal temp that
      # the chain reads — same shape as the *_poly_hash arms but with
      # in-bounds + auto-grow handling for the indexed access.

      class T_chained_or_assign_collection_poly_array_C
        def initialize
          @a = Array.new(3) { [] }    # promotes to poly_array of empty poly_arrays
        end
        def push(idx, v)
          (@a[idx] ||= []) << v
        end
        def count(i); @a[i].length; end
      end

      c = T_chained_or_assign_collection_poly_array_C.new
      c.push(0, 10)
      c.push(0, 20)
      c.push(1, 100)
      puts c.count(0)   # 2
      puts c.count(1)   # 1
      puts c.count(2)   # 0
    RUBY

    _(result).must_answer <<~'OUT'
      2
      1
      0
    OUT
  end

  it "chained or assign collection str keys" do
    result = ze0(<<~'RUBY')
      # Same chained-`||=` lowering, but for `str_poly_hash` instead of
      # `sym_poly_hash`. Exercises the `const char *` key path (vs the
      # `sp_sym` integer key path) of the typed-poly-hash branch added
      # alongside the sym_poly_hash arm.

      class T_chained_or_assign_collection_str_keys_C
        def initialize
          @h = {}
          @h["init"] = []      # forces str_poly_hash
        end
        def add(k, v)
          (@h[k] ||= []) << v
        end
        def count(k); @h[k].length; end
      end

      c = T_chained_or_assign_collection_str_keys_C.new
      c.add("init", 7)         # appends to existing
      c.add("foo", 1)
      c.add("foo", 2)
      c.add("bar", 100)
      puts c.count("init")     # 1
      puts c.count("foo")      # 2
      puts c.count("bar")      # 1
    RUBY

    _(result).must_answer <<~'OUT'
      1
      2
      1
    OUT
  end

  it "cvar op write" do
    result = ze0(<<~'RUBY')
      # Issue #398: `@@x op= rhs` was rejected as unsupported syntax
      # (`ClassVariableOperatorWriteNode` had no parser/codegen handling).
      # `@@x = @@x op rhs` worked. Same gap for `||=` / `&&=`. Adds the
      # parser cases (PM_CLASS_VARIABLE_{OPERATOR,OR,AND}_WRITE_NODE) and
      # codegen arms (compile_stmt, compile_expr, compile_body_return).
      #
      # Limited to type-compatible cvar slots: cvar widening (e.g.
      # `@@x = nil; @@x ||= "str"` needing the slot to widen from int
      # to string) is a separate issue (sister to ivar widening at
      # scan_ivars).

      class T_cvar_op_write_Counter
        @@count = 0
        @@total = 100
        @@flag = 1

        def self.bump
          @@count += 1
          @@total += 10
        end

        def self.shift
          @@count <<= 2
        end

        def self.zero_flag
          @@flag &&= 7
        end

        def self.report
          puts @@count
          puts @@total
          puts @@flag
        end
      end

      T_cvar_op_write_Counter.bump
      T_cvar_op_write_Counter.bump
      T_cvar_op_write_Counter.bump
      T_cvar_op_write_Counter.report     # 3, 130, 1

      T_cvar_op_write_Counter.shift
      T_cvar_op_write_Counter.report     # 12, 130, 1

      T_cvar_op_write_Counter.zero_flag  # @@flag is truthy (1), so &&= writes 7
      T_cvar_op_write_Counter.report     # 12, 130, 7
    RUBY

    _(result).must_answer <<~'OUT'
      3
      130
      1
      12
      130
      1
      12
      130
      7
    OUT
  end

  it "def aset mixed ivar widen" do
    result = ze0(<<~'RUBY')
      # `def []=(name, value)` whose body dispatches on `name` and writes
      # `value` into ivars of differing types (`@id = value` and
      # `@name = value`, with `@id: mrb_int` and `@name: const char *`).
      # Pre-fix the param was pinned at `mrb_int` from the initialize-time
      # observation, and the second ivar assignment errored with
      # "incompatible integer to pointer conversion".
      #
      # widen_param_types_from_body_writes now also looks at
      # InstanceVariableWriteNode whose RHS is the param: when two or
      # more distinct ivar slot types are observed across such writes
      # within a `def []=` body, the param widens to poly. Each branch
      # can then unbox / box as the slot demands.

      class T_def_aset_mixed_ivar_widen_Foo
        def initialize
          @id = 0
          @name = ""
        end

        def []=(name, value)
          case name
          when :id
            @id = value
          when :name
            @name = value
          end
        end

        def id
          @id
        end

        def name
          @name
        end
      end

      f = T_def_aset_mixed_ivar_widen_Foo.new
      f[:id] = 42
      f[:name] = "hello"
      puts f.id
      puts f.name
    RUBY

    _(result).must_answer "42\nhello\n"
  end

  it "default argv narrows from string call site" do
    result = ze0(<<~'RUBY')
      # `def initialize(conf = ARGV)` typed `conf` as the specialised
      # `argv` scalar (because `infer_type(ARGV) == "argv"`). A caller
      # that passes a single string then unified the call-site `string`
      # against `argv` — the unifier had no argv-vs-string rule, so it
      # dropped to the catch-all poly tail. `conf` widened to poly and
      # `T_default_argv_narrows_from_string_call_site_Wrapper.new(conf)` (which expects a String) received a poly arg,
      # miscompiling the inner `@s.length` read.
      #
      # Narrowing argv + string → string biases toward the call-site
      # shape: single-string entry points don't drag the whole signature
      # into poly, while genuinely-array-of-strings call sites still
      # unify on their own type via the existing array-array path.

      class T_default_argv_narrows_from_string_call_site_Wrapper
        def initialize(s)
          @s = s
        end
        def show
          puts @s.length
        end
      end

      class T_default_argv_narrows_from_string_call_site_Entry
        def initialize(conf = ARGV)
          @conf = T_default_argv_narrows_from_string_call_site_Wrapper.new(conf)
        end
        def show
          @conf.show
        end
      end

      T_default_argv_narrows_from_string_call_site_Entry.new("hello").show     # 5
    RUBY

    _(result).must_answer "5\n"
  end

  it "default nil param with hash lookup" do
    result = ze0(<<~'RUBY')
      # #482. `def m(other = nil)` whose body uses `other[key]` (Hash
      # receiver index read) failed C compile when the lookup result
      # landed in a concretely-typed pointer field. With no caller
      # passing a non-nil `other`, spinel typed the param at the
      # `mrb_int` default; `other["key"]` fell through to the
      # unresolved-call warning (emits 0); and the resulting `lv_v`
      # assigned to the typed `iv_s` slot tripped
      # -Wint-conversion. Both the `return if other.nil?` and the
      # `if !v.nil?` guards folded away because spinel reasoned about
      # `mrb_int 0` as Integer 0 whose `.nil?` is false.
      #
      # Fix: a new back-propagation pass detects an int-typed param
      # with `nil` default whose body uses it as a String-keyed Hash
      # receiver, and widens the param's stored type from int to
      # str_str_hash. Spinel already treats hash pointers as nullable,
      # so the early-return / `.nil?` checks survive DCE.

      class T_default_nil_param_with_hash_lookup_Box
        attr_accessor :s

        def initialize(other = nil)
          @s = nil
          return if other.nil?
          v = other["key"]
          @s = v if !v.nil?
        end
      end

      b = T_default_nil_param_with_hash_lookup_Box.new
      b.s = "hello"
      puts b.s
    RUBY

    _(result).must_answer "hello\n"
  end

  it "default nil param with sym hash lookup" do
    result = ze0(<<~'RUBY')
      # Sym-keyed sibling of #482. Same shape — nil-default param +
      # body uses param as Hash receiver — but with a SymbolNode key
      # instead of a StringNode key. The widening pass now distinguishes
      # between str / sym keys and picks sym_str_hash instead of
      # str_str_hash when the body's `param[<key>]` carries a symbol.

      class T_default_nil_param_with_sym_hash_lookup_Box
        attr_accessor :s
        def initialize(other = nil)
          @s = nil
          return if other.nil?
          v = other[:key]
          @s = v if !v.nil?
        end
      end

      b = T_default_nil_param_with_sym_hash_lookup_Box.new
      b.s = "hello"
      puts b.s
    RUBY

    _(result).must_answer "hello\n"
  end

  it "each block cmeth widen" do
    result = ze0(<<~'RUBY')
      # Issue #424. `T_each_block_cmeth_widen_Json.escape(k)` inside `h.each |k, v|` couldn't
      # pick up k's narrowed string type from the hash variant -- the
      # cmeth param `s` stayed at the int default and the C compile
      # of the call site failed with `passing 'const char *' to
      # parameter of type 'mrb_int'`. Fix runs a targeted pre-scan
      # (widen_cmeths_via_hash_each_blocks) that walks hash-typed
      # params for `<p>.each |k, v|` blocks and widens any nested
      # `<Class>.<cmeth>(k|v)` call's param types from the hash's
      # key/value variant.
      #
      # Coverage:
      #   - str_str_hash: k and v both string; escape's param s
      #     widens to string via both call sites.
      #   - str_int_hash variant: k string, v int. Mixed types
      #     force the cmeth widening to handle each arg independently.

      class T_each_block_cmeth_widen_Json
        def self.escape(s)
          out = ""
          i = 0
          n = s.length
          while i < n
            out = out + s[i]
            i += 1
          end
          out
        end

        def self.from_str_hash(h)
          out = "{"
          h.each do |k, v|
            out = out + "\"" + T_each_block_cmeth_widen_Json.escape(k) + "\":\"" + T_each_block_cmeth_widen_Json.escape(v) + "\""
          end
          out + "}"
        end
      end

      puts T_each_block_cmeth_widen_Json.from_str_hash({"a" => "b"})
      puts T_each_block_cmeth_widen_Json.from_str_hash({"x" => "y"})
    RUBY

    _(result).must_answer <<~'OUT'
      {"a":"b"}
      {"x":"y"}
    OUT
  end

  it "each poly recv block auto splat" do
    result = ze0(<<~'RUBY')
      # `arr.each {|a, b| ... }` over a poly receiver (an sp_RbVal that
      # carries an array of arrays at runtime) should auto-splat each
      # element across the block params, matching CRuby's
      # `arr.each {|*args| a, b, *_ = args }` shape.  Pre-fix the poly
      # branch only assigned `bp1` and dropped `bp2`, so e.g.
      # `[[1, 2], [3, 4]].each {|a, b| sum += a + b }` skipped `b`
      # entirely.  Cover both inner kinds the destructuring uses:
      # poly_array (heterogeneous element types) and int_array
      # (homogeneous int element types — what `[i, fixed]` lowers to in
      # optcarrot's `setup_lut`).

      class T_each_poly_recv_block_auto_splat_C
        def initialize
          @h = {}
        end

        def push_int(bank, pair)
          # `pair` lowers to int_array because both elements are ints.
          (@h[bank] ||= []) << pair
        end

        def push_poly(bank, pair)
          # `pair` lowers to poly_array because the elements are mixed.
          (@h[bank] ||= []) << pair
        end

        def each_pair(bank)
          arr = @h[bank]
          sum = 0
          arr.each {|a, b| sum += a.to_i + b.to_i }
          sum
        end
      end

      c = T_each_poly_recv_block_auto_splat_C.new
      c.push_int(0, [10, 20])
      c.push_int(0, [3,  4])
      puts c.each_pair(0)         # 10 + 20 + 3 + 4 = 37

      d = T_each_poly_recv_block_auto_splat_C.new
      d.push_poly(1, [100, "x"])  # b is a string, exercising the poly_array branch
      d.push_poly(1, [5,   "y"])
      puts d.each_pair(1)         # 100 + 0 + 5 + 0 = 105 (string `to_i` of "x" / "y" = 0)
    RUBY

    _(result).must_answer "37\n105\n"
  end

  it "empty hash ivar string value" do
    result = ze0(<<~'RUBY')
      # Issue #64: an ivar initialized as `{}` defaulted to `str_int_hash`,
      # and a later `@h[k] = "string"` write fed `const char *` into
      # `sp_StrIntHash_set` (which expects `mrb_int`). Three pieces of the
      # fix:
      #   - scan_writer_calls now recognises `@h[k] = v` against an ivar
      #     still typed as the empty-hash default and promotes the slot
      #     based on the actual key/value types
      #   - the same scanner skips empty `{}` / `[]` writes when re-scanning
      #     so the iterative loop doesn't widen the promoted type back to
      #     poly via "old=str_str_hash, new=str_int_hash"
      #   - both compile_stmt(InstanceVariableWriteNode) and the inline
      #     constructor walker route empty `{}` against a promoted ivar to
      #     the matching `sp_*Hash_new()` ctor

      class T_empty_hash_ivar_string_value_Sources
        def initialize
          @file_sources = {}
          @current_file = "a.rb"
        end

        def add(source)
          @file_sources[@current_file] = source if @current_file
        end

        def lookup(name)
          @file_sources[name]
        end
      end

      s = T_empty_hash_ivar_string_value_Sources.new
      s.add("body")
      puts s.lookup("a.rb")        # body
      puts s.lookup("missing")     # (empty line — string hash default for missing key)

      # The other key/value-type combos covered by the same promotion path.
      class T_empty_hash_ivar_string_value_IntKeyed
        def initialize; @h = {}; end
        def put(k, v); @h[k] = v; end
        def get(k); @h[k]; end
      end

      ik = T_empty_hash_ivar_string_value_IntKeyed.new
      ik.put(7, "seven")
      ik.put(42, "forty-two")
      puts ik.get(7)               # seven
      puts ik.get(42)              # forty-two

      # Symbol-keyed promotion is also wired through but exercises a
      # pre-existing -Walloc-size-larger-than warning in the runtime
      # `sp_SymIntHash_grow` (unrelated to this issue), so it isn't part
      # of the make-test surface here.
    RUBY

    _(result).must_answer <<~'OUT'
      body

      seven
      forty-two
    OUT
  end

  it "ensure raise overrides body raise" do
    result = ze0(<<~'RUBY')
      # Ruby semantics: when both the body and the ensure clause raise,
      # the ensure-raise wins — the original body exception is replaced
      # by the ensure exception as it propagates.

      class T_ensure_raise_overrides_body_raise_C
        def f
          begin
            raise "original"
          ensure
            raise "from-ensure"
          end
        end
      end

      begin
        T_ensure_raise_overrides_body_raise_C.new.f
      rescue => e
        puts e
      end
    RUBY

    _(result).must_answer "from-ensure\n"
  end

  it "ensure runs on raise" do
    result = ze0(<<~'RUBY')
      # When the body of a `begin..ensure..end` raises, the ensure
      # clause must still run before the exception keeps propagating.
      # Previously the generated T_ensure_runs_on_raise_C had no setjmp around the body, so
      # raise unwound past the ensure entirely.

      class T_ensure_runs_on_raise_C
        def initialize
          @cleanup = "no"
          @before_raise = 0
        end

        def f
          begin
            @before_raise = 1
            raise "boom"
          ensure
            @cleanup = "yes"
          end
        end

        def report
          begin
            f
          rescue => e
            puts e
          end
          puts @before_raise
          puts @cleanup
        end
      end

      T_ensure_runs_on_raise_C.new.report
    RUBY

    _(result).must_answer <<~'OUT'
      boom
      1
      yes
    OUT
  end

  it "ensure runs on raise nested" do
    result = ze0(<<~'RUBY')
      # Nested `begin..ensure..end` with raise — both ensures must run
      # (inner first, then outer) before the exception reaches the
      # enclosing rescue.

      class T_ensure_runs_on_raise_nested_T
        def initialize
          @inner = "no"
          @outer = "no"
          @log = ""
        end

        def f
          begin
            begin
              raise "inner-boom"
            ensure
              @inner = "yes"
              @log = @log + "i"
            end
          ensure
            @outer = "yes"
            @log = @log + "o"
          end
        end

        def report
          begin
            f
          rescue => e
            puts e
          end
          puts @inner
          puts @outer
          puts @log
        end
      end

      T_ensure_runs_on_raise_nested_T.new.report
    RUBY

    _(result).must_answer <<~'OUT'
      inner-boom
      yes
      yes
      io
    OUT
  end

  it "ensure runs on return from rescue" do
    result = ze0(<<~'RUBY')
      # `begin..rescue..ensure..end` — when the rescue body exits via
      # `return`, the ensure clause must still run before the function
      # returns.

      class T_ensure_runs_on_return_from_rescue_C
        def initialize
          @cleanup = "no"
        end

        def f
          begin
            raise "boom"
          rescue
            return 99
          ensure
            @cleanup = "yes"
          end
        end

        def report
          puts f
          puts @cleanup
        end
      end

      T_ensure_runs_on_return_from_rescue_C.new.report
    RUBY

    _(result).must_answer "99\nyes\n"
  end

  it "ensure runs on return nested" do
    result = ze0(<<~'RUBY')
      # Nested `begin..ensure..end` — a `return` inside the inner begin
      # must replay the inner ensure first, then the outer ensure, then
      # return. Both writebacks must take effect, in order.

      class T_ensure_runs_on_return_nested_T
        def initialize
          @inner = 0
          @outer = 0
          @log = ""
        end

        def run
          begin
            a = 1
            begin
              b = 10
              a = 2
              return
            ensure
              @inner = b
              @log = @log + "i"
            end
          ensure
            @outer = a
            @log = @log + "o"
          end
        end

        def report
          run
          puts "inner=" + @inner.to_s
          puts "outer=" + @outer.to_s
          puts "log=" + @log
        end
      end

      T_ensure_runs_on_return_nested_T.new.report
    RUBY

    _(result).must_answer <<~'OUT'
      inner=10
      outer=2
      log=io
    OUT
  end

  it "enumerable" do
    result = ze0(<<~'RUBY')
      class T_enumerable_NumberList
        include Enumerable
        def initialize
          @data = (1..5).to_a
        end
        def each
          @data.each do |x|
            yield x
          end
        end
      end

      list = T_enumerable_NumberList.new
      total = 0
      list.each do |x|
        total += x
      end
      puts total  # 15
      puts "done"
    RUBY

    _(result).must_answer "15\ndone\n"
  end

  it "a rescue picks the first arm whose class matches, and a bare rescue catches all" do
    result = ze0(<<~'RUBY')
      # Test exception classes

      class T_exceptions_AppError < RuntimeError
      end

      class T_exceptions_NotFoundError < T_exceptions_AppError
      end

      # Raise custom exception
      begin
        raise T_exceptions_NotFoundError, "item not found"
      rescue T_exceptions_NotFoundError => e
        puts e  # item not found
      rescue T_exceptions_AppError => e
        puts "app error"
      end

      # Raise with class name
      begin
        raise T_exceptions_AppError, "something went wrong"
      rescue T_exceptions_NotFoundError => e
        puts "not found"
      rescue T_exceptions_AppError => e
        puts e  # something went wrong
      end

      # Bare rescue catches all
      begin
        raise "generic error"
      rescue => e
        puts e  # generic error
      end

      puts "done"
    RUBY

    _(result).must_answer <<~'OUT'
      item not found
      something went wrong
      generic error
      done
    OUT
  end

  it "fiber ivar persists across yield" do
    result = ze0(<<~'RUBY')
      # The cycle this program builds on purpose, and the census it leaves
      # behind. A cycle alive at exit is not a defect: it is a ring the
      # program never broke, so the census below is recorded as an
      # observation rather than gated on.
      #
      # An Outer and its inherited Sub hold each other through the forwarded class-method init.
      # At exit: cycle leak: 2 objects (T_forward_call_class_method_inherited_init_Outer x1, T_forward_call_class_method_inherited_init_Sub x1)
      # Bundled tests:
      #   - fiber_ivar_persists_across_yield
      #   - fiber_yield_across_method_call
      #   - file_write_poly_arg
      #   - forward_call_class_method_inherited_init
      #   - forward_call_class_method_inherited_init_int_array


      class T_fiber_ivar_persists_across_yield_Counter
        def initialize
          @n = 0
          @fiber = Fiber.new do
            @n += 10
            Fiber.yield
            @n += 100
            Fiber.yield
            @n += 1000
          end
        end

        def step
          @fiber.resume
          @n
        end
      end

      c = T_fiber_ivar_persists_across_yield_Counter.new
      puts c.step
      puts c.step
      puts c.step
    RUBY

    _(result).must_answer <<~'OUT'
      10
      110
      1110
    OUT
  end

  it "fiber yield across method call" do
    result = ze0(<<~'RUBY')
      # The cycle this program builds on purpose, and the census it leaves
      # behind. A cycle alive at exit is not a defect: it is a ring the
      # program never broke, so the census below is recorded as an
      # observation rather than gated on.
      #
      # An Outer and its inherited Sub hold each other through the forwarded class-method init.
      # At exit: cycle leak: 2 objects (T_forward_call_class_method_inherited_init_Outer x1, T_forward_call_class_method_inherited_init_Sub x1)
      # Bundled tests:
      #   - fiber_ivar_persists_across_yield
      #   - fiber_yield_across_method_call
      #   - file_write_poly_arg
      #   - forward_call_class_method_inherited_init
      #   - forward_call_class_method_inherited_init_int_array


      class T_fiber_yield_across_method_call_Stepper
        def initialize
          @count = 0
          @fiber = Fiber.new { main_loop }
        end

        def step
          @fiber.resume
          @count
        end

        def main_loop
          while @count < 5
            tick
            tick
            Fiber.yield
          end
        end

        def tick
          @count += 1
        end
      end

      s = T_fiber_yield_across_method_call_Stepper.new
      puts s.step
      puts s.step
      puts s.step
    RUBY

    _(result).must_answer <<~'OUT'
      2
      4
      6
    OUT
  end

  it "file write poly arg" do
    result = ze0(<<~'RUBY')
      # The cycle this program builds on purpose, and the census it leaves
      # behind. A cycle alive at exit is not a defect: it is a ring the
      # program never broke, so the census below is recorded as an
      # observation rather than gated on.
      #
      # An Outer and its inherited Sub hold each other through the forwarded class-method init.
      # At exit: cycle leak: 2 objects (T_forward_call_class_method_inherited_init_Outer x1, T_forward_call_class_method_inherited_init_Sub x1)
      # Bundled tests:
      #   - fiber_ivar_persists_across_yield
      #   - fiber_yield_across_method_call
      #   - file_write_poly_arg
      #   - forward_call_class_method_inherited_init
      #   - forward_call_class_method_inherited_init_int_array


      # Issue #643: `File.write(path, value)` where `value`'s static
      # type is poly (cross-class union widened the return slot of the
      # producer to sp_RbVal) used to emit `sp_file_write(lv_path,
      # lv_value)` with a struct value passed where const char * was
      # expected — C compile failure with "incompatible type for
      # argument 2".
      #
      # Fix: when either arg's static type is poly, extract `.v.s`
      # before the call.

      class T_file_write_poly_arg_Worker
        def run(x)
          "result-#{x}"
        end
      end

      class T_file_write_poly_arg_OtherWorker
        def run(x)
          "alt-#{x}"
        end
      end

      # Cross-class union via array — both classes' `run` returns String,
      # but the union of obj_Worker | obj_OtherWorker pushed through
      # `.each` widens the dispatch return to sp_RbVal in some shapes.
      workers = [T_file_write_poly_arg_Worker.new, T_file_write_poly_arg_OtherWorker.new]
      results = workers.map { |w| w.run(42) }

      # results is poly_array; result of [0] dispatch is poly. File.write
      # call site must unbox before the sp_file_write boundary.
      # Use cwd-relative path so Windows MinGW (no `/tmp`) passes —
      # memory: feedback_windows_tmp_path.
      path = "spinel_i643_test.txt"
      File.write(path, results[0])
      puts File.read(path)
      File.delete(path)
    RUBY

    _(result).must_answer "result-42\n"
  end

  it "forward call class method inherited init" do
    result = ze0(<<~'RUBY')
      # The cycle this program builds on purpose, and the census it leaves
      # behind. A cycle alive at exit is not a defect: it is a ring the
      # program never broke, so the census below is recorded as an
      # observation rather than gated on.
      #
      # An Outer and its inherited Sub hold each other through the forwarded class-method init.
      # At exit: cycle leak: 2 objects (T_forward_call_class_method_inherited_init_Outer x1, T_forward_call_class_method_inherited_init_Sub x1)
      # Bundled tests:
      #   - fiber_ivar_persists_across_yield
      #   - fiber_yield_across_method_call
      #   - file_write_poly_arg
      #   - forward_call_class_method_inherited_init
      #   - forward_call_class_method_inherited_init_int_array


      # Forward-ref `Class.new(arg)` whose Class is a subclass with its
      # own `def initialize(_arg); super; end`. Pre-fix codegen widened
      # the child's #initialize ptype from the call site but never
      # propagated the type through the bare `super` to the parent's
      # #initialize, leaving the parent's `owner` param at the default
      # `mrb_int`. The parent's body `@owner = owner` then stored the
      # int payload; subsequent `@owner.<method>` dispatches on a child
      # instance landed on the wrong class via the int→class fallback.

      class T_forward_call_class_method_inherited_init_Outer
        def initialize
          @child = T_forward_call_class_method_inherited_init_Sub.new(self)
        end
        def report
          @child.read_owner_name
        end
        def name; "outer"; end
      end

      class T_forward_call_class_method_inherited_init_Base
        def initialize(owner)
          @owner = owner
        end
        def read_owner_name
          @owner.name
        end
      end

      class T_forward_call_class_method_inherited_init_Sub < T_forward_call_class_method_inherited_init_Base
        def initialize(_owner)
          super
        end
      end

      o = T_forward_call_class_method_inherited_init_Outer.new
      puts o.report
    RUBY

    _(result).must_answer "outer\n"
  end

  it "forward call class method inherited init int array" do
    result = ze0(<<~'RUBY')
      # The cycle this program builds on purpose, and the census it leaves
      # behind. A cycle alive at exit is not a defect: it is a ring the
      # program never broke, so the census below is recorded as an
      # observation rather than gated on.
      #
      # An Outer and its inherited Sub hold each other through the forwarded class-method init.
      # At exit: cycle leak: 2 objects (T_forward_call_class_method_inherited_init_Outer x1, T_forward_call_class_method_inherited_init_Sub x1)
      # Bundled tests:
      #   - fiber_ivar_persists_across_yield
      #   - fiber_yield_across_method_call
      #   - file_write_poly_arg
      #   - forward_call_class_method_inherited_init
      #   - forward_call_class_method_inherited_init_int_array


      # Inherited-init forward-ref with an IntArray param flowing through
      # the super call. The parent's `arr` param must end up
      # `sp_IntArray *` (not the default `mrb_int`) so the body's
      # `@arr = arr` stores the right pointer type and a parent-defined
      # accessor reads the typed value.

      class T_forward_call_class_method_inherited_init_int_array_Driver
        def initialize
          @child = T_forward_call_class_method_inherited_init_int_array_Subscriber.new([10, 20, 30, 40])
        end
        def report
          @child.length
        end
      end

      class T_forward_call_class_method_inherited_init_int_array_Listener
        def initialize(arr)
          @arr = arr
        end
        def length
          @arr.length
        end
      end

      class T_forward_call_class_method_inherited_init_int_array_Subscriber < T_forward_call_class_method_inherited_init_int_array_Listener
        def initialize(_arr)
          super
        end
      end

      d = T_forward_call_class_method_inherited_init_int_array_Driver.new
      puts d.report
    RUBY

    _(result).must_answer "4\n"
  end

  it "forward call class method inherited init obj" do
    result = ze0(<<~'RUBY')
      # Inherited-init forward-ref where the param type is itself an
      # obj_X user class. Verifies the type flows through both the
      # `Class.new(@h)` constructor branch and the bare `super` of the
      # child's initialize.

      class T_forward_call_class_method_inherited_init_obj_Holder
        def initialize(name)
          @name = name
        end
        def label
          "h:#{@name}"
        end
      end

      class T_forward_call_class_method_inherited_init_obj_Outer
        def initialize
          @h = T_forward_call_class_method_inherited_init_obj_Holder.new("alpha")
          @child = T_forward_call_class_method_inherited_init_obj_Sub.new(@h)
        end
        def report
          @child.held_label
        end
      end

      class T_forward_call_class_method_inherited_init_obj_Base
        def initialize(holder)
          @holder = holder
        end
        def held_label
          @holder.label
        end
      end

      class T_forward_call_class_method_inherited_init_obj_Sub < T_forward_call_class_method_inherited_init_obj_Base
        def initialize(_holder)
          super
        end
      end

      o = T_forward_call_class_method_inherited_init_obj_Outer.new
      puts o.report
    RUBY

    _(result).must_answer "h:alpha\n"
  end

  it "forward call class method int array" do
    result = ze0(<<~'RUBY')
      # `Class.new(int_array_arg)` where the callee class is defined later
      # than the call site. Pre-fix codegen left T_forward_call_class_method_int_array_Target's `arr` param at
      # the default `mrb_int`; the int→class fallback then emitted the
      # call with a Wint-conversion error. Source order kept caller-first.

      class T_forward_call_class_method_int_array_Caller
        def make_target
          @t = T_forward_call_class_method_int_array_Target.new([10, 20, 30])
        end
        def length
          @t.show
        end
      end

      class T_forward_call_class_method_int_array_Target
        def initialize(arr)
          @arr = arr
        end
        def show
          @arr.length
        end
      end

      c = T_forward_call_class_method_int_array_Caller.new
      c.make_target
      puts c.length
    RUBY

    _(result).must_answer "3\n"
  end

  it "forward call class method nested" do
    result = ze0(<<~'RUBY')
      # Nested forward-ref: `T_forward_call_class_method_nested_Outer.new(T_forward_call_class_method_nested_Inner.new)` where both T_forward_call_class_method_nested_Outer and
      # T_forward_call_class_method_nested_Inner are defined later than the construction site. The T_forward_call_class_method_nested_Inner.new
      # nested arg type must propagate to T_forward_call_class_method_nested_Outer.initialize's param so the
      # outer Class.new ptype widens correctly.

      class T_forward_call_class_method_nested_Driver
        def boot
          @outer = T_forward_call_class_method_nested_Outer.new(T_forward_call_class_method_nested_Inner.new(42))
        end
        def reach
          @outer.payload.value
        end
      end

      class T_forward_call_class_method_nested_Inner
        def initialize(v)
          @v = v
        end
        def value
          @v
        end
      end

      class T_forward_call_class_method_nested_Outer
        def initialize(inner)
          @inner = inner
        end
        def payload
          @inner
        end
      end

      d = T_forward_call_class_method_nested_Driver.new
      d.boot
      puts d.reach
    RUBY

    _(result).must_answer "42\n"
  end

  it "forward call class method obj" do
    result = ze0(<<~'RUBY')
      # `Class.new(obj_X)` shape: caller passes a user-class instance to a
      # forward-defined Class.new. Mirrors the optcarrot
      # `PPU.new(@conf, @cpu, @video.palette)` site where the callee's
      # obj-typed param flowed in from a yet-to-be-defined sibling class.

      class T_forward_call_class_method_obj_Holder
        def initialize(name)
          @name = name
        end
        def label
          "h:#{@name}"
        end
      end

      class T_forward_call_class_method_obj_Caller
        def make
          @h = T_forward_call_class_method_obj_Holder.new("alpha")
          @t = T_forward_call_class_method_obj_Target.new(@h)
        end
        def show
          @t.held_label
        end
      end

      class T_forward_call_class_method_obj_Target
        def initialize(h)
          @holder = h
        end
        def held_label
          @holder.label
        end
      end

      c = T_forward_call_class_method_obj_Caller.new
      c.make
      puts c.show
    RUBY

    _(result).must_answer "h:alpha\n"
  end

  it "forward call param type int array" do
    result = ze0(<<~'RUBY')
      # File-order caller-first / callee-second: a T_forward_call_param_type_int_array_Caller class invokes a
      # method on a yet-untyped ivar (because the callee class is defined
      # later in the source). Pre-fix codegen left the callee's params at
      # the default `mrb_int` so the IntArray + bool args produced
      # "incompatible-pointer" / "Wint-conversion" errors when the
      # int→class fallback emitted the call. With the forward-ref widening
      # in place the callee picks up `sp_IntArray *` + `mrb_bool` from
      # this single call site.

      class T_forward_call_param_type_int_array_Caller
        def initialize(target)
          @target = target
          @arr = [1, 2, 3]
          @flag = false
        end
        def go
          @target.set_payload(@arr, @flag)
        end
      end

      class T_forward_call_param_type_int_array_Target
        def set_payload(arr, flag)
          @arr = arr
          @flag = flag
        end
        def info
          "len=#{@arr.length} flag=#{@flag}"
        end
      end

      t = T_forward_call_param_type_int_array_Target.new
      c = T_forward_call_param_type_int_array_Caller.new(t)
      c.go
      puts t.info
    RUBY

    _(result).must_answer "len=3 flag=false\n"
  end

  it "forward call param type obj" do
    result = ze0(<<~'RUBY')
      # Forward-call with a user-class-typed arg flowing through the
      # caller's ivar to the callee's parameter slot. Mirrors optcarrot's
      # `@ppu.nametables = @mirroring` shape — the callee accepts an
      # `obj_<UserClass>` and the int→class fallback dispatches via the
      # yet-untyped `@ppu` ivar.

      class T_forward_call_param_type_obj_Holder
        def initialize(name)
          @name = name
        end
        def label
          "h:#{@name}"
        end
      end

      class T_forward_call_param_type_obj_Caller
        def initialize(target)
          @target = target
          @holder = T_forward_call_param_type_obj_Holder.new("alpha")
        end
        def go
          @target.attach(@holder)
        end
      end

      class T_forward_call_param_type_obj_Target
        def attach(h)
          @holder = h
        end
        def held_label
          @holder.label
        end
      end

      t = T_forward_call_param_type_obj_Target.new
      c = T_forward_call_param_type_obj_Caller.new(t)
      c.go
      puts t.held_label
    RUBY

    _(result).must_answer "h:alpha\n"
  end

  it "gc save double in new" do
    result = ze0(<<~'RUBY')
      class T_gc_save_double_in_new_GcSaveDoubleInNew
        def initialize(path)
          data = [1, 2, 3]
          @x = data
        end

        def step
          @x.length
        end
      end

      o = T_gc_save_double_in_new_GcSaveDoubleInNew.new("a")
      puts o.step
    RUBY

    _(result).must_answer "3\n"
  end

  it "gc scan skip inherited ivar" do
    result = ze0(<<~'RUBY')
      # When parent and child both record the same ivar name, the struct
      # field is contributed once by `emit_parent_fields`. `emit_class_struct`
      # already skips child-side redeclaration, so child's own gc_scan walk
      # must also skip the inherited slot — otherwise it emits a second
      # (often miscast) mark on top of the parent walk's correct mark.
      #
      # Here parent's `@data` is widened to poly (heterogeneous writes), and
      # child also writes `@data` from a method-returned poly value, exercising
      # the inherited-slot path under GC pressure.

      class T_gc_scan_skip_inherited_ivar_Base
        def initialize(kind)
          if kind == 0
            @data = [1, 2, 3]
          else
            @data = "hello"
          end
        end
      end

      class T_gc_scan_skip_inherited_ivar_Holder
        def initialize(v)
          @v = v
        end
        attr_reader :v
      end

      class T_gc_scan_skip_inherited_ivar_Child < T_gc_scan_skip_inherited_ivar_Base
        def initialize(h)
          super(0)
          @data = h.v
        end
      end

      class T_gc_scan_skip_inherited_ivar_Trash
        def initialize(n)
          @n = n
          @s = "padding payload " * 64
        end
      end

      h_str = T_gc_scan_skip_inherited_ivar_Holder.new("from-holder")
      T_gc_scan_skip_inherited_ivar_Holder.new(123)
      c = T_gc_scan_skip_inherited_ivar_Child.new(h_str)

      junk = []
      i = 0
      while i < 5000
        junk << T_gc_scan_skip_inherited_ivar_Trash.new(i)
        i = i + 1
      end

      puts junk.length
      puts "ok"
    RUBY

    _(result).must_answer "5000\nok\n"
  end

  it "hash each param narrow" do
    result = ze0(<<~'RUBY')
      # Issue #408. Regression guard for the hash-each body-walker
      # narrow path (9ca01d7 + analyze-side port in 02003ad).
      #
      # Pre-fix shape: a class method whose only signal on its hash
      # param is `h.each |k, v|` inside the body left `h` typed as
      # poly_poly_hash, made `k` / `v` poly, and the str-concat
      # `\"\\\"\" + k + \"\\\":\"` cascaded into compile errors at the C
      # layer ("passing sp_RbVal to parameter of incompatible type
      # 'const char *'").
      #
      # Post-fix: the body-walker harvests usage signals -- here, k/v
      # both flowing into str-concat -- and narrows the param to
      # str_str_hash (or str_int_hash when v is int-shaped). Both
      # compile clean and produce the expected output.
      #
      # This test re-runs the exact confirmation snippet Ori posted on
      # #408; closing the issue without a regression guard would leave
      # the narrow path exposed to silent regressions on future
      # refactors to the each-body walker.

      class T_hash_each_param_narrow_Encoder
        def self.from_str_hash(h)
          out = "{"
          first = true
          h.each do |k, v|
            out += "," unless first
            first = false
            out += "\"" + k + "\":\"" + v + "\""
          end
          out + "}"
        end

        def self.from_int_hash(h)
          out = "{"
          first = true
          h.each do |k, v|
            out += "," unless first
            first = false
            out += "\"" + k + "\":" + v.to_s
          end
          out + "}"
        end
      end

      puts T_hash_each_param_narrow_Encoder.from_str_hash({"name" => "alice", "city" => "NYC"})
      puts T_hash_each_param_narrow_Encoder.from_int_hash({"a" => 1, "b" => 2, "c" => 3})
    RUBY

    _(result).must_answer <<~'OUT'
      {"name":"alice","city":"NYC"}
      {"a":1,"b":2,"c":3}
    OUT
  end

  it "hash fetch hash default" do
    result = ze0(<<~'RUBY')
      # `Hash#fetch(key, {})` on an int-leaf hash. Sequel to #454 which
      # closed the string-default case via sp_int_to_s conversion. The
      # hash-default case can't unify the two ternary arms to a single
      # primitive: get returns int, default is a hash pointer. Box both
      # arms to sp_RbVal and surface the return type as poly.

      class T_hash_fetch_hash_default_P
        def self.lookup_present(params)
          params.fetch "x", {}
        end

        def self.lookup_missing(params)
          params.fetch "missing", {}
        end
      end

      box = { "x" => 7 }
      v1 = T_hash_fetch_hash_default_P.lookup_present(box)
      v2 = T_hash_fetch_hash_default_P.lookup_missing(box)
      # Hit path returns the int value (boxed)
      puts v1.is_a?(Integer) ? v1 : "non-int"
      # Miss path returns the empty hash (boxed)
      puts v2.is_a?(Hash) ? "hash" : "non-hash"
    RUBY

    _(result).must_answer "7\nhash\n"
  end

  it "hash fetch hash default narrowing" do
    result = ze0(<<~'RUBY')
      # Sequel to hash_fetch_hash_default: when `params.fetch "k", {}`
      # is followed by `is_a?(Hash)` narrowing into an if-expression
      # whose else arm returns an empty hash, the receiving local was
      # typed as the concrete hash variant (str_int_hash) by the
      # pass-1 scan_locals (the if-expr's then-arm reads raw_sub but
      # raw_sub is still in the deferred-declaration window), then
      # stuck there because the pass-2 merge had no "concrete → poly"
      # rule. The codegen-emitted assignment then puts an sp_RbVal
      # poly into the typed slot, failing C compile with
      # `incompatible types when assigning to type 'sp_StrIntHash *'
      #  from type 'sp_RbVal'`.

      class T_hash_fetch_hash_default_narrowing_ArticleParams
        def self.from_raw(params)
          raw_sub = params.fetch "article", {}
          sub = if raw_sub.is_a?(Hash)
            raw_sub
          else
            {}
          end
          sub.is_a?(Hash) ? "got-hash" : "no-hash"
        end
      end

      puts T_hash_fetch_hash_default_narrowing_ArticleParams.from_raw({ "x" => 1 })
      puts T_hash_fetch_hash_default_narrowing_ArticleParams.from_raw({ "y" => 2 })
    RUBY

    _(result).must_answer "got-hash\ngot-hash\n"
  end

  it "hash fetch string default on int leaf" do
    result = ze0(<<~'RUBY')
      # #454: `params.fetch "k", ""` on a Hash[String, Int] (or
      # Hash[Symbol, Int]) emitted a type-mismatched ternary
      # (`has_key ? get_int : char_star_default`) and failed C compile
      # under -Werror=int-conversion.
      #
      # Narrow fix: when the default is a string literal and the hash
      # leaf is int, widen the call's static return type to "string"
      # and route the get arm through sp_int_to_s so both arms agree
      # on `const char *`. Limited to (int leaf + string default);
      # broader (poly leaf, hash default, etc.) cascades through the
      # `is_a?(Hash)` narrowing in real-blog params and is left for
      # a follow-up.

      class T_hash_fetch_string_default_on_int_leaf_P
        def self.lookup_str(params)
          params.fetch "title", ""
        end

        def self.lookup_sym(params)
          params.fetch :title, ""
        end
      end

      # Hit path: the integer at the key gets stringified.
      puts T_hash_fetch_string_default_on_int_leaf_P.lookup_str({ "x" => 1, "title" => 42 })
      # Miss path: the empty-string default.
      puts T_hash_fetch_string_default_on_int_leaf_P.lookup_str({ "x" => 1 })

      # Sym-keyed counterpart.
      puts T_hash_fetch_string_default_on_int_leaf_P.lookup_sym({ x: 1, title: 99 })
      puts T_hash_fetch_string_default_on_int_leaf_P.lookup_sym({ x: 1 })

      # Matched-default control (no fix needed; existing behavior).
      class T_hash_fetch_string_default_on_int_leaf_Q
        def self.lookup(params)
          params.fetch "x", 0
        end
      end
      puts T_hash_fetch_string_default_on_int_leaf_Q.lookup({ "x" => 7 })
      puts T_hash_fetch_string_default_on_int_leaf_Q.lookup({ "other" => 1 })
    RUBY

    _(result).must_answer <<~'OUT'
      42

      99

      7
      0
    OUT
  end

  it "heterogeneous dispatch int return narrow" do
    result = ze0(<<~'RUBY')
      # Approach-2 narrowing: when `<poly>[k]` chases an `arr[i]` whose
      # `arr` is a poly_array with observed elements that all return int
      # from `[]` (IntArray + Method-objects), narrow the outer dispatch
      # return type from poly to int. Without narrowing, the outer call
      # returns sp_RbVal and downstream sites — `total + 1`, `~bits`,
      # `iv += 1`, etc. — fail the C compile or cascade widen ivars to
      # poly.

      class T_heterogeneous_dispatch_int_return_narrow_Box
        def initialize
          @slots = [nil] * 4         # int_array initially
          @int_arr = [10, 20, 30, 40]
          @slots[0] = method(:double_at)   # widens via obj_Method_ptr_array
          @slots[1] = @int_arr             # then widens to poly_array
          @total = 0
        end

        def double_at(i)
          i * 2
        end

        # Direct ivar access: narrowing fires via `InstanceVariableReadNode`.
        def via_ivar(i)
          @slots[i][i]
        end

        # Local-variable alias: narrowing fires via `LocalVariableReadNode`
        # with the AST-walking fallback in `find_lv_ivar_alias_in_ast`.
        def via_local(i)
          cache = @slots
          cache[i][i]
        end

        def run
          # IntArray arm of @slots[1]: returns @int_arr[1] = 20.
          @total = via_ivar(1)
          @total += 1
          puts @total                # 21
          # Method arm of @slots[0]: returns double_at(0) = 0.
          @total = via_local(0)
          @total += 1
          puts @total                # 1
        end
      end

      T_heterogeneous_dispatch_int_return_narrow_Box.new.run
    RUBY

    _(result).must_answer "21\n1\n"
  end

  it "if static false skips dead branch compile" do
    result = ze0(<<~'RUBY')
      # `compile_cond_expr` already returns the literal "FALSE" for a
      # predicate whose static type is `nil` (e.g. an attr-style read
      # of an ivar only ever assigned `nil`). The if/unless emit then
      # wraps the dead body in `if (FALSE) { … }`, but the body's C
      # statements still pass through gcc — and they often type-error
      # against ivars/methods whose shapes only make sense when the
      # predicate is true. Skipping body emission lets the rest of
      # the program compile.

      class T_if_static_false_skips_dead_branch_compile_Profiler
        def initialize
          # `@mode` is statically nil — only ever assigned this literal.
          # The read in the predicate below folds to `if (FALSE)`.
          @mode = nil
        end

        def run
          # Dead branch when @mode is nil. Pre-fix, spinel emits the
          # body anyway: `sp_str_sub("...", "MODE", iv_mode)` with
          # iv_mode typed as `mrb_int` (its only init being `= nil`)
          # — the 3rd arg fails -Wint-conversion.
          if @mode
            out = "label_MODE".sub("MODE", @mode)
            puts out
          end
          puts "ran"
        end
      end

      # `if @nil_ivar; ... else; ... end` with a trailing stmt forces
      # the if into statement position (compile_if_stmt). The else arm
      # is the live one when the predicate is statically nil.
      class T_if_static_false_skips_dead_branch_compile_Either
        def initialize
          @verbose = nil
        end

        def run
          if @verbose
            out = "label_MODE".sub("MODE", @verbose)
            puts out
          else
            puts "quiet"
          end
          puts "done"
        end
      end

      T_if_static_false_skips_dead_branch_compile_Profiler.new.run
      T_if_static_false_skips_dead_branch_compile_Either.new.run
    RUBY

    _(result).must_answer <<~'OUT'
      ran
      quiet
      done
    OUT
  end

  it "imeth name collision recv aware" do
    result = ze0(<<~'RUBY')
      # Issue #429. Two unrelated classes each defining `def get(k)`
      # with different return types caused the analyzer's int-recv
      # cross-class widening to pick the first match -- so a local
      # `r = c.get("/foo")` where c is statically obj_IntClient ended
      # up declared `const char *` (from T_imeth_name_collision_recv_aware_StrBag#get's String return),
      # crashing the C compile when sp_IntClient_get returned an
      # sp_IntBag *.
      #
      # Fix: scan_locals' first pass calls infer_type before the
      # scope decls land, so `c`'s var-type is "" / "int" at that
      # point. infer_recv_method_type's int-recv arm enumerates
      # every user class with `mname` and picks the first non-int
      # return. The fix bails out of that path when (a) the recv is
      # a LocalVariableReadNode whose var-type isn't pinned yet, and
      # (b) the candidate classes disagree on the return type --
      # leaving a later iteration of the iterative loop to pick the
      # right one via the is_obj_type arm once `c`'s declaration
      # has propagated.
      #
      # Coverage: the canonical "two classes, same imeth name,
      # different return types, statically-typed call sites for
      # each" shape from Ori's repro.

      class T_imeth_name_collision_recv_aware_StrBag
        def initialize
          @h = {"a" => "b"}
          @h.delete("a")
          @h["x"] = "got-x"
        end
        def get(k)
          @h[k]
        end
      end

      class T_imeth_name_collision_recv_aware_IntBag
        attr_accessor :status
        def initialize
          @status = 42
        end
      end

      class T_imeth_name_collision_recv_aware_IntClient
        def get(path)
          out = T_imeth_name_collision_recv_aware_IntBag.new
          out.status = path.length
          out
        end
      end

      s = T_imeth_name_collision_recv_aware_StrBag.new
      puts s.get("x")

      c = T_imeth_name_collision_recv_aware_IntClient.new
      r = c.get("/foo")
      puts r.status
    RUBY

    _(result).must_answer "got-x\n4\n"
  end

  it "imeth override widen to poly" do
    result = ze0(<<~'RUBY')
      # #567 (Sam Ruby). Sibling of #563. When an override widens a
      # value param to sp_RbVal (poly) because its call sites pass
      # mixed types, but the parent's same param stays scalar, the C
      # function signatures of base and override disagree. The
      # override-dispatch gate cls_imeth_override_ptypes_match
      # rejected the family, so a `self[k] = v` inside a parent body
      # fell through to the static call on the parent's raise stub
      # rather than dispatching to the override.
      #
      # Fix: post-fixpoint, unify the family's ptypes at any slot
      # where at least one member is "poly" so all member signatures
      # agree. The cls_id switch then fires and routes to the
      # concrete override.

      class T_imeth_override_widen_to_poly_Base
        def []=(name, value); raise NotImplementedError; end
        def fill; self[:title] = "Hello"; end
      end

      class T_imeth_override_widen_to_poly_Article < T_imeth_override_widen_to_poly_Base
        attr_accessor :id, :title
        def []=(name, value)
          case name
          when :id then @id = value
          when :title then @title = value
          end
        end
      end

      a = T_imeth_override_widen_to_poly_Article.new
      a.id = 0
      a.title = ""
      a[:id] = 42
      a[:title] = "Other"
      a.fill
      puts a.title.inspect
    RUBY

    _(result).must_answer <<~'OUT'
      "Hello"
    OUT
  end

  it "implicit self param poly" do
    result = ze0(<<~'RUBY')
      class T_implicit_self_param_poly_TokenSink
        def initialize
          @value = ""
        end

        def set_token(value)
          @value = value.to_s
        end

        def run
          set_token(1)
          set_token("done")
          puts @value
        end
      end

      T_implicit_self_param_poly_TokenSink.new.run
    RUBY

    _(result).must_answer "done\n"
  end

  it "inherit" do
    result = ze0(<<~'RUBY')
      # Test inheritance and super

      class T_inherit_Animal
        def initialize(name)
          @name = name
        end

        def name
          @name
        end

        def speak
          "..."
        end

        def describe
          name
        end
      end

      class T_inherit_Dog < T_inherit_Animal
        def initialize(name, breed)
          super(name)
          @breed = breed
        end

        def breed
          @breed
        end

        def speak
          "Woof!"
        end
      end

      class T_inherit_Cat < T_inherit_Animal
        def speak
          "Meow!"
        end
      end

      # Basic inheritance
      dog = T_inherit_Dog.new("Rex", "Labrador")
      puts dog.name       # Rex (inherited)
      puts dog.breed      # Labrador
      puts dog.speak      # Woof! (overridden)
      puts dog.describe   # Rex (inherited, calls name)

      cat = T_inherit_Cat.new("Whiskers")
      puts cat.name       # Whiskers (inherited)
      puts cat.speak      # Meow! (overridden)
      puts cat.describe   # Whiskers (inherited)
    RUBY

    _(result).must_answer <<~'OUT'
      Rex
      Labrador
      Woof!
      Rex
      Whiskers
      Meow!
      Whiskers
    OUT
  end

  it "inherited cmeth self returning local" do
    result = ze0(<<~'RUBY')
      # Inherited class method whose body holds a local typed by a
      # method that each subclass overrides. The local's C type
      # needs to specialize per-subclass.
      #
      # Pre-fix: scan_locals stored the result in @nd_scope_names
      # keyed by the shared AST body id; whichever subclass scanned
      # last won, leaving every other subclass with the wrong LV
      # C type. Surfaced in real-blog's `T_inherited_cmeth_self_returning_local_Comment.find` returning
      # `sp_Article *` (warning under -Wincompatible-pointer-types,
      # silent miscompile if T_inherited_cmeth_self_returning_local_Article / T_inherited_cmeth_self_returning_local_Comment struct layouts
      # diverge).
      #
      # Fix: per-(class, cmeth_idx) scope tables in
      # @cls_cmeth_scope_names / @cls_cmeth_scope_types preserve
      # each subclass's scan result. Codegen consumes the per-
      # subclass entry instead of the per-bid one.

      class T_inherited_cmeth_self_returning_local_Base
        def self.find(id)
          result = adapter_find(id)
          result
        end
      end

      class T_inherited_cmeth_self_returning_local_Article < T_inherited_cmeth_self_returning_local_Base
        attr_accessor :id, :title
        def self.adapter_find(id)
          a = T_inherited_cmeth_self_returning_local_Article.new
          a.id = id
          a.title = "art-#{id}"
          a
        end
      end

      class T_inherited_cmeth_self_returning_local_Comment < T_inherited_cmeth_self_returning_local_Base
        attr_accessor :id, :body
        def self.adapter_find(id)
          c = T_inherited_cmeth_self_returning_local_Comment.new
          c.id = id
          c.body = "comment-#{id}"
          c
        end
      end

      a = T_inherited_cmeth_self_returning_local_Article.find(7)
      puts a.title
      c = T_inherited_cmeth_self_returning_local_Comment.find(9)
      puts c.body
    RUBY

    _(result).must_answer "art-7\ncomment-9\n"
  end

  it "inherited cmethod subclass dispatch" do
    result = ze0(<<~'RUBY')
      # #523. Sibling to #516. When a subclass inherits a class method
      # whose body calls another class method (`self.last` calls bare
      # `all`), spinel correctly monomorphized the call (`sp_Sub_cls_all`
      # is invoked) but the surrounding inference of the call's result
      # type used the parent's signature -- the local slot for the
      # returned array was typed `sp_IntArray *` (from T_inherited_cmethod_subclass_dispatch_Base.all's empty
      # `[]` literal) while `sp_Sub_cls_all` returned `sp_PtrArray *`,
      # triggering an `incompatible pointer types` C warning and an
      # `int-from-pointer` error on the subsequent `[-1]` dispatch.
      #
      # Root cause: analyze's walk_and_cache wrote a per-AST-node-id
      # type cache, and inherited cmethod bodies share their AST node
      # ids across subclass copies. The first walker (typically the
      # defining class) populated the cache; later walkers' recomputes
      # under different @current_class_idx were short-circuited by the
      # cache hit at the top of infer_type.
      #
      # Fix (analyze): walk_and_cache invalidates the cache before
      # recompute so the second walker overwrites, and skip_cache is
      # extended to bare CallNodes that resolve to a sibling cmeth on
      # the current class. Fix (codegen): infer_type's CallNode arm now
      # mirrors analyze's @cls_cmeth_returns lookup for bare cmeth
      # calls so the cache-miss path picks up the subclass's override
      # at emit time.

      class T_inherited_cmethod_subclass_dispatch_Base
        def self.all
          []
        end

        def self.last
          records = all
          records.empty? ? nil : records[-1]
        end
      end

      class T_inherited_cmethod_subclass_dispatch_Sub < T_inherited_cmethod_subclass_dispatch_Base
        def self.all
          [Object.new]
        end
      end

      # T_inherited_cmethod_subclass_dispatch_Sub.last (inherited from T_inherited_cmethod_subclass_dispatch_Base) sees T_inherited_cmethod_subclass_dispatch_Sub.all's PtrArray return
      # type now, so `records.empty?` and `records[-1]` dispatch into
      # the PtrArray path instead of the IntArray path.
      r = T_inherited_cmethod_subclass_dispatch_Sub.last
      if r != nil
        puts "got object"
      else
        puts "nil"
      end
    RUBY

    _(result).must_answer "got object\n"
  end

  it "inherited method param widen" do
    result = ze0(<<~'RUBY')
      # Issue #286: a parent class's instance method param needs to widen
      # from subclass call sites too, not just from same-class call sites.
      # Previously scan_new_calls's bare-call branch only checked
      # `find_method_idx` (top-level methods); a `bar(arg)` inside a
      # subclass that resolves through inheritance to the parent's `bar`
      # would leave the parent's param frozen at its initial type and
      # fail to type-check at the call site.
      #
      # Fix: when the bare call is inside a class method body
      # (@current_class_idx >= 0), walk up the inheritance chain via
      # find_method_owner to locate the ancestor that defines the
      # method, then widen *that* class's @cls_meth_ptypes from the
      # call-site arg types — same shape the recv >= 0 branch already
      # uses for explicit-receiver calls.

      class T_inherited_method_param_widen_T
        def assert_eq(expected, actual)
          if expected == actual
            puts "ok"
          else
            puts "ng"
          end
        end
      end

      class T_inherited_method_param_widen_Article
        def initialize
          @id = 0
        end
        def write_str(s)
          @id = s   # widens @id to poly (#247)
        end
        def id
          @id
        end
      end

      class T_inherited_method_param_widen_T2 < T_inherited_method_param_widen_T
        def test_it
          a = T_inherited_method_param_widen_Article.new
          a.write_str("hi")
          # Bare call to inherited assert_eq, passing a poly value (a.id).
          # Without the fix, `T_inherited_method_param_widen_T#assert_eq`'s `actual` param stays at int
          # and the call site emits a type-mismatched store.
          assert_eq("hi", a.id)
        end
      end

      T_inherited_method_param_widen_T2.new.test_it
    RUBY

    _(result).must_answer "ok\n"
  end

  it "init locals" do
    result = ze0(<<~'RUBY')
      # Regression test for issue #17: locals inside `initialize` were not
      # declared in the generated `_new` constructor (and `_initialize`
      # helper for value-type classes), so cc rejected the body with
      # `'lv_x' undeclared`.

      class T_init_locals_Test
        attr_reader :a
        def initialize
          x = 1
          @a = x
        end
      end

      class T_init_locals_Sum
        attr_reader :total
        def initialize(n)
          s = 0
          i = 0
          while i < n
            s = s + i
            i = i + 1
          end
          @total = s
        end
      end

      class T_init_locals_Compound
        attr_reader :result
        def initialize(x, y)
          a = x * 2
          b = y + 1
          @result = a + b
        end
      end

      t = T_init_locals_Test.new
      puts t.a              # 1

      s = T_init_locals_Sum.new(5)
      puts s.total          # 10

      c = T_init_locals_Compound.new(3, 4)
      puts c.result         # 11
    RUBY

    _(result).must_answer <<~'OUT'
      1
      10
      11
    OUT
  end

  it "initialize param poly call sites" do
    result = ze0(<<~'RUBY')
      # Regression test: when an `initialize` parameter is widened to "poly"
      # by conflicting Foo.new(...) call sites, the param type must stay poly
      # end-to-end. The extended merge logic explicitly returns existing_pt
      # when it is "poly" so that body inference (which can return a narrower
      # concrete type via super-call propagation or via the @ivar's type when
      # the ivar was seeded by a literal write elsewhere) does not silently
      # narrow the param back.

      class T_initialize_param_poly_call_sites_Box
        def initialize(v)
          @v = v
        end

        def show
          puts @v
        end
      end

      T_initialize_param_poly_call_sites_Box.new("hello").show
      T_initialize_param_poly_call_sites_Box.new(42).show
    RUBY

    _(result).must_answer "hello\n42\n"
  end

  it "initialize param through call" do
    result = ze0(<<~'RUBY')
      # Regression test: an initialize parameter that is never written to an
      # ivar must still pick up its type from `Foo.new(...)` call sites.
      #
      # Before the fix, body inference (which returns "int" when no `@x = x`
      # write is found) unconditionally overwrote the call-site-inferred type,
      # silently miscompiling code where the parameter was a string, array, or
      # any other concrete type.

      class T_initialize_param_through_call_Greeter
        def initialize(name)
          puts name
        end
      end

      T_initialize_param_through_call_Greeter.new("hello")
    RUBY

    _(result).must_answer "hello\n"
  end

  it "initialize void wrapper gc save" do
    result = ze0(<<~'RUBY')
      # Issue #314 follow-up: the synthesized void
      # `sp_<C>_initialize` super-chain wrapper inherits @in_gc_scope
      # from the prior `sp_<C>_new` constructor emit. When that left
      # @in_gc_scope at 1, declare_method_locals' `@in_gc_scope == 0`
      # guard skipped emitting `SP_GC_SAVE()` at the top of the void
      # wrapper. But the body's bare `return` (e.g. `return if x.nil?`)
      # still emitted `SP_GC_RESTORE()` — which references `_gc_saved`
      # that the missing SP_GC_SAVE never declared.
      #
      # Fix: reset @in_gc_scope to 0 when entering the void wrapper so
      # declare_method_locals decides cleanly.
      #
      # The void wrapper is only emitted when a subclass calls `super`,
      # so this reproducer needs the inheritance shape. The body uses
      # a String pointer local (which forces declare_method_locals'
      # has_gc_locals branch to want SP_GC_SAVE) and an early bare
      # `return` (which forces compile_return_stmt to emit
      # SP_GC_RESTORE).

      class T_initialize_void_wrapper_gc_save_Base
        attr_reader :extra
        def initialize(skip)
          note = "base"
          if skip
            return        # bare `return` — emits SP_GC_RESTORE()
          end
          @extra = note
        end
      end

      class T_initialize_void_wrapper_gc_save_Child < T_initialize_void_wrapper_gc_save_Base
        def initialize
          super(false)    # calls sp_Base_initialize (the void wrapper)
        end
      end

      # Push into a [T_initialize_void_wrapper_gc_save_Child] array so neither class is value-typed —
      # the void wrapper is only emitted for heap classes.
      all = [T_initialize_void_wrapper_gc_save_Child.new, T_initialize_void_wrapper_gc_save_Child.new]
      puts all.length          # 2
    RUBY

    _(result).must_answer "2\n"
  end

  it "intarray slice assign from intarray ptr array first" do
    result = ze0(<<~'RUBY')
      # `arr[start, len] = src` slice-assign where `src` came from
      # `<X>_ptr_array.first` (or `.last`). Spinel's compile_bracket_assign
      # already had a same-prefix slice-assign path for `int_array[i, n] =
      # int_array`, but `infer_type` for `.first` / `.last` fell through
      # to "int" on a `_ptr_array` receiver, so the slice-assign branch's
      # `infer_type(arg_ids[2]) == "int_array"` test missed and the call
      # silently lowered to `arr[start] = len` (using arg_ids[1] as the
      # value, dropping arg_ids[2] entirely).

      class T_intarray_slice_assign_from_intarray_ptr_array_first_C
        def initialize
          buf = (0...32).to_a
          @banks = (0...2).map { buf.slice!(0, 8) }
          @ref = [0] * 24
          @ref[5, 8] = @banks.first
          @ref[15, 8] = @banks.last
        end

        def show
          @ref.each { |x| print x, " " }
          puts
        end
      end

      T_intarray_slice_assign_from_intarray_ptr_array_first_C.new.show
    RUBY

    _(result).must_answer <<~'OUT'
      0 0 0 0 0 0 1 2 3 4 5 6 7 0 0 8 9 10 11 12 13 14 15 0 
    OUT
  end

  it "introspect" do
    result = ze0(<<~'RUBY')
      # Test respond_to?, is_a?, class name, to_s

      class T_introspect_Animal
        def initialize(name)
          @name = name
        end
        def name; @name; end
        def speak; "..."; end
      end

      class T_introspect_Dog < T_introspect_Animal
        def speak; "Woof!"; end
        def fetch; "ball"; end
      end

      d = T_introspect_Dog.new("Rex")

      # is_a?
      puts d.is_a?(T_introspect_Dog)      # true
      puts d.is_a?(T_introspect_Animal)   # true

      # respond_to?
      puts d.respond_to?(:speak)   # true
      puts d.respond_to?(:fetch)   # true
      puts d.respond_to?(:fly)     # false

      # nil?
      puts nil.nil?          # true
      puts d.nil?            # false
      puts 0.nil?            # false

      # Integer predicates
      puts 0.zero?           # true
      puts 5.positive?       # true
      puts (-3).negative?    # true
    RUBY

    _(result).must_answer <<~'OUT'
      true
      true
      true
      true
      false
      true
      false
      false
      true
      true
      true
    OUT
  end

  it "isa hash narrow typed param" do
    result = ze0(<<~'RUBY')
      # `is_a?(Hash)`-narrowed poly value passed to a typed-Hash param
      # slot should unbox via `(sp_<Variant> *).v.p`, matching the
      # obj-narrow arm at #448. Pre-fix compile_typed_call_args's
      # dispatch only routed `poly`/`string`/array params (and
      # obj-typed params when arg was poly) through
      # compile_expr_for_expected_type; hash-typed params fell through
      # to `compile_expr` and emitted the bare sp_RbVal, failing the
      # C compile with "passing 'sp_RbVal' to parameter of incompatible
      # type 'sp_StrStrHash *'". Issue #631.

      class T_isa_hash_narrow_typed_param_Bag
        def render(hash)
          hash["k"]
        end

        def visit(table)
          seed = { "k" => "v" }
          render(seed)

          val = table["inner"]
          if val.is_a?(Hash)
            render(val)
          else
            "default"
          end
        end
      end

      b = T_isa_hash_narrow_typed_param_Bag.new
      puts b.visit({ "inner" => { "k" => "tokyo" } })
    RUBY

    _(result).must_answer "tokyo\n"
  end

  it "issue176 empty hash default" do
    result = ze0(<<~'RUBY')
      # Issue #176: empty-Hash default parameter `def m(h = {})` used to
      # silently corrupt the caller-supplied Hash because unify_call_types
      # widened the param type to "poly" and the poly dispatch tree had no
      # arm for SymIntHash/StrIntHash. Hash variants now escalate the
      # str_int_hash empty default to the call-site type, mirroring the
      # int_array → typed-array escalation.

      class T_issue176_empty_hash_default_A
        def initialize(attrs = {})
          @x = attrs[:x]
        end
        def x; @x; end
      end

      puts T_issue176_empty_hash_default_A.new({x: 42}).x

      class T_issue176_empty_hash_default_B
        def initialize(attrs = {})
          @name = attrs[:name]
        end
        def name; @name; end
      end

      puts T_issue176_empty_hash_default_B.new({name: "alice"}).name

      # String-keyed hash also works.
      class T_issue176_empty_hash_default_C
        def initialize(attrs = {})
          @v = attrs["v"]
        end
        def v; @v; end
      end

      puts T_issue176_empty_hash_default_C.new({"v" => 7}).v
    RUBY

    _(result).must_answer <<~'OUT'
      42
      alice
      7
    OUT
  end

  it "issue204 user find fetch" do
    result = ze0(<<~'RUBY')
      # Issue #204: user-defined `find` / `fetch` were overridden by the
      # method-name dispatch's "int" fallback even when the receiver
      # wasn't a built-in collection. The body's actual return type
      # (string here) lost; the call site mistyped the result as int.

      # Class method form (canonical ActiveRecord finder shape).
      class T_issue204_user_find_fetch_Bag
        def self.find(id); "row-#{id}"; end
        def self.fetch(id); "fetched-#{id}"; end
      end
      puts T_issue204_user_find_fetch_Bag.find(42)        # row-42
      puts T_issue204_user_find_fetch_Bag.fetch(99)       # fetched-99

      # Instance method form on a hash-wrapping class.
      class T_issue204_user_find_fetch_C
        def initialize(h); @h = h; end
        def find(key); @h[key.to_sym]; end
        def fetch(key); @h[key.to_sym]; end
      end
      c = T_issue204_user_find_fetch_C.new({a: "alpha", b: "beta"})
      puts c.find(:a)          # alpha
      puts c.fetch(:b)         # beta

      # Built-in collection dispatch still works (regression check).
      puts ["x", "y", "z"].find { |v| v == "y" }   # y
    RUBY

    _(result).must_answer <<~'OUT'
      row-42
      fetched-99
      alpha
      beta
      y
    OUT
  end

  it "issue207 factory pattern" do
    result = ze0(<<~'RUBY')
      # Issue #207: factory class method (`def self.from_raw`) using
      # implicit `new`, calling a setter on the new instance whose value
      # came from a poly-hash-returning fetch. Several composing gaps:
      #
      #   1. Bare `new` inside a `def self.<m>` body must resolve to
      #      <CurrentClass>.new (returning obj_<CurrentClass>).
      #   2. The class method's parameter type must widen from the
      #      class-constant call site (`T_issue207_factory_pattern_T.from_raw(p)` → params: obj_P).
      #   3. The setter's poly arg must widen the receiving ivar's slot
      #      type (sp_RbVal field, not mrb_int).
      #   4. The fetch's nil-default param must widen from the call-site
      #      string default ("" → string?).

      class T_issue207_factory_pattern_P
        def initialize(h)
          @h = h
        end
        def fetch(key, default = nil)
          return @h[key] if @h.key?(key)
          default
        end
      end

      class T_issue207_factory_pattern_T
        attr_accessor :title
        def self.from_raw(params)
          instance = new
          instance.title = params.fetch(:title, "")
          instance
        end
      end

      p = T_issue207_factory_pattern_P.new({title: "hello", count: 42})
      t = T_issue207_factory_pattern_T.from_raw(p)
      puts t.title
    RUBY

    _(result).must_answer "hello\n"
  end

  it "issue207 full repro" do
    result = ze0(<<~'RUBY')
      # Issue #207: full Sam Ruby repro — Rails-style ActiveRecord
      # T_issue207_full_repro_Parameters wrapper with symbolize_keys recursion plus a typed
      # Params factory using fetch.
      #
      # This combines several fixes that had to land together:
      #
      # - Implicit `new` inside `def self.<m>` resolves to the enclosing
      #   class's constructor (#207 partial fix).
      # - cls method body return inference picks up locals (#207 partial
      #   fix).
      # - attr_writer call inside cls method body widens the ivar slot.
      # - Class-constant call sites (T.from_raw(p)) widen the cls method's
      #   parameter types.
      # - Static is_a? / kind_of? on a known-concrete-type receiver
      #   eliminates the unreachable arm so the dead recursion call
      #   doesn't land in C and trip the type checker.

      class T_issue207_full_repro_Parameters
        def initialize(hash = {})
          @hash = symbolize_keys(hash)
        end

        def symbolize_keys(input)
          out = {}
          input.each do |k, v|
            sym = k.is_a?(Symbol) ? k : k.to_s.to_sym
            out[sym] = v.is_a?(Hash) ? symbolize_keys(v) : v
          end
          out
        end

        def fetch(key, default = nil)
          sym = key.to_sym
          return @hash[sym] if @hash.key?(sym)
          default
        end
      end

      class T_issue207_full_repro_ArticleParams
        def title; @title; end
        def title=(value); @title = value; end

        def self.from_raw(params)
          instance = new
          instance.title = params.fetch(:title, "")
          instance
        end
      end

      p = T_issue207_full_repro_Parameters.new({title: "hello"})
      ap = T_issue207_full_repro_ArticleParams.from_raw(p)
      puts ap.title
    RUBY

    _(result).must_answer "hello\n"
  end

  it "issue208 inherited class method" do
    result = ze0(<<~'RUBY')
      # Issue #208: a class method (`def self.<name>`) defined on the
      # parent class must dispatch when called via the subclass. Spinel
      # previously emitted "cannot resolve call to '<method>' on
      # class_<Subclass>" and substituted 0 because cls_cmethod lookup
      # only walked the immediate class.

      class T_issue208_inherited_class_method_Base
        def self.all
          [42, 1, 7]
        end
      end

      # Single level
      class T_issue208_inherited_class_method_Leaf < T_issue208_inherited_class_method_Base; end
      puts T_issue208_inherited_class_method_Leaf.all.size                   # 3

      # Multi level
      class T_issue208_inherited_class_method_Mid < T_issue208_inherited_class_method_Base; end
      class T_issue208_inherited_class_method_Deep < T_issue208_inherited_class_method_Mid; end
      puts T_issue208_inherited_class_method_Mid.all.size                    # 3
      puts T_issue208_inherited_class_method_Deep.all.size                   # 3

      # Direct call on the defining class still works
      puts T_issue208_inherited_class_method_Base.all.size                   # 3
    RUBY

    _(result).must_answer <<~'OUT'
      3
      3
      3
      3
    OUT
  end

  it "issue219 aref chain" do
    result = ze0(<<~'RUBY')
      # Issue #219: chained calls on a user-defined `[]` operator's
      # result silently lost their coercion (`.to_i` / `.length`) because
      # infer_type's `mname == "[]"` branch handled built-in collection
      # receivers but fell through to "int" for obj receivers.
      # `bag[:id].to_i` then routed through compile_int_method_expr's
      # `to_i` (which is identity) and the underlying `const char *`
      # leaked through.

      class T_issue219_aref_chain_Bag
        def initialize(h); @h = h; end
        def [](k); @h[k.to_sym]; end
      end

      bag = T_issue219_aref_chain_Bag.new({id: "42"})

      # .to_i: infers as int via String#to_i
      puts bag[:id].to_i              # 42
      puts bag[:id].to_i + 1          # 43

      # .length: routes through String#length
      puts bag[:id].length            # 2

      # Chained into a method expecting mrb_int
      class T_issue219_aref_chain_M
        def self.find(id); id + 1; end
      end
      puts T_issue219_aref_chain_M.find(bag[:id].to_i)      # 43

      # Integer-valued bag — .to_s works the other direction (already
      # worked before the fix; pinning regression).
      class T_issue219_aref_chain_IntBag
        def initialize(h); @h = h; end
        def [](k); @h[k]; end
      end
      ib = T_issue219_aref_chain_IntBag.new({n: 42})
      puts ib[:n].to_s                # "42"
    RUBY

    _(result).must_answer <<~'OUT'
      42
      43
      2
      43
      42
    OUT
  end

  it "issue235 chain tail widening" do
    result = ze0(<<~'RUBY')
      # Issue #235 follow-up to #234: chained `@a = @b = expr` only widened
      # the chain *head*. The tail (and intermediate participants in
      # longer chains) relied on scan_ivars's dual-definite-literal gate,
      # which fires for literal RHS but not for CallNode/expression RHS.
      # A `@a = @b = make_int` with `@a`/`@b` previously string-typed left
      # `@b`'s slot at `const char *` while compile_chained_ivar_writes
      # emitted `iv_b = _t1;` with `_t1 : mrb_int`. Same T_issue235_chain_tail_widening_C error shape
      # #234 was fixing for the head, just on the tail.

      class T_issue235_chain_tail_widening_C
        def initialize
          @a = "hello"
          @b = "world"
        end

        def make_int
          42
        end

        # CallNode RHS — bypasses scan_ivars's literal-gate widening so
        # the chain-drill path is the only thing that can widen `@b`.
        def reset_call
          @a = @b = make_int
        end

        # 3-chain with CallNode RHS — every intermediate must widen.
        def reset_three(c)
          @a = @b = @c = c.length
        end

        def show
          puts @a
          puts @b
        end
      end

      c = T_issue235_chain_tail_widening_C.new
      c.reset_call
      c.show                  # 42 / 42

      c2 = T_issue235_chain_tail_widening_C.new
      c2.reset_three("ab")
      c2.show                 # 2 / 2

      # 3-chain that adds an `@c` slot to the picture too. After
      # reset_three sets @c, calling show wouldn't read it (no accessor),
      # but the struct emit needs to type-check.
      puts "ok"
    RUBY

    _(result).must_answer <<~'OUT'
      42
      42
      2
      2
      ok
    OUT
  end

  it "ivar and write basic" do
    result = ze0(<<~'RUBY')
      class T_ivar_and_write_basic_T
        def initialize
          @ready = false
          @count = 0
        end

        def maybe_inc
          @ready &&= step
        end

        def arm
          @ready = true
        end

        def step
          @count += 1
          true
        end

        def state
          "ready=#{@ready} count=#{@count}"
        end
      end

      t = T_ivar_and_write_basic_T.new
      puts t.state
      t.maybe_inc
      puts t.state
      t.arm
      puts t.state
      t.maybe_inc
      puts t.state
      t.maybe_inc
      puts t.state
    RUBY

    _(result).must_answer <<~'OUT'
      ready=false count=0
      ready=false count=0
      ready=true count=0
      ready=true count=1
      ready=true count=2
    OUT
  end

  it "ivar c keyword" do
    result = ze0(<<~'RUBY')
      # Test: ivar naming remains safe for C keywords and iv_ prefix collisions.

      class T_ivar_c_keyword_KeywordIvar
        def initialize
          @if = 40
          @iv_if = 1
        end

        def value
          @if + @iv_if + 1
        end
      end

      puts T_ivar_c_keyword_KeywordIvar.new.value
    RUBY

    _(result).must_answer "42\n"
  end

  it "ivar float array" do
    result = ze0(<<~'RUBY')
      # Regression: instance variables initialized via Array.new(n, FILL) must be
      # typed by inspecting the fill argument, not always returned as "int_array".
      #
      # infer_ivar_init_type's CallNode/"new" branch used to unconditionally return
      # "int_array" for Array.new(...). That mistyped class fields as the
      # containing class's pointer; pointer-type fills additionally lost their GC
      # scan function, which would let live elements be swept.
      #
      # We now check the fill type and use the appropriate typed array container
      # (FloatArray for float fills, StrArray for string, sym_array (IntArray
      # internally) for symbol, PtrArray for object/pointer fills).
      #
      # Use float values whose fractional part is non-zero so Spinel's float-puts
      # matches CRuby's.

      class T_ivar_float_array_Box
        attr_accessor :nums
        def initialize
          @nums = Array.new(3, 0.5)
        end
      end

      class T_ivar_float_array_SymHolder
        attr_accessor :tags
        def initialize
          @tags = Array.new(2, :alpha)
        end
      end

      class T_ivar_float_array_Marker
        attr_accessor :id
        def initialize(id)
          @id = id
        end
      end

      class T_ivar_float_array_ObjHolder
        attr_accessor :marks
        def initialize
          @marks = Array.new(3, T_ivar_float_array_Marker.new(42))
        end
      end

      b = T_ivar_float_array_Box.new
      puts b.nums[0]      # 0.5
      puts b.nums[1]      # 0.5
      puts b.nums[2]      # 0.5
      puts b.nums.length  # 3

      s = T_ivar_float_array_SymHolder.new
      puts s.tags[0]      # alpha
      puts s.tags[1]      # alpha
      puts s.tags.length  # 2

      m = T_ivar_float_array_ObjHolder.new
      puts m.marks[0].id  # 42
      puts m.marks[1].id  # 42  (Array.new(n, obj) shares the same obj)
      puts m.marks[2].id  # 42
      puts m.marks.length # 3
    RUBY

    _(result).must_answer <<~'OUT'
      0.5
      0.5
      0.5
      3
      alpha
      alpha
      2
      42
      42
      42
      3
    OUT
  end

  it "ivar hash aset param widen" do
    result = ze0(<<~'RUBY')
      # #488. A class method writing a param into a typed ivar hash —
      # `@data[key] = value` where @data is pinned to e.g. str_str_hash
      # by another method — left the writer's `key` and `value` params
      # at the `mrb_int` default. The C emit then passed mrb_int into
      # the const char * key / value slots and failed -Wint-conversion.
      # Sibling to #482's nil-default + Hash-receiver back-propagation
      # pass; this one covers the @hash-write side of the same
      # back-propagation gap.

      class T_ivar_hash_aset_param_widen_Bag
        def initialize
          @data = {}
        end

        # Pins @data to str_str_hash from a typed source.
        def populate(source)
          source.each do |k, v|
            @data[k] = v
          end
        end

        # No caller; without back-propagation `key` and `value` stayed
        # at mrb_int and the body's sp_StrStrHash_set fired
        # -Wint-conversion.
        def []=(key, value)
          @data[key] = value
        end

        def fetch(k)
          @data[k]
        end
      end

      b = T_ivar_hash_aset_param_widen_Bag.new
      b.populate({ "x" => "hello" })
      puts "ok"
      puts b.fetch("x")
    RUBY

    _(result).must_answer "ok\nhello\n"
  end

  it "ivar lazy init push via getter" do
    result = ze0(<<~'RUBY')
      # Issue #430. `@ivar = [] if @ivar.nil?` plus push-through-getter:
      # the ivar stayed inferred as IntArray (from the empty `[]`
      # literal) even when pushes through a getter method handed in
      # string values. sp_IntArray_push then took the string as a
      # mrb_int -- C compile error.
      #
      # Fix: scan_writer_calls now also matches the bare-call shape
      # `<getter>(*args) << v` / `<getter>.push(v)` by resolving
      # through method_returns_ivar_in_class -- if the getter method's
      # body returns a bare `@<iname>` as its last expression, the
      # push observation lands on `@<iname>` directly. The empty-array
      # default promotes the same way it does for direct `@x.push`
      # / `@x << v` writes.
      #
      # Coverage:
      #   - The canonical Rails-style `ActiveRecord::Base#errors`
      #     shape: lazy-init via nil guard, push via a sibling
      #     `add_error` method that calls `errors << "..."`.
      #   - Same shape with `self.<getter>` (explicit self-recv) so
      #     both the bare and self-prefixed call forms route to the
      #     ivar.

      class T_ivar_lazy_init_push_via_getter_Errors
        def list
          @list = [] if @list.nil?
          @list
        end

        def add(msg)
          list << msg
        end
      end

      class T_ivar_lazy_init_push_via_getter_ErrorsSelf
        def list
          @list = [] if @list.nil?
          @list
        end

        def add(msg)
          self.list << msg
        end
      end

      e = T_ivar_lazy_init_push_via_getter_Errors.new
      e.add("a")
      e.add("b")
      puts e.list.length
      puts e.list[0]
      puts e.list[1]

      es = T_ivar_lazy_init_push_via_getter_ErrorsSelf.new
      es.add("x")
      puts es.list[0]
    RUBY

    _(result).must_answer <<~'OUT'
      2
      a
      b
      x
    OUT
  end

  it "ivar op assign bitwise and shift" do
    result = ze0(<<~'RUBY')
      # Statement-form `@x OP= v` for the bitwise / shift / multiplicative
      # operators. The pre-fix codegen only handled `+=` and `-=`; every
      # other op-assign was silently dropped, so `@a &= 0x80` left @a
      # untouched. Walks all the operators that map onto T_ivar_op_assign_bitwise_and_shift_C `OP=` directly.

      class T_ivar_op_assign_bitwise_and_shift_C
        attr_reader :a
        def initialize; @a = 0xff; end
        def m_amp; @a &= 0x80; end
        def m_or;  @a |= 0x01; end
        def m_xor; @a ^= 0xff; end
        def m_lsh; @a <<= 1; end
        def m_rsh; @a >>= 1; end
        def m_mul; @a *= 2; end
      end

      c = T_ivar_op_assign_bitwise_and_shift_C.new; c.m_amp; puts "amp: #{c.a}"
      c = T_ivar_op_assign_bitwise_and_shift_C.new; c.m_or;  puts "or: #{c.a}"
      c = T_ivar_op_assign_bitwise_and_shift_C.new; c.m_xor; puts "xor: #{c.a}"
      c = T_ivar_op_assign_bitwise_and_shift_C.new; c.m_lsh; puts "lsh: #{c.a}"
      c = T_ivar_op_assign_bitwise_and_shift_C.new; c.m_rsh; puts "rsh: #{c.a}"
      c = T_ivar_op_assign_bitwise_and_shift_C.new; c.m_mul; puts "mul: #{c.a}"
    RUBY

    _(result).must_answer <<~'OUT'
      amp: 128
      or: 255
      xor: 0
      lsh: 510
      rsh: 127
      mul: 510
    OUT
  end

  it "ivar or write basic" do
    result = ze0(<<~'RUBY')
      class T_ivar_or_write_basic_T
        def initialize
          @str = nil
          @hits = 0
          @marker = "init"
        end

        def cache
          @str ||= compute
        end

        def compute
          @hits += 1
          "hello"
        end

        def get
          @str
        end

        def hits
          @hits
        end
      end

      t = T_ivar_or_write_basic_T.new
      puts t.get.nil? ? "nil-before" : "not-nil-before"
      puts t.cache
      puts t.get
      puts t.cache
      puts t.get
      puts "hits=#{t.hits}"

      class T_ivar_or_write_basic_U
        def initialize
          @v = nil
          @hits = 0
          @log = []
        end

        def value
          @v ||= 42
        end

        def hits
          @hits
        end

        def log_size
          @log.size
        end
      end

      u = T_ivar_or_write_basic_U.new
      puts u.value
      puts u.value
      puts u.value
    RUBY

    _(result).must_answer <<~'OUT'
      nil-before
      hello
      hello
      hello
      hello
      hits=1
      42
      42
      42
    OUT
  end

  it "ivar same shape string new no widen" do
    result = ze0(<<~'RUBY')
      # Two `String.new` writes to the same ivar should keep the slot at
      # `sp_String *`, not widen to `sp_RbVal`. Pre-fix scan_ivars used
      # `infer_ivar_init_type` which returned `obj_String` for the first
      # write; later writer-scan saw `mutable_str` via `infer_type` for the
      # second; update_ivar_type took the disagreement as a real conflict
      # and widened to poly. Issue #629.

      class T_ivar_same_shape_string_new_no_widen_T
        def initialize
          @body = String.new
        end

        def reset
          @body = String.new
        end

        def append(s)
          @body << s
        end

        def body
          @body
        end
      end

      t = T_ivar_same_shape_string_new_no_widen_T.new
      t.append("hello")
      puts t.body
      t.reset
      t.append("world")
      puts t.body
    RUBY

    _(result).must_answer "hello\nworld\n"
  end

  it "ivar writer heterogeneity" do
    result = ze0(<<~'RUBY')
      # Issue #247: when two writers in different methods of the same class
      # disagree on the value type, spinel used to narrow the slot to
      # whichever writer's update_ivar_type call ran last — and the loser's
      # emit site silently miscompiled. Here writer 1 in initialize assigns
      # an int (via SymIntHash#[]) and writer 2 in write_any assigns a
      # string param; the slot must widen to poly so both store cleanly.

      class T_ivar_writer_heterogeneity_C
        def initialize(h)
          @id = h[:id]
        end

        def id; @id; end

        def write_any(value)
          @id = value
        end
      end

      c = T_ivar_writer_heterogeneity_C.new({id: 42})
      c.write_any("string")
      puts c.id

      # Ensure the int-writer side still works when we don't re-write to a
      # different type — the slot stays as observed.
      class T_ivar_writer_heterogeneity_D
        def initialize(h)
          @v = h[:v]
        end
        def v; @v; end
      end

      d = T_ivar_writer_heterogeneity_D.new({v: 7})
      puts d.v
    RUBY

    _(result).must_answer "string\n7\n"
  end

  it "kernel module function call" do
    result = ze0(<<~'RUBY')
      # Issue #428. `Kernel.<m>` cmeth-style calls (the disambiguator
      # users reach for when a `def self.<m>` shadows a Kernel
      # module-function) emitted `0` instead of dispatching. Bare
      # `<m>(...)` worked but couldn't be used inside a method body
      # that shadowed the name -- which is exactly when callers
      # write `Kernel.<m>`.
      #
      # Fix: in compile_object_method_expr's recv_type == "class"
      # arm, when the recv AST is the ConstantReadNode "Kernel",
      # route through compile_no_recv_call_expr. The bare-dispatch
      # path already handles every Kernel module-function the
      # runtime ships (sleep / puts / print / rand / etc.), so the
      # Kernel-prefixed form gets the same shape uniformly.

      class T_kernel_module_function_call_Sched
        def self.nap(seconds)
          # Kernel-prefixed to disambiguate from a hypothetical
          # def self.sleep on the same class.
          Kernel.sleep(seconds)
          0
        end
      end

      T_kernel_module_function_call_Sched.nap(0)
      puts "ok"
    RUBY

    _(result).must_answer "ok\n"
  end

  it "known constants" do
    result = ze0(<<~'RUBY')
      # Issue #75: the codegen now rejects an unknown constant reference
      # with a "uninitialized constant <Name>" error instead of either
      # leaking the bare identifier into the C output (`p Foo`) or
      # silently lowering to `0` (`p Foo.bar`). This regression test pins
      # the legitimate constant references that look superficially like
      # the failing cases but resolve to known names — the fix shouldn't
      # reject any of them.

      # User-defined class — `find_class_idx` resolves it.
      class T_known_constants_Box
        def initialize(v); @v = v; end
        attr_reader :v
      end

      puts T_known_constants_Box.new(7).v          # 7

      # User-defined constant.
      N = 42
      puts N                     # 42

      # Built-in module-like receiver (Math).
      puts Math.sqrt(16).to_i    # 4

      # ARGV / STDOUT pass through.
      puts ARGV.length           # 0
    RUBY

    _(result).must_answer <<~'OUT'
      7
      42
      4
      0
    OUT
  end

  it "kwarg default empty hash kind" do
    result = ze0(<<~'RUBY')
      # #486. Class method with a kwarg `set_cookies: {}` whose
      # param is body-widened (via other call sites passing a
      # sym-keyed hash) to sp_SymStrHash *. A bare call site that
      # omits the kwarg synthesized the default at the call site as
      # the generic sp_StrIntHash_new(), tripping
      # -Wincompatible-pointer-types because the callee expects
      # sp_SymStrHash *. Fix: the kwarg-default emit at the class-
      # method dispatch site routes through empty_hash_coerce so an
      # empty `{}` literal default takes on the param's declared
      # hash variant.

      class T_kwarg_default_empty_hash_kind_W
        def self.write(io, status, set_cookies: {})
          n = 0
          set_cookies.each do |name, val|
            n = n + 1
          end
          n
        end
      end

      class T_kwarg_default_empty_hash_kind_Use
        def self.kick
          cookies = { flash_notice: "Hi" }
          T_kwarg_default_empty_hash_kind_W.write(1, 200, set_cookies: cookies)
        end
      end

      puts T_kwarg_default_empty_hash_kind_W.write(1, 404).to_s
    RUBY

    _(result).must_answer "0\n"
  end

  it "kwargs into default hash param" do
    result = ze0(<<~'RUBY')
      # When a method's only positional has a default hash literal
      # (`attrs = {}`), call sites that pass kwargs whose names DON'T
      # match the param name should bundle the kwargs into that hash
      # slot. CRuby auto-folds trailing unmatched kwargs into a hash
      # positional; spinel previously dropped them silently because:
      #  - The analyzer fixpoint left the param typed `str_int_hash`
      #    (from the literal `{}` default) and never widened despite
      #    the call site carrying mixed-type values.
      #  - The codegen `compile_typed_call_args` / class-method dispatch
      #    arm filled the unmatched slot with the literal default
      #    (`sp_StrIntHash_new()` / `sp_StrPolyHash_new()`), so the
      #    callee saw an empty hash and constructed all-default values.
      #
      # Surfaced by Sam Ruby's roundhouse `comment_test.rb`
      # `test_belongs_to_article_association` (issue #572 follow-up):
      # `Comment.create(article_id: article.id, ...)` against
      # `def self.create(attrs = {})` had the kwargs dropped, so the
      # created Comment's article_id stayed 0 and the assertion
      # `article.id != comment.article_id` raised.

      class T_kwargs_into_default_hash_param_Bag
        def self.create(attrs = {})
          new(attrs)
        end
        def initialize(attrs = {})
          @id = attrs[:id] || 0
          @name = attrs[:name] || "(none)"
          @count = attrs.length
        end
        attr_reader :id, :name, :count
      end

      # Class method form: `.create(kw: val, ...)`.
      b1 = T_kwargs_into_default_hash_param_Bag.create(id: 7, name: "alpha")
      puts b1.id     # 7
      puts b1.name   # alpha
      puts b1.count  # 2

      # Instance constructor form: `.new(kw: val, ...)` with default
      # hash param. Without the analyzer widening, sp_Bag_new(0)
      # segfaulted on the NULL hash. Issue #530 sibling.
      b2 = T_kwargs_into_default_hash_param_Bag.new(id: 42, name: "beta")
      puts b2.id     # 42
      puts b2.name   # beta
      puts b2.count  # 2

      # Empty call: defaults still kick in.
      b3 = T_kwargs_into_default_hash_param_Bag.create
      puts b3.id     # 0
      puts b3.name   # (none)
      puts b3.count  # 0

      # Mixed kwarg types -- string + int -- exercise the str_poly_hash
      # poly value path.
      b4 = T_kwargs_into_default_hash_param_Bag.create(id: 99, name: "gamma")
      puts b4.id     # 99
      puts b4.name   # gamma
    RUBY

    _(result).must_answer <<~'OUT'
      7
      alpha
      2
      42
      beta
      2
      0
      (none)
      0
      99
      gamma
    OUT
  end

  it "alias method" do
    result = ze0(<<~'RUBY')
      # AliasMethodNode -- `alias greet hello` inside a class body.
      #
      # CRuby snapshots the method at alias time -- if `hello` is later
      # redefined, `greet` still calls the original. In Spinel's AOT model
      # methods are static C functions; we register a compile-time
      # synonym so dispatch on `.greet` routes to the same C function as
      # `.hello`. Out of scope: alias inside a method body (CRuby allows
      # but the semantics differ); alias of an inherited method.

      class T_alias_method_Greeter
        def hello = "hi from hello"
        alias greet hello
      end

      g = T_alias_method_Greeter.new
      puts g.hello   # hi from hello
      puts g.greet   # hi from hello

      # Two aliases of the same method.
      class T_alias_method_Counter
        def value = 42
        alias get value
        alias read value
      end
      c = T_alias_method_Counter.new
      puts c.value   # 42
      puts c.get     # 42
      puts c.read    # 42
    RUBY

    _(result).must_answer <<~'OUT'
      hi from hello
      hi from hello
      42
      42
      42
    OUT
  end

  it "and node poly operand" do
    result = ze0(<<~'RUBY')
      # `a && b` codegen used to lower to raw C `a && b` regardless of
      # operand type. When either operand is `sp_RbVal` (poly), C rejects
      # `&&` between a struct and an int. Wrap poly operands with
      # `sp_poly_truthy`.

      class T_and_node_poly_operand_Holder
        def initialize
          @poly = "x"   # string first…
          @poly = 42    # …then int — slot widens to poly
          @counter = 0
        end

        attr_reader :poly, :counter

        def chain
          if @poly && @counter == 0
            @counter = 1
          end
          @counter
        end
      end

      h = T_and_node_poly_operand_Holder.new
      puts h.chain    # 1
    RUBY

    _(result).must_answer "1\n"
  end

  it "array 3d nested" do
    result = ze0(<<~'RUBY')
      # Deep-nested array literals (3D and beyond). Spinel doesn't
      # have a typed `<X>_ptr_array_ptr_array` slot — the second-level
      # `[[1,2,3],[4,5,6]]` infers as `int_array_ptr_array` and the
      # outer `[[[...]],[[...]]]` would naively box each element via
      # `sp_box_ptr_array`, which erases the elem-type info and
      # leaves the dispatch returning an unknown obj at the next `[]`
      # read.
      #
      # Fix: when an array literal element is itself a typed
      # ptr_array (or already poly_array) and the outer is
      # poly_array, recompile the inner literal as poly_array so
      # every level boxes via `sp_box_poly_array` / `sp_box_int_array`
      # / etc. — the cls_id chain stays tagged and the poly-builtin
      # dispatch recurses correctly through `arr[i][j][k]...`.
      #
      # The recursion in `compile_array_literal_as_poly` makes the
      # fix dimension-agnostic — 3D, 4D, 5D, ... all work.
      #
      # Without the fix `read` returned 0 for every index (sp_box_nil
      # fallback). With the fix it returns the right ints.

      class T_array_3d_nested_H3
        def initialize
          @t = [[[1, 2, 3], [4, 5, 6]], [[7, 8, 9], [10, 11, 12]]]
        end
        def read(i, j, k); @t[i][j][k]; end
      end

      h3 = T_array_3d_nested_H3.new
      puts h3.read(0, 0, 0)   # 1
      puts h3.read(0, 1, 1)   # 5
      puts h3.read(1, 0, 2)   # 9
      puts h3.read(1, 1, 2)   # 12

      # 4D — recursion handles arbitrary depth.
      class T_array_3d_nested_H4
        def initialize
          @t = [[[[1, 2], [3, 4]], [[5, 6], [7, 8]]],
                [[[9, 10], [11, 12]], [[13, 14], [15, 16]]]]
        end
        def read(i, j, k, l); @t[i][j][k][l]; end
      end

      h4 = T_array_3d_nested_H4.new
      puts h4.read(0, 0, 0, 0)   # 1
      puts h4.read(0, 1, 0, 1)   # 6
      puts h4.read(1, 0, 1, 0)   # 11
      puts h4.read(1, 1, 1, 1)   # 16
    RUBY

    _(result).must_answer <<~'OUT'
      1
      5
      9
      12
      1
      6
      11
      16
    OUT
  end

  it "instance eval return value" do
    result = ze0(<<~'RUBY')
      # instance_eval as an expression: the block's last expression is the
      # call's value (CRuby semantics). Void-bodied blocks (assignment-only)
      # fall through to a truthy receiver so `if obj.instance_eval { @f = 1 }`
      # still works.

      class T_instance_eval_return_value_Counter
        def initialize
          @count = 0
        end
        def inc
          @count = @count + 1
        end
      end

      c = T_instance_eval_return_value_Counter.new
      c.inc
      c.inc
      c.inc

      # Int-valued block returns the ivar, not the receiver.
      n = c.instance_eval { @count }
      puts n   # 3

      # Boolean-valued block.
      big = c.instance_eval { @count > 2 }
      puts big # true

      # Arithmetic expression body.
      doubled = c.instance_eval { @count + @count }
      puts doubled # 6

      # String-valued block (pointer-typed return).
      class T_instance_eval_return_value_Greeter
        def initialize
          @greeting = "hello"
        end
      end

      g = T_instance_eval_return_value_Greeter.new
      msg = g.instance_eval { @greeting }
      puts msg # hello

      # Void body: receiver flows out via comma-expr fallback, keeping the
      # `if` arm truthy.
      class T_instance_eval_return_value_Flag
        def initialize
          @flag = 0
        end
      end

      f = T_instance_eval_return_value_Flag.new
      if f.instance_eval { @flag = 1 }
        puts "truthy"
      end

      puts "done"
    RUBY

    _(result).must_answer <<~'OUT'
      3
      true
      6
      hello
      truthy
      done
    OUT
  end

  it "map array block result" do
    result = ze0(<<~'RUBY')
      # `arr.map { array_block }` — outer recv is a typed Array, block
      # returns a typed array (`(0..i).to_a` here is int_array). Without
      # the fix, two issues conspire:
      #
      #   - infer_method_name_type returned int_array, so the ivar `@rows`
      #     was typed as int_array. The outer accumulator was an
      #     sp_IntArray pushed via sp_IntArray_push — but each iteration's
      #     value was an sp_IntArray pointer reinterpreted as mrb_int,
      #     which gcc rejects on -Wint-conversion.
      #   - Even if the cast were silent, the inner arrays would not be
      #     traced from an IntArray slot and could be collected mid-loop.
      #
      # After the fix, the result is `<elem>_ptr_array` and the codegen
      # accumulator is an sp_PtrArray pushed via sp_PtrArray_push.

      class T_map_array_block_result_C
        def initialize
          @rows = [1, 6].map { |i| (0..i).to_a }
        end

        def show
          @rows.each do |row|
            row.each { |x| print x, " " }
            puts
          end
        end
      end

      T_map_array_block_result_C.new.show
    RUBY

    _(result).must_answer <<~'OUT'
      0 1 
      0 1 2 3 4 5 6 
    OUT
  end

  it "map block returns nested array" do
    result = ze0(<<~'RUBY')
      # `Range#map` / `int_array.map` whose block returns an array
      # (1D, 2D, 3D nested) used to silently degrade — the codegen
      # returned `0` for non-int/string/float block returns at the
      # Range#map path, and `int_array.map` boxed inner ptr_array
      # results via `sp_box_ptr_array(val)` which erased the
      # elem-type info (cls_id PTR_ARRAY only) so deeper indexing
      # fell through every dispatch arm to `sp_box_nil()`.
      #
      # Fixes:
      #
      # - Range#map block returning a typed array now stores in
      #   `sp_PtrArray` (matching the inferred `<bret>_ptr_array`
      #   type). Deeper nesting (block returns ptr_array /
      #   poly_array) stores in `sp_PolyArray` with `box_value_to_poly`
      #   boxing — preserves cls_id chain for `arr[i][j][k]...`.
      #
      # - `int_array.map`'s deep-array branch (block returns
      #   `<X>_ptr_array`) converts the inner sp_PtrArray to
      #   sp_PolyArray inline via a per-element `sp_box_<elem>` re-tag,
      #   so the outer PolyArray's elements carry the right cls_id at
      #   the next dispatch level.
      #
      # Together this lets nested-map-of-array-block constructs
      # (e.g. optcarrot's `TILE_LUT = [...].map { (0..7).map {
      # (0...0x10000).map { ... } }.transpose }`) compile and read
      # at every depth.

      # Range#map -> int_array_ptr_array (2D)
      class T_map_block_returns_nested_array_M2
        def initialize
          @t = (0..2).map { |i| (0..3).map { |j| i * 10 + j } }
        end
        def read(i, j); @t[i][j]; end
      end
      m2 = T_map_block_returns_nested_array_M2.new
      puts m2.read(0, 0)   # 0
      puts m2.read(1, 2)   # 12
      puts m2.read(2, 3)   # 23

      # int_array.map { Range#map { ... } } -> 3D via PolyArray
      class T_map_block_returns_nested_array_M3
        def initialize
          @t = [10, 20].map do |a|
            (0..2).map { |b| [a + b, a + b + 100] }
          end
        end
        def read(i, j, k); @t[i][j][k]; end
      end
      m3 = T_map_block_returns_nested_array_M3.new
      puts m3.read(0, 0, 0)   # 10
      puts m3.read(0, 1, 1)   # 111
      puts m3.read(1, 2, 0)   # 22
      puts m3.read(1, 2, 1)   # 122
    RUBY

    _(result).must_answer <<~'OUT'
      0
      12
      23
      10
      111
      22
      122
    OUT
  end

  it "map empty block" do
    result = ze0(<<~'RUBY')
      # Issue #210 follow-up: an empty `map {}` block must still produce
      # an array of the same length as the receiver. Each map dispatch
      # (Range#, N.times#, int_array#, str_array#, poly_array#) used to
      # skip the push entirely on an empty block, leaving the typed
      # accumulator short and downstream `.length` / `[i]` wrong.

      # Range#map
      puts (0..2).map {}.length          # 3

      # N.times.map
      puts 4.times.map {}.length         # 4

      # int_array#map
      puts [10, 20, 30].map {}.length    # 3

      # str_array#map
      puts ["a", "b", "c", "d"].map {}.length   # 4

      # poly_array#map
      puts [1, "two", :three].map {}.length     # 3

      # ptr_array#map (homogeneous obj_X[])
      class T_map_empty_block_Box
        def initialize(v); @v = v; end
      end
      puts [T_map_empty_block_Box.new(1), T_map_empty_block_Box.new(2), T_map_empty_block_Box.new(3)].map {}.length  # 3
    RUBY

    _(result).must_answer <<~'OUT'
      3
      4
      3
      4
      3
      3
    OUT
  end

  it "map range recv array block" do
    result = ze0(<<~'RUBY')
      # `infer_method_name_type` for `map` used to fall through to
      # `infer_type(recv)` when the block returned a non-trivial shape
      # (an array literal). For a Range recv that yielded `range`,
      # poisoning any ivar holding the result; an `@x = something_else`
      # assignment then failed to type-check (`@x = 0` against an
      # `sp_Range` slot).
      #
      # Now `Range#map { array_block }` infers as `<inner>_ptr_array`
      # (matching the runtime sp_PtrArray storage), so the result can
      # be indexed `arr[i][j]` directly. A subsequent re-assignment
      # with a different array shape goes to a separate slot to avoid
      # spinel's slot widening to poly.

      class T_map_range_recv_array_block_C
        def initialize
          # Block returns an int_array — outer is int_array_ptr_array.
          @rows = (0...3).map { |i| [i, i * 10] }
          # Separate slot for a plain int_array.
          @flat = [10, 20, 30]
        end

        def show
          @rows.each { |row| row.each { |v| puts v } }
          @flat.each { |v| puts v }
        end
      end

      T_map_range_recv_array_block_C.new.show
      # Expected:
      #   0 / 0 / 1 / 10 / 2 / 20 (each row's elements)
      #   10 / 20 / 30 (flat)
    RUBY

    _(result).must_answer <<~'OUT'
      0
      0
      1
      10
      2
      20
      10
      20
      30
    OUT
  end

  it "method name collision imeth" do
    result = ze0(<<~'RUBY')
      # Issue #407 (imeth follow-up): user-defined instance methods
      # named `hash`, `to_i`, `to_s`, `length`, `size`, `count` were
      # pre-empted by the hardcoded name -> int / string arms in
      # `infer_method_name_type`. The arm returned without consulting
      # the user's class table, so even when the recv was a typed
      # obj_<C>, the call was inferred as int (Object#hash etc.) and
      # the C compile cast the user's actual `const char *` return
      # through (long long).
      #
      # Fix: each hardcoded arm defers (returns "") when (a) the recv
      # is plausibly an obj_<C> at runtime (LocalVariableReadNode /
      # CallNode / InstanceVariableReadNode -- not a literal primitive
      # node), and (b) at least one user class declares the same imeth.
      # Falling through lands at infer_recv_method_type, whose
      # cls_method_return path resolves to the user's inferred return
      # type. Primitive recvs (literal IntegerNode / StringNode / ...)
      # still hit the hardcode, so 5.hash / "x".hash etc. stay int.
      #
      # Coverage:
      #   - `hash` shadowed -- the canonical bcrypt-shape from Ori's
      #     report, but in instance form.
      #   - `to_s` shadowed -- collides with Object#to_s (string).
      #   - `to_i` shadowed -- collides with Integer#to_i.
      #   - `length` shadowed -- collides with String#length.

      class T_method_name_collision_imeth_Item
        attr_accessor :tag
        def initialize(t); @tag = t; end
        def hash;   "item-hash:"   + @tag; end
        def to_i;   "item-toi:"    + @tag; end
        def to_s;   "item-tos:"    + @tag; end
        def length; "item-length:" + @tag; end
      end

      i = T_method_name_collision_imeth_Item.new("a")
      puts i.hash
      puts i.to_i
      puts i.to_s
      puts i.length
    RUBY

    _(result).must_answer <<~'OUT'
      item-hash:a
      item-toi:a
      item-tos:a
      item-length:a
    OUT
  end

  it "method name collision multi class" do
    result = ze0(<<~'RUBY')
      # Issue #407 case 2/3. Multiple unrelated classes define the
      # same method name; cross-class poly-recv widening picks the
      # correct param types via arity match.
      #
      # Pre-fix the scan_new_calls' forward-ref widening at line
      # 9910 bailed when more than one user class defined the same
      # `mname` (matched_ci_fwd = -2 = ambiguous), leaving every
      # candidate's params at the int default. Heterogeneous-array
      # iteration (`[T_method_name_collision_multi_class_IndexHandler.new, T_method_name_collision_multi_class_UsersHandler.new].each |h|;
      # h.handle(req, res); end`) then C-compiled with
      # `T_method_name_collision_multi_class_IndexHandler#handle(int, int)` against a `"/"` arg ->
      # Wint-conversion error.
      #
      # Fix: when the recv is statically `int`/unresolved
      # (var-type-table-not-yet-populated case matz called out),
      # walk every user class with the method and widen the ones
      # whose ptypes count matches the call's arg count. The arity
      # filter excludes attr_accessor entries (0-param getters)
      # that happen to share the name with a multi-arg def.
      #
      # Coverage:
      #   - Two unrelated classes (Index/T_method_name_collision_multi_class_UsersHandler) define
      #     `handle(req, res)` -- both get widened to (string, string)
      #     from the heterogeneous-array iteration's "/" + "" call site.
      #   - A third class (T_method_name_collision_multi_class_SQLite) has `attr_accessor :handle` (a
      #     0-param getter). Its ptypes count (0) doesn't match the
      #     call's arg count (2), so the arity filter excludes it
      #     from the widening.
      #   - The T_method_name_collision_multi_class_SQLite attr_accessor path is still reachable via
      #     `db.handle` (0-arg call) and returns the ivar value
      #     unchanged.

      class T_method_name_collision_multi_class_IndexHandler
        def handle(req, res); "i-" + req + ":" + res; end
      end
      class T_method_name_collision_multi_class_UsersHandler
        def handle(req, res); "u-" + req + ":" + res; end
      end
      class T_method_name_collision_multi_class_SQLite
        attr_accessor :handle
        def initialize(name); @handle = name; end
      end

      handlers = [T_method_name_collision_multi_class_IndexHandler.new, T_method_name_collision_multi_class_UsersHandler.new]
      i = 0
      while i < handlers.length
        h = handlers[i]
        puts h.handle("/", "ok")
        i += 1
      end

      db = T_method_name_collision_multi_class_SQLite.new("conn-1")
      puts db.handle
    RUBY

    _(result).must_answer <<~'OUT'
      i-/:ok
      u-/:ok
      conn-1
    OUT
  end

  it "method named log no math collision" do
    result = ze0(<<~'RUBY')
      # Method names that collide with Math module functions (log, sin,
      # cos, sqrt, exp, atan2, hypot, ...) should not be misinferred as
      # float-returning. Previously, infer_math_and_misc_type blindly
      # matched on the method name and returned float regardless of the
      # receiver — so a `def log; @log; end` accessor on a non-Math
      # class typed callers' locals as float and the downstream
      # `obj.log[i]` index emit dispatched as float (bit access). Fix:
      # gate the Math.<fn> branch on `recv` being either the literal
      # Math module ConstantReadNode or absent.

      class T_method_named_log_no_math_collision_Notebook
        attr_accessor :log
        def initialize
          @log = []
        end
        def add(line)
          @log.push(line)
        end
      end

      n = T_method_named_log_no_math_collision_Notebook.new
      n.add("first")
      n.add("second")
      entries = n.log
      puts entries[0]
      puts entries[1]
      puts entries.length.to_s

      # Also verify Math.log still works
      puts Math.log(1.0).to_i.to_s
    RUBY

    _(result).must_answer <<~'OUT'
      first
      second
      2
      0
    OUT
  end

  it "method param unify to poly" do
    result = ze0(<<~'RUBY')
      # Disagreeing call-site types for the same parameter need to widen
      # to `poly`. Pre-fix, `scan_new_calls` (obj-recv) and
      # `scan_cls_method_calls` (self-call inside the same class) both
      # only widened FROM "int": once the first non-int call site set the
      # param type, subsequent disagreeing calls were silently accepted
      # and the C compiler rejected the eventual mismatched call.
      #
      # Once the param widens to `poly`, the int / pointer / etc. arguments
      # at the call sites need to be boxed via `sp_box_*`. That boxing
      # branch was also missing from `compile_typed_call_args`, so even
      # after unify produced "poly", the call sites still passed raw
      # mrb_int / pointers to a sp_RbVal-typed parameter.

      class T_method_param_unify_to_poly_CPU
        def feed(x, val)
          val
        end
        # Self-call (no receiver). Lands in scan_cls_method_calls.
        def boot
          feed("hello", 1)
          feed(20, 2)
          feed("world", 3)
        end
      end

      class T_method_param_unify_to_poly_User
        def initialize(cpu)
          @cpu = cpu
        end
        # Obj-recv call. Lands in scan_new_calls' obj branch.
        def reset
          @cpu.feed(100, 10)
          @cpu.feed("via_user", 20)
          @cpu.feed(500, 30)
        end
      end

      cpu = T_method_param_unify_to_poly_CPU.new
      puts cpu.boot
      puts T_method_param_unify_to_poly_User.new(cpu).reset
    RUBY

    _(result).must_answer "3\n30\n"
  end

  it "method redefinition warning" do
    result = ze0(<<~'RUBY')
      # Issue #667: spinel is an AOT compiler with static dispatch; method
      # redefinition is a documented subset limitation. The analyzer detects
      # the case in append_cls_meth and emits a stderr warning, then follows
      # "last def wins" semantics (matching class reopen for new methods).
      # This test verifies the program compiles and runs with the warning
      # emitted; full CRuby semantics ("original" then "redefined") would
      # require source-order call-site versioning, which is a separate
      # multi-day effort.

      class T_method_redefinition_warning_Foo
        def test
          "original"
        end
      end

      f = T_method_redefinition_warning_Foo.new
      puts f.test

      class T_method_redefinition_warning_Foo
        def test
          "redefined"
        end
      end

      puts f.test
    RUBY

    _(result).must_answer "original\nredefined\n"
  end

  it "multi arg block call" do
    result = ze0(<<~'RUBY')
      # Multi-argument `block.call(a, b, ...)` on the proc-object path.
      #
      # Pre-fix, `compile_proc_literal` hardcoded the lambda's signature
      # as `static mrb_int <fn>(void *_cap, mrb_int lv_<bp>)` — a single
      # `mrb_int` slot — and the call site always lowered to
      # `sp_proc_call(lv_<rname>, <arg0>)`, so any second/third positional
      # arg was silently dropped.
      #
      # Fix collects every block param at proc-literal time and emits
      # `(void *_cap, mrb_int lv_<bp1>, mrb_int lv_<bp2>, ...)`, then
      # dispatches the call site to `sp_proc_call_N` (added to the
      # runtime: cast the stored function pointer to the matching N-arg
      # signature and invoke).
      #
      # Out of scope: arity-mismatched calls (`proc { |a| } .call(1, 2)`)
      # stay UB on the C side. Spinel's static dispatch enforces match in
      # the test cases below.

      # 1. Basic: forwarded `&block` invoked with 2 args.
      class T_multi_arg_block_call_App
        def run(&block)
          block.call(10, 20)
        end
      end

      T_multi_arg_block_call_App.new.run { |a, b| puts a + b }

      # 2. 3-arg block.call.
      class T_multi_arg_block_call_Wider
        def go(&block)
          block.call(1, 2, 3)
        end
      end

      T_multi_arg_block_call_Wider.new.go { |x, y, z| puts x + y + z }

      # 3. Same proc invoked twice with different concrete args.
      class T_multi_arg_block_call_Twice
        def both(&block)
          block.call(100, 1)
          block.call(200, 2)
        end
      end

      T_multi_arg_block_call_Twice.new.both { |a, b| puts a * b }

      # 4. 0-param block called with one arg. Extra arg is silently dropped
      # (matches CRuby semantics). Exercises the `_unused` fallback path
      # that the multi-param refactor must leave intact.
      class T_multi_arg_block_call_Drop
        def go(&block)
          block.call(99)
        end
      end

      T_multi_arg_block_call_Drop.new.go { puts "called" }
    RUBY

    _(result).must_answer <<~'OUT'
      30
      6
      100
      400
      called
    OUT
  end

  it "multi assign ivar" do
    result = ze0(<<~'RUBY')
      class T_multi_assign_ivar_A
        attr_reader :x
        def initialize; @x = 11; end
      end
      class T_multi_assign_ivar_B
        attr_reader :y
        def initialize; @y = 22; end
      end
      class T_multi_assign_ivar_C
        attr_reader :z
        def initialize; @z = 33; end
      end

      class T_multi_assign_ivar_Driver
        def self.load
          a = T_multi_assign_ivar_A.new
          b = T_multi_assign_ivar_B.new
          c = T_multi_assign_ivar_C.new
          return a, b, c
        end
      end

      class T_multi_assign_ivar_Holder
        def initialize
          @a, @b, @c = T_multi_assign_ivar_Driver.load
        end
        def show
          puts "a.x=#{@a.x} b.y=#{@b.y} c.z=#{@c.z}"
        end
      end

      h = T_multi_assign_ivar_Holder.new
      h.show
    RUBY

    _(result).must_answer "a.x=11 b.y=22 c.z=33\n"
  end

  it "multi write const" do
    result = ze0(<<~'RUBY')
      # Multi-write to constants — `A, B, T_multi_write_const_C = expr` — used to silently
      # drop the targets because the parser emitted ConstantTargetNode as
      # `UnknownNode_43` and the codegen had no MultiWriteNode branch in
      # the constant-collection passes. Subsequent reads of A/B/T_multi_write_const_C compiled
      # to undefined-identifier errors.
      #
      # Two RHS shapes are exercised: a literal ArrayNode (split element
      # by element at emit time) and a call returning int_array (evaluated
      # once into a temp, then sp_IntArray_get for each target).

      class T_multi_write_const_C
        N1, N2, N3 = [10, 20, 30]
      end

      puts T_multi_write_const_C::N1
      puts T_multi_write_const_C::N2
      puts T_multi_write_const_C::N3

      class T_multi_write_const_D
        ARR = [100, 200, 300, 400]
        M1, M2, M3, M4 = ARR
      end

      puts T_multi_write_const_D::M1
      puts T_multi_write_const_D::M2
      puts T_multi_write_const_D::M3
      puts T_multi_write_const_D::M4

      # RHS with a block — the block param introduces a local that
      # must be declared in main() (or the enclosing scope) so the
      # emitted `lv_<bp>` reference resolves. Single-const init already
      # scans @const_expr_ids; the multi-write form needs the same scan
      # over @multi_const_inits.
      P, Q = [1, 2].map { |n| n * 10 }
      puts P
      puts Q
    RUBY

    _(result).must_answer <<~'OUT'
      10
      20
      30
      100
      200
      300
      400
      10
      20
    OUT
  end

  it "multi write from poly recv" do
    result = ze0(<<~'RUBY')
      # Multi-write `a, b = rhs` where rhs's static type is `poly` (an
      # sp_RbVal that carries a poly_array at runtime).  Pre-fix:
      # `multi_write_target_type` fell through to the default `int` for
      # rt == "poly", so `a` / `b` were declared as mrb_int and the
      # emit-side dispatch (which DOES handle `val_t_local == "poly"` by
      # unboxing to sp_PolyArray*) wrote `(sp_PolyArray_get(...)).v.i`,
      # truncating the poly elements to garbage ints.

      class T_multi_write_from_poly_recv_C
        def setup
          @h = {}
          [0, 1].each do |bank|
            [0, 1].each do |idx|
              # Outermost ||= produces a poly_poly_hash slot, then a
              # poly_array of poly_arrays of two-tuples — same shape as
              # optcarrot's @lut_update.
              (((@h[bank] ||= [])[idx] ||= [nil, nil])[0] ||= []) << [idx * 10 + bank, idx + bank]
            end
          end
        end

        def name_lut_size(bank, idx)
          # Multi-write whose RHS infers to `poly`: @h[bank][idx] indexes
          # into poly_poly_hash (returns poly), then into the unboxed
          # poly_array (returns poly).
          name_lut_update, _attr_lut_update = @h[bank][idx]
          name_lut_update.length
        end
      end

      c = T_multi_write_from_poly_recv_C.new
      c.setup
      # bank=1 / idx=0 yields a 1-element list (one push at this slot).
      puts c.name_lut_size(1, 0)
    RUBY

    _(result).must_answer "1\n"
  end

  it "multi write ivar" do
    result = ze0(<<~'RUBY')
      # `@a, @b = expr1, expr2` (multi-write to ivars) was not picked up by
      # `scan_ivars`, so the ivars were never registered and the struct
      # came out missing them. The emit-time path in compile_stmt already
      # handled InstanceVariableTargetNode; the gap was only in the
      # collection pass.

      class T_multi_write_ivar_Inner
        def initialize(x); @x = x; end
        attr_reader :x
      end

      class T_multi_write_ivar_HasObjects
        def initialize
          @left, @right = T_multi_write_ivar_Inner.new(7), T_multi_write_ivar_Inner.new(8)
        end
        def sum
          @left.x + @right.x
        end
      end

      class T_multi_write_ivar_Holder
        def initialize
          @a, @b = 1, 2
        end
        attr_reader :a, :b
        def has_obj
          T_multi_write_ivar_HasObjects.new.sum
        end
      end

      h = T_multi_write_ivar_Holder.new
      puts h.a
      puts h.b
      puts h.has_obj
    RUBY

    _(result).must_answer <<~'OUT'
      1
      2
      15
    OUT
  end

  it "multi write ivar widening" do
    result = ze0(<<~'RUBY')
      class T_multi_write_ivar_widening_Pair
        def initialize(a, b)
          @x, @y = [a, b]
        end
        attr_reader :x, :y
      end

      p = T_multi_write_ivar_widening_Pair.new("hello", "world")
      puts p.x
      puts p.y
    RUBY

    _(result).must_answer "hello\nworld\n"
  end

  it "multi write map block" do
    result = ze0(<<~'RUBY')
      # `A, B = arr.map { block }` is destructuring assignment where
      # each LHS target receives one element of the mapped array.
      # Two related codegen pieces need to land together:
      #
      # 1. Type inference for the target slot. When the block returns a
      #    typed array (e.g. int_array), the target must be typed
      #    accordingly. Without the fix, the outer `infer_type` collapses
      #    array-of-array to the int_array placeholder and every target
      #    comes out as int.
      #
      # 2. Code emission for constant targets when the RHS evaluates to
      #    a ptr_array. Without the fix, the multi-write codegen had
      #    branches for ArrayNode literal RHS and int_array RHS but no
      #    ptr_array branch — every constant target stayed unset.

      class T_multi_write_map_block_C
        # Outer map produces a ptr_array (each element is an int_array
        # produced by the inner map).
        P, Q = [3, 5].map { |n| (0...n).to_a }
      end

      # Without the inference fix, P and Q would be typed `int` and the
      # `.length` / `[]` calls below wouldn't compile against the real
      # `sp_IntArray *` values stored in them.
      puts T_multi_write_map_block_C::P.length   # 3
      puts T_multi_write_map_block_C::P[0]       # 0
      puts T_multi_write_map_block_C::P[1]       # 1
      puts T_multi_write_map_block_C::P[2]       # 2
      puts T_multi_write_map_block_C::Q.length   # 5
      puts T_multi_write_map_block_C::Q[3]       # 3
      puts T_multi_write_map_block_C::Q[4]       # 4
    RUBY

    _(result).must_answer <<~'OUT'
      3
      0
      1
      2
      5
      3
      4
    OUT
  end

  it "multi write setter" do
    result = ze0(<<~'RUBY')
      # `a, b, c.x = expr` where one target is a setter call (`c.x =`)
      # parses to a CallTargetNode in the targets list. Without parser
      # support for CallTargetNode the setter target was silently dropped.

      class T_multi_write_setter_Box
        def initialize; @v = 0; end
        attr_accessor :v
      end

      class T_multi_write_setter_Holder
        def initialize
          @a = 0
          @b = 0
          @c = T_multi_write_setter_Box.new
        end
        def fill
          @a, @b, @c.v = [11, 22, 33]
        end
        def show
          puts @a
          puts @b
          puts @c.v
        end
      end

      h = T_multi_write_setter_Holder.new
      h.fill
      h.show
    RUBY

    _(result).must_answer <<~'OUT'
      11
      22
      33
    OUT
  end

  it "multi write typed array dispatch" do
    result = ze0(<<~'RUBY')
      # Regression: `a, b = self.method(...)` where `method` returns a typed
      # array other than int_array. compile_multi_write previously emitted
      # `sp_IntArray *tmp = call(); sp_IntArray_get(tmp, k)` for every
      # array-returning RHS that wasn't poly_array / poly. A method
      # returning e.g. obj_<C>_ptr_array therefore type-mismatched at the
      # C-temp declaration and dispatched the wrong getter.
      #
      # Each shape below has the call return a typed array and destructures
      # with two locals; the values must round-trip cleanly.

      class T_multi_write_typed_array_dispatch_Mat
        attr_accessor :v
        def initialize(v); @v = v; end
      end

      class T_multi_write_typed_array_dispatch_N
        def two_mats
          [T_multi_write_typed_array_dispatch_Mat.new(11), T_multi_write_typed_array_dispatch_Mat.new(22)]
        end
        def two_floats
          [1.5, 2.5]
        end
        def two_strs
          ["a", "b"]
        end

        def go_mats
          a, b = self.two_mats
          a.v + b.v
        end
        def go_floats
          a, b = self.two_floats
          a + b
        end
        def go_strs
          a, b = self.two_strs
          a + b
        end
      end

      n = T_multi_write_typed_array_dispatch_N.new
      puts n.go_mats     # 33
      puts n.go_floats   # 4.0
      puts n.go_strs     # "ab"
    RUBY

    _(result).must_answer <<~'OUT'
      33
      4.0
      ab
    OUT
  end

  it "mutable str into poly slot" do
    result = ze0(<<~'RUBY')
      # #541. A view function returning sp_String * boxed into a
      # `body` slot that had been widened to poly (other classes wrote
      # ints/etc. to the same-named slot) emitted
      # `sp_box_obj((void *)val, 0)` -- a generic SP_TAG_OBJ box with
      # cls_id 0 (BasicObject). Downstream code that dispatches on
      # the body's tag/cls_id (e.g. Tep::Server#write_response in
      # roundhouse, computing Content-Length and writing the wire)
      # had no arm matching SP_TAG_OBJ + cls_id 0, so the body was
      # silently dropped -- HTTP 200 with empty body in real-blog.
      #
      # Fix: `box_non_nullable_value_to_poly`'s mutable_str arm now
      # routes through `sp_box_str(s->data)` (SP_TAG_STR with the
      # underlying char* buffer) instead of the catch-all
      # `sp_box_obj((void *)..., 0)`. Consumers reading `v.v.s` on
      # the tag find the string content.

      class T_mutable_str_into_poly_slot_View
        def self.index
          s = String.new
          s << "<h1>title</h1>"
          s << "<p>body</p>"
          s
        end
      end

      class T_mutable_str_into_poly_slot_Resp
        attr_accessor :body
        def initialize; @body = ""; end
      end

      class T_mutable_str_into_poly_slot_OtherResp
        attr_accessor :body
        def initialize; @body = 42; end  # widens body across classes to poly
      end

      r = T_mutable_str_into_poly_slot_Resp.new
      r.body = T_mutable_str_into_poly_slot_View.index
      # Without the fix: body boxed as sp_box_obj((void *), 0); .inspect
      # dispatches via sp_poly_inspect which falls into the SP_TAG_OBJ
      # case but cls_id 0 matches no arm; result is generic /
      # truncated. With the fix: body boxed as SP_TAG_STR; inspect
      # returns the quoted string.
      puts r.body.inspect

      # Trigger the T_mutable_str_into_poly_slot_OtherResp widening so the analyzer sees both
      # int and string writes; verifies the str arm still works under
      # pre-widened body slots.
      o = T_mutable_str_into_poly_slot_OtherResp.new
      puts o.body.inspect

      r2 = T_mutable_str_into_poly_slot_Resp.new
      r2.body = T_mutable_str_into_poly_slot_View.index
      puts r2.body.inspect
    RUBY

    _(result).must_answer <<~'OUT'
      "<h1>title</h1><p>body</p>"
      42
      "<h1>title</h1><p>body</p>"
    OUT
  end

  it "nested class in class" do
    result = ze0(<<~'RUBY')
      # Nested class definition inside another class.
      # Spinel has no namespace table; bare class names must be unique, so
      # `class T_nested_class_in_class_A; class B; ... end; end` registers `B` at top level the same
      # way `module M; class B; ... end; end` does.

      class T_nested_class_in_class_A
        class B
          def initialize(x)
            @x = x
          end
          attr_reader :x
        end

        def make_b(x)
          B.new(x)
        end
      end

      # Direct construction via the path
      b = T_nested_class_in_class_A::B.new(7)
      puts b.x

      # Construction via the outer class
      b2 = T_nested_class_in_class_A.new.make_b(42)
      puts b2.x

      # T_nested_class_in_class_A nested class with its own nested class
      class T_nested_class_in_class_Outer
        class Mid
          class Inner
            def hello
              "hi"
            end
          end
        end
      end

      puts T_nested_class_in_class_Outer::Mid::Inner.new.hello
    RUBY

    _(result).must_answer <<~'OUT'
      7
      42
      hi
    OUT
  end

  it "nested proc interp capture" do
    result = ze0(<<~'RUBY')
      # Nested blocks that capture a variable through string interpolation
      # inside a block that itself captures the same variable.
      #
      # This exercises the @nd_parts recursion fix in scan_lambda_free_vars:
      # LocalVariableReadNode("i") is nested under
      #   InterpolatedStringNode → @nd_parts → EmbeddedStatementsNode → body
      # and without @nd_parts recursion the variable is never detected as free.

      class T_nested_proc_interp_capture_Defer
        def initialize
          @cnt = 0
        end

        def add(&blk)
          if @cnt == 0
            @blk0 = blk
          elsif @cnt == 1
            @blk1 = blk
          else
            @blk2 = blk
          end
          @cnt += 1
          nil
        end

        def call
          @blk2.call
          @blk1.call
          @blk0.call
        end
      end

      class T_nested_proc_interp_capture_Runner
        def self.with_deferred(&outer)
          d = T_nested_proc_interp_capture_Defer.new
          outer.call(d)
          d.call
        end
      end

      T_nested_proc_interp_capture_Runner.with_deferred do |d|
        i = 1
        d.add { puts "first #{i}" }
        i += 1
        d.add { puts "second #{i}" }
        puts "mid"
        i += 1
        d.add { puts "third #{i}" }
      end
    RUBY

    _(result).must_answer <<~'OUT'
      mid
      third 3
      second 3
      first 3
    OUT
  end

  it "new kwarg bundle" do
    result = ze0(<<~'RUBY')
      # #530. `Class.new(kw: val)` (Symbol-keyed kwargs) where the
      # class's initialize takes a single positional `attrs` param.
      # CRuby binds `attrs = {kw: val}` (the kwargs become a positional
      # hash whose keys are the kwarg *symbols*). Spinel previously
      # emitted `sp_Foo_new(0)` because the kwarg name didn't match the
      # positional param name -- the kwarg got silently dropped and the
      # param defaulted to int.
      #
      # Fix: when a KeywordHashNode arg's keys match no param name
      # and there's still an unfilled positional, treat the whole
      # hash as that positional's value. analyze widens the param's
      # inferred type to `sym_poly_hash` (symbol keys, poly values for
      # kwarg-value variety) and codegen builds the hash from the
      # kwargs at the call site. Access is via the kwarg symbols
      # (`attrs[:title]`); string keys would not match, matching CRuby.

      class T_new_kwarg_bundle_Article
        def initialize(attrs)
          @title = attrs[:title]
          @body  = attrs[:body]
        end
        attr_reader :title, :body
      end

      a = T_new_kwarg_bundle_Article.new(title: "Hello", body: "World")
      puts a.title
      puts a.body

      # Two kwarg call sites with different value shapes -- both flow
      # into the same sym_poly_hash widening.
      b = T_new_kwarg_bundle_Article.new(title: "Second", body: "Post")
      puts b.title

      # T_new_kwarg_bundle_Mixed value types in one kwarg call: the sym_poly_hash carries
      # all the boxed values; consumers unbox at the use site.
      class T_new_kwarg_bundle_Mixed
        def initialize(opts)
          @s = opts[:name]
          @n = opts[:count]
        end
        attr_reader :s, :n
      end

      m = T_new_kwarg_bundle_Mixed.new(name: "abc", count: 42)
      puts m.s
      puts m.n.inspect
    RUBY

    _(result).must_answer <<~'OUT'
      Hello
      World
      Second
      abc
      42
    OUT
  end

  it "nil ivar no predicate stays scalar" do
    result = ze0(<<~'RUBY')
      # #497. Regression guard for the optcarrot APU::Pulse shape that
      # motivated reverting #495: an ivar initialized to `nil` and later
      # used purely as int arithmetic (no `.nil?` read anywhere on it)
      # must stay at `int` storage. The pre-revert widening cascaded
      # `@wave_length` to poly via scan_writer_calls's new nil branch,
      # which then forced `@freq = (@wave_length + 1) * 2 * @fixed`
      # to a poly expression and broke every downstream `iv_freq`,
      # `iv_timer`, `iv_step` arithmetic site under -Werror.
      #
      # Test asserts both program output AND the implicit -Werror=int-
      # conversion compile (the harness drops cc stderr but a widened
      # ivar would surface as a missing binary / wrong output).

      class T_nil_ivar_no_predicate_stays_scalar_APUFake
        def initialize
          @wave_length = nil
          @fixed = 1
          @freq = 0
          @timer = 0
          @step = 0
        end

        def configure(n)
          @wave_length = n
          @freq = (@wave_length + 1) * 2 * @fixed
          @timer = @freq
        end

        def step!
          @step = (@step + 1) & 7
          @timer += @freq
          @step
        end

        def report
          @step.to_s + "," + @timer.to_s
        end
      end

      a = T_nil_ivar_no_predicate_stays_scalar_APUFake.new
      a.configure(3)
      puts a.report
      a.step!
      a.step!
      puts a.report
    RUBY

    _(result).must_answer "0,8\n2,24\n"
  end

  it "nil scalar ivar widen" do
    result = ze0(<<~'RUBY')
      class T_nil_scalar_ivar_widen_HitState
        def initialize
          @material_index = nil
        end

        def hit!(idx)
          @material_index = idx
        end

        def label
          @material_index.nil? ? "miss" : "hit"
        end
      end

      state = T_nil_scalar_ivar_widen_HitState.new
      puts state.label
      state.hit!(0)
      puts state.label

      class T_nil_scalar_ivar_widen_ResetState
        def initialize
          @material_index = 0
        end

        def clear!
          @material_index = nil
        end

        def label
          @material_index.nil? ? "miss" : "hit"
        end
      end

      reset = T_nil_scalar_ivar_widen_ResetState.new
      puts reset.label
      reset.clear!
      puts reset.label

      class T_nil_scalar_ivar_widen_ParamResetState
        def initialize
          @material_index = 0
        end

        def set(idx)
          @material_index = idx
        end

        def label
          @material_index.nil? ? "miss" : "hit"
        end
      end

      param_reset = T_nil_scalar_ivar_widen_ParamResetState.new
      puts param_reset.label
      param_reset.set(nil)
      puts param_reset.label
    RUBY

    _(result).must_answer <<~'OUT'
      miss
      hit
      hit
      miss
      hit
      miss
    OUT
  end

  it "no attr write shortcut complex" do
    result = ze0(<<~'RUBY')
      # `def x=(v); @x = v * 2; end` looks like an attr_writer at first glance
      # (single InstanceVariableWriteNode body) but the assignment value is a
      # computation, not a bare param reference — `is_simple_writer_method`
      # must not classify it as auto-attr_writer.
      #
      # Without that fix, the method gets auto-registered in @cls_attr_writers,
      # `cls_has_attr_writer(T_no_attr_write_shortcut_complex_C, "doubled")` returns true, and the call site
      # short-circuits `c.doubled = 5` to `c->iv_doubled = 5` — bypassing the
      # `* 2` entirely. Ruby would print 10; pre-fix Spinel printed 5.

      class T_no_attr_write_shortcut_complex_C
        def initialize
          @doubled = 0
        end

        def doubled=(v)
          @doubled = v * 2
        end

        def get_doubled
          @doubled
        end
      end

      c = T_no_attr_write_shortcut_complex_C.new

      c.doubled = 5
      puts c.get_doubled    # 10  (5 * 2)

      c.doubled = -7
      puts c.get_doubled    # -14

      puts "done"
    RUBY

    _(result).must_answer <<~'OUT'
      10
      -14
      done
    OUT
  end

  it "no attr write shortcut multi" do
    result = ze0(<<~'RUBY')
      # `obj.x = v` must dispatch to `def x=(v)` when x= is not a registered
      # attr_writer. A multi-statement body never matched the auto-attr_writer
      # pattern (which requires a single `InstanceVariableWriteNode` body), so
      # the fix at the call site is sufficient on its own to make this case
      # work — no auto-classification change required.

      class T_no_attr_write_shortcut_multi_C
        attr_accessor :real

        def initialize
          @real = 0
          @logged = ""
        end

        # Multi-statement writer. Side-effects on a *different* ivar so we can
        # tell whether the def actually ran.
        def logged=(v)
          @logged = "set:" + v
          @real = v.length
        end

        def get_logged
          @logged
        end
      end

      c = T_no_attr_write_shortcut_multi_C.new

      # attr_accessor path: still short-circuits to field write.
      c.real = 7
      puts c.real           # 7

      # Multi-statement def x=: must dispatch (not bypass).
      c.logged = "hello"
      puts c.get_logged     # set:hello
      puts c.real           # 5  (overwritten by the side effect)

      puts "done"
    RUBY

    _(result).must_answer <<~'OUT'
      7
      set:hello
      5
      done
    OUT
  end

  it "obj array" do
    result = ze0(<<~'RUBY')
      class T_obj_array_Point
        attr_accessor :x
        attr_accessor :y
        def initialize(x, y)
          @tag = "p"
          @x = x
          @y = y
        end
        def to_s
          x.to_s + "," + y.to_s
        end
      end

      points = [T_obj_array_Point.new(1, 2), T_obj_array_Point.new(3, 4), T_obj_array_Point.new(5, 6)]
      points.each { |p|
        puts p.to_s
      }
      puts points.length

      # push to obj array
      more = []
      more.push(T_obj_array_Point.new(10, 20))
      more.push(T_obj_array_Point.new(30, 40))
      more.each { |p|
        puts p.x + p.y
      }
    RUBY

    _(result).must_answer <<~'OUT'
      1,2
      3,4
      5,6
      3
      30
      70
    OUT
  end

  it "poly aref shift via block param" do
    result = ze0(<<~'RUBY')
      # `<poly>[idx]` flowing into an int operator (`>>` / `<<` / ...)
      # inside an `.each {|a| ... }` block must unbox the sp_RbVal result
      # of `a[idx]` before the T_poly_aref_shift_via_block_param_C operator.
      #
      # `entries` here is one half of a destructured 2-tuple from a
      # nested-ivar chain (`@store[bank][idx]`), which widens it to poly.
      # The block param `a` is then poly (not poly_array), so `a[2]`
      # emits via compile_poly_method_call's runtime tag-check → sp_RbVal.
      # Pre-fix, the analyze cache for `a[2]` sat at "int" (one observed
      # elem kind), so `compile_arg0_as_int` for `data >> a[2]` skipped
      # the unbox and emitted `lv_data >> _t.sp_RbVal` into the T_poly_aref_shift_via_block_param_C —
      # `invalid operands to binary >>`. The fix in infer_type matches
      # the actual emit so the unbox lands.

      class T_poly_aref_shift_via_block_param_C
        def initialize
          # @store[bank][idx] is a 2-tuple: (names, entries).  Each entry
          # in `entries` is a [tag, payload, shift] triple; the
          # heterogeneous element shape forces poly typing through the
          # destructure.
          @store = [[ [[1], [[10, [0, 1, 2], 4], [20, [3, 4, 5], 6]]] ]]
        end

        def run(bank, idx, data)
          _names, entries = @store[bank][idx]
          entries.each do |a|
            shifted = data >> a[2]
            puts shifted & 3
          end
        end
      end

      T_poly_aref_shift_via_block_param_C.new.run(0, 0, 0xff)
    RUBY

    _(result).must_answer "3\n3\n"
  end

  it "poly array literal callnode typed elem" do
    result = ze0(<<~'RUBY')
      # `[A, B]` outer literal where A and B are non-ArrayNode expressions
      # returning a typed `<X>_ptr_array` (e.g. `(0..N).map { ... }`).
      # Without the fix, compile_array_literal's poly_array branch hits
      # `box_value_to_poly(et, val)` for the CallNode element, which lowers
      # to `sp_box_ptr_array(val)` — cls_id PTR_ARRAY only, the inner
      # element type is erased. Subsequent `arr[b][i][j]` reads dispatch
      # through the PTR_ARRAY arm at level 1, which boxes the next-level
      # element as `sp_box_obj(p, 0)` (cls_id 0, "unknown obj"), and the
      # level-2 dispatch can't match any cls_id arm — every leaf read
      # returns 0.
      #
      # With the fix, the runtime conversion loop iterates the typed
      # PtrArray and pushes each inner with `sp_box_<inner-type>` (e.g.
      # `sp_box_int_array(...)` for an IntArray element), so the cls_id
      # chain stays tagged through every level.

      class T_poly_array_literal_callnode_typed_elem_C
        def initialize
          @a = [(0..3).map { |i| [i * 10, i * 10 + 1, i * 10 + 2] },
                (0..3).map { |i| [i * 100, i * 100 + 1, i * 100 + 2] }]
        end
        def get(b, i, j); @a[b][i][j]; end
        def out_len; @a.length; end
        def mid_len(b); @a[b].length; end
        def in_len(b, i); @a[b][i].length; end
      end

      c = T_poly_array_literal_callnode_typed_elem_C.new
      puts c.out_len           # 2
      puts c.mid_len(0)        # 4
      puts c.in_len(0, 0)      # 3
      puts c.get(0, 0, 0)      # 0
      puts c.get(0, 1, 1)      # 11
      puts c.get(0, 3, 2)      # 32
      puts c.get(1, 0, 0)      # 0
      puts c.get(1, 2, 1)      # 201
      puts c.get(1, 3, 2)      # 302
    RUBY

    _(result).must_answer <<~'OUT'
      2
      4
      3
      0
      11
      32
      0
      201
      302
    OUT
  end

  it "poly array slot literal" do
    result = ze0(<<~'RUBY')
      # `@arr = [a, b]` going into a poly_array slot used to compile the
      # rhs via `compile_array_literal`, which infers a typed storage
      # (ptr_array of one class for homogeneous obj literals, etc.) and
      # emits the matching `sp_PtrArray *`. The slot is `sp_PolyArray *`
      # (widened by writer-scan via heterogeneous `@arr[i] = v` writes
      # elsewhere in the class), so the resulting C contains a pointer-
      # type mismatch:
      #
      #   sp_PtrArray *_t1 = sp_PtrArray_new();
      #   sp_PtrArray_push(_t1, sp_Pad_new());
      #   self->iv_pads = _t1;          /* iv_pads is sp_PolyArray * */
      #
      # The default `-Wno-all` build accepts the cast silently and
      # coerces, but strict flags reject it as
      # `assignment to 'sp_PolyArray *' from incompatible pointer type
      # 'sp_PtrArray *'`. Even under `-Wno-all` the runtime is wrong:
      # `PolyArray_set` writes 16-byte sp_RbVal entries into 8-byte
      # PtrArray slots and silently corrupts adjacent memory.

      class T_poly_array_slot_literal_Pad
        def initialize(n)
          @n = n
          @arr = []
          @arr << n
        end
        attr_reader :n
      end

      class T_poly_array_slot_literal_Holder
        def initialize
          @pads = [T_poly_array_slot_literal_Pad.new(10), T_poly_array_slot_literal_Pad.new(20)]
          @pads[0] = "x"   # heterogeneous []= → @pads widens to poly_array
        end
        attr_reader :pads

        def count
          @pads.length
        end
      end

      puts T_poly_array_slot_literal_Holder.new.count    # 2
    RUBY

    _(result).must_answer "2\n"
  end

  it "poly array slot sized default" do
    result = ze0(<<~'RUBY')
      # `@arr = [nil] * N` going into a poly_array slot used to lower
      # the rhs via the default `*` codegen, which produces an sp_IntArray.
      # The slot is `sp_PolyArray *` (widened by writer-scan via
      # heterogeneous `@arr[i] = v` writes elsewhere in the class), so
      # the resulting C contains a pointer-type mismatch:
      #
      #   sp_IntArray *_t1 = sp_IntArray_new();
      #   ...
      #   self->iv_arr = _t1;          /* iv_arr is sp_PolyArray * */
      #
      # The default `-Wno-all` build silently coerces and the runtime
      # runs with garbage: subsequent `sp_PolyArray_set(@arr, ...)`
      # calls write 16-byte sp_RbVal entries into 8-byte IntArray slots,
      # corrupting adjacent memory and skewing `@arr.length`.
      #
      # An equivalent guard exists for ptr_array slots; this PR extends
      # it to poly_array slots (constructor + general InstanceVariable-
      # WriteNode paths) so the lowered storage matches the slot.

      class T_poly_array_slot_sized_default_Holder
        def initialize
          @arr = [nil] * 3
          @arr[0] = 42      # int
          @arr[1] = "two"   # str — heterogeneous → @arr widens to poly_array
        end
        attr_reader :arr

        def count
          @arr.length
        end
      end

      puts T_poly_array_slot_sized_default_Holder.new.count   # 3
    RUBY

    _(result).must_answer "3\n"
  end

  it "poly dispatch args ret" do
    result = ze0(<<~'RUBY')
      # Regression test for polymorphic return flow:
      # a method returning different class instances from branches.

      class T_poly_dispatch_args_ret_A
        def read(v)
          v + 1
        end
      end

      class T_poly_dispatch_args_ret_B
        def read(v)
          v + 2
        end
      end

      class T_poly_dispatch_args_ret_Builder
        def make(flag)
          if flag == 0
            T_poly_dispatch_args_ret_A.new
          else
            T_poly_dispatch_args_ret_B.new
          end
        end

        def make_with_return(flag)
          if flag == 0
            return T_poly_dispatch_args_ret_A.new
          end
          return T_poly_dispatch_args_ret_B.new
        end
      end

      b = T_poly_dispatch_args_ret_Builder.new

      obj0 = b.make(0)
      puts obj0.read(41)

      obj1 = b.make(1)
      puts obj1.read(41)

      ret0 = b.make_with_return(0)
      puts ret0.read(41)

      ret1 = b.make_with_return(1)
      puts ret1.read(41)
    RUBY

    _(result).must_answer <<~'OUT'
      42
      43
      42
      43
    OUT
  end

  it "poly dispatch arity padding" do
    result = ze0(<<~'RUBY')
      # Poly dispatch over user classes whose `m` definitions have
      # different arities — T_poly_dispatch_arity_padding_Switch#toggle takes 0 args; T_poly_dispatch_arity_padding_Knob#toggle takes
      # one positional default. Without per-arm padding, the C compiler
      # rejects the dispatch table with "too few arguments to function
      # 'sp_Knob_toggle'" (the dispatch arms have one fixed call shape
      # but the candidate methods have different arities).

      class T_poly_dispatch_arity_padding_Switch
        def initialize
          @v = 1
        end
        def toggle
          @v = 0
        end
        attr_reader :v
      end

      class T_poly_dispatch_arity_padding_Knob
        def toggle(soft = true)
          0
        end
      end

      class T_poly_dispatch_arity_padding_Box
        def initialize
          @items = [T_poly_dispatch_arity_padding_Switch.new, T_poly_dispatch_arity_padding_Switch.new]   # poly-typed; .toggle dispatch
                                              # over every class with `toggle`
        end
        attr_reader :items
      end

      b = T_poly_dispatch_arity_padding_Box.new
      b.items[0].toggle
      b.items[1].toggle
      puts b.items[0].v   # 0
      puts b.items[1].v   # 0
    RUBY

    _(result).must_answer "0\n0\n"
  end

  it "poly dispatch arity truncate" do
    result = ze0(<<~'RUBY')
      # Poly-dispatch arms must match each candidate method's *fixed* C
      # arity. The padding side (target takes more params than the call
      # supplied — defaults fill the extras) was already in place. The
      # truncate side is the complement: when a candidate class's method
      # accepts *fewer* params than the call supplied, that arm has to
      # drop the surplus to compile, even though the runtime cls_id check
      # would skip it for a non-matching receiver.

      class T_poly_dispatch_arity_truncate_Heater
        def initialize
          @v = 0
        end
        def write(addr, data)
          @v = addr + data
        end
        attr_reader :v
      end

      class T_poly_dispatch_arity_truncate_Buzzer
        def initialize
          @v = 0
        end
        def write(addr)        # one fewer arg than T_poly_dispatch_arity_truncate_Heater#write
          @v = addr
        end
        attr_reader :v
      end

      class T_poly_dispatch_arity_truncate_Box
        def initialize
          @poly = nil
          @poly = "x"
          @poly = T_poly_dispatch_arity_truncate_Heater.new   # widen to poly via heterogeneous writes
        end

        attr_reader :poly

        def call_write(addr, data)
          @poly.write(addr, data)   # poly recv → arms over T_poly_dispatch_arity_truncate_Heater + T_poly_dispatch_arity_truncate_Buzzer
        end
      end

      b = T_poly_dispatch_arity_truncate_Box.new
      b.call_write(7, 5)
      puts b.poly.v   # 12  (T_poly_dispatch_arity_truncate_Heater: addr + data)
    RUBY

    _(result).must_answer "12\n"
  end

  it "poly hash literal from ivar" do
    result = ze0(<<~'RUBY')
      # Issue #287: a method that returns `{ key: @x, ... }` had its
      # inferred return type frozen at the first scan, before #247 widened
      # the ivar slot to poly via a sibling-writer disagreement. The hash
      # literal then emitted as `sp_StrIntHash *` (int-valued) and tried
      # to insert the now-poly ivar value at T_poly_hash_literal_from_ivar_C compile time.
      #
      # Fix: extend `infer_hash_val_type`'s all_same branch to handle
      # `first_vt == "poly"` — sym/str-keyed poly hashes get the same
      # *_poly_hash storage as the mixed-types `else` branch.

      class T_poly_hash_literal_from_ivar_C
        def initialize
          @x = 0
        end
        def write_str(s)
          @x = s
        end
        def hash_of_x
          { key: @x }
        end
      end

      c = T_poly_hash_literal_from_ivar_C.new
      c.write_str("hello")
      puts c.hash_of_x.size       # 1
      puts c.hash_of_x.has_key?(:key)  # true

      # Multiple sym-keyed entries, all flowing from poly ivars.
      class T_poly_hash_literal_from_ivar_D
        def initialize
          @a = 0
          @b = 0
        end
        def write(sa, sb)
          @a = sa
          @b = sb
        end
        def attrs
          { a: @a, b: @b }
        end
      end

      d = T_poly_hash_literal_from_ivar_D.new
      d.write("alpha", "beta")
      puts d.attrs.size           # 2
      puts d.attrs.has_key?(:a)   # true
      puts d.attrs.has_key?(:c)   # false
    RUBY

    _(result).must_answer <<~'OUT'
      1
      true
      2
      true
      false
    OUT
  end

  it "poly int arith auto unify" do
    result = ze0(<<~'RUBY')
      # Auto-unify int receiver + poly argument in arithmetic. Common
      # case: `addr + arr[i][j]` where the inner dispatch is a
      # heterogeneous user-class+IntArray array — both arms genuinely
      # return int at runtime, but spinel statically types `[]`
      # dispatch as poly. Spinel previously emitted `(addr +
      # <sp_RbVal>)` and the C compile failed (`invalid operands to
      # binary + (have 'mrb_int' and 'sp_RbVal')`). The operator-site
      # fall-through now unboxes the poly arg via .v.i, mirroring PR
      # #347's LV-write semantics.

      # Class that defines `[]` returning int — when stored alongside an
      # IntArray in a poly_array, the outer `[]` dispatch returns poly.
      class T_poly_int_arith_auto_unify_Lookup
        def [](i); i * 10 + 1; end
      end

      arr = [T_poly_int_arith_auto_unify_Lookup.new, [100, 200, 300]]

      # arr[i] is poly (T_poly_int_arith_auto_unify_Lookup or IntArray), then `[j]` dispatches —
      # every runtime arm returns int, but the static return type is
      # poly. So `addr + arr[1][0]` is `int + poly` at codegen time.
      addr = 7
      puts(addr + arr[1][0])  # 7 + 100 = 107
      puts(addr - arr[0][2])  # 7 - 21  = -14
      puts(addr * arr[1][1])  # 7 * 200 = 1400
      puts(arr[1][2] / 3)     # 300 / 3 = 100  (recv-poly + arg-int already worked via sp_poly_div, included for coverage)
    RUBY

    _(result).must_answer <<~'OUT'
      107
      -14
      1400
      100
    OUT
  end

  it "poly int bit index" do
    result = ze0(<<~'RUBY')
      # `Integer#[N]` (bit-extraction) where the receiver was typed
      # poly via cascading inference. Used to fall through to the
      # SP_TAG_OBJ array dispatch in `emit_poly_builtin_dispatch`'s
      # `[]` branch, leaving the result at the nil/0 default — so
      # `int[i]` returned 0 for every i, and downstream
      # `pc[8] == tmp[8] ? a : b` style page-bit checks always took
      # the same-page branch.

      class T_poly_int_bit_index_Holder
        # Mixed-type ivar writes widen @x to poly. Reads return sp_RbVal
        # even when the runtime value is concretely int.
        def initialize
          @x = "init"
          @x = 0b10110100  # 180 — actual value at test time
        end

        attr_reader :x

        # Same-page check pattern: extract bit 8 from each poly-typed int.
        def same_page?(a, b)
          a[8] == b[8]
        end
      end

      h = T_poly_int_bit_index_Holder.new
      v = h.x  # `v` is poly here

      # Static index, dynamic value. Without the fix, every output is 0.
      puts v[0]    # 0
      puts v[1]    # 0
      puts v[2]    # 1
      puts v[3]    # 0
      puts v[4]    # 1
      puts v[5]    # 1
      puts v[6]    # 0
      puts v[7]    # 1

      # Dynamic index. Same buggy fallthrough.
      i = 0
      while i < 4
        puts v[i]
        i += 1
      end

      # Page-bit check: `0x100 | x` flips bit 8 on/off so the comparison
      # meaningfully differs depending on input. With the bug both values
      # get bit-8 == 0 (default), the comparison is always true, and
      # branch-cycle counting collapses.
      puts h.same_page?(h.x, h.x | 0x100)   # false (bit 8 differs)
      puts h.same_page?(h.x, h.x | 0x10)    # true (bit 8 same — both 0)
    RUBY

    _(result).must_answer <<~'OUT'
      0
      0
      1
      0
      1
      1
      0
      1
      0
      0
      1
      0
      false
      true
    OUT
  end

  it "poly nil return dispatch" do
    result = ze0(<<~'RUBY')
      # Regression: a subclass override whose static return type is `nil`
      # must still be called when dispatched through a poly receiver.
      # Previously `box_value_to_poly("nil", call_expr)` dropped `call_expr`
      # and emitted a bare `sp_box_nil()` for that arm, so the body of the
      # override never ran.
      #
      # Two checks:
      #  1. The override's side effect runs (the `puts` inside T_poly_nil_return_dispatch_Sub#hook).
      #  2. The dispatched call's *return value* is correctly observable as
      #     nil (i.e. the boxing path threads through, not just the side
      #     effect).

      class T_poly_nil_return_dispatch_Base
        def hook(arg); end          # empty body -> static return "nil"
      end

      class T_poly_nil_return_dispatch_Sub < T_poly_nil_return_dispatch_Base
        def hook(arg)
          puts "subclass-ran: " + arg   # `puts` returns nil
        end
      end

      class T_poly_nil_return_dispatch_Holder
        attr_accessor :h
        def initialize; @h = T_poly_nil_return_dispatch_Base.new; end
        def set(x); @h = x; end
        def call_hook(arg); @h.hook(arg); end
      end

      h = T_poly_nil_return_dispatch_Holder.new
      h.set(T_poly_nil_return_dispatch_Sub.new)
      result = h.call_hook("ok")
      puts result == nil
    RUBY

    _(result).must_answer "subclass-ran: ok\ntrue\n"
  end

  it "poly proc call" do
    result = ze0(<<~'RUBY')
      # poly_proc_call.rb — verify that .call on a Proc stored in an
      # ivar actually invokes the proc body.  Before the fix the dispatch
      # body was empty (two separate missing code paths).
      # Case 1: Proc stored as sp_RbVal (poly) → emit_poly_builtin_dispatch fix
      # Case 2: Proc stored as sp_Proc * (proc) → compile_dot_call_expr fix

      class T_poly_proc_call_Runner
        def initialize(pr)
          @pr = pr
        end

        def run
          @pr.call
        end
      end

      class T_poly_proc_call_Factory
        def wrap(&block)
          block
        end
      end

      f = T_poly_proc_call_Factory.new

      puts "start"
      T_poly_proc_call_Runner.new(f.wrap { puts "one" }).run
      T_poly_proc_call_Runner.new(f.wrap { puts "two" }).run
      puts "end"
    RUBY

    _(result).must_answer <<~'OUT'
      start
      one
      two
      end
    OUT
  end

  it "poly recv bracket assign" do
    result = ze0(<<~'RUBY')
      # `compile_bracket_assign` had no `rt == "poly"` branch. When an
      # ivar slot widens to plain `poly` (sp_RbVal — wider than
      # poly_array, set by `finalize_ivar_heterogeneity` because of
      # multiple distinct non-array writes), `@arr[i] = v` falls through
      # every typed branch and emits *nothing* — the assignment silently
      # drops from generated T_poly_recv_bracket_assign_C.
      #
      # Trigger: @arr is observed as int_array (`[nil] * N`) AND as a
      # scalar (string, int) — finalize collapses to plain `poly`. Then
      # `@arr[i] = v` should still write to the underlying storage, but
      # without the poly arm spinel emits zero code for the assignment.

      class T_poly_recv_bracket_assign_C
        def init_arr(n)
          @arr = [nil] * n      # int_array observation
          @arr[0] = 100
        end
        def init_str
          @arr = "scalar"       # string observation — widens slot to poly
        end
        def init_int
          @arr = 42             # int observation
        end
        def at(i)
          @arr[i]
        end
      end

      c = T_poly_recv_bracket_assign_C.new
      c.init_arr(3)
      puts c.at(0)              # post-write: 100 (master: 0 — write dropped)
    RUBY

    _(result).must_answer "100\n"
  end

  it "poly recv dispatch includes subclasses" do
    result = ze0(<<~'RUBY')
      # Polymorphic-receiver dispatch must include subclass arms when the
      # ivar's observed types narrow to a base class but the runtime value
      # may be a subclass instance written via a typed setter. Without this
      # the dispatch loop only emits the base-class arm and a subclass
      # override is silently skipped — the #616 filter-elision shape (tep's
      # `app.@before_filter.before(req, res)` where the override never
      # fires because @before_filter is declared `Tep::Filter` but the
      # stored runtime value is `TepFilters_before`).

      class T_poly_recv_dispatch_includes_subclasses_Pipeline
        attr_accessor :step
        def initialize; @step = T_poly_recv_dispatch_includes_subclasses_Step.new; end
        def set_step(s); @step = s; end
        def run(out)
          @step.process(out)
        end
      end

      class T_poly_recv_dispatch_includes_subclasses_Step
        def process(out)
          out[:base] = "ran"
        end
      end

      class T_poly_recv_dispatch_includes_subclasses_UpcaseStep < T_poly_recv_dispatch_includes_subclasses_Step
        def process(out)
          out[:sub] = "UPPER"
        end
      end

      p = T_poly_recv_dispatch_includes_subclasses_Pipeline.new
      p.set_step(T_poly_recv_dispatch_includes_subclasses_UpcaseStep.new)
      result = { base: "" , sub: "" }
      p.run(result)
      puts result[:base]   # "" (base override not invoked)
      puts result[:sub]    # "UPPER" (subclass override invoked)
    RUBY

    _(result).must_answer "\nUPPER\n"
  end

  it "poly recv dispatch narrow" do
    result = ze0(<<~'RUBY')
      # #513. When `obj.run(arg)` virtual-dispatched through an
      # unpinned receiver slot, the generated cls_id switch
      # enumerated EVERY class that defines `run`, not just classes
      # that can reach the receiver. Unrelated classes that share
      # the method name got pulled into the switch and their
      # parameters were widened to sp_RbVal to accept the dispatch
      # site's arg.
      #
      # Fix: when scan_new_calls' poly-recv widening fires for
      # `recv.mname(...)` and the recv is an ivar read, compute the
      # observed-class set for that ivar via observed_class_ids_for_recv.
      # When the recorded observation is just "poly" (because the rhs
      # of `@x = w` was a poly-typed param), walk the class's call
      # sites for the enclosing method and aggregate the concrete
      # obj types observed at the matching arg position. Restrict
      # the per-class param-widening loop to that set.
      #
      # The codegen-side cls_id-switch then naturally drops the
      # unrelated arms via the existing arm_incompat check: classes
      # whose `run` param stayed at the original concrete type can't
      # accept the dispatch site's (different concrete) arg, so the
      # arm is suppressed.

      class T_poly_recv_dispatch_narrow_WorkerA
        def run(item)
          item + "!"
        end
      end

      class T_poly_recv_dispatch_narrow_WorkerB
        def run(item)
          item + "?"
        end
      end

      class T_poly_recv_dispatch_narrow_Holder
        def initialize(w)
          @w = w
        end
        def use(item)
          @w.run(item)
        end
      end

      class T_poly_recv_dispatch_narrow_Server
        def run(port)
          port + 1
        end
      end

      # The fix: T_poly_recv_dispatch_narrow_Server#run's `port` stays mrb_int (not widened to
      # sp_RbVal by the @w.run(item) dispatch), so the int arithmetic
      # `port + 1` compiles cleanly and the direct call
      # `T_poly_recv_dispatch_narrow_Server.new.run(80)` doesn't have a poly-cast/unbox layer.
      puts T_poly_recv_dispatch_narrow_Holder.new(T_poly_recv_dispatch_narrow_WorkerA.new).use("x")
      puts T_poly_recv_dispatch_narrow_Holder.new(T_poly_recv_dispatch_narrow_WorkerB.new).use("y")
      puts T_poly_recv_dispatch_narrow_Server.new.run(80)
    RUBY

    _(result).must_answer <<~'OUT'
      x!
      y?
      81
    OUT
  end

  it "poly recv each" do
    result = ze0(<<~'RUBY')
      # `<poly>.each` runtime dispatch on cls_id. The compile_each_block
      # handler previously bailed when the receiver type was `poly` (no
      # matching `if rt == "..."` branch), so a method body that ends in
      # `iterable.each do |a| ... end` over a poly slot silently dropped
      # the iteration.
      #
      # Repro: an ivar `@store` widened to poly via two distinct array
      # shapes (an int_array and a poly_array) is iterated via `.each`.
      # Spinel previously emitted no loop at all — the body never ran.
      # The block param `a` is delivered as sp_RbVal (the widest fit
      # across the cls_id arms).

      class T_poly_recv_each_C
        def store_int_array
          @store = [10, 20, 30]
        end
        def store_poly_array
          @store = [nil] * 3
          @store[0] = "a"
          @store[1] = "b"
          @store[2] = "c"
        end
        def visit
          @store.each do |x|
            puts x.to_s
          end
        end
      end

      c = T_poly_recv_each_C.new
      c.store_int_array
      c.visit
      puts "---"
      c.store_poly_array
      c.visit
    RUBY

    _(result).must_answer <<~'OUT'
      10
      20
      30
      ---
      a
      b
      c
    OUT
  end

  it "poly recv ivar narrow drops unrelated" do
    result = ze0(<<~'RUBY')
      # Poly-recv user-class dispatch on an ivar previously dragged in
      # arms for any class that happened to share the method name, even
      # when that class was never assigned to the ivar (never even
      # instantiated). Issue #575: an unrelated `run` method on
      # T_poly_recv_ivar_narrow_drops_unrelated_Unrelated leaked into the @worker dispatch and forced the
      # result temp to widen to sp_RbVal, breaking the downstream
      # typed-string consumer.
      #
      # Fix has two parts:
      #   (a) compile_poly_method_call's emit loop consults the existing
      #       poly_dispatch_narrow_class_set helper (it was already
      #       used by the return-type union but missing from the arm
      #       emit).
      #   (b) A new analyzer pass forward-propagates each `<C>.new(args)`
      #       callsite's arg types into the ivar observations for any
      #       `@ivar = pname` write in C#initialize, so the narrow set
      #       isn't blocked by the param-union "poly" entry that the
      #       writer-scan would have recorded.

      class T_poly_recv_ivar_narrow_drops_unrelated_Worker
        def run(item)
          item + ""
        end
      end

      class T_poly_recv_ivar_narrow_drops_unrelated_Other < T_poly_recv_ivar_narrow_drops_unrelated_Worker
        def run(item)
          item + "!"
        end
      end

      # T_poly_recv_ivar_narrow_drops_unrelated_Unrelated to T_poly_recv_ivar_narrow_drops_unrelated_Worker. Never instantiated, never assigned to a
      # T_poly_recv_ivar_narrow_drops_unrelated_Pool@worker slot. Its `run` has zero formal args and returns
      # Integer — pre-fix this leaked into the dispatch and dragged the
      # result type to sp_RbVal, tripping the downstream File.write.
      class T_poly_recv_ivar_narrow_drops_unrelated_Unrelated
        def run
          1
        end
      end

      class T_poly_recv_ivar_narrow_drops_unrelated_Pool
        attr_accessor :worker
        def initialize(w); @worker = w; end
        def go(item, path)
          File.write(path, @worker.run(item))
          0
        end
      end

      T_poly_recv_ivar_narrow_drops_unrelated_Pool.new(T_poly_recv_ivar_narrow_drops_unrelated_Worker.new).go("a", "spinel_poly_recv_ivar_narrow_a.txt")
      T_poly_recv_ivar_narrow_drops_unrelated_Pool.new(T_poly_recv_ivar_narrow_drops_unrelated_Other.new).go("b", "spinel_poly_recv_ivar_narrow_b.txt")
      puts File.read("spinel_poly_recv_ivar_narrow_a.txt")
      puts File.read("spinel_poly_recv_ivar_narrow_b.txt")
      File.delete("spinel_poly_recv_ivar_narrow_a.txt")
      File.delete("spinel_poly_recv_ivar_narrow_b.txt")
    RUBY

    _(result).must_answer "a\nb!\n"
  end

  it "poly recv setter widens ivar" do
    result = ze0(<<~'RUBY')
      # #579 (Sam Ruby). `recv.attr = val` where `recv` is statically
      # poly (typed sp_RbVal because it came from `case ... when X
      # then T_poly_recv_setter_widens_ivar_A.new; when Y then T_poly_recv_setter_widens_ivar_B.new`) lowers to a cls_id-switch
      # dispatch in codegen -- each arm does `((sp_C *)_t.v.p)->iv_x = rhs`.
      # The analyzer's ivar-type pass only observed setters when recv
      # was a single obj_X type; for poly-recv setters every candidate
      # class's iv_x stayed at whatever its initialize-time default
      # typed it as (e.g. `@data = {}` → sp_StrIntHash *). The per-arm
      # assignment then mismatched the wider RHS at the C boundary.
      #
      # Fix: when scan_writer_calls sees `recv.attr = val` with recv_t
      # == "poly", iterate every class that declares the matching
      # attr_writer and call update_ivar_type on each. Mirrors the
      # codegen dispatch's behavior: every candidate class receives
      # the assignment at runtime, so every candidate's ivar type
      # must widen against the RHS.

      class T_poly_recv_setter_widens_ivar_Base
        attr_accessor :data
        def initialize
          @data = {}
        end
      end

      class T_poly_recv_setter_widens_ivar_A < T_poly_recv_setter_widens_ivar_Base
      end

      class T_poly_recv_setter_widens_ivar_B < T_poly_recv_setter_widens_ivar_Base
      end

      # Force the receiver into the poly shape via a case-expression
      # whose branches return different sibling subclasses.
      n = 1
      receiver = case n
                 when 0 then T_poly_recv_setter_widens_ivar_A.new
                 when 1 then T_poly_recv_setter_widens_ivar_B.new
                 end
      merged = { "name" => "foo" }
      receiver.data = merged
      puts receiver.data["name"]
    RUBY

    _(result).must_answer "foo\n"
  end

  it "poly return to str unbox" do
    result = ze0(<<~'RUBY')
      # Issue #655: A function whose RBS declares `-> String` but
      # whose body returns a poly (sp_RbVal) ternary tripped the
      # `incompatible types when returning sp_RbVal from a function
      # with incompatible result type 'const char *'` T_poly_return_to_str_unbox_C error. Canonical
      # shape: `@hash[key] || ""` where the hash inferred to value-type
      # Int (no writes observed) and the `||` ternary boxed both arms.
      #
      # Fix: compile_body_return_inner now unboxes via `.v.s` when
      # expr_type is poly and return_type is string / mutable_str.
      #
      # This test pins runtime behaviour on the writes-observed case
      # (which produces the real value) since the no-writes path's
      # semantics are inherently lossy — Ruby's `0 || ""` returns 0
      # (int is truthy), so a no-write hash returning the default-0
      # Int and then taking `.v.s` reads the union as a NULL pointer
      # (which `sp_str_length` guards as length 0). The standalone
      # repro from the issue is included to verify T_poly_return_to_str_unbox_C compile.

      class T_poly_return_to_str_unbox_C
        attr_reader :h
        def initialize
          @h = {}
          @h["a"] = "alpha"
          @h["b"] = "beta"
        end

        def get(key)
          @h[key] || ""
        end
      end

      c = T_poly_return_to_str_unbox_C.new
      puts c.get("a")
      puts c.get("b")
      puts c.get("missing")
      puts c.get("a").length
      puts c.get("missing").length
    RUBY

    _(result).must_answer <<~'OUT'
      alpha
      beta

      5
      0
    OUT
  end

  it "poly shl array push dispatch" do
    result = ze0(<<~'RUBY')
      # `<<` on a poly recv used to always lower to sp_poly_shl, which
      # was Integer-bit-shift only. An IntArray boxed into a poly slot
      # (e.g. an ivar that the type-inference passes widened to poly
      # because it received both nil and an array) had its `<<` push
      # silently turn into a bit-shift of the encoded pointer/length,
      # dropping the rhs.
      #
      # After the fix, sp_poly_shl dispatches by recv cls_id and invokes
      # the matching Array#<< push. Falls through to bit-shift only when
      # the recv is a non-array (genuine Integer<<int).

      class T_poly_shl_array_push_dispatch_C
        def initialize
          # `nil` then concrete-array writes widen @v to poly (Issue #130
          # "definite int/nil + obj → poly"). Once poly, the runtime
          # carries cls_id INT_ARRAY at access time.
          @v = nil
          @v = [10, 20, 30]
        end
        def push(x); @v << x; end
        def length; @v.length; end
        def get(i); @v[i]; end
      end

      c = T_poly_shl_array_push_dispatch_C.new
      c.push(99)
      c.push(88)
      puts c.length         # 5
      puts c.get(0)         # 10
      puts c.get(3)         # 99
      puts c.get(4)         # 88

      # Bit-shift on genuine Integer recv still works (the fall-through).
      x = 1
      puts x << 3           # 8
    RUBY

    _(result).must_answer <<~'OUT'
      5
      10
      99
      88
      8
    OUT
  end

  it "proc array push" do
    result = ze0(<<~'RUBY')
      # Ensure that pushing a Proc into an ivar array (int_array default
      # from []) promotes the array to poly_array so .each { |b| b.call }
      # actually dispatches the proc. Without the fix, .call on the
      # iteration variable is a no-op because b stays typed as mrb_int.
      class T_proc_array_push_Runner
        def initialize
          @procs = []
        end

        def add(&block)
          @procs.push(block)
        end

        def call_all
          @procs.each do |p|
            p.call
          end
        end
      end

      r = T_proc_array_push_Runner.new
      r.add { puts "first" }
      r.add { puts "second" }
      puts "before"
      r.call_all
      puts "after"
    RUBY

    _(result).must_answer <<~'OUT'
      before
      first
      second
      after
    OUT
  end

  it "proc body nested block" do
    result = ze0(<<~'RUBY')
      class T_proc_body_nested_block_Defer
        def initialize
          @blocks = []
        end

        def add(&blk)
          @blocks.push(blk)
        end

        def call_all
          @blocks.each do |b|
            b.call
          end
        end
      end

      class T_proc_body_nested_block_Runner
        def self.with_deferred(&outer)
          d = T_proc_body_nested_block_Defer.new
          outer.call(d)
          d.call_all
        end
      end

      T_proc_body_nested_block_Runner.with_deferred do |d|
        d.add { puts "first" }
        d.add { puts "second" }
        puts "mid"
      end
    RUBY

    _(result).must_answer <<~'OUT'
      mid
      first
      second
    OUT
  end

  it "proc hash value" do
    result = ze0(<<~'RUBY')
      # Issue #65: an ivar initialized as `{}` and later assigned `&block`
      # captured procs lowered the slot to str_int_hash, then fed
      # `sp_Proc *` into `sp_StrIntHash_set` (which expects mrb_int).
      #
      # Two fixes:
      #   - Issue #64's empty-hash promotion now resolves the slot to
      #     `str_poly_hash` when the value type is `proc`.
      #   - `box_expr_to_poly` / `box_value_to_poly` learned a `proc`
      #     branch so the `[]=` site emits `sp_box_proc(...)` instead of
      #     falling through to `sp_box_int`.
      #   - The empty-hash inline-init paths (compile_stmt and
      #     emit_constructor) now route to `sp_StrPolyHash_new()` /
      #     `sp_SymPolyHash_new()` for poly-valued promotions.

      class T_proc_hash_value_Registry
        def initialize
          @builtins = {}
        end

        def define_builtin(name, &block)
          @builtins[name] = block
        end
      end

      r = T_proc_hash_value_Registry.new
      r.define_builtin("x") { 1 }
      puts "ok"
    RUBY

    _(result).must_answer "ok\n"
  end

  it "ptr array delete at" do
    result = ze0(<<~'RUBY')
      # Regression: `Array#delete_at(i)` on an array of user-class
      # instances. Pre-fix the codegen had the dispatch arm only for
      # IntArray / StrArray; PtrArray<UserClass> hit the unresolved-call
      # warning and emitted 0, so user-class arrays could push but never
      # shrink. Hit while building Tep::Scheduler's fiber-slot list:
      # the `clear` loop never terminated because `delete_at` was a no-op.

      class T_ptr_array_delete_at_Box
        attr_accessor :tag
        def initialize(tag)
          @tag = tag
        end
      end

      a = [T_ptr_array_delete_at_Box.new("seed")]
      a.delete_at(0)
      a.push(T_ptr_array_delete_at_Box.new("a"))
      a.push(T_ptr_array_delete_at_Box.new("b"))
      a.push(T_ptr_array_delete_at_Box.new("c"))
      puts a.length.to_s     # 3

      # Remove from middle.
      v = a.delete_at(1)
      puts v.tag             # b
      puts a.length.to_s     # 2
      puts a[0].tag          # a
      puts a[1].tag          # c

      # Negative index counts from end.
      last = a.delete_at(-1)
      puts last.tag          # c
      puts a.length.to_s     # 1

      # Out-of-range index returns nil-equivalent (NULL); array
      # unchanged.
      gone = a.delete_at(99)
      puts gone.nil? ? "nil" : "not-nil"
      puts a.length.to_s     # 1

      # Drain via repeated delete_at(0) -- the use case that surfaced
      # this bug. Loop must terminate.
      while a.length > 0
        a.delete_at(0)
      end
      puts a.length.to_s     # 0
      puts a.empty? ? "empty" : "not-empty"
    RUBY

    _(result).must_answer <<~'OUT'
      3
      b
      2
      a
      c
      c
      1
      nil
      1
      0
      empty
    OUT
  end

  it "reopen class" do
    result = ze0(<<~'RUBY')
      # Test: reopening a user-defined class merges into the existing one
      # instead of producing duplicate C struct/constructor definitions.

      class T_reopen_class_Point
        attr_accessor :x
        def initialize(x, y)
          @x = x
          @y = y
        end
      end

      class T_reopen_class_Point
        attr_accessor :y
        def to_s
          "(" + @x.to_s + "," + @y.to_s + ")"
        end
      end

      p = T_reopen_class_Point.new(3, 4)
      puts p.to_s
      puts p.x
      puts p.y
      p.x = 10
      p.y = 20
      puts p.to_s

      class T_reopen_class_Foo
      end

      class T_reopen_class_Foo
      end

      puts "ok"
    RUBY

    _(result).must_answer <<~'OUT'
      (3,4)
      3
      4
      (10,20)
      ok
    OUT
  end

  it "runtime widen int to poly array" do
    result = ze0(<<~'RUBY')
      # `compile_bracket_assign`'s `rt == "poly"` branch dispatches
      # `@arr[i] = v` by runtime cls_id, but when the slot's runtime
      # storage is IntArray and the rhs carries a non-int payload (a
      # typed pointer / box whose cls_id we'd lose if cast to int),
      # the write silently truncates to int.
      #
      # This patch widens the storage at runtime: allocate a fresh
      # PolyArray, copy each existing IntArray element as sp_box_int,
      # set the new slot, and reassign the slot expression to hold the
      # new PolyArray.

      class T_runtime_widen_int_to_poly_array_C
        def init_arr_widen
          @arr = [10, 20, 30]   # int_array storage
          @arr[1] = "string!"   # heterogeneous → triggers runtime widen
        end
        def init_str
          @arr = "scalar"       # forces slot type to widen to poly
        end
        def at(i); @arr[i]; end
      end

      c = T_runtime_widen_int_to_poly_array_C.new
      c.init_arr_widen
      puts c.at(0)               # 10 (preserved as int)
      puts c.at(1)               # "string!" (recovered via widen)
      puts c.at(2)               # 30
    RUBY

    _(result).must_answer <<~'OUT'
      10
      string!
      30
    OUT
  end

  it "sample user method" do
    result = ze0(<<~'RUBY')
      # `infer_method_name_type` had a name-based shortcut for `sample`
      # that returned the Array#sample default of int regardless of recv.
      # A user-defined `sample` on an obj receiver inferred as int even
      # though the method returns a non-int — and downstream consumers
      # (puts, comparisons, etc.) used the wrong shape.

      class T_sample_user_method_Box
        def initialize(label)
          @label = label
        end

        attr_reader :label

        def sample
          @label
        end
      end

      b = T_sample_user_method_Box.new("ok")
      puts b.sample    # ok
    RUBY

    _(result).must_answer "ok\n"
  end

  it "scan ivars inherited slot" do
    result = ze0(<<~'RUBY')
      # When a child class first writes to an ivar that already lives on
      # a parent, scan_ivars used to register the ivar on the child too.
      # update_ivar_type then recursed up to the parent and widened
      # (e.g. `int` → `poly` for heterogeneous writes), but the child's
      # own-table entry kept the new write's narrower type. Two tables
      # disagreed about the slot — and downstream type lookups picked
      # the wrong one depending on path, so codegen for the same field
      # disagreed across class methods.
      #
      # Now scan_ivars detects that the slot is already in an ancestor's
      # table and routes the write through update_ivar_type without
      # adding a duplicate entry to the child. The parent's table stays
      # the single source of truth.

      class T_scan_ivars_inherited_slot_Parent
        def initialize
          @v = 0
          @v = "s"     # parent widens @v to poly
        end
      end

      class T_scan_ivars_inherited_slot_Child < T_scan_ivars_inherited_slot_Parent
        def initialize
          super
          @v = 42      # child writes through inherited slot
        end
        def read
          @v
        end
      end

      puts T_scan_ivars_inherited_slot_Child.new.read     # 42
    RUBY

    _(result).must_answer "42\n"
  end

  it "scan new calls class scope" do
    result = ze0(<<~'RUBY')
      # `scan_new_calls` walks the AST looking for `Foo.new(args)` and
      # propagates each arg's inferred type into Foo's initialize param-
      # type table. The arg inference uses `infer_type`, which for an
      # `InstanceVariableReadNode` consults `@current_class_idx` —
      # previously the scan never set it.
      #
      # Result: `Bar.new(@x, ...)` inside `Foo#initialize` resolved
      # `@x` against an empty scope (returned the int default), so
      # Bar.initialize's first param wedged at mrb_int. The fix pins
      # `@current_class_idx` while recursing into ClassNode bodies.

      class T_scan_new_calls_class_scope_A
        attr_reader :n
        def initialize(n)
          @n = n
        end
      end

      class T_scan_new_calls_class_scope_B
        attr_reader :a
        def initialize(a_arg)
          @a = a_arg
        end
      end

      class T_scan_new_calls_class_scope_C
        attr_reader :b
        def initialize
          @inner = T_scan_new_calls_class_scope_A.new(7)
          @b = T_scan_new_calls_class_scope_B.new(@inner)
        end
      end

      c = T_scan_new_calls_class_scope_C.new
      puts c.b.a.n   # 7
    RUBY

    _(result).must_answer "7\n"
  end

  it "self class subclass dispatch" do
    result = ze0(<<~'RUBY')
      # Issue #422. `self.class.<cmeth>` inside a parent-defined
      # instance method must dispatch to the subclass override at
      # runtime, not to the parent's cmeth. Pre-fix the codegen
      # resolved cmeth statically against the method body's defining
      # class, so a T_self_class_subclass_dispatch_Child instance routed through a T_self_class_subclass_dispatch_Base-defined
      # `describe` always landed on `T_self_class_subclass_dispatch_Base.label`.
      #
      # Fix shape:
      #   - lib structs: every non-value-type sp_<C> gets `mrb_int
      #     cls_id` as its first field (layout-roots emit it; subclasses
      #     inherit via parent-fields-first ordering, so a cast preserves
      #     the offset).
      #   - constructors: `sp_<C>_new` writes `self->cls_id = <C's idx>`
      #     so the runtime carries the concrete class tag.
      #   - chained dispatch: `<recv>.class.<cmeth>()` lowers to a
      #     `switch (<recv>->cls_id)` when descendants of recv's static
      #     class override the cmeth.
      #
      # Coverage:
      #   - Plain T_self_class_subclass_dispatch_Base/T_self_class_subclass_dispatch_Child override.
      #   - Multi-level (T_self_class_subclass_dispatch_GrandChild overrides label).
      #   - Subclass that doesn't override -- inherits via the default
      #     (T_self_class_subclass_dispatch_Sibling has no .label, falls through to T_self_class_subclass_dispatch_Base).
      #   - Direct T_self_class_subclass_dispatch_Base instance still routes to T_self_class_subclass_dispatch_Base.

      class T_self_class_subclass_dispatch_Base
        def self.label
          "BASE"
        end

        def describe
          self.class.label
        end
      end

      class T_self_class_subclass_dispatch_Child < T_self_class_subclass_dispatch_Base
        def self.label
          "CHILD"
        end
      end

      class T_self_class_subclass_dispatch_GrandChild < T_self_class_subclass_dispatch_Child
        def self.label
          "GRANDCHILD"
        end
      end

      class T_self_class_subclass_dispatch_Sibling < T_self_class_subclass_dispatch_Base
      end

      puts T_self_class_subclass_dispatch_Base.new.describe
      puts T_self_class_subclass_dispatch_Child.new.describe
      puts T_self_class_subclass_dispatch_GrandChild.new.describe
      puts T_self_class_subclass_dispatch_Sibling.new.describe
    RUBY

    _(result).must_answer <<~'OUT'
      BASE
      CHILD
      GRANDCHILD
      BASE
    OUT
  end

  it "send" do
    result = ze0(<<~'RUBY')
      # Test send(:literal_symbol)
      # Note: send rewrite requires Ruby parser (spinel_parse.rb)
      x = [1,2,3]
      puts x.length

      class T_send_Adder
        def initialize(n)
          @n = n
        end
        def add(x)
          @n + x
        end
      end
      a = T_send_Adder.new(10)
      puts a.add(5)
    RUBY

    _(result).must_answer "3\n15\n"
  end

  it "send double underscore" do
    result = ze0(<<~'RUBY')
      # .__send__(:sym, args) and .__send__("sym", args) statically rewrite
      # to .sym(args) at parse time, identical to .send. CRuby exposes
      # __send__ as the overrides-resistant alias of send; Spinel does not
      # model the visibility distinction, so the two are semantically
      # equivalent here.

      class T_send_double_underscore_Calc
        def add(a, b)
          a + b
        end

        def hello
          "hi"
        end
      end

      c = T_send_double_underscore_Calc.new

      # Symbol arm: .__send__(:sym, args) -> .sym(args).
      puts c.__send__(:add, 10, 20)   # 30
      puts c.__send__(:hello)         # hi

      # String arm: .__send__("sym", args) -> .sym(args).
      puts c.__send__("add", 3, 4)    # 7
      puts c.__send__("hello")        # hi

      puts "done"
    RUBY

    _(result).must_answer <<~'OUT'
      30
      hi
      7
      hi
      done
    OUT
  end

  it "send literal string" do
    result = ze0(<<~'RUBY')
      # .send("sym", args) plain string literal rewrites to .sym(args) at
      # parse time, identical to the :symbol form. Interpolated strings and
      # variable args still fall through to runtime dispatch.

      class T_send_literal_string_Calc
        def add(a, b)
          a + b
        end

        def hello
          "hi"
        end
      end

      c = T_send_literal_string_Calc.new
      puts c.send("add", 2, 3)       # 5
      puts c.send("hello")           # hi

      puts "done"
    RUBY

    _(result).must_answer <<~'OUT'
      5
      hi
      done
    OUT
  end

  it "send literal symbol" do
    result = ze0(<<~'RUBY')
      # .send(:sym, args) statically rewrites to .sym(args) at parse time.
      # Non-literal symbol args (variable, interpolation) leave the call
      # alone -- those require runtime dispatch which Spinel doesn't model.

      class T_send_literal_symbol_Calc
        def add(a, b)
          a + b
        end

        def double(x)
          x * 2
        end

        def hello
          "hi"
        end

        # Returns the input length; used to exercise quoted-paren args.
        def length_of(s)
          s.length
        end
      end

      # 1. Basic shapes.
      c = T_send_literal_symbol_Calc.new
      puts c.send(:add, 3, 4)        # 7
      puts c.send(:double, 21)       # 42
      puts c.send(:hello)            # hi

      # 2. Quoted parens inside args must not prematurely close the call.
      #    The rewriter tracks `"..."` state so `)` inside the string is
      #    treated as a literal character, not as the call's close paren.
      puts c.send(:length_of, "a)b")     # 3
      puts c.send(:length_of, "x(y)z")   # 5
      puts c.send(:length_of, 'p)q')     # 3

      # 3. Operator method `[]` via send rewrites to .[](idx) which Prism
      #    parses as the index operator.
      arr = [10, 20, 30]
      puts arr.send(:[], 0)          # 10
      puts arr.send(:[], 2)          # 30

      # 4. Operator method `[]=` via send rewrites to .[]=(idx, val).
      arr.send(:[]=, 1, 99)
      puts arr[0]                    # 10
      puts arr[1]                    # 99
      puts arr[2]                    # 30

      puts "done"
    RUBY

    _(result).must_answer <<~'OUT'
      7
      42
      hi
      3
      5
      3
      10
      30
      10
      99
      30
      done
    OUT
  end

  it "str setbyte frozen literal" do
    result = ze0(<<~'RUBY')
      # frozen_string_literal: true
      # Bundled tests:
      #   - str_setbyte_frozen_literal
      #   - strip_nullable_int_cast


      # Spinel adopts `# frozen_string_literal: true` semantics
      # globally — every string literal is frozen, mutation requires
      # a heap-allocated buffer (`.dup`, `+`, etc.). setbyte on a
      # literal raises FrozenError with the same message CRuby uses
      # when the pragma is in effect.

      # Direct literal recv.
      begin
        "abc".setbyte(0, 67)
        puts "no raise (literal)"
      rescue FrozenError => e
        puts "literal: " + e.message
      end

      # LV pointing at a literal.
      s = "abc"
      begin
        s.setbyte(0, 67)
        puts "no raise (lv-literal): " + s
      rescue FrozenError => e
        puts "lv-literal: " + e.message
      end

      # Dup'd heap string mutates cleanly.
      s2 = "abc".dup
      s2.setbyte(0, 67)
      puts s2   # Cbc

      # Concatenation produces a heap buffer too.
      s3 = "x" + "y"
      s3.setbyte(0, 90)
      puts s3   # Zy

      # Heap aliasing: setbyte on shared object affects both refs.
      s4 = "ab".dup
      s5 = s4
      s4.setbyte(0, 67)
      puts s5   # Cb (shared heap, both see the mutation)

      # ivar holding a heap string mutates through method dispatch.
      class T_str_setbyte_frozen_literal_Buf
        attr_reader :s
        def initialize
          @s = "abc".dup
        end
        def hit
          @s.setbyte(0, 67)
        end
      end
      b = T_str_setbyte_frozen_literal_Buf.new
      b.hit
      puts b.s   # Cbc
    RUBY

    _(result).must_answer <<~'OUT'
      literal: can't modify frozen String: "abc"
      lv-literal: can't modify frozen String: "abc"
      Cbc
      Zy
      Cb
      Cbc
    OUT
  end

  it "strip nullable int cast" do
    result = ze0(<<~'RUBY')
      # frozen_string_literal: true
      # Bundled tests:
      #   - str_setbyte_frozen_literal
      #   - strip_nullable_int_cast


      # `compile_typed_call_args` casts an int arg to an object-pointer
      # parameter via `(sp_<base> *)<expr>`. The base name was derived
      # from the raw param-type string. When the param type is nullable
      # (e.g. `obj_Foo?`, set when the writer-scan sees both `Foo.new`
      # and `nil` writes), the cast came out as `(sp_Foo? *)expr` and
      # gcc rejected the stray `?`.
      #
      # Repro: a setter-shaped method whose param is widened to
      # `obj_Foo?` by mixed Foo + nil writes, then called with an int-
      # typed argument (a method that returns int). The int-arg path
      # fires the cast.

      class Foo; end
      class T_strip_nullable_int_cast_C
        def take(f)
          @f = f
        end
        def get_int; 42; end
      end
      c = T_strip_nullable_int_cast_C.new
      c.take(Foo.new)
      c.take(nil)
      c.take(c.get_int)
      puts "ok"
    RUBY

    _(result).must_answer "ok\n"
  end

  it "subclass inherited attr reader" do
    result = ze0(<<~'RUBY')
      # #508. Bare `attr_reader_name` and `self.attr_reader_name`
      # inside a subclass instance method failed to resolve when the
      # reader was declared via `attr_accessor` / `attr_reader` on the
      # parent class. Codegen's attr_reader lookup only consulted
      # @cls_attr_readers[current_class] and didn't walk the parent
      # chain.
      #
      # Fix: swap the per-class loop for a call to
      # `cls_has_attr_reader(ci, mname)`, which already walks
      # @cls_parents recursively. Two emit sites: the bare-name path
      # in compile_call_expr (instance method body, no receiver) and
      # the obj-receiver path in compile_object_method_expr (the
      # `self.fmt` shape).

      class T_subclass_inherited_attr_reader_Base
        attr_accessor :fmt
        attr_reader :tag
        def initialize
          @fmt = :html
          @tag = :base_tag
        end
      end

      class T_subclass_inherited_attr_reader_Sub < T_subclass_inherited_attr_reader_Base
        def doit
          fmt == :html ? "html" : "json"
        end
        def doit_self
          self.fmt == :html ? "html-self" : "json-self"
        end
        def tag_str
          tag.to_s
        end
      end

      s = T_subclass_inherited_attr_reader_Sub.new
      puts s.doit
      puts s.doit_self
      puts s.tag_str

      # Deeper chain: grandchild via T_subclass_inherited_attr_reader_Mid -> T_subclass_inherited_attr_reader_Base.
      class T_subclass_inherited_attr_reader_Mid < T_subclass_inherited_attr_reader_Base
      end

      class T_subclass_inherited_attr_reader_Leaf < T_subclass_inherited_attr_reader_Mid
        def show
          fmt.to_s + "/" + tag.to_s
        end
      end

      puts T_subclass_inherited_attr_reader_Leaf.new.show
    RUBY

    _(result).must_answer <<~'OUT'
      html
      html-self
      base_tag
      html/base_tag
    OUT
  end

  it "subclass override param propagate" do
    result = ze0(<<~'RUBY')
      # #516. When a parent-class instance method calls another method
      # via implicit-self dispatch and a subclass overrides that
      # method, the parent's typed call-site arg didn't propagate to
      # the subclass override's parameter. The override's param
      # stayed at the int default and the body's dispatch on it
      # failed.
      #
      # Fix: in scan_cls_method_calls' implicit-self CallNode arm,
      # after widening the same-class method's ptypes from the
      # arg_ids, also walk @cls_names for descendants that
      # direct-override the same method name and widen their
      # ptypes from the same arg_ids. The descendant's C signature
      # now agrees with the cls_id-switch dispatch that the imeth
      # emit later builds.

      class T_subclass_override_param_propagate_Base
        def reload(row)
          consume(row)
        end
        def consume(_row)
          "base default"
        end
      end

      class T_subclass_override_param_propagate_Sub < T_subclass_override_param_propagate_Base
        def consume(row)
          row["id"]
        end
      end

      puts T_subclass_override_param_propagate_Sub.new.reload({"id" => "42"})

      # Three-level chain: param flows through two override layers.
      class T_subclass_override_param_propagate_Parent
        def kick(payload)
          handle(payload)
        end
        def handle(_p)
          "parent"
        end
      end

      class T_subclass_override_param_propagate_Mid < T_subclass_override_param_propagate_Parent
        def handle(p)
          "mid:" + p[:name]
        end
      end

      class T_subclass_override_param_propagate_Leaf < T_subclass_override_param_propagate_Mid
        def handle(p)
          "leaf:" + p[:name]
        end
      end

      puts T_subclass_override_param_propagate_Mid.new.kick({name: "m"})
      puts T_subclass_override_param_propagate_Leaf.new.kick({name: "l"})
    RUBY

    _(result).must_answer <<~'OUT'
      42
      mid:m
      leaf:l
    OUT
  end

  it "super arg cross class cast" do
    result = ze0(<<~'RUBY')
      # Two subclasses each call `super` from `initialize` forwarding a
      # differently-typed arg. The parent's param-type inference picks one
      # concrete C type, so the other subclass's super-forwarded arg ends
      # up with a mismatching C type at the call site without an explicit
      # cast.

      class T_super_arg_cross_class_cast_Box
        def initialize(v)
          @v = v
        end
      end

      class T_super_arg_cross_class_cast_StrBox < T_super_arg_cross_class_cast_Box
        def initialize(s)
          super
          @len = s.length
        end

        def len
          @len
        end
      end

      class T_super_arg_cross_class_cast_IntBox < T_super_arg_cross_class_cast_Box
        def initialize(n)
          super
          @doubled = n * 2
        end

        def doubled
          @doubled
        end
      end

      s = T_super_arg_cross_class_cast_StrBox.new("hello")
      puts s.len

      n = T_super_arg_cross_class_cast_IntBox.new(7)
      puts n.doubled
    RUBY

    _(result).must_answer "5\n14\n"
  end

  it "super forwarding" do
    result = ze0(<<~'RUBY')
      # Bare `super` (no args, no parens) inside a constructor parses as
      # `ForwardingSuperNode`, not `SuperNode`. Without the
      # ForwardingSuperNode case, the call to the parent's `initialize`
      # was silently dropped — the parent's ivar setup never ran and the
      # child object was left in a half-initialized state.

      class T_super_forwarding_Base
        def initialize(x)
          @x = x
          @y = x * 10
        end
      end

      class T_super_forwarding_Child < T_super_forwarding_Base
        attr_reader :x, :y, :z
        def initialize(x)
          super              # bare — forwards x to T_super_forwarding_Base#initialize
          @z = x + 1
        end
      end

      c = T_super_forwarding_Child.new(3)
      puts c.x   # 3
      puts c.y   # 30
      puts c.z   # 4
    RUBY

    _(result).must_answer <<~'OUT'
      3
      30
      4
    OUT
  end

  it "super with block" do
    result = ze0(<<~'RUBY')
      # Issue #665: `super { ... }` from a child method passes a literal block
      # to the parent. Pre-fix the parser dropped ForwardingSuperNode's block
      # field and compile_super_expr emitted `sp_Parent_test((sp_Parent*)self)`
      # which type-checked one arg against a 3-arg signature
      # `(self, _block, _benv)` and failed at C compile. The fix wires the
      # block through the parser, then inlines the parent body in place of
      # the call (mirroring compile_yield_call_expr) so `yield` inside the
      # parent body becomes the literal block body.
      class T_super_with_block_Parent
        def test
          yield
        end
      end

      class T_super_with_block_Child < T_super_with_block_Parent
        def test
          super { puts "from child" }
        end
      end

      T_super_with_block_Child.new.test
    RUBY

    _(result).must_answer "from child\n"
  end

  it "sym keyed hash ivar value" do
    result = ze0(<<~'RUBY')
      # Issue #415. A `{ sym_key: <ivar-or-param> }` hash literal whose
      # values are NOT string literals -- ivars, params, method-call
      # results -- compiled to a C reference of `sp_SymStrHash *` without
      # the matching typedef + helpers in the same translation unit, so
      # the cc step failed with "unknown type name 'sp_SymStrHash'".
      #
      # Root cause: `infer_hash_val_type` returned the inferred hash
      # variant string ("sym_str_hash" etc.) without flagging the
      # template-instantiation need, so `@needs_sym_str_hash` stayed at
      # 0 and `emit_hash_runtime` skipped the typedef. The string-literal
      # case happened to work because a separate write path through
      # `compose_hash_type` flagged it via that route.
      #
      # Fix: route `infer_hash_val_type`'s return value through
      # `mark_hash_needs` so every observed hash variant flags its
      # template need, regardless of whether the values are literals.
      #
      # Coverage:
      #   - sym_str_hash from an ivar value (the canonical issue shape).
      #   - sym_str_hash from a method param (same gap, different write).
      #   - mixed-shape attributes hash with a method-call value (proves
      #     the path also reaches through CallNode-typed values).

      class T_sym_keyed_hash_ivar_value_Foo
        attr_reader :title

        def initialize
          @title = "hello"
        end

        def attributes
          { title: @title }
        end

        def with_extra(more)
          { title: @title, extra: more }
        end
      end

      f = T_sym_keyed_hash_ivar_value_Foo.new
      puts f.attributes[:title]       # hello
      puts f.with_extra("world")[:extra]  # world

      class T_sym_keyed_hash_ivar_value_Bar
        def initialize
          @body = "lorem"
        end

        def to_h
          { body: @body, len: @body.length.to_s }
        end
      end

      b = T_sym_keyed_hash_ivar_value_Bar.new
      puts b.to_h[:body]              # lorem
      puts b.to_h[:len]               # 5
    RUBY

    _(result).must_answer <<~'OUT'
      hello
      world
      lorem
      5
    OUT
  end

  it "symbol ivar reassign" do
    result = ze0(<<~'RUBY')
      # Reassigning an instance variable to a different symbol used to demote
      # its type to `poly` because `infer_ivar_init_type` reported `:foo` as
      # `string` while `infer_type` reported it as `symbol`. The mismatch
      # tripped `update_ivar_type`'s "old != new_type" branch, widening the
      # field to `sp_RbVal`. Subsequent assignments emitted `self->s = SPS_bar`
      # (sp_sym = mrb_int) into an `sp_RbVal` slot — a T_symbol_ivar_reassign_C type error.

      class T_symbol_ivar_reassign_C
        def initialize
          @s = :foo
        end

        def reset
          @s = :bar
        end

        def show
          @s
        end
      end

      c = T_symbol_ivar_reassign_C.new
      puts c.show
      c.reset
      puts c.show
    RUBY

    _(result).must_answer "foo\nbar\n"
  end

  it "unbox poly index in dispatch" do
    result = ze0(<<~'RUBY')
      # `emit_poly_builtin_dispatch` referenced `arg_types` out of scope.
      # Without the fix, `(poly_recv)[poly_idx]` produced
      # `sp_PolyArray_get(arr, sp_RbVal_idx)` — passing sp_RbVal where
      # mrb_int is expected and failing the T_unbox_poly_index_in_dispatch_C compile.
      #
      # Trigger: poly recv (from heterogeneous Hash) + poly idx (also).

      class T_unbox_poly_index_in_dispatch_C
        def initialize
          @bag  = { "arr" => [100, 200, 300, 400], "lbl" => "x" }
          @keys = { "i" => 2, "s" => "lbl" }
        end
        def at(k)
          arr = @bag["arr"]      # poly
          idx = @keys[k]         # poly
          arr[idx]               # poly recv + poly idx
        end
      end

      puts T_unbox_poly_index_in_dispatch_C.new.at("i").to_s    # use .to_s (handled separately) instead of .to_i
    RUBY

    _(result).must_answer "300\n"
  end

  it "uncalled method dce" do
    result = ze0(<<~'RUBY')
      # Issue #393. An uncalled `def f(x); @typed = x; end` whose param
      # defaulted to `mrb_int` (no caller pinned the type) tripped a T_uncalled_method_dce_C
      # type mismatch against a narrower ivar slot like `const char *`.
      #
      # Fix: instance methods not reachable from any call site / SymbolNode
      # / `super` get a stub body (`(void)params; return default;`).
      # `initialize` and operator / conversion methods (`<=>`, `[]`, `to_s`,
      # etc.) are always live regardless.

      class T_uncalled_method_dce_C
        def initialize
          @body = ""
        end

        # Never called. Param defaults to mrb_int; @body is const char *.
        # Pre-fix: emit assigns `self->iv_body = lv_html` -- type mismatch.
        # Post-fix: body becomes `(void)lv_html; return 0;`.
        def render(html)
          @body = html
        end
      end

      c = T_uncalled_method_dce_C.new
      puts "ok"
    RUBY

    _(result).must_answer "ok\n"
  end

  it "undef" do
    result = ze0(<<~'RUBY')
      # UndefNode -- `undef foo` inside a class body.
      #
      # CRuby raises NoMethodError if the undef'd method is called. In
      # Spinel's AOT model we cannot dispatch at runtime (methods are
      # static T_undef_C functions resolved at compile time), so `undef foo`
      # becomes a compile-time error: any call to `.foo` on an instance
      # of this class fails to compile with a precise message.
      #
      # This test verifies that defining + calling another method on the
      # same class still works after undef -- undef removes only the
      # named method, not the whole class.

      class T_undef_C
        def foo = "foo"
        def bar = "bar"
        undef foo
      end

      c = T_undef_C.new
      puts c.bar     # bar

      # Multi-name form: `undef foo, bar` exercises the names-array path in
      # spinel_parse.c (PM_UNDEF_NODE emits `names` as A(...)). Defining a
      # third method `baz` and undef'ing the other two verifies that exactly
      # the named methods are removed.
      class T_undef_D
        def foo = "foo"
        def bar = "bar"
        def baz = "baz"
        undef foo, bar
      end

      puts T_undef_D.new.baz # baz
    RUBY

    _(result).must_answer "bar\nbaz\n"
  end

  it "uninit attr accessor reads as nil" do
    result = ze0(<<~'RUBY')
      # `attr_accessor :foo` with no `initialize`-time assignment must
      # read as nil before any write. Pre-fix spinel registered the
      # slot as the "int" placeholder, so the unset read returned 0
      # (the type's zero) and downstream `"[#{a.counter}]"` rendered
      # `[0]` instead of MRI's `[]`. Issue #634 shape B.
      #
      # The widening fires only when (a) the ivar is exposed via
      # attr_reader / attr_accessor, (b) no method body assigns it,
      # and (c) no writer call site has been observed during the
      # iterative inference loop. T_uninit_attr_accessor_reads_as_nil_A class whose `reset` method writes
      # the slot (optcarrot's APU oscillators) keeps the typed slot;
      # `b.counter = 0` on a sibling instance also keeps the typed
      # slot, but the uninitialized `a.counter` read on a fresh
      # `T_uninit_attr_accessor_reads_as_nil_A.new` still returns nil through the per-instance poly
      # storage.

      class T_uninit_attr_accessor_reads_as_nil_A
        attr_accessor :counter
      end

      a = T_uninit_attr_accessor_reads_as_nil_A.new
      puts "[#{a.counter}]"

      b = T_uninit_attr_accessor_reads_as_nil_A.new
      b.counter = 0
      puts "[#{b.counter}]"

      # Shape with attr_reader-only (no writer at all).
      class T_uninit_attr_accessor_reads_as_nil_Box
        attr_reader :tag
      end

      box = T_uninit_attr_accessor_reads_as_nil_Box.new
      puts "tag=[#{box.tag}]"
    RUBY

    _(result).must_answer <<~'OUT'
      []
      [0]
      tag=[]
    OUT
  end

  it "user cmp int ivars" do
    result = ze0(<<~'RUBY')
      # Issue #399: a user-defined `def <=>(other)` whose body calls
      # `<=>` on Integer ivars (`@n <=> other.n`) lowered to a recursive
      # call to the user's own `<=>` method (passing the int receivers
      # cast to `sp_V *`). Type error + would-be infinite recursion.
      #
      # Fix: compile_int_method_expr now has a `<=>` arm that emits the
      # standard 3-way compare for int-vs-int (and int-vs-float). Plus
      # `<=>` is added to is_primitive_shared_method so the int-recv
      # fallback at compile_call_expr's tail doesn't pick a user class.

      class T_user_cmp_int_ivars_V
        attr_reader :n
        def initialize(n)
          @n = n
        end

        def <=>(other)
          @n <=> other.n
        end
      end

      a = T_user_cmp_int_ivars_V.new(1)
      b = T_user_cmp_int_ivars_V.new(2)
      c = T_user_cmp_int_ivars_V.new(2)

      puts (a <=> b).to_s   # -1
      puts (b <=> a).to_s   # 1
      puts (b <=> c).to_s   # 0

      # Standalone `==` falls back to identity, which doesn't help here;
      # the issue is just the recursion inside `<=>`. Spinel's Comparable
      # include path is a separate feature.
    RUBY

    _(result).must_answer <<~'OUT'
      -1
      1
      0
    OUT
  end

  it "user method named like mutator" do
    result = ze0(<<~'RUBY')
      # compile_body_return treats certain method names (`update`, `clear`,
      # `concat`, `delete`, `each`, `pop`, `push`, `merge!`, ...) as
      # statement-only because Hash and Array mutators are conventionally
      # called for side-effect. That's right when the receiver IS a Hash
      # or Array, but it silently throws away the value when a user class
      # happens to define a method with one of those names — including the
      # implicit `self.update(...)` form, since the receiver chain isn't
      # even consulted before the name match fires.
      #
      # Pre-fix, `T_user_method_named_like_mutator_C.new.f(7)` returned 0 (correct: 8) and
      # `T_user_method_named_like_mutator_D.new.run(T_user_method_named_like_mutator_C.new)` returned 0 (correct: 30). Both follow Ruby
      # semantics now.

      class T_user_method_named_like_mutator_C
        def update(target)
          target
        end
        def f(n)
          update(n + 1)   # implicit self.update — was discarded
        end
      end

      class T_user_method_named_like_mutator_D
        def run(c)
          c.update(30)    # explicit recv on user class — was discarded
        end
      end

      puts T_user_method_named_like_mutator_C.new.f(7)
      puts T_user_method_named_like_mutator_D.new.run(T_user_method_named_like_mutator_C.new)
    RUBY

    _(result).must_answer "8\n30\n"
  end

  it "value type constructor arg gc root" do
    result = ze0(<<~'RUBY')
      class T_value_type_constructor_arg_gc_root_NameTag
        attr_reader :present, :text

        def initialize(present, text)
          @present = present
          @text = text
        end
      end

      class T_value_type_constructor_arg_gc_root_Payload
      end

      class T_value_type_constructor_arg_gc_root_Wrapper
        attr_reader :tag, :payload

        def initialize(tag, payload)
          @tag = tag
          @payload = payload
        end

        def self.for_tag(tag)
          junk = []
          i = 0
          while i < 50
            junk << "junk" + i.to_s
            i = i + 1
          end

          T_value_type_constructor_arg_gc_root_Wrapper.new(tag, T_value_type_constructor_arg_gc_root_Payload.new)
        end
      end

      wrapper = nil
      i = 0
      while i < 2000
        wrapper = T_value_type_constructor_arg_gc_root_Wrapper.for_tag(T_value_type_constructor_arg_gc_root_NameTag.new(1, "label" + i.to_s))
        i = i + 1
      end

      puts wrapper.tag.text
    RUBY

    _(result).must_answer "label1999\n"
  end

  it "value type ctor gc save" do
    result = ze0(<<~'RUBY')
      # A value-type constructor body that introduces a GC-managed local
      # (here `arr`, an int_array) needs `SP_GC_SAVE()` paired with the
      # `SP_GC_ROOT(lv_arr)` that `declare_method_locals` emits.
      #
      # `emit_constructor` only emits SP_GC_SAVE for the non-value-type
      # branch. For value types it leaves `@in_gc_scope` whatever the
      # *previous* method left it as. If the previous method was a
      # non-value class's body (which sets `@in_gc_scope = 1`), the
      # inherited scope made `declare_method_locals` skip its SP_GC_SAVE
      # and the value-type ctor emitted an unbalanced SP_GC_ROOT —
      # pushing a stack pointer that becomes dangling on return.
      #
      # Reproducer: T_value_type_ctor_gc_save_Foo (heap class) is compiled before T_value_type_ctor_gc_save_Vec (value type),
      # so without the fix Vec_new's lv_arr root gets pushed without a
      # matching save. The fix resets `@in_gc_scope = 0` at the value-
      # type ctor entry so declare_method_locals emits SP_GC_SAVE.

      class T_value_type_ctor_gc_save_Foo
        def make
          [1, 2, 3]
        end
      end

      class T_value_type_ctor_gc_save_Vec
        attr_reader :sum
        def initialize(x, y)
          arr = [x, y, x + y]
          @sum = arr[2]
        end
      end

      f = T_value_type_ctor_gc_save_Foo.new
      puts f.make.length            # 3
      v = T_value_type_ctor_gc_save_Vec.new(3, 4)
      puts v.sum                    # 7

      # Many ctor calls so the unbalanced ROOTs would saturate
      # sp_gc_nroots if they weren't matched by SP_GC_RESTORE.
      sum = 0
      i = 0
      while i < 200
        vv = T_value_type_ctor_gc_save_Vec.new(i, i + 1)
        sum = sum + vv.sum
        i = i + 1
      end
      puts sum                       # 200 * (i + (i+1)) summed = sum of (2i+1) for i=0..199 = 200*200 = 40000
    RUBY

    _(result).must_answer <<~'OUT'
      3
      7
      40000
    OUT
  end

  it "value type ivar gc scan" do
    result = ze0(<<~'RUBY')
      class T_value_type_ivar_gc_scan_NameTag
        attr_reader :text

        def initialize(text)
          @text = text
        end
      end

      class T_value_type_ivar_gc_scan_Payload
      end

      class T_value_type_ivar_gc_scan_Wrapper
        attr_reader :tag, :payload

        def initialize(tag, payload)
          @tag = tag
          @payload = payload
        end
      end

      wrappers = []
      i = 0
      while i < 2000
        wrappers << T_value_type_ivar_gc_scan_Wrapper.new(T_value_type_ivar_gc_scan_NameTag.new("label" + i.to_s), T_value_type_ivar_gc_scan_Payload.new)
        i = i + 1
      end

      junk = []
      i = 0
      while i < 5000
        junk << "garbage" + i.to_s
        i = i + 1
      end

      puts wrappers[1999].tag.text
    RUBY

    _(result).must_answer "label1999\n"
  end

  it "value type recycled field clear" do
    result = ze0(<<~'RUBY')
      class T_value_type_recycled_field_clear_NameTag
        attr_reader :text

        def initialize(text)
          @text = text
        end
      end

      class T_value_type_recycled_field_clear_Holder
        attr_reader :tag, :junk

        def initialize(tag)
          @junk = []
          @tag = tag
        end
      end

      i = 0
      while i < 3000
        T_value_type_recycled_field_clear_Holder.new(T_value_type_recycled_field_clear_NameTag.new("old" + i.to_s))
        i = i + 1
      end

      junk = []
      i = 0
      while i < 5000
        junk << "garbage" + i.to_s
        i = i + 1
      end

      holder = nil
      i = 0
      while i < 3000
        holder = T_value_type_recycled_field_clear_Holder.new(T_value_type_recycled_field_clear_NameTag.new("new" + i.to_s))
        i = i + 1
      end

      puts holder.tag.text
    RUBY

    _(result).must_answer "new2999\n"
  end

  it "volatile discarded at call" do
    result = ze0(<<~'RUBY')
      # #487. Top-level begin/rescue sets @needs_setjmp = 1, which emits
      # every main() local as `volatile T *`. Passing such a local to a
      # function expecting plain `T *` triggers gcc's
      # -Wdiscarded-qualifiers / clang's
      # -Wincompatible-pointer-types-discards-qualifiers. The program
      # still runs correctly (volatile is strictly stronger than what the
      # callee asks for); the fix casts away the qualifier at the call
      # site so clean builds under -Wall stay green.

      class T_volatile_discarded_at_call_M
        def self.read(env)
          env["k"]
        end
      end

      env = { "k" => "v" }
      begin
        puts T_volatile_discarded_at_call_M.read(env)
      rescue
        puts "rescued"
      end
    RUBY

    _(result).must_answer "v\n"
  end

  it "while cond side effect" do
    result = ze0(<<~'RUBY')
      # #500. `while (n = gets.to_i) > 0` looped forever because codegen
      # emitted `_t1 = sp_gets(); SP_GC_ROOT(_t1);` BEFORE the while line,
      # so every iteration re-read the same captured first line. Fix:
      # compile the predicate into a scratch buffer and replay its
      # emits inside `while (1) { ...; if (!cond) break; ... }` so any
      # transient temp/root tied to the receiver call lives per-iter.
      #
      # Test uses an instance method returning a String — `.to_i` then
      # routes through compile_expr_gc_rooted's hoist for the heap-
      # allocated receiver. Stdin gets isn't reachable from the test
      # harness, so we drive the same code path via an iterator class.

      class T_while_cond_side_effect_Source
        def initialize
          @data = ["5", "4", "3", "0"]
          @idx = 0
        end

        def next_line
          s = @data[@idx]
          @idx += 1
          s
        end
      end

      src = T_while_cond_side_effect_Source.new
      count = 0
      while (n = src.next_line.to_i) > 0
        count += 1
      end
      puts count
    RUBY

    _(result).must_answer "3\n"
  end

  it "while condition recomputed" do
    result = ze0(<<~'RUBY')
      # A while condition that depends on a mutated receiver must be evaluated on
      # every iteration.

      items = [1, 2, 3]
      sum = 0

      while items.length > 0
        item = items.pop
        sum += item
      end

      puts sum
      puts items.length

      items2 = [4, 5, 6]
      sum2 = 0

      while items2.length > 0
        sum2 += items2.pop
      end

      puts sum2
      puts items2.length

      items3 = [7, 8, 9]
      packed = 0

      while items3.length != 0
        packed = packed * 10 + items3.shift
      end

      puts packed
      puts items3.length

      class T_while_condition_recomputed_IvarDrain
        def initialize
          @items = [10, 20, 30]
        end

        def drain
          sum = 0
          while @items.length > 0
            sum += @items.pop
          end
          sum
        end

        def remaining
          @items.length
        end
      end

      drain = T_while_condition_recomputed_IvarDrain.new
      puts drain.drain
      puts drain.remaining
    RUBY

    _(result).must_answer <<~'OUT'
      6
      0
      15
      0
      789
      0
      60
      0
    OUT
  end

  it "widen int obj to poly" do
    result = ze0(<<~'RUBY')
      # When an ivar's first observed write is a definite int / nil
      # literal and a later write assigns an obj-typed value, the slot
      # was overwritten with the obj type — silently casting the prior
      # int payload to a struct pointer. Subsequent dispatch through
      # the slot then read garbage or computed pointer arithmetic.
      #
      # Widening to poly so the slot carries either case at runtime
      # preserves the program's actual semantics: the dispatch path
      # decides per cls_id at the call site.

      class T_widen_int_obj_to_poly_Box
        def initialize(n)
          @n = n
          @arr = []
          @arr << n
        end
        attr_reader :n
      end

      class T_widen_int_obj_to_poly_Holder
        def initialize
          @poly = 10              # definite int first
          @poly = T_widen_int_obj_to_poly_Box.new(5)      # …then obj — slot widens to poly
        end
        attr_reader :poly
      end

      # poly recv → T_widen_int_obj_to_poly_Box#n via cls_id == T_widen_int_obj_to_poly_Box dispatch
      puts T_widen_int_obj_to_poly_Holder.new.poly.n      # 5
    RUBY

    _(result).must_answer "5\n"
  end

  it "Kernel#rand truncates a Float bound to an Integer draw" do
    result = ze0(<<~'RUBY')
      p rand(3.5).class
      p (0...3).include?(rand(3.5))
    RUBY

    _(result).must_answer "Integer\ntrue\n"
  end

  it "sort_by over a Hash orders by a two-element key" do
    result = ze0(<<~'RUBY')
      counts = Hash.new(0)
      counts["the"] = 3
      counts["dog"] = 1
      ranked = counts.sort_by { |w, n| [-n, w] }
      ranked.first(2).each { |w, n| puts "#{w}: #{n}" }
    RUBY

    _(result).must_answer "the: 3\ndog: 1\n"
  end

  it "a class held in a Hash value constructs and dispatches through the lookup" do
    result = ze0(<<~'RUBY')
      class Circle
        def initialize(r) = @r = r
        def area = 3.14 * @r * @r
      end
      class Square
        def initialize(s) = @s = s
        def area = @s * @s
      end
      REG = { "c" => Circle, "s" => Square }
      p REG["c"].new(2).area
      p REG["s"].new(3).area
      %w[c s].each { |k| p REG[k].new(4).area }
    RUBY

    _(result).must_answer <<~'OUT'
      12.56
      9
      50.24
      16
    OUT
  end

  it "group_by keys the groups by the block's value" do
    result = ze0(<<~'RUBY')
      class Graph
        def key(x) = x % 3
        def buckets = (0...6).group_by { |x| key(x) }
      end
      p Graph.new.buckets
      p (0...6).group_by { |x| x % 3 }
      p %w[a bb ccc dd].group_by { |s| s.length }
    RUBY

    _(result).must_answer <<~'OUT'
      {0 => [0, 3], 1 => [1, 4], 2 => [2, 5]}
      {0 => [0, 3], 1 => [1, 4], 2 => [2, 5]}
      {1 => ["a"], 2 => ["bb", "dd"], 3 => ["ccc"]}
    OUT
  end

  it "an Array is a Hash key by value, and [1] and [1.0] are two keys" do
    result = ze0(<<~'RUBY')
      counts = Hash.new(0)
      [0].product([0]).each { |k| counts[k] += 1 }
      p counts[[0, 0]]

      grid = Hash.new(0)
      [1, 2].product([3, 4]).each { |pair| grid[pair] += 1 }
      p grid[[1, 4]]
      p grid[[2, 3]]

      # eql? strictness preserved: [1] and [1.0] are distinct keys
      h = {}
      h[[1]] = "int"
      h[[1.0]] = "float"
      p h.size
    RUBY

    _(result).must_answer <<~'OUT'
      1
      1
      1
      2
    OUT
  end

  it "an empty Range#sum with a block answers the block's zero, not an integer one" do
    result = ze0(<<~'RUBY')
      # An empty `Range#sum { block }` whose block value is poly (a product of
      # values read from nested poly containers) must accumulate via the block, not
      # drop it and emit a block-less int-array sum.
      aug = [[2.0, 3.0, 0.0]]
      x = Array.new(1, 0.0)
      s = (1...1).sum { |j| aug[0][j] * x[j] }
      x[0] = (aug[0][1] - s) / aug[0][0]
      p x
      # non-empty poly-block range sum
      t = (0...2).sum { |j| aug[0][j] * 2 }
      p t
    RUBY

    _(result).must_answer "[1.5]\n10.0\n"
  end

  it "sum with a block over objects rounds to the places asked for" do
    result = ze0(<<~'RUBY')
      # An object whose ivar comes from a destructured-pair block param, summed via a
      # block and rounded (Refs #2913 sum, #2926 round).
      class Shape
        def initialize(s) = @s = s
        def area = @s * 3.14
      end

      shapes = [["a", 2], ["b", 3]].map { |_, s| Shape.new(s) }
      p shapes.sum { |x| x.area }.round(2)
    RUBY

    _(result).must_answer "15.7\n"
  end

  it "attr defines the reader alone" do
    result = ze0(<<~'RUBY')
      class C001
        attr :x
        def initialize; @x = 5; end
      end
      p(C001.new.x)
    RUBY

    _(result).must_answer "5\n"
  end

  it "a class object is not frozen" do
    result = ze0(<<~'RUBY')
      class C001; end
      p(C001.frozen?)
    RUBY

    _(result).must_answer "false\n"
  end

  it "instance_exec passes its arguments to a BasicObject's block" do
    result = ze0(<<~'RUBY')
      class BO < BasicObject
        def initialize; @x = 0; end
      end
      b001 = BO.new; p(b001.instance_exec(1, 2, 3) { |*xs| xs })
      b002 = BO.new; p(b002.instance_exec(9) { |*xs| xs })
      b003 = BO.new; p(b003.instance_exec(2, 3) { |a, *rest| [a, rest] })
      b004 = BO.new; p(b004.instance_exec { |*xs| xs })
    RUBY

    _(result).must_answer <<~'OUT'
      [1, 2, 3]
      [9]
      [2, [3]]
      []
    OUT
  end

  it "the Integer methods answer for a bignum argument" do
    result = ze0(<<~'RUBY')
      b = 2 ** 70
      p 5.pow(3, b).class
      p 255.digits(b).class
      p 12.gcd(b).class
      p 12.lcm(b).class
      p 5.clamp(0, b)
      p 5.coerce(b).class
      p 255[b]
      p 1.step(b, 10 ** 20).first(2)
      p 1.step(10, 3).to_a
    RUBY

    _(result).must_answer <<~'OUT'
      Integer
      Array
      Integer
      Integer
      5
      Array
      0
      [1, 100000000000000000001]
      [1, 4, 7, 10]
    OUT
  end

  it "Object#<=> answers 0 for itself and nil for another" do
    result = ze0(<<~'RUBY')
      o = Object.new
      p(o <=> o)
      p(o <=> Object.new)
      p(o == o)
      a = "x"
      b = "y"
      p(a <=> b)
      p([1,2] <=> [1,2])
      class C; end
      c = C.new
      p(c <=> c)
      p(c <=> C.new)
    RUBY

    _(result).must_answer <<~'OUT'
      0
      nil
      true
      -1
      0
      0
      nil
    OUT
  end

  it "=== falls through to ==, and a class may define its own" do
    result = ze0(<<~'RUBY')
      class Point
        def initialize(x); @x = x; end
      end
      a = Point.new(1)
      b = Point.new(1)
      p(a === b)
      p(a === a)
      class Eq
        def initialize(v); @v = v; end
        def ==(o); o.is_a?(Eq) && o.val == @v; end
        def val; @v; end
      end
      p(Eq.new(3) === Eq.new(3))
      class Own
        def ===(o); "custom"; end
      end
      p(Own.new === 1)
    RUBY

    _(result).must_answer <<~'OUT'
      false
      true
      true
      "custom"
    OUT
  end

  it "Interrupt descends from SignalException, not from StandardError" do
    result = ze0(<<~'RUBY')
      p Interrupt.new.class.superclass
      p Interrupt.new.class.ancestors
      p RuntimeError.new.class.superclass
      p RuntimeError.new.class.ancestors
    RUBY

    _(result).must_answer <<~'OUT'
      SignalException
      [Interrupt, SignalException, Exception, Object, Kernel, BasicObject]
      StandardError
      [RuntimeError, StandardError, Exception, Object, Kernel, BasicObject]
    OUT
  end

  it "ScriptError and SystemExit are Exceptions but not StandardErrors" do
    result = ze0(<<~'RUBY')
      e = LocalJumpError.new("no block given")
      p e.class
      p e.message
      p e.is_a?(StandardError)
      p e.is_a?(Exception)
      s = ScriptError.new("y")
      p s.class
      p s.is_a?(Exception)
      p s.is_a?(StandardError)
      x = SystemExit.new
      p x.is_a?(Exception)
      p x.is_a?(StandardError)
    RUBY

    _(result).must_answer <<~'OUT'
      LocalJumpError
      "no block given"
      true
      true
      ScriptError
      true
      false
      true
      false
    OUT
  end

  it "NoMethodError carries the arguments the call was made with" do
    result = ze0(<<~'RUBY')
      e = NoMethodError.new("msg", :meth, [1, 2])
      p e.args
      p e.name
      p e.message
      e2 = NoMethodError.new("m2", :other)
      p e2.name
      n = NameError.new("nm", :sym)
      p n.name
    RUBY

    _(result).must_answer <<~'OUT'
      [1, 2]
      :meth
      "msg"
      :other
      :sym
    OUT
  end

  it "Random#rand answers an Integer for a bignum bound" do
    result = ze0(<<~'RUBY')
      r = Random.new(5)
      p r.rand(2 ** 70).class
      p r.rand(2 ** 70) >= 0
      p r.rand(100).class
      p rand(2 ** 70).class
    RUBY

    _(result).must_answer <<~'OUT'
      Integer
      true
      Integer
      Integer
    OUT
  end

  it "select and reject with no block answer an Enumerator" do
    result = ze0(<<~'RUBY')
      x = (1..3).select
      p x.class
      p x.next
      p [1, 2, 3].select.class
      p [1, 2, 3].reject.class
      p((1..3).select { |i| i.odd? })
      p((1..3).reject { |i| i.odd? })
      p [1, 2, 3].select.with_index { |v, i| i > 0 }
    RUBY

    _(result).must_answer <<~'OUT'
      Enumerator
      1
      Enumerator
      Enumerator
      [1, 3]
      [2]
      [2, 3]
    OUT
  end

  it "a String range answers every Range method a numeric one does" do
    result = ze0(<<~'RUBY')
      a = ("a".."e")
      p a.class
      p a.to_s
      p a.inspect
      p a.begin
      p a.end
      p a.first
      p a.last
      p a.exclude_end?
      p a.to_a
      p a.size
      p a.include?("c")
      p a.include?("z")
      p a === "c"
      p a.cover?(5)
      p a.map { |s| s.upcase }
      p a.select { |s| s < "c" }
      p a.count { |s| s < "c" }
      p a.first(2)
      p a == ("a".."e")
      p a == ("a"..."e")
      b = ("a"..."d")
      p b.to_a
      p b.inspect
      p ("a".."e").to_s
      p [*"a".."c"]
    RUBY

    _(result).must_answer <<~'OUT'
      Range
      "a..e"
      "\"a\"..\"e\""
      "a"
      "e"
      "a"
      "e"
      false
      ["a", "b", "c", "d", "e"]
      nil
      true
      false
      true
      false
      ["A", "B", "C", "D", "E"]
      ["a", "b"]
      2
      ["a", "b"]
      true
      false
      ["a", "b", "c"]
      "\"a\"...\"d\""
      "a..e"
      ["a", "b", "c"]
    OUT
  end

  it "a method added to String reaches every string, however the string was built" do
    result = ze0(<<~'RUBY')
      class String
        def shout
          upcase + "!"
        end
      end
      puts "hello".shout
      s = String.new
      s << "world"
      puts s.shout
      puts s
      t = String.new("abc")
      puts t.shout

      # a plain user class still constructs normally
      class Point
        def initialize(x); @x = x; end
        def x; @x; end
      end
      p Point.new(5).x

      # a reopened Array still uses the builtin constructor
      class Array
        def tag; "arr"; end
      end
      a = Array.new(3, 0)
      a << 9
      p a
      p [1, 2].tag
    RUBY

    _(result).must_answer <<~'OUT'
      HELLO!
      WORLD!
      world
      ABC!
      5
      [0, 0, 0, 9]
      "arr"
    OUT
  end

  it "the Integer methods answer for a bignum receiver" do
    result = ze0(<<~'RUBY')
      b = 2 ** 80
      p b[3]
      p b[79]
      p b.coerce(5).class
      p b.clamp(0, 10)
      p (2 ** 70).clamp(0, 2 ** 90).class
      p (2 ** 80).coerce(5)
      p (-(2 ** 80))[0]
    RUBY

    _(result).must_answer <<~'OUT'
      0
      0
      Array
      10
      Integer
      [5, 1208925819614629174706176]
      0
    OUT
  end

  it "reading a StringIO's string between writes does not disturb the buffer" do
    result = ze0(<<~'RUBY')
      require "stringio"
      5.times do
        buf = StringIO.new
        19.times { |i| buf << ("a".."z").to_a[i] }
        _ = buf.string
        19.times { |i| buf << ("a".."z").to_a[i] }
      end
      puts "ok"
    RUBY

    _(result).must_answer "ok\n"
  end

  it "a method that writes through an Array.new block's array is seen by the caller" do
    result = ze0(<<~'RUBY')
      def setit(arr, i)
        arr[i] = 99
      end
      a = Array.new(4) { |i| i }
      setit(a, 1)
      p a

      def bump(arr)
        arr.each_index { |k| arr[k] += 1 }
      end
      b = Array.new(3) { |i| i * 10 }
      bump(b)
      p b

      # element type still narrows correctly for a plain-literal-element block
      def push_it(arr)
        arr << 5
      end
      c = Array.new(2) { [] }
      push_it(c)
      p c
    RUBY

    _(result).must_answer <<~'OUT'
      [0, 99, 2, 3]
      [1, 11, 21]
      [[], [], 5]
    OUT
  end

  it "rjust, ljust and center take a width that is only known at run time" do
    result = ze0(<<~'RUBY')
      # rjust/ljust/center with a dynamically-typed width (Hash#keys.max -> poly)
      counts = Hash.new(0)
      counts[1] = 1; counts[4] = 1
      w = counts.keys.max
      p "x".rjust(w)
      p "y".ljust(w)
      p "z".center(w)
      p "ab".rjust(w, "*")
      p "cd".ljust(w, "-")
      # static int width still works
      p "s".rjust(5)
      p "t".ljust(5, ".")
    RUBY

    _(result).must_answer <<~'OUT'
      "   x"
      "y   "
      " z  "
      "**ab"
      "cd--"
      "    s"
      "t...."
    OUT
  end

  it "a Set stored as a Hash value takes writes through the lookup" do
    result = ze0(<<~'RUBY')
      require 'set'
      h = { a: Set.new }
      h[:a] << 1
      p h[:a].to_a
      adj = Hash.new { |hh, k| hh[k] = Set.new }
      adj[:x] << 1
      adj[:x] << 2
      adj[:y] << 3
      p adj[:x].to_a.sort
      p adj[:y].to_a
    RUBY

    _(result).must_answer <<~'OUT'
      [1]
      [1, 2]
      [3]
    OUT
  end

  it "a matrix product built from zip and sum with a block" do
    result = ze0(<<~'RUBY')
      a = [[1, 2, 3], [4, 5, 6]]
      b = [[7, 8], [9, 10], [11, 12]]
      result = Array.new(a.size) { Array.new(b.first.size, 0) }
      a.each_with_index do |row, i|
        b.transpose.each_with_index do |col, j|
          result[i][j] = row.zip(col).sum { |x, y| x * y }
        end
      end
      p result
    RUBY

    _(result).must_answer "[[58, 64], [139, 154]]\n"
  end

  it "trailing keyword arguments arrive as a Hash where the method wants one" do
    result = ze0(<<~'RUBY')
      class V
        def run(data); "#{data[:age]}/#{data.size}"; end
        def kw(name:, age: 0); "#{name}:#{age}"; end
        def mixed(x, opts); "#{x}|#{opts[:k]}"; end
      end
      v = V.new
      p v.run(age: 5, city: "x")
      p v.kw(name: "a", age: 3)
      p v.mixed(1, k: 9)
      p v.run({age: 7})
    RUBY

    _(result).must_answer <<~'OUT'
      "5/2"
      "a:3"
      "1|9"
      "7/1"
    OUT
  end

  it "a method writes to a global Hash and the caller sees it" do
    result = ze0(<<~'RUBY')
      $wifis = Hash.new
      class Client
        def run
          $wifis["test"] = "value"
        end
      end
      Client.new.run
      p $wifis
    RUBY

    _(result).must_answer "{\"test\" => \"value\"}\n"
  end

  it "a Method object stored in a container still calls and reports its arity" do
    result = ze0(<<~'RUBY')
      def square(x) = x * x
      arr = [method(:square)]
      m = arr[0]
      p m.call(9)
      p m.arity
      h = { sq: method(:square) }
      p h[:sq].call(6)
      def g(a, *b) = a
      gm = [method(:g)][0]
      p gm.arity
      p gm.call(1, 2, 3)
      class C
        def dbl(x) = x + x
      end
      cm = [C.new.method(:dbl)][0]
      p cm.call(21)
    RUBY

    _(result).must_answer <<~'OUT'
      81
      1
      36
      -2
      1
      42
    OUT
  end

  it "Kernel#loop with no block answers an endless Enumerator of nil" do
    result = ze0(<<~'RUBY')
      # Blockless Kernel#loop returns an infinite Enumerator (yields nil).
      e = loop
      p e.class
      p loop.first(3)
      p loop.take(2)
      e2 = loop
      p e2.next
      p e2.next
    RUBY

    _(result).must_answer <<~'OUT'
      Enumerator
      [nil, nil, nil]
      [nil, nil]
      nil
      nil
    OUT
  end

  it "a cloned or duped Method calls the method it came from" do
    result = ze0(<<~'RUBY')
      def dbl(n) = n * 2
      p(method(:dbl).clone.call(5))
      p(method(:dbl).dup.call(5))
      m = method(:dbl); c = m.clone; p c.call(5)
      p(method(:dbl).call(7))
      class K
        def tw(x) = x + x
      end
      mm = K.new.method(:tw)
      p(mm.clone.call(8))
      p(mm.dup.call(9))
    RUBY

    _(result).must_answer <<~'OUT'
      10
      10
      10
      14
      16
      18
    OUT
  end

  it "a multiple assignment in initialize sets every ivar it names" do
    result = ze0(<<~'RUBY')
      class MyClass
        def initialize
          @foo, @bar = nil, nil
          @x, @y = 1, 2
        end
        def vals = [@foo, @bar, @x, @y]
      end
      p MyClass.new.vals

      class C2
        def initialize
          @a, @b, @c = "p", "q", "r"
        end
        def read = [@a, @b, @c]
      end
      p C2.new.read
    RUBY

    _(result).must_answer <<~'OUT'
      [nil, nil, 1, 2]
      ["p", "q", "r"]
    OUT
  end
end
