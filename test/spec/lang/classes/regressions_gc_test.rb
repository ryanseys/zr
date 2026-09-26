# frozen_string_literal: true

require "spec_helper"

describe "Classes: regressions" do
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
end
