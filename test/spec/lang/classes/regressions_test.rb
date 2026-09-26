# frozen_string_literal: true

require "spec_helper"

describe "Classes: regressions" do
  it "array plus" do
    result = zr(<<~'RUBY')
      # Array#+ joins two mixed Arrays, and two Arrays of user objects.

      # mixed element classes
      a = [1, "x"]
      b = [2, "y"]
      puts (a + b).length

      # user objects
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

  it "chained or assign collection str keys" do
    result = zr(<<~'RUBY')
      # Same chained `||=`, but on a Hash with String keys.

      class T_chained_or_assign_collection_str_keys_C
        def initialize
          @h = {}
          @h["init"] = []      # a String key with an Array value
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
    result = zr(<<~'RUBY')
      # `@@x op= rhs` works as `@@x = @@x op rhs`. `&&=` on a class variable
      # works too.

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

  it "ensure raise overrides body raise" do
    result = zr(<<~'RUBY')
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
    result = zr(<<~'RUBY')
      # When the body of a `begin..ensure..end` raises, the ensure
      # clause must still run before the exception keeps propagating.

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
    result = zr(<<~'RUBY')
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
    result = zr(<<~'RUBY')
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
    result = zr(<<~'RUBY')
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

  it "a rescue picks the first arm whose class matches, and a bare rescue catches all" do
    result = zr(<<~'RUBY')
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

  it "if static false skips dead branch compile" do
    result = zr(<<~'RUBY')
      # A predicate that reads an ivar only ever assigned `nil` is always
      # false. The body never runs, so a call in it that needs a String
      # (as `sub("MODE", @mode)`) does not stop the program.

      class T_if_static_false_skips_dead_branch_compile_Profiler
        def initialize
          # `@mode` is always nil — only ever assigned this literal.
          # So the predicate below is always false.
          @mode = nil
        end

        def run
          # Dead branch when @mode is nil. `sub` with a nil argument
          # would raise TypeError, but this body never runs.
          if @mode
            out = "label_MODE".sub("MODE", @mode)
            puts out
          end
          puts "ran"
        end
      end

      # `if @nil_ivar; ... else; ... end` with a trailing stmt puts
      # the if in statement position. The else arm runs when the
      # predicate is always nil.
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

  it "intarray slice assign from intarray ptr array first" do
    result = zr(<<~'RUBY')
      # `arr[start, len] = src` slice-assign where `src` came from
      # `.first` (or `.last`) of an Array of Integer Arrays. The slice
      # assign puts the elements of `src` in place. It does not do
      # `arr[start] = len`.

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
    result = zr(<<~'RUBY')
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

  it "a user-defined find and fetch return their own values" do
    result = zr(<<~'RUBY')
      # A user-defined `find` or `fetch` returns the value of its own body
      # (a String here), not the value of the built-in method with that
      # name.

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

      # The built-in Array#find still works.
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

  it "a Parameters wrapper symbolizes nested keys for a factory" do
    result = zr(<<~'RUBY')
      # A Rails-style Parameters wrapper changes each key to a Symbol, and
      # calls itself for a nested Hash. A factory class method makes an
      # instance with a bare `new` and sets a field from the `fetch` of
      # the wrapper. The factory returns a local, and the recursive call
      # is in an `is_a?(Hash)` arm that this input never takes.

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

  it "a call on the result of a user-defined [] sees the real value" do
    result = zr(<<~'RUBY')
      # A call on the result of a user-defined `[]` (`.to_i`, `.length`)
      # sees the real value that `[]` returns, here a String.

      class T_issue219_aref_chain_Bag
        def initialize(h); @h = h; end
        def [](k); @h[k.to_sym]; end
      end

      bag = T_issue219_aref_chain_Bag.new({id: "42"})

      # .to_i calls String#to_i.
      puts bag[:id].to_i              # 42
      puts bag[:id].to_i + 1          # 43

      # .length calls String#length.
      puts bag[:id].length            # 2

      # The Integer goes into a method that adds to it.
      class T_issue219_aref_chain_M
        def self.find(id); id + 1; end
      end
      puts T_issue219_aref_chain_M.find(bag[:id].to_i)      # 43

      # A bag of Integer values: .to_s gives a String.
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

  it "kernel module function call" do
    result = zr(<<~'RUBY')
      # `Kernel.<m>` calls the Kernel module function, the same as a bare
      # `<m>(...)`. Users write it when a `def self.<m>` shadows the
      # Kernel method.

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
    result = zr(<<~'RUBY')
      # An unknown constant raises "uninitialized constant <Name>". This
      # test checks constant references that resolve to known names: a user
      # class, a user constant, Math and ARGV.

      # User-defined class.
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

  it "array 3d nested" do
    result = zr(<<~'RUBY')
      # Deep-nested array literals (3D and beyond). `arr[i][j][k]...`
      # reads the right Integer at each depth — 3D, 4D, 5D, ... all work.

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

      # 4D — any depth works.
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
    result = zr(<<~'RUBY')
      # instance_eval as an expression: the block's last expression is the
      # call's value (CRuby semantics). An assignment-only block gives the
      # assigned value, so `if obj.instance_eval { @f = 1 }` is truthy.

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

      # String-valued block.
      class T_instance_eval_return_value_Greeter
        def initialize
          @greeting = "hello"
        end
      end

      g = T_instance_eval_return_value_Greeter.new
      msg = g.instance_eval { @greeting }
      puts msg # hello

      # Assignment body: the value 1 is truthy, so the `if` arm runs.
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

  it "multi write const" do
    result = zr(<<~'RUBY')
      # Multi-write to constants — `A, B, C = expr` — sets each constant.
      #
      # Two RHS shapes are exercised: an Array literal and a constant that
      # holds an Integer Array.

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

      # RHS with a block — the block param is a local of the block, and
      # each constant gets one mapped value.
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

  it "multi write setter" do
    result = zr(<<~'RUBY')
      # `a, b, c.x = expr` where one target is a setter call (`c.x =`)
      # parses to a CallTargetNode in the targets list. The setter gets its
      # value too.

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

  it "nested class in class" do
    result = zr(<<~'RUBY')
      # Nested class definition inside another class.
      # `T_nested_class_in_class_A::B` names the inner class, and a bare `B`
      # inside the outer class finds it too.

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

  it "obj array" do
    result = zr(<<~'RUBY')
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

  it "ptr array delete at" do
    result = zr(<<~'RUBY')
      # `Array#delete_at(i)` on an array of user-class instances removes
      # and returns the element. Tep::Scheduler's fiber-slot list uses it
      # in a `clear` loop.

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

      # Out-of-range index returns nil; array unchanged.
      gone = a.delete_at(99)
      puts gone.nil? ? "nil" : "not-nil"
      puts a.length.to_s     # 1

      # Drain via repeated delete_at(0). The loop must end.
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
    result = zr(<<~'RUBY')
      # Test: reopening a user-defined class adds to the existing class.

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

  it "str setbyte frozen literal" do
    result = zr(<<~'RUBY')
      # frozen_string_literal: true
      # Bundled tests:
      #   - str_setbyte_frozen_literal
      #   - strip_nullable_int_cast


      # With `# frozen_string_literal: true`, every string literal is
      # frozen, and mutation needs a new String (`.dup`, `+`, etc.).
      # setbyte on a literal raises FrozenError with the CRuby message.

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

      # A dup'd string can change.
      s2 = "abc".dup
      s2.setbyte(0, 67)
      puts s2   # Cbc

      # Concatenation produces a new String too.
      s3 = "x" + "y"
      s3.setbyte(0, 90)
      puts s3   # Zy

      # Aliasing: setbyte on a shared object affects both refs.
      s4 = "ab".dup
      s5 = s4
      s4.setbyte(0, 67)
      puts s5   # Cb (shared object, both see the mutation)

      # ivar holding a dup'd string changes through a method call.
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
    result = zr(<<~'RUBY')
      # frozen_string_literal: true
      # Bundled tests:
      #   - str_setbyte_frozen_literal
      #   - strip_nullable_int_cast


      # A setter-shaped method gets a Foo, then nil, then an Integer (from
      # a method that returns an Integer). The ivar takes each value.

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

  it "undef" do
    result = zr(<<~'RUBY')
      # UndefNode -- `undef foo` inside a class body.
      #
      # CRuby raises NoMethodError if the undef'd method is called.
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

      # Multi-name form: `undef foo, bar`. Defining a third method `baz` and
      # undef'ing the other two verifies that exactly the named methods are
      # removed.
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

  it "Kernel#rand truncates a Float bound to an Integer draw" do
    result = zr(<<~'RUBY')
      p rand(3.5).class
      p (0...3).include?(rand(3.5))
    RUBY

    _(result).must_answer "Integer\ntrue\n"
  end

  it "sort_by over a Hash orders by a two-element key" do
    result = zr(<<~'RUBY')
      counts = Hash.new(0)
      counts["the"] = 3
      counts["dog"] = 1
      ranked = counts.sort_by { |w, n| [-n, w] }
      ranked.first(2).each { |w, n| puts "#{w}: #{n}" }
    RUBY

    _(result).must_answer "the: 3\ndog: 1\n"
  end

  it "an Array is a Hash key by value, and [1] and [1.0] are two keys" do
    result = zr(<<~'RUBY')
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

  it "a class object is not frozen" do
    result = zr(<<~'RUBY')
      class C001; end
      p(C001.frozen?)
    RUBY

    _(result).must_answer "false\n"
  end

  it "Object#<=> answers 0 for itself and nil for another" do
    result = zr(<<~'RUBY')
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
    result = zr(<<~'RUBY')
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
    result = zr(<<~'RUBY')
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
    result = zr(<<~'RUBY')
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

  it "Random#rand answers an Integer for a bignum bound" do
    result = zr(<<~'RUBY')
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

  it "reading a StringIO's string between writes does not disturb the buffer" do
    result = zr(<<~'RUBY')
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

  it "rjust, ljust and center take a width that is only known at run time" do
    result = zr(<<~'RUBY')
      # rjust/ljust/center with a width known only at run time (Hash#keys.max)
      counts = Hash.new(0)
      counts[1] = 1; counts[4] = 1
      w = counts.keys.max
      p "x".rjust(w)
      p "y".ljust(w)
      p "z".center(w)
      p "ab".rjust(w, "*")
      p "cd".ljust(w, "-")
      # a literal Integer width
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
    result = zr(<<~'RUBY')
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

  it "a Method object stored in a container still calls and reports its arity" do
    result = zr(<<~'RUBY')
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
end
