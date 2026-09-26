# frozen_string_literal: true

require "spec_helper"

describe "Classes: regressions" do
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
