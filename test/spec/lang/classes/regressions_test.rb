# frozen_string_literal: true

require "spec_helper"

describe "Classes: regressions" do
  it "array each with object" do
    result = zr(<<~'RUBY')
      # Array#each_with_object runs the block for each element, on a mixed
      # Array and on an Array of user objects.

      # mixed element classes
      n = 0
      [1, "x"].each_with_object("") {|_e, _a| n += 1 }
      puts n

      # user objects
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

  it "chained or assign collection poly array" do
    result = zr(<<~'RUBY')
      # `(arr[idx] ||= []) << v` — chained `||=` over an Array element.
      # The `||=` expression gives the element, so `<<` appends to the
      # element in the Array.

      class T_chained_or_assign_collection_poly_array_C
        def initialize
          @a = Array.new(3) { [] }    # an Array of empty Arrays
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

  it "def aset mixed ivar widen" do
    result = zr(<<~'RUBY')
      # `def []=(name, value)` whose body dispatches on `name` and writes
      # `value` into ivars of differing types (`@id = value` and
      # `@name = value`, where `@id` holds an Integer and `@name` a String).
      # The param takes each value, and each ivar keeps the value it gets.

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
    result = zr(<<~'RUBY')
      # `def initialize(conf = ARGV)` with a caller that passes a String.
      # `conf` holds that String, so `@s.length` gives the String's length.

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
    result = zr(<<~'RUBY')
      # `def m(other = nil)` whose body uses `other[key]` (a Hash read with a
      # String key). No caller passes a non-nil `other`. The
      # `return if other.nil?` guard returns early, so the body keeps
      # `@s = nil`, and the attr writer sets the value later.

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
    result = zr(<<~'RUBY')
      # Same shape as the example above — nil-default param, and the body
      # uses the param as a Hash — but with a Symbol key.

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
    result = zr(<<~'RUBY')
      # A class method called with the `k` and `v` of `h.each { |k, v| }`
      # gets the Hash's String keys and values as its argument.

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
    result = zr(<<~'RUBY')
      # `arr.each {|a, b| ... }` over an Array of Arrays auto-splats each
      # element across the block params, matching CRuby's
      # `arr.each {|*args| a, b, *_ = args }` shape. So `b` gets the second
      # element. The inner Arrays hold only Integers (as `[i, fixed]` in
      # optcarrot's `setup_lut`) or mixed classes.

      class T_each_poly_recv_block_auto_splat_C
        def initialize
          @h = {}
        end

        def push_int(bank, pair)
          # `pair` holds only Integers.
          (@h[bank] ||= []) << pair
        end

        def push_poly(bank, pair)
          # `pair` holds mixed classes.
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
      d.push_poly(1, [100, "x"])  # b is a string, in a mixed Array
      d.push_poly(1, [5,   "y"])
      puts d.each_pair(1)         # 100 + 0 + 5 + 0 = 105 (string `to_i` of "x" / "y" = 0)
    RUBY

    _(result).must_answer "37\n105\n"
  end

  it "empty hash ivar string value" do
    result = zr(<<~'RUBY')
      # An ivar set to `{}` takes later `@h[k] = "string"` writes. A read
      # gives back the String, and a missing key gives nil.

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
      puts s.lookup("missing")     # (empty line — a missing key gives nil)

      # Integer keys with String values.
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
    RUBY

    _(result).must_answer <<~'OUT'
      body

      seven
      forty-two
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

  it "enumerable" do
    result = zr(<<~'RUBY')
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

  it "fiber ivar persists across yield" do
    result = zr(<<~'RUBY')
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
    result = zr(<<~'RUBY')
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
    result = zr(<<~'RUBY')
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


      # `File.write(path, value)` where `value` comes from a call on objects
      # of two classes. Each `run` returns a String, and File.write writes it.

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

      # An Array of objects of two classes — both classes' `run` returns a
      # String.
      workers = [T_file_write_poly_arg_Worker.new, T_file_write_poly_arg_OtherWorker.new]
      results = workers.map { |w| w.run(42) }

      # results[0] is the String from the first worker.
      # Use a cwd-relative path, because Windows MinGW has no `/tmp`.
      path = "spinel_i643_test.txt"
      File.write(path, results[0])
      puts File.read(path)
      File.delete(path)
    RUBY

    _(result).must_answer "result-42\n"
  end

  it "forward call class method inherited init" do
    result = zr(<<~'RUBY')
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
      # own `def initialize(_arg); super; end`. The bare `super` passes the
      # argument to the parent's #initialize, so `@owner` holds the Outer
      # object, and `@owner.name` calls Outer#name.

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
    result = zr(<<~'RUBY')
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


      # Inherited-init forward-ref with an Integer Array param that goes
      # through the super call. The parent's `@arr = arr` stores the Array,
      # and a parent-defined accessor reads it.

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
    result = zr(<<~'RUBY')
      # Inherited-init forward-ref where the param is an object of a
      # user class. Verifies the object goes through both the
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
    result = zr(<<~'RUBY')
      # `Class.new(an_integer_array)` where the callee class is defined later
      # than the call site. The Target's `arr` param gets the Array. The
      # source order keeps the caller first.

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
    result = zr(<<~'RUBY')
      # Nested forward-ref: `T_forward_call_class_method_nested_Outer.new(T_forward_call_class_method_nested_Inner.new)` where both T_forward_call_class_method_nested_Outer and
      # T_forward_call_class_method_nested_Inner are defined later than the construction site. The T_forward_call_class_method_nested_Inner.new
      # nested arg must reach T_forward_call_class_method_nested_Outer.initialize's param as the Inner
      # object.

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
    result = zr(<<~'RUBY')
      # `Class.new(obj)` shape: caller passes a user-class instance to a
      # forward-defined Class.new. Mirrors the optcarrot
      # `PPU.new(@conf, @cpu, @video.palette)` site, where the callee's
      # param gets an object of a sibling class defined later.

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
    result = zr(<<~'RUBY')
      # File-order caller-first / callee-second: a T_forward_call_param_type_int_array_Caller class invokes a
      # method on a yet-untyped ivar (because the callee class is defined
      # later in the source). The callee's params get the Integer Array and
      # the boolean from this single call site.

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
    result = zr(<<~'RUBY')
      # Forward-call with a user-class-typed arg flowing through the
      # caller's ivar to the callee's parameter slot. Mirrors optcarrot's
      # `@ppu.nametables = @mirroring` shape — the callee accepts an
      # object of a user class, and the call goes through the `@target`
      # ivar.

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
    result = zr(<<~'RUBY')
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
    result = zr(<<~'RUBY')
      # When parent and child both write the same ivar name, the object has
      # one `@data`. The GC marks it once and keeps its value alive.
      #
      # Here parent's `@data` gets an Array or a String, and child also
      # writes `@data` from a method that can return different classes.
      # The loop below makes GC pressure.

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
    result = zr(<<~'RUBY')
      # A class method whose only use of its Hash param is `h.each |k, v|`.
      # The body joins `k` and `v` into a String with `+`, for a Hash with
      # String values and for a Hash with Integer values.

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
    result = zr(<<~'RUBY')
      # `Hash#fetch(key, {})` on a Hash with Integer values. A hit gives the
      # Integer, and a miss gives the empty Hash default.

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
      # Hit path returns the Integer value
      puts v1.is_a?(Integer) ? v1 : "non-int"
      # Miss path returns the empty hash
      puts v2.is_a?(Hash) ? "hash" : "non-hash"
    RUBY

    _(result).must_answer "7\nhash\n"
  end

  it "hash fetch hash default narrowing" do
    result = zr(<<~'RUBY')
      # Sequel to hash_fetch_hash_default: `params.fetch "k", {}`, then an
      # if-expression on `is_a?(Hash)` whose else arm returns an empty Hash.
      # Both arms give a Hash, so `sub.is_a?(Hash)` answers true.

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
    result = zr(<<~'RUBY')
      # `params.fetch "k", ""` on a Hash[String, Int] (or
      # Hash[Symbol, Int]). A hit gives the Integer, and a miss gives the
      # empty String default.

      class T_hash_fetch_string_default_on_int_leaf_P
        def self.lookup_str(params)
          params.fetch "title", ""
        end

        def self.lookup_sym(params)
          params.fetch :title, ""
        end
      end

      # Hit path: the Integer at the key.
      puts T_hash_fetch_string_default_on_int_leaf_P.lookup_str({ "x" => 1, "title" => 42 })
      # Miss path: the empty-string default.
      puts T_hash_fetch_string_default_on_int_leaf_P.lookup_str({ "x" => 1 })

      # Sym-keyed counterpart.
      puts T_hash_fetch_string_default_on_int_leaf_P.lookup_sym({ x: 1, title: 99 })
      puts T_hash_fetch_string_default_on_int_leaf_P.lookup_sym({ x: 1 })

      # Control: the default has the same class as the values.
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
    result = zr(<<~'RUBY')
      # `@slots[i][i]`, where `@slots` holds an Integer Array and a Method
      # object. `[]` on each of them returns an Integer, so `@total += 1`
      # does Integer math.

      class T_heterogeneous_dispatch_int_return_narrow_Box
        def initialize
          @slots = [nil] * 4         # all nil at first
          @int_arr = [10, 20, 30, 40]
          @slots[0] = method(:double_at)   # a Method object
          @slots[1] = @int_arr             # an Integer Array
          @total = 0
        end

        def double_at(i)
          i * 2
        end

        # Direct ivar access.
        def via_ivar(i)
          @slots[i][i]
        end

        # Access through a local that aliases the ivar.
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

  it "imeth name collision recv aware" do
    result = zr(<<~'RUBY')
      # Two unrelated classes each define `def get(k)` with different
      # return types. `r = c.get("/foo")` calls IntClient#get, so `r` is
      # an IntBag, not the String that StrBag#get returns.

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
    result = zr(<<~'RUBY')
      # An override's `value` param gets values of mixed classes from its
      # call sites. A `self[k] = v` inside a parent method calls the
      # override, not the parent's method that raises.

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
    result = zr(<<~'RUBY')
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
    result = zr(<<~'RUBY')
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
    result = zr(<<~'RUBY')
      # Inherited class method whose body holds a local typed by a
      # method that each subclass overrides. For each subclass, the local
      # holds that subclass's object: Comment.find returns a Comment, not
      # an Article. The real-blog app uses this shape.

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
    result = zr(<<~'RUBY')
      # A subclass inherits a class method whose body calls another class
      # method (`self.last` calls bare `all`). The bare `all` calls the
      # subclass's override, so `records` holds the subclass's Array of
      # objects, not the parent's empty Array.

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

      # T_inherited_cmethod_subclass_dispatch_Sub.last (inherited from T_inherited_cmethod_subclass_dispatch_Base)
      # gets T_inherited_cmethod_subclass_dispatch_Sub.all's Array, so `records[-1]` is the object.
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
    result = zr(<<~'RUBY')
      # A parent class's instance method param takes the values from
      # subclass call sites too, not only from same-class call sites. A
      # bare `bar(arg)` in a subclass calls the parent's `bar` with `arg`.

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
          @id = s   # @id now holds a String, not an Integer
        end
        def id
          @id
        end
      end

      class T_inherited_method_param_widen_T2 < T_inherited_method_param_widen_T
        def test_it
          a = T_inherited_method_param_widen_Article.new
          a.write_str("hi")
          # Bare call to inherited assert_eq, passing a.id, which can be
          # an Integer or a String. Here it is the String "hi".
          assert_eq("hi", a.id)
        end
      end

      T_inherited_method_param_widen_T2.new.test_it
    RUBY

    _(result).must_answer "ok\n"
  end

  it "init locals" do
    result = zr(<<~'RUBY')
      # Locals inside `initialize` work as in any other method.

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
    result = zr(<<~'RUBY')
      # An `initialize` parameter gets a String from one Foo.new(...) call
      # site and an Integer from another. Each object keeps its own value.

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
    result = zr(<<~'RUBY')
      # An initialize parameter that is never written to an ivar still gets
      # the value from the `Foo.new(...)` call site, here a String.

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
    result = zr(<<~'RUBY')
      # A subclass calls a parent `initialize` through `super`. The parent
      # body has a String local and an early bare `return` (as in
      # `return if x.nil?`). Both calls to `new` work.

      class T_initialize_void_wrapper_gc_save_Base
        attr_reader :extra
        def initialize(skip)
          note = "base"
          if skip
            return        # bare `return` from initialize
          end
          @extra = note
        end
      end

      class T_initialize_void_wrapper_gc_save_Child < T_initialize_void_wrapper_gc_save_Base
        def initialize
          super(false)    # calls the parent's initialize
        end
      end

      # Keep both T_initialize_void_wrapper_gc_save_Child objects in an Array.
      all = [T_initialize_void_wrapper_gc_save_Child.new, T_initialize_void_wrapper_gc_save_Child.new]
      puts all.length          # 2
    RUBY

    _(result).must_answer "2\n"
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

  it "isa hash narrow typed param" do
    result = zr(<<~'RUBY')
      # A value that `is_a?(Hash)` checks goes to a param that also gets a
      # Hash literal. `render` reads the key from each Hash.

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

  it "an empty Hash default argument reads the Hash the caller gives" do
    result = zr(<<~'RUBY')
      # A parameter with an empty Hash default, `def m(h = {})`, reads the
      # Hash that the caller gives, with Symbol keys or String keys.

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

  it "a factory class method sets a field on the object that bare new makes" do
    result = zr(<<~'RUBY')
      # A factory class method (`def self.from_raw`) makes an instance
      # with a bare `new`, then calls a setter on it with the value of a
      # user-defined `fetch`. The `fetch` has a nil default, and the call
      # gives "" in its place.

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

  it "a class method of the parent class answers through each subclass" do
    result = zr(<<~'RUBY')
      # A class method (`def self.<name>`) that the parent class defines
      # answers when a subclass calls it, at one level or at two.

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

  it "a chained ivar assignment of a call result sets every ivar" do
    result = zr(<<~'RUBY')
      # A chained assignment `@a = @b = expr` with a call on the right sets
      # every ivar in the chain to the result, also when the ivars held
      # Strings before and the result is an Integer.

      class T_issue235_chain_tail_widening_C
        def initialize
          @a = "hello"
          @b = "world"
        end

        def make_int
          42
        end

        # A method call on the right, not a literal.
        def reset_call
          @a = @b = make_int
        end

        # A chain of three, with a call on the right.
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

      # reset_three also sets @c, which no code reads.
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
    result = zr(<<~'RUBY')
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
    result = zr(<<~'RUBY')
      # Test: an ivar can have a keyword name (`@if`), and `@iv_if` is a different ivar.

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
    result = zr(<<~'RUBY')
      # Instance variables set with Array.new(n, FILL) hold the FILL value in
      # each element: a Float, a Symbol or an object. The GC keeps the object
      # elements alive.
      #
      # The Float values have a non-zero fractional part, so `puts` shows them
      # as CRuby does.

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
    result = zr(<<~'RUBY')
      # A method writes its params into an ivar Hash —
      # `@data[key] = value` — and another method fills @data with String
      # keys and values. No code calls the writer, and the program runs.

      class T_ivar_hash_aset_param_widen_Bag
        def initialize
          @data = {}
        end

        # Fills @data with String keys and values.
        def populate(source)
          source.each do |k, v|
            @data[k] = v
          end
        end

        # No caller.
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
    result = zr(<<~'RUBY')
      # `@ivar = [] if @ivar.nil?` plus push-through-getter: a push
      # through the getter method adds String values to the ivar's Array.
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
    result = zr(<<~'RUBY')
      # Statement-form `@x OP= v` for the bitwise / shift / multiplicative
      # operators. Each one changes the ivar, so `@a &= 0x80` sets @a to
      # 128. Walks each operator that has an `OP=` form.

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
    result = zr(<<~'RUBY')
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
    result = zr(<<~'RUBY')
      # Two `String.new` writes to the same ivar, in two methods. Each one
      # gives a String that `<<` can append to.

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
    result = zr(<<~'RUBY')
      # Two writers in different methods of the same class give the ivar
      # values of different classes. Here writer 1 in initialize assigns
      # an Integer (from a Hash read) and writer 2 in write_any assigns a
      # String param. The ivar holds the last value written.

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

      # The Integer writer alone still works when no other writer gives a
      # different class.
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

  it "kwarg default empty hash kind" do
    result = zr(<<~'RUBY')
      # Class method with a kwarg `set_cookies: {}`. Another call site
      # passes a Hash with Symbol keys and String values. A call that
      # omits the kwarg gets the empty `{}` default, so `each` runs zero
      # times.

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
    result = zr(<<~'RUBY')
      # When a method's only positional has a default hash literal
      # (`attrs = {}`), call sites that pass kwargs whose names DON'T
      # match the param name should bundle the kwargs into that hash
      # slot. CRuby auto-folds trailing unmatched kwargs into a hash
      # positional. The callee sees the kwargs in the Hash, not an empty
      # Hash, even when the values have mixed classes.
      #
      # Sam Ruby's roundhouse `comment_test.rb` uses this shape:
      # `Comment.create(article_id: article.id, ...)` against
      # `def self.create(attrs = {})`.

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
      # hash param.
      b2 = T_kwargs_into_default_hash_param_Bag.new(id: 42, name: "beta")
      puts b2.id     # 42
      puts b2.name   # beta
      puts b2.count  # 2

      # Empty call: defaults still kick in.
      b3 = T_kwargs_into_default_hash_param_Bag.create
      puts b3.id     # 0
      puts b3.name   # (none)
      puts b3.count  # 0

      # Mixed kwarg types -- String + Integer -- in one Hash.
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
    result = zr(<<~'RUBY')
      # AliasMethodNode -- `alias greet hello` inside a class body.
      #
      # CRuby snapshots the method at alias time -- if `hello` is later
      # redefined, `greet` still calls the original. Here a call to
      # `.greet` runs the body of `.hello`. This test does not check alias
      # inside a method body, or alias of an inherited method.

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
    result = zr(<<~'RUBY')
      # `a && b` where `a` is an ivar that held a String and then an
      # Integer. Any value that is not nil or false is truthy.

      class T_and_node_poly_operand_Holder
        def initialize
          @poly = "x"   # string first…
          @poly = 42    # …then an Integer
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

  it "map array block result" do
    result = zr(<<~'RUBY')
      # `arr.map { array_block }` — the block returns an Integer Array
      # (`(0..i).to_a` here). The result is an Array of Arrays, and the GC
      # keeps each inner Array alive.

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
    result = zr(<<~'RUBY')
      # `Range#map` / `Array#map` whose block returns an array
      # (1D, 2D, 3D nested). `arr[i][j][k]...` reads the right value at
      # each depth. Optcarrot builds a table this way:
      # `TILE_LUT = [...].map { (0..7).map { (0...0x10000).map { ... }
      # }.transpose }`.

      # Range#map -> an Array of Integer Arrays (2D)
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

      # Integer Array map { Range#map { ... } } -> 3D
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
    result = zr(<<~'RUBY')
      # An empty `map {}` block still gives an array of the same length as
      # the receiver, with nil in each element. This is true for each kind
      # of receiver.

      # Range#map
      puts (0..2).map {}.length          # 3

      # N.times.map
      puts 4.times.map {}.length         # 4

      # Integer Array#map
      puts [10, 20, 30].map {}.length    # 3

      # String Array#map
      puts ["a", "b", "c", "d"].map {}.length   # 4

      # mixed Array#map
      puts [1, "two", :three].map {}.length     # 3

      # Array#map on objects of one user class
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
    result = zr(<<~'RUBY')
      # `Range#map { array_block }` gives an Array of Arrays, not a Range.
      # So the result can be indexed `arr[i][j]` directly. A second ivar
      # holds a plain Integer Array.

      class T_map_range_recv_array_block_C
        def initialize
          # Block returns an Integer Array — outer is an Array of Arrays.
          @rows = (0...3).map { |i| [i, i * 10] }
          # Separate ivar for a plain Integer Array.
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
    result = zr(<<~'RUBY')
      # User-defined instance methods named `hash`, `to_i`, `to_s` and
      # `length` return the user's value (a String here), not the value of
      # the built-in method with that name.
      #
      # Coverage:
      #   - `hash` shadowed -- the bcrypt shape, but in instance form.
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
    result = zr(<<~'RUBY')
      # Multiple unrelated classes define the same method name. A call on
      # each element of an Array of mixed objects calls each object's own
      # method with the String arguments.
      #
      # Coverage:
      #   - Two unrelated classes (Index/T_method_name_collision_multi_class_UsersHandler) define
      #     `handle(req, res)` -- both get the Strings "/" and "ok".
      #   - A third class (T_method_name_collision_multi_class_SQLite) has `attr_accessor :handle` (a
      #     0-param getter). It takes no arguments, so the 2-arg call does
      #     not go to it.
      #   - `db.handle` (0-arg call) on the T_method_name_collision_multi_class_SQLite returns the ivar value
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
    result = zr(<<~'RUBY')
      # Method names that collide with Math module functions (log, sin,
      # cos, sqrt, exp, atan2, hypot, ...) should not be misinferred as
      # float-returning. A `def log; @log; end` accessor on a user class
      # returns the ivar's Array, so `obj.log[i]` reads an element.

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
    result = zr(<<~'RUBY')
      # Call sites pass values of different classes (String and Integer)
      # for the same parameter. Each call works, for a self-call inside the
      # class and for a call on an object.

      class T_method_param_unify_to_poly_CPU
        def feed(x, val)
          val
        end
        # Self-call (no receiver).
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
        # Call on an object.
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
    result = zr(<<~'RUBY')
      # A reopened class redefines a method. A call before the redefinition
      # runs the original body, and a call after it runs the new body
      # ("original" then "redefined"), as in CRuby.

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
    result = zr(<<~'RUBY')
      # Multi-argument `block.call(a, b, ...)` on the proc-object path.
      #
      # Each positional argument reaches its block param, not only the
      # first one.

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
      # (matches CRuby semantics).
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
    result = zr(<<~'RUBY')
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

  it "multi write from poly recv" do
    result = zr(<<~'RUBY')
      # Multi-write `a, b = rhs` where rhs is an element of a nested
      # structure that holds values of mixed classes. `a` gets the first
      # element, an Array, so `a.length` works.

      class T_multi_write_from_poly_recv_C
        def setup
          @h = {}
          [0, 1].each do |bank|
            [0, 1].each do |idx|
              # A Hash of Arrays of pairs of Arrays of two-tuples — same
              # shape as optcarrot's @lut_update.
              (((@h[bank] ||= [])[idx] ||= [nil, nil])[0] ||= []) << [idx * 10 + bank, idx + bank]
            end
          end
        end

        def name_lut_size(bank, idx)
          # Multi-write whose RHS is @h[bank][idx]: a Hash read, then an
          # Array read.
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
    result = zr(<<~'RUBY')
      # `@a, @b = expr1, expr2` (multi-write to ivars) sets each ivar, for
      # Integer values and for objects.

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
    result = zr(<<~'RUBY')
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
    result = zr(<<~'RUBY')
      # `A, B = arr.map { block }` is destructuring assignment where
      # each LHS target receives one element of the mapped array.
      # Here the block returns an Integer Array, so each constant holds an
      # Integer Array.

      class T_multi_write_map_block_C
        # Outer map produces an Array of Arrays (each element is an Integer
        # Array from `to_a`).
        P, Q = [3, 5].map { |n| (0...n).to_a }
      end

      # P and Q are Arrays, so `.length` and `[]` work on them.
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

  it "multi write typed array dispatch" do
    result = zr(<<~'RUBY')
      # `a, b = self.method(...)` where `method` returns an Array of objects,
      # Floats or Strings. Each shape below destructures into two locals,
      # and each local gets its element.

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
    result = zr(<<~'RUBY')
      # A view method returns a String built with `String.new` and `<<`.
      # It goes into a `body` attr, and another class writes an Integer to
      # its own `body`. The String keeps its content, so `inspect` gives
      # the quoted String. Roundhouse's Tep::Server#write_response reads a
      # body in this way to write an HTTP response.

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
        def initialize; @body = 42; end  # an Integer body in another class
      end

      r = T_mutable_str_into_poly_slot_Resp.new
      r.body = T_mutable_str_into_poly_slot_View.index
      # inspect returns the quoted String.
      puts r.body.inspect

      # Use T_mutable_str_into_poly_slot_OtherResp too, so the program has both
      # Integer and String bodies. The String body still works.
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

  it "nested proc interp capture" do
    result = zr(<<~'RUBY')
      # Nested blocks that capture a variable through string interpolation
      # inside a block that itself captures the same variable.
      #
      # LocalVariableReadNode("i") is nested under
      #   InterpolatedStringNode → EmbeddedStatementsNode → body
      # and each block sees the last value of `i`.

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
    result = zr(<<~'RUBY')
      # `Class.new(kw: val)` (Symbol-keyed kwargs) where the
      # class's initialize takes a single positional `attrs` param.
      # CRuby binds `attrs = {kw: val}` (the kwargs become a positional
      # hash whose keys are the kwarg *symbols*). Access is via the kwarg
      # symbols (`attrs[:title]`); String keys would not match, as in CRuby.

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

      # A second kwarg call site to the same initialize.
      b = T_new_kwarg_bundle_Article.new(title: "Second", body: "Post")
      puts b.title

      # Mixed value types in one kwarg call: the Hash holds each value with
      # its own class.
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
    result = zr(<<~'RUBY')
      # The optcarrot APU::Pulse shape: an ivar initialized to `nil` and
      # later used only in Integer arithmetic (no `.nil?` read anywhere on
      # it). `@freq = (@wave_length + 1) * 2 * @fixed` and the later
      # arithmetic on `@timer` and `@step` give the right Integers.

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
    result = zr(<<~'RUBY')
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
    result = zr(<<~'RUBY')
      # `def x=(v); @x = v * 2; end` looks like an attr_writer at first glance
      # (single InstanceVariableWriteNode body) but the assignment value is a
      # computation, not a bare param reference. So `c.doubled = 5` runs the
      # method body, and the `* 2` makes the ivar 10.

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
    result = zr(<<~'RUBY')
      # `obj.x = v` must dispatch to `def x=(v)` when x= is not a registered
      # attr_writer. The multi-statement body runs, with its side effect on
      # another ivar.

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

      # attr_accessor path: writes the ivar.
      c.real = 7
      puts c.real           # 7

      # Multi-statement def x=: the method body runs.
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

  it "poly aref shift via block param" do
    result = zr(<<~'RUBY')
      # `a[idx]` goes into an Integer operator (`>>` / `<<` / ...)
      # inside an `.each {|a| ... }` block, where `a` is an Array of mixed
      # elements.
      #
      # `entries` here is one half of a destructured 2-tuple from a
      # nested-ivar chain (`@store[bank][idx]`). `a[2]` is an Integer, so
      # `data >> a[2]` is an Integer shift.

      class T_poly_aref_shift_via_block_param_C
        def initialize
          # @store[bank][idx] is a 2-tuple: (names, entries).  Each entry
          # in `entries` is a [tag, payload, shift] triple, with elements
          # of mixed classes.
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
    result = zr(<<~'RUBY')
      # `[A, B]` outer literal where A and B are calls (not Array literals)
      # that return an Array of Arrays (e.g. `(0..N).map { ... }`).
      # `arr[b][i][j]` reads the right Integer at each level, and `length`
      # works at each level.

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
    result = zr(<<~'RUBY')
      # `@arr = [a, b]` with objects of one class, then `@arr[i] = v` with a
      # String. The Array holds both classes, and its length stays 2.

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
          @pads[0] = "x"   # a String in an Array of Pads
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
    result = zr(<<~'RUBY')
      # `@arr = [nil] * N`, then `@arr[i] = v` writes of an Integer and a
      # String. The Array holds the mixed values, and its length stays N.

      class T_poly_array_slot_sized_default_Holder
        def initialize
          @arr = [nil] * 3
          @arr[0] = 42      # int
          @arr[1] = "two"   # a String — the Array now holds mixed classes
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
    result = zr(<<~'RUBY')
      # A method returns instances of different classes from its branches.

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
    result = zr(<<~'RUBY')
      # Two user classes define `toggle` with different arities —
      # T_poly_dispatch_arity_padding_Switch#toggle takes 0 args; T_poly_dispatch_arity_padding_Knob#toggle takes
      # one positional default. A 0-arg call on each Switch works.

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
          @items = [T_poly_dispatch_arity_padding_Switch.new, T_poly_dispatch_arity_padding_Switch.new]   # two classes
                                              # define `toggle`
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
    result = zr(<<~'RUBY')
      # Two user classes define `write` with different arities. Heater#write
      # takes 2 args and Buzzer#write takes 1. A 2-arg call on an ivar that
      # holds a Heater calls Heater#write.

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
          @poly = T_poly_dispatch_arity_truncate_Heater.new   # the last of three writes of mixed classes
        end

        attr_reader :poly

        def call_write(addr, data)
          @poly.write(addr, data)   # Heater and Buzzer both define write
        end
      end

      b = T_poly_dispatch_arity_truncate_Box.new
      b.call_write(7, 5)
      puts b.poly.v   # 12  (T_poly_dispatch_arity_truncate_Heater: addr + data)
    RUBY

    _(result).must_answer "12\n"
  end

  it "poly hash literal from ivar" do
    result = zr(<<~'RUBY')
      # A method returns `{ key: @x, ... }`, where one writer sets `@x` to
      # an Integer and another sets it to a String. The Hash literal holds
      # the ivar value, whatever its class.

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

      # Multiple sym-keyed entries, all from ivars of mixed classes.
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
    result = zr(<<~'RUBY')
      # Integer receiver + an argument that can be of mixed classes, in
      # arithmetic. Common case: `addr + arr[i][j]`, where `arr` holds a
      # user object and an Integer Array. `[]` on each returns an Integer,
      # so the arithmetic gives an Integer.

      # Class that defines `[]` returning an Integer, stored alongside an
      # Integer Array.
      class T_poly_int_arith_auto_unify_Lookup
        def [](i); i * 10 + 1; end
      end

      arr = [T_poly_int_arith_auto_unify_Lookup.new, [100, 200, 300]]

      # arr[i] is a T_poly_int_arith_auto_unify_Lookup or an Integer Array, then `[j]` is called on it —
      # each one returns an Integer.
      addr = 7
      puts(addr + arr[1][0])  # 7 + 100 = 107
      puts(addr - arr[0][2])  # 7 - 21  = -14
      puts(addr * arr[1][1])  # 7 * 200 = 1400
      puts(arr[1][2] / 3)     # 300 / 3 = 100
    RUBY

    _(result).must_answer <<~'OUT'
      107
      -14
      1400
      100
    OUT
  end

  it "poly int bit index" do
    result = zr(<<~'RUBY')
      # `Integer#[N]` (bit-extraction) where the receiver is an ivar that
      # held a String and then an Integer. `int[i]` gives the bit at `i`,
      # so a `pc[8] == tmp[8] ? a : b` style page-bit check works.

      class T_poly_int_bit_index_Holder
        # Mixed-type ivar writes: first a String, then an Integer.
        def initialize
          @x = "init"
          @x = 0b10110100  # 180 — actual value at test time
        end

        attr_reader :x

        # Same-page check pattern: extract bit 8 from each Integer.
        def same_page?(a, b)
          a[8] == b[8]
        end
      end

      h = T_poly_int_bit_index_Holder.new
      v = h.x  # `v` is the Integer 180 here

      # Static index, dynamic value.
      puts v[0]    # 0
      puts v[1]    # 0
      puts v[2]    # 1
      puts v[3]    # 0
      puts v[4]    # 1
      puts v[5]    # 1
      puts v[6]    # 0
      puts v[7]    # 1

      # Dynamic index.
      i = 0
      while i < 4
        puts v[i]
        i += 1
      end

      # Page-bit check: `0x100 | x` flips bit 8 on/off so the comparison
      # differs depending on input.
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
    result = zr(<<~'RUBY')
      # A subclass override that returns nil must still run when called
      # through an ivar that can hold a Base or a Sub.
      #
      # Two checks:
      #  1. The override's side effect runs (the `puts` inside T_poly_nil_return_dispatch_Sub#hook).
      #  2. The call's *return value* is nil.

      class T_poly_nil_return_dispatch_Base
        def hook(arg); end          # empty body -> returns nil
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
    result = zr(<<~'RUBY')
      # `.call` on a Proc stored in an ivar runs the proc body.

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
    result = zr(<<~'RUBY')
      # `@arr[i] = v` on an ivar that other methods set to a String or an
      # Integer. When @arr holds an Array (`[nil] * N`), the write goes into
      # that Array.

      class T_poly_recv_bracket_assign_C
        def init_arr(n)
          @arr = [nil] * n      # an Array
          @arr[0] = 100
        end
        def init_str
          @arr = "scalar"       # a String
        end
        def init_int
          @arr = 42             # an Integer
        end
        def at(i)
          @arr[i]
        end
      end

      c = T_poly_recv_bracket_assign_C.new
      c.init_arr(3)
      puts c.at(0)              # 100
    RUBY

    _(result).must_answer "100\n"
  end

  it "poly recv dispatch includes subclasses" do
    result = zr(<<~'RUBY')
      # An ivar first holds a base class object, and a setter then stores a
      # subclass object. A call on the ivar runs the subclass override. Tep
      # uses this shape for `app.@before_filter.before(req, res)`.

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
    result = zr(<<~'RUBY')
      # `@w.run(item)` calls `run` on the object in `@w`, a WorkerA or a
      # WorkerB. An unrelated class (Server) also defines `run`, with an
      # Integer param. The String call does not affect Server#run, so
      # `port + 1` gives an Integer.

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

      # T_poly_recv_dispatch_narrow_Server#run gets only the Integer 80.
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
    result = zr(<<~'RUBY')
      # `.each` on an ivar `@store` that two methods set to different
      # Arrays: an Integer Array, and an Array filled with Strings. The
      # block runs for each element of the Array that `@store` holds.

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
    result = zr(<<~'RUBY')
      # `@worker.run(item)` calls `run` on the Worker or Other object in the
      # ivar. An unrelated class also defines `run`, but no code makes one
      # or puts one in the ivar. So the call returns a String, and
      # File.write writes it.

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

      # T_poly_recv_ivar_narrow_drops_unrelated_Unrelated has no relation to
      # T_poly_recv_ivar_narrow_drops_unrelated_Worker.
      # Never instantiated, never assigned to a T_poly_recv_ivar_narrow_drops_unrelated_Pool@worker slot.
      # Its `run` has zero formal args and returns an Integer.
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
    result = zr(<<~'RUBY')
      # `recv.attr = val` where `recv` comes from `case ... when X
      # then T_poly_recv_setter_widens_ivar_A.new; when Y then T_poly_recv_setter_widens_ivar_B.new`. The setter
      # stores the Hash with String keys and values in `@data`, which
      # initialize set to `{}`. A later read gives the stored Hash.

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

      # A case-expression whose branches return different sibling
      # subclasses.
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
    result = zr(<<~'RUBY')
      # A method returns `@hash[key] || ""`. A hit gives the String value.
      # A missing key gives nil, which is falsy, so the method returns "".

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
    result = zr(<<~'RUBY')
      # `<<` on an ivar that held nil and then an Integer Array pushes the
      # value onto the Array. It is a bit-shift only when the receiver is
      # an Integer.

      class T_poly_shl_array_push_dispatch_C
        def initialize
          # First `nil`, then an Integer Array.
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

      # Bit-shift on an Integer receiver.
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
    result = zr(<<~'RUBY')
      # Push a Proc into an ivar Array (set to `[]` first). Then
      # `.each { |b| b.call }` runs each proc.
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
    result = zr(<<~'RUBY')
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
    result = zr(<<~'RUBY')
      # An ivar set to `{}` takes a captured `&block` proc as a value.

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

  it "runtime widen int to poly array" do
    result = zr(<<~'RUBY')
      # `@arr[i] = v` puts a String into an Integer Array held by an ivar
      # that another method sets to a String. The element keeps the String,
      # and the other elements keep their Integers.

      class T_runtime_widen_int_to_poly_array_C
        def init_arr_widen
          @arr = [10, 20, 30]   # an Integer Array
          @arr[1] = "string!"   # a String element
        end
        def init_str
          @arr = "scalar"       # a String in the same ivar
        end
        def at(i); @arr[i]; end
      end

      c = T_runtime_widen_int_to_poly_array_C.new
      c.init_arr_widen
      puts c.at(0)               # 10
      puts c.at(1)               # "string!"
      puts c.at(2)               # 30
    RUBY

    _(result).must_answer <<~'OUT'
      10
      string!
      30
    OUT
  end

  it "sample user method" do
    result = zr(<<~'RUBY')
      # A user-defined `sample` returns its own value (a String here), not
      # an element as Array#sample does.

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
    result = zr(<<~'RUBY')
      # A child class writes to an ivar that the parent also writes. The
      # object has one `@v`, and a read gives the last value written.

      class T_scan_ivars_inherited_slot_Parent
        def initialize
          @v = 0
          @v = "s"     # parent writes an Integer, then a String
        end
      end

      class T_scan_ivars_inherited_slot_Child < T_scan_ivars_inherited_slot_Parent
        def initialize
          super
          @v = 42      # child writes the same ivar
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
    result = zr(<<~'RUBY')
      # `Bar.new(@x, ...)` inside `Foo#initialize` passes the object in
      # `@x`, so Bar#initialize's first param gets that object.

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
    result = zr(<<~'RUBY')
      # `self.class.<cmeth>` inside a parent-defined instance method calls
      # the class method of the object's own class, so a subclass override
      # runs.
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
    result = zr(<<~'RUBY')
      # Test send(:literal_symbol)
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
    result = zr(<<~'RUBY')
      # .__send__(:sym, args) and .__send__("sym", args) call .sym(args),
      # the same as .send. CRuby gives __send__ as the alias of send that
      # a class cannot easily override.

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
    result = zr(<<~'RUBY')
      # .send("sym", args) with a plain string literal calls .sym(args), the
      # same as the :symbol form.

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
    result = zr(<<~'RUBY')
      # .send(:sym, args) calls .sym(args).

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

        # Returns the input length; the test passes args with parens in them.
        def length_of(s)
          s.length
        end
      end

      # 1. Basic shapes.
      c = T_send_literal_symbol_Calc.new
      puts c.send(:add, 3, 4)        # 7
      puts c.send(:double, 21)       # 42
      puts c.send(:hello)            # hi

      # 2. Parens inside String args are part of the String.
      puts c.send(:length_of, "a)b")     # 3
      puts c.send(:length_of, "x(y)z")   # 5
      puts c.send(:length_of, 'p)q')     # 3

      # 3. Operator method `[]` via send calls the index operator.
      arr = [10, 20, 30]
      puts arr.send(:[], 0)          # 10
      puts arr.send(:[], 2)          # 30

      # 4. Operator method `[]=` via send calls .[]=(idx, val).
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

  it "subclass inherited attr reader" do
    result = zr(<<~'RUBY')
      # Bare `attr_reader_name` and `self.attr_reader_name` inside a
      # subclass instance method call the reader that the parent class
      # declares with `attr_accessor` / `attr_reader`.

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
    result = zr(<<~'RUBY')
      # A parent-class instance method calls another method with an
      # implicit self, and a subclass overrides that method. The override
      # runs, and its param gets the Hash that the parent passes.

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
    result = zr(<<~'RUBY')
      # Two subclasses each call `super` from `initialize` forwarding a
      # differently-typed arg (a String and an Integer). The parent's
      # param takes each one.

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
    result = zr(<<~'RUBY')
      # Bare `super` (no args, no parens) inside a constructor parses as
      # `ForwardingSuperNode`, not `SuperNode`. It calls the parent's
      # `initialize` with the same arguments, so the parent sets its ivars.

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
    result = zr(<<~'RUBY')
      # `super { ... }` from a child method passes a literal block to the
      # parent, so `yield` inside the parent body runs the block.
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
    result = zr(<<~'RUBY')
      # A `{ sym_key: <ivar-or-param> }` hash literal whose values are NOT
      # string literals -- ivars, params, method-call results. A read by
      # key gives the String value.
      #
      # Coverage:
      #   - a Symbol-keyed Hash with a value from an ivar.
      #   - a Symbol-keyed Hash with a value from a method param.
      #   - an attributes Hash with a value from a method call.

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
    result = zr(<<~'RUBY')
      # Reassigning an instance variable to a different Symbol. A read gives
      # the new Symbol.

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
    result = zr(<<~'RUBY')
      # `arr[idx]`, where both `arr` and `idx` come from Hashes with values
      # of mixed classes. Here `arr` is an Array and `idx` is an Integer.

      class T_unbox_poly_index_in_dispatch_C
        def initialize
          @bag  = { "arr" => [100, 200, 300, 400], "lbl" => "x" }
          @keys = { "i" => 2, "s" => "lbl" }
        end
        def at(k)
          arr = @bag["arr"]      # an Array
          idx = @keys[k]         # an Integer
          arr[idx]               # Array#[] with an Integer index
        end
      end

      puts T_unbox_poly_index_in_dispatch_C.new.at("i").to_s    # 300
    RUBY

    _(result).must_answer "300\n"
  end

  it "uncalled method dce" do
    result = zr(<<~'RUBY')
      # An uncalled `def f(x); @typed = x; end`, where no caller gives the
      # param a value and the ivar holds a String. The program still runs.

      class T_uncalled_method_dce_C
        def initialize
          @body = ""
        end

        # Never called. @body holds a String.
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

  it "uninit attr accessor reads as nil" do
    result = zr(<<~'RUBY')
      # `attr_accessor :foo` with no `initialize`-time assignment must
      # read as nil before any write, so `"[#{a.counter}]"` renders `[]`,
      # as in MRI.
      #
      # `b.counter = 0` on a sibling instance sets that instance only. The
      # unset `a.counter` read on a fresh `T_uninit_attr_accessor_reads_as_nil_A.new` still returns nil.

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
    result = zr(<<~'RUBY')
      # A user-defined `def <=>(other)` whose body calls `<=>` on Integer
      # ivars (`@n <=> other.n`). The inner `<=>` is Integer#<=>, not a
      # recursive call to the user's own method.

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

      # Standalone `==` falls back to identity, which doesn't help here.
      # This test does not include Comparable.
    RUBY

    _(result).must_answer <<~'OUT'
      -1
      1
      0
    OUT
  end

  it "user method named like mutator" do
    result = zr(<<~'RUBY')
      # A user class defines a method with the name of a Hash or Array
      # mutator (`update`, `clear`, `concat`, `delete`, `each`, `pop`,
      # `push`, `merge!`, ...). A call to it as the last expression gives
      # its return value, also in the implicit `self.update(...)` form.
      #
      # `T_user_method_named_like_mutator_C.new.f(7)` returns 8, and
      # `T_user_method_named_like_mutator_D.new.run(T_user_method_named_like_mutator_C.new)` returns 30.

      class T_user_method_named_like_mutator_C
        def update(target)
          target
        end
        def f(n)
          update(n + 1)   # implicit self.update
        end
      end

      class T_user_method_named_like_mutator_D
        def run(c)
          c.update(30)    # explicit recv on user class
        end
      end

      puts T_user_method_named_like_mutator_C.new.f(7)
      puts T_user_method_named_like_mutator_D.new.run(T_user_method_named_like_mutator_C.new)
    RUBY

    _(result).must_answer "8\n30\n"
  end

  it "value type constructor arg gc root" do
    result = zr(<<~'RUBY')
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
    result = zr(<<~'RUBY')
      # A constructor body with a local Array (`arr`), in a small class
      # defined after another class. Each call gives the right value, and
      # many calls do not use up the GC roots.

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

      # Many constructor calls.
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
    result = zr(<<~'RUBY')
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
    result = zr(<<~'RUBY')
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
    result = zr(<<~'RUBY')
      # A top-level begin/rescue around a call that passes a top-level
      # local Hash. The call reads the Hash and returns its value.

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
    result = zr(<<~'RUBY')
      # `while (n = gets.to_i) > 0` runs the call in the predicate on each
      # iteration, so each iteration reads a new line.
      #
      # The test uses an instance method that returns a String, then
      # calls `.to_i`. The test cannot give input to stdin `gets`, so an
      # iterator class takes its place.

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
    result = zr(<<~'RUBY')
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
    result = zr(<<~'RUBY')
      # An ivar's first write is an Integer (or nil) literal, and a later
      # write assigns an object. A read gives the object, and a call on it
      # runs the object's method.

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
          @poly = 10              # an Integer first
          @poly = T_widen_int_obj_to_poly_Box.new(5)      # …then an object
        end
        attr_reader :poly
      end

      # calls T_widen_int_obj_to_poly_Box#n on the object in @poly
      puts T_widen_int_obj_to_poly_Holder.new.poly.n      # 5
    RUBY

    _(result).must_answer "5\n"
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

  it "a class held in a Hash value constructs and dispatches through the lookup" do
    result = zr(<<~'RUBY')
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
    result = zr(<<~'RUBY')
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

  it "an empty Range#sum with a block answers the block's zero, not an integer one" do
    result = zr(<<~'RUBY')
      # An empty `Range#sum { block }` whose block value is a product of Floats
      # read from nested Arrays. The sum uses the block, so it is the Integer 0,
      # and the division gives a Float.
      aug = [[2.0, 3.0, 0.0]]
      x = Array.new(1, 0.0)
      s = (1...1).sum { |j| aug[0][j] * x[j] }
      x[0] = (aug[0][1] - s) / aug[0][0]
      p x
      # non-empty range sum with a block
      t = (0...2).sum { |j| aug[0][j] * 2 }
      p t
    RUBY

    _(result).must_answer "[1.5]\n10.0\n"
  end

  it "sum with a block over objects rounds to the places asked for" do
    result = zr(<<~'RUBY')
      # An object whose ivar comes from a destructured-pair block param, summed via a
      # block and rounded.
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
    result = zr(<<~'RUBY')
      class C001
        attr :x
        def initialize; @x = 5; end
      end
      p(C001.new.x)
    RUBY

    _(result).must_answer "5\n"
  end

  it "a class object is not frozen" do
    result = zr(<<~'RUBY')
      class C001; end
      p(C001.frozen?)
    RUBY

    _(result).must_answer "false\n"
  end

  it "instance_exec passes its arguments to a BasicObject's block" do
    result = zr(<<~'RUBY')
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
    result = zr(<<~'RUBY')
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

  it "NoMethodError carries the arguments the call was made with" do
    result = zr(<<~'RUBY')
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

  it "select and reject with no block answer an Enumerator" do
    result = zr(<<~'RUBY')
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
    result = zr(<<~'RUBY')
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
    result = zr(<<~'RUBY')
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
    result = zr(<<~'RUBY')
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

  it "a method that writes through an Array.new block's array is seen by the caller" do
    result = zr(<<~'RUBY')
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

      # a block that returns an empty Array literal
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

  it "a matrix product built from zip and sum with a block" do
    result = zr(<<~'RUBY')
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
    result = zr(<<~'RUBY')
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
    result = zr(<<~'RUBY')
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

  it "Kernel#loop with no block answers an endless Enumerator of nil" do
    result = zr(<<~'RUBY')
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
    result = zr(<<~'RUBY')
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
    result = zr(<<~'RUBY')
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
