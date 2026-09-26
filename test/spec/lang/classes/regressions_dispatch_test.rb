# frozen_string_literal: true

require "spec_helper"

describe "Classes: regressions" do
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
end
