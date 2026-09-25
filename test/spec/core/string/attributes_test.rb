# frozen_string_literal: true

require "spec_helper"

describe "String: generated attribute methods" do
  it "alias attr reader source" do
    result = zr(<<~'RUBY')
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
    result = zr(<<~'RUBY')
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
    result = zr(<<~'RUBY')
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
    result = zr(<<~'RUBY')
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
    result = zr(<<~'RUBY')
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
    result = zr(<<~'RUBY')
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
    result = zr(<<~'RUBY')
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
    result = zr(<<~'RUBY')
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
    result = zr(<<~'RUBY')
      # attr_reader/attr_accessor/attr_writer only work in a literal `class`/`module`
      # body. Invoked from inside a `Class.new { ... }` or `#class_eval { ... }`
      # block, zr raises NoMethodError instead of defining the accessor.
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
    result = zr(<<~'RUBY')
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

  it "module singleton attr accessor" do
    result = zr(<<~'RUBY')
      # `module M; class << self; attr_accessor :x; end; end` gives the
      # module a reader and a writer, also when the value written is not
      # a constant. Roundhouse does this with
      # `ActiveRecord.adapter = SqliteAdapter.new` (the RHS is a method
      # call, not a constant). A read before any write returns nil.

      module Cfg
        class << self
          attr_accessor :adapter, :timeout
        end
      end

      # String RHS (non-constant).
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
    result = zr(<<~'RUBY')
      # An attr_reader/attr_accessor whose name collides with a builtin
      # zero-arg method (value/resume/join -> Thread#value, sum/min/max/first/
      # last/sample -> array reductions) must shadow the helper exactly like an
      # explicit `def` does.
      #
      # So `node.value` on an element of an array calls the user reader, and
      # arithmetic on the result works.
      #
      # Reduced from the BART engine, where @roots (an ivar array of Nodes) is
      # read in Tree.leaf_stats' `node.value * node.value`.

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
          @roots = []          # ivar array of user objects
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

      # (The builtin side -- Thread#value through a container when NO user
      # class defines the name -- is covered by thread_value_through_container.rb.
      # This example does not mix a user `value` reader with Threads in a
      # container.)
    RUBY

    _(result).must_answer <<~'OUT'
      2.25
      14
      peak
    OUT
  end

  it "poly attr writer" do
    result = zr(<<~'RUBY')
      # A setter call (`obj.x = val`) on a parameter that can hold objects
      # of more than one class must execute the assignment.
      #
      # Three subcases:
      #  1. Single class with `x`, second class without.
      #  2. Two classes share an ivar name; same value type.
      #  3. Two classes share an ivar name; differing value types
      #     (string vs int).
      #
      # The example checks the *side effect* (the ivar's value), not the
      # return value of the setter expression.

      # --- 1. Single class ----------------------------------------------------

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
      # Each setter stores the value with its own type.

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
    result = zr(<<~'RUBY')
      # Reading a rescued exception's attr works when the program defines a
      # SECOND, unrelated exception subclass. The second subclass's `initialize`
      # `message` param can be any value (its own call sites do not fix its type),
      # and `super(message)` still sets the message.

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
    result = zr(<<~'RUBY')
      # A receiver's attr_reader keeps the type of its own ivar, also when an
      # unrelated class has an attr with the same name.
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
