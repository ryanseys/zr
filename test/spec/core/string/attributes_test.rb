# frozen_string_literal: true

require "spec_helper"

describe "String: generated attribute methods" do
  it "alias attr reader source" do
    result = ze0(<<~'RUBY')
      # `alias`/`alias_method` may name an attr_reader/attr_accessor-generated
      # method as the source. The new name then reads the same backing ivar,
      # carrying the ivar's inferred type (so typed uses like upcase work).
      class Token
        attr_reader :access_token
        attr_accessor :scope
        alias value access_token
        alias_method :token2, :access_token
        alias scope_alias scope

        def initialize
          @access_token = "tok"
          @scope = "read"
        end
      end

      t = Token.new
      puts t.value
      puts t.token2
      puts t.value.upcase          # type must propagate: string method
      puts "#{t.value}!"           # interpolation
      puts t.scope_alias

      # Aliasing an inherited attr_reader from the parent class.
      class Base
        attr_reader :name
        def initialize(n)
          @name = n
        end
      end

      class Derived < Base
        alias title name
      end

      d = Derived.new("spinel")
      puts d.title
      puts d.title.upcase
    RUBY

    _(result).must_answer <<~'OUT'
      tok
      tok
      TOK
      tok!
      read
      spinel
      SPINEL
    OUT
  end

  it "attr accessor reader and writer generate real methods" do
    result = ze0(<<~'RUBY')
      class Box
        attr_accessor :value
        attr_reader :ro
        def initialize
          @value = 1
          @ro = 7
        end
      end
      b = Box.new
      puts b.value
      b.value = 99
      puts b.value
      puts b.ro
    RUBY

    _(result).must_answer <<~'OUT'
      1
      99
      7
    OUT
  end

  it "attr override dispatch" do
    result = ze0(<<~'RUBY')
      # An explicit method overriding an inherited (or same-class) attr_reader/
      # attr_accessor must run via normal dispatch, not be shadowed by direct field
      # access at the call site. The more-derived definition wins.

      # subclass def x overrides inherited attr_accessor reader
      class Attr
        attr_accessor :x
        def initialize(v)
          @x = v
        end
      end

      class Child < Attr
        def x
          @x * 10
        end
      end

      puts Child.new(3).x            # 30

      # subclass def x= overrides inherited attr_accessor writer
      class ChildW < Attr
        def x=(v)
          @x = v * 10
        end
      end

      cw = ChildW.new(1)
      cw.x = 5
      puts cw.x                       # 50

      # same-class def overrides its own attr_reader
      class Same
        attr_reader :x
        def initialize(v)
          @x = v
        end
        def x
          @x + 100
        end
      end

      puts Same.new(3).x             # 103

      # child attr_reader overrides parent's explicit def -> reads the field
      class Parent
        def initialize(v)
          @x = v
        end
        def x
          @x + 100
        end
      end

      class ChildA < Parent
        attr_reader :x
      end

      puts ChildA.new(3).x           # 3

      # plain attr with no override keeps direct field access
      class Plain
        attr_accessor :x
        def initialize(v)
          @x = v
        end
      end

      p = Plain.new(7)
      p.x = 9
      puts p.x                        # 9
    RUBY

    _(result).must_answer <<~'OUT'
      30
      50
      103
      3
      9
    OUT
  end

  it "attr reader and attr writer declared standalone generate only their own half" do
    result = ze0(<<~'RUBY')
      class Point
        attr_reader :x
        attr_writer :y
        def initialize(x, y)
          @x = x
          @y = y
        end
        def show_y
          @y
        end
      end
      p1 = Point.new(1, 2)
      puts p1.x
      p1.y = 99
      puts p1.show_y
    RUBY

    _(result).must_answer "1\n99\n"
  end

  it "attr reader override type" do
    result = ze0(<<~'RUBY')
      class Attr
        attr_accessor :x
        def initialize(v)
          @x = v
        end
      end

      class Child < Attr
        def x
          @x.length
        end
      end

      puts Child.new('abc').x

      class IntAttr
        attr_reader :n
        def initialize(n)
          @n = n
        end
      end

      class Formatted < IntAttr
        def n
          "n=#{@n}"
        end
      end

      puts Formatted.new(7).n
      puts IntAttr.new(7).n

      module Sized
        attr_reader :w
      end

      class Box
        include Sized
        def initialize(w)
          @w = w
        end
        def w
          "#{@w}px"
        end
      end

      puts Box.new(12).w
    RUBY

    _(result).must_answer <<~'OUT'
      3
      n=7
      7
      12px
    OUT
  end

  it "attr write boxed dispatch" do
    result = ze0(<<~'RUBY')
      class Attr
        attr_accessor :x

        def initialize
          @x = 0
        end
      end

      class Def
        def initialize
          @x1 = 0
        end

        def x
          @x1
        end

        def x=(v)
          @x1 = v
        end
      end

      class Sub < Attr
        def x=(v)
          @x = v * 2
        end
      end

      box = [Def.new, Attr.new, Sub.new]

      o = box[0]
      o.x = 42
      puts "def writer  x=#{o.x}"

      a = box[1]
      a.x = 99
      puts "attr writer x=#{a.x}"

      s = box[2]
      s.x = 21
      puts "override    x=#{s.x}"

      class Mute
        def initialize
          @y = 0
        end
      end

      begin
        m = [Mute.new, Attr.new][0]
        m.x = 7
        puts "no raise"
      rescue NoMethodError => e
        puts "raised: #{e.class}"
      end
    RUBY

    _(result).must_answer <<~'OUT'
      def writer  x=42
      attr writer x=99
      override    x=42
      raised: NoMethodError
    OUT
  end

  it "attr writer from a block loses to a later def" do
    result = ze0(<<~'RUBY')
      class C
        attr_writer :x
        def x=(v)
          @x = [v, v]
        end
        attr_reader :x
      end
      c = C.new
      c.x = 1
      p c.x

      class D
        [:y].each { |a| attr_writer(a) }
        def y=(v)
          @y = [v, v]
        end
        attr_reader :y
      end
      d = D.new
      d.y = 2
      p d.y

      class E
        %i[z].each { |a| attr_accessor(a) }
        def z = 9
      end
      p E.new.z

      class F
        def self.make(n) = attr_writer(n)
        make :w
        def w=(v)
          @w = [v]
        end
        attr_reader :w
      end
      f = F.new
      f.w = 3
      p f.w
    RUBY

    _(result).must_answer <<~'OUT'
      [1, 1]
      [2, 2]
      9
      [3]
    OUT
  end

  it "extended attr accessor override wins" do
    result = ze0(<<~'RUBY')
      module Macros
        def attr_accessor(name)
          puts "macro attr_accessor #{name}"
          define_method(name) { 42 }
        end
      end

      class Direct
        extend Macros
        attr_accessor :alpha
      end
      p Direct.new.alpha
      p Direct.instance_methods(false).sort

      module ViaHook
        def self.included(mod) = mod.extend(Macros)
      end

      class Hooked
        include ViaHook
        attr_accessor :beta
      end
      p Hooked.new.beta
      p Hooked.instance_methods(false).sort

      module Silencer
        def attr_reader(*) = nil
      end

      class Silent
        extend Silencer
        attr_reader :gamma
      end
      p Silent.instance_methods(false).sort

      module Typed
        def attr_accessor(name, type: nil)
          define_method(name) { type }
        end
      end

      class Coerced
        extend Typed
        attr_accessor :delta, type: Integer
      end
      p Coerced.new.delta
    RUBY

    _(result).must_answer <<~'OUT'
      macro attr_accessor alpha
      42
      [:alpha]
      macro attr_accessor beta
      42
      [:beta]
      []
      Integer
    OUT
  end

  it "issue attr in dynamic class body" do
    result = ze0(<<~'RUBY')
      # attr_reader/attr_accessor/attr_writer only work in a literal `class`/`module`
      # body. Invoked from inside a `Class.new { ... }` or `#class_eval { ... }`
      # block, zeo raises NoMethodError instead of defining the accessor.
      klass = Class.new do
        attr_reader :v
        def initialize(v)
          @v = v
        end
      end
      p klass.new(5).v

      Klass2 = Class.new
      Klass2.class_eval do
        attr_accessor :y
      end
      o = Klass2.new
      o.y = 99
      p o.y
    RUBY

    _(result).must_answer "5\n99\n"
  end

  it "module attr alias include" do
    result = ze0(<<~'RUBY')
      module M001
        attr_accessor :x001
      end
      class C001
        include M001
        def initialize; @x001 = 5; end
      end
      p C001.new.x001
      c = C001.new
      c.x001 = 9
      p c.x001

      module M002
        def visible002; true; end
        alias_method :visible002?, :visible002
      end
      class C002
        include M002
      end
      p C002.new.visible002?
    RUBY

    _(result).must_answer <<~'OUT'
      5
      9
      true
    OUT
  end

  it "module metaprogramming attr class eval exec and invented ivars" do
    result = ze0(<<~'RUBY')
      # attr (== attr_reader), class_eval/module_exec block forms whose
      # added methods are inherited by subclasses and includers, and an
      # invented ivar (assigned by a class_eval/instance_exec body, never
      # declared on the struct) surviving in the per-object overflow map.

      class C001
        attr :x
        def initialize; @x = 5; end
      end
      p C001.new.x

      class Box
        def initialize(v); @v = v; end
      end
      class BoxPlus < Box; end
      Box.class_eval do
        def doubled; @v * 2; end
        define_method(:tripled) { @v * 3 }
        def labelled; @label = "n=#{@v}"; @label; end
      end
      b = Box.new(21)
      p [b.doubled, b.tripled, b.labelled]
      p BoxPlus.new(5).doubled

      module M; end
      M.module_exec { def mm; "mm"; end }
      class D; include M; end
      p D.new.mm

      o = Object.new
      o.instance_exec { @invented = 99 }
      p o.instance_variable_get(:@invented)
    RUBY

    _(result).must_answer <<~'OUT'
      5
      [42, 63, "n=21"]
      10
      "mm"
      99
    OUT
  end

  it "module singleton attr accessor" do
    result = ze0(<<~'RUBY')
      # #511. `module M; class << self; attr_accessor :x; end; end` on a
      # module previously didn't recognize either the reader or writer
      # for non-constant-RHS assignments — the existing constant-fold
      # path (rewrite_module_singleton_accessors) only resolved when
      # every observed write was a ConstantReadNode RHS. Roundhouse hit
      # this with `ActiveRecord.adapter = SqliteAdapter.new` (the RHS
      # is a method call, not a constant).
      #
      # Fix: when the SingletonClassNode + attr_accessor shape is seen,
      # also synthesize a poly-typed file-scope const `<Mod>_<accessor>`.
      # Reads of `Mod.accessor` and writes of `Mod.accessor = v` then
      # fall through to the const slot when the constant-fold path is
      # empty or poisoned. The const initializes to `{SP_TAG_NIL,...}`
      # so an un-assigned read returns nil.

      module Cfg
        class << self
          attr_accessor :adapter, :timeout
        end
      end

      # String RHS (non-constant): codegen falls through to the poly
      # slot. Reader returns sp_RbVal -> sp_poly_puts.
      Cfg.adapter = "sqlite"
      puts Cfg.adapter

      # Int RHS.
      Cfg.timeout = 30
      puts Cfg.timeout

      # Re-assign.
      Cfg.adapter = "postgres"
      puts Cfg.adapter

      # Pre-assignment read is nil.
      module Empty
        class << self
          attr_accessor :slot
        end
      end
      puts Empty.slot.nil?
    RUBY

    _(result).must_answer <<~'OUT'
      sqlite
      30
      postgres
      true
    OUT
  end

  it "poly attr reader shadows builtin" do
    result = ze0(<<~'RUBY')
      # An attr_reader/attr_accessor whose name collides with a builtin poly
      # zero-arg helper (value/resume/join -> Thread#value, sum/min/max/first/
      # last/sample -> array reductions) must shadow the helper exactly like an
      # explicit `def` does.
      #
      # The shortcut in emit_call only counted comp_method_in_chain when deciding
      # "no user class defines this name", so an accessor-declared reader was
      # invisible: `node.value` on a poly element emitted sp_poly_fiber_value(...)
      # (an sp_RbVal), and typed arithmetic on the result failed C compilation with
      #   invalid operands to binary expression ('sp_RbVal' and 'sp_RbVal')
      #
      # Reduced from the BART engine, where @roots (a poly array of Nodes, ivar
      # arrays never narrow to obj arrays) made Tree.leaf_stats' `node.value *
      # node.value` the build blocker.

      class Node
        attr_accessor :value, :first
        attr_reader :max
        def initialize
          @value = 1.5
          @first = 7
          @max = "peak"
        end
      end

      class Forest
        def initialize
          @roots = []          # ivar array of user objects: stays poly_array
          @roots << Node.new
        end

        def go
          @roots[0].value * @roots[0].value   # Float reader named like Thread#value
        end

        def head
          n = @roots[0]
          n.first + n.first                   # Int reader named like Array#first
        end

        def peak
          @roots[0].max                       # String reader named like Array#max
        end
      end

      f = Forest.new
      puts f.go        # 2.25
      puts f.head      # 14
      puts f.peak      # peak

      # (The builtin side -- Thread#value through a poly container when NO user
      # class defines the name -- is covered by thread_value_through_container.rb.
      # A program mixing BOTH a user `value` reader and poly-carried Threads still
      # hits the missing Fiber arm in the dispatch switch: a separate, pre-existing
      # gap, out of scope here.)
    RUBY

    _(result).must_answer <<~'OUT'
      2.25
      14
      peak
    OUT
  end

  it "poly attr writer" do
    result = ze0(<<~'RUBY')
      # Regression: a setter call (`obj.x = val`) on a parameter typed as
      # a class union must execute the assignment. Previously the dispatch
      # loop emitted no arms for attr_writer setters on poly receivers and
      # silently dropped the store.
      #
      # Three subcases:
      #  1. Single class with `x`, second class without -- the union case
      #     where the dispatch arm is "skipped silently."
      #  2. Two classes share an ivar name; same value type. Verifies
      #     both arms emit and the result temp's C type fits the slot.
      #  3. Two classes share an ivar name; differing value types
      #     (string vs int). Forces the new arm to box the rhs poly-style
      #     for one cls_id and unbox for the other.
      #
      # Verifying via the *side effect* (the ivar's value) rather than the
      # setter expression's return value -- propagating setter returns
      # through the dispatch into the enclosing function's return is a
      # separate concern that this PR doesn't try to fix.

      # --- 1. Single class (the no-op repro) ---------------------------------

      class Foo
        attr_accessor :x
        def initialize; @x = 0; end
      end

      class Bar
        # No `x`; coexists only to widen `obj` to a class union.
      end

      def set_x(obj, v)
        obj.x = v
      end

      foo = Foo.new
      bar = Bar.new
      set_x(foo, 42)
      set_x(bar, 99) rescue nil

      puts foo.x


      # --- 2. Two classes share `body` (string in both) ---------------------

      class Req
        attr_accessor :body
        def initialize; @body = ""; end
      end

      class Res
        attr_accessor :body
        def initialize; @body = ""; end
      end

      def set_body(o, b)
        o.body = b
      end

      req = Req.new
      res = Res.new
      set_body(req, "REQ")
      set_body(res, "RES")

      puts req.body
      puts res.body


      # --- 3. Two classes share `slot` with *different* value types ---------
      # Pre-fix poly_dispatch_return_type returned "int" for any setter
      # whose name didn't appear as an explicit method, so the result temp
      # was mrb_int and the string arm's `tmp = lv` mismatched. The new
      # arm now also unboxes the rhs to the slot's concrete type when
      # the function param widened to poly.

      class IBox
        attr_accessor :slot
        def initialize; @slot = 0; end
      end

      class SBox
        attr_accessor :slot
        def initialize; @slot = ""; end
      end

      def set_slot(o, v)
        o.slot = v
      end

      ibox = IBox.new
      sbox = SBox.new
      set_slot(ibox, 7)
      set_slot(sbox, "hello")

      puts ibox.slot
      puts sbox.slot
    RUBY

    _(result).must_answer <<~'OUT'
      42
      REQ
      RES
      7
      hello
    OUT
  end

  it "rescue attr with sibling exc subclass" do
    result = ze0(<<~'RUBY')
      # Reading a rescued exception's attr must still compile when the program
      # defines a SECOND, unrelated exception subclass. The second subclass's
      # `initialize` `message` param is never constrained to a String (its own
      # call sites don't pin it), so `super(message)` must coerce the poly message
      # into the const-char* msg slot rather than emit a struct assignment.

      class AError < StandardError
        attr_reader :code
        def initialize(message, code: 3)
          super(message)
          @code = code
        end
      end

      class BError < StandardError
        attr_reader :level
        def initialize(message, level = 7)
          super(message)
          @level = level
        end
      end

      begin
        raise AError.new("boom", code: 9)
      rescue AError => ea
        puts ea.code
        puts "code is #{ea.code}"
      end

      begin
        raise BError.new("bad", 5)
      rescue BError => eb
        puts eb.level
        puts "msg=#{eb.message} level=#{eb.level}"
      end
    RUBY

    _(result).must_answer <<~'OUT'
      9
      code is 9
      5
      msg=bad level=5
    OUT
  end

  it "same named attr no widen" do
    result = ze0(<<~'RUBY')
      # #684: a concretely-typed receiver's attr_reader must not widen to
      # poly just because an unrelated class shares the same attr name.
      class Bag
        attr_accessor :payload
        def initialize; @payload = {"k" => "v"}; end
      end

      class Wire
        attr_accessor :payload
        def initialize; @payload = ""; end
      end

      def first_byte_of(s)
        s.bytes[0]
      end

      def handle_wire(w)
        first_byte_of(w.payload)
      end

      _b = Bag.new
      _w = Wire.new
      _w.payload = "hello"
      puts handle_wire(_w)
    RUBY

    _(result).must_answer "104\n"
  end
end
