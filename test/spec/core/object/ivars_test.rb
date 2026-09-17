# frozen_string_literal: true

require "spec_helper"

describe "Object: instance and class variables" do
  it "accessor call is the ivar access" do
    result = ze0(<<~'RUBY')
      # An accessor call on this body's OWN class is replaced by the ivar access
      # itself -- no dispatch, no trampoline, no frame -- at a statically-typed
      # receiver.
      #
      # What must NOT fold, and why each is a question only the run time answers:
      #   - a hand-written accessor under TracePoint or line coverage (it has a
      #     body an instrumented run has to be able to observe)
      #   - an argument count the accessor does not take (ArgumentError)
      #   - a frozen receiver on the writer (FrozenError, from the write itself)
      class C
        attr_accessor :a
        attr_reader :b
        def initialize = (@a = 1; @b = 2)
        def read_a = a
        def read_self_a = self.a
        def write_a(v) = (self.a = v)
        def read_b = b
        def hand_written = @a * 10
        def bad_arity = (a(1) rescue "ArgumentError: #{$!.message}")
      end

      c = C.new
      p [c.read_a, c.read_self_a, c.read_b]
      p c.write_a(9)
      p [c.a, c.read_a]
      p c.hand_written
      p c.bad_arity

      d = C.new.freeze
      begin
        d.write_a(1)
      rescue FrozenError => e
        puts e.message.sub(/0x[0-9a-f]+/, "0xADDR")
      end

      # An inherited accessor read from a subclass body resolves through the
      # chain and folds against the SUBCLASS's own layout.
      class D < C
        def peek = a
        def poke(v) = (self.a = v)
      end
      p D.new.peek
      p D.new.poke(7)

      # A writer answers the value ASSIGNED, whatever the ivar ends up holding.
      class E
        attr_writer :w
        def set(v) = (self.w = v)
        def w = @w
      end
      e = E.new
      p e.set(3)
      p e.w
    RUBY

    _(result).must_answer <<~'OUT'
      [1, 1, 2]
      9
      [9, 9]
      90
      "ArgumentError: wrong number of arguments (given 1, expected 0)"
      can't modify frozen C: #<C:0xADDR @a=1, @b=2>
      1
      7
      3
      3
    OUT
  end

  it "chained ivar write call rhs" do
    result = ze0(<<~'RUBY')
      # Chained `@a = @b = foo` where the rhs is a method call with a side
      # effect. The naive per-slot lowering re-evaluates the rhs once per
      # target, calling foo() N times instead of once. The chain handler
      # must evaluate the rhs once into a temp and store from the temp into
      # each ivar slot.

      $count = 0

      def foo
        $count = $count + 1
        $count
      end

      class C
        def initialize
          @a = "hello"
          @b = 42
        end

        def reset
          @a = @b = foo
        end

        attr_reader :a, :b
      end

      c = C.new
      c.reset
      puts $count
      puts c.b
    RUBY

    _(result).must_answer <<~'OUT'
      1
      1
    OUT
  end

  it "class body ivar write initializes class level state" do
    result = ze0(<<~'RUBY')
      # A bare `@x = ...` directly in a class body -- the ordinary way
      # class-level state gets seeded. It used to fall through `register_class`'s
      # catch-all arm and be SILENTLY DROPPED, leaving the reader a bare nil
      # with no diagnostic at all.

      class Registry
        @items = []
        @count = 0
        def self.add(x); @items << x; @count += 1; self; end
        def self.items; @items; end
        def self.count; @count; end
      end
      Registry.add("a").add("b")
      p Registry.items
      p Registry.count
    RUBY

    _(result).must_answer <<~'OUT'
      ["a", "b"]
      2
    OUT
  end

  it "class ivar and an instance ivar of the same name are distinct storage" do
    _(ze0(<<~'RUBY')).must_answer "[\"class-level\", \"instance-level\"]\n"
      # `@x` in a class body/class method and `@x` in an instance method name
      # two completely different slots -- the class object's own, and the
      # instance's. Also exercises the same-name collision across Ruby's two
      # method namespaces (`def self.x` + `def x`), which share one generated
      # container and so need `ident::class_method_ident`'s mangling.

      class C
        @x = "class-level"
        def initialize; @x = "instance-level"; end
        def self.x; @x; end
        def x; @x; end
      end
      p [C.x, C.new.x]
    RUBY
  end

  it "class ivar in class method" do
    result = ze0(<<~'RUBY')
      # Class-instance-variable accessed inside a class method (def self.x).
      # The emitted C class-method function has no `self`, so `@v` must lower
      # to a per-class static slot rather than `self->iv_v`. Covers the
      # memoized-class-method idiom, plain write+read across calls, the
      # `class << self` form, name collision with an instance ivar, and a
      # nil read before any write.

      class Foo
        def self.cache
          @cache ||= 42
        end
      end
      p Foo.cache

      class Cfg
        def self.label
          @label ||= "config"
        end
      end
      p Cfg.label
      p Cfg.label

      class Bar
        def self.set
          @v = 7
          @v + 1
        end
        def self.get
          @v
        end
      end
      p Bar.set
      p Bar.get
      p Bar.get

      class Baz
        class << self
          def memo
            @m ||= 100
          end
        end
      end
      p Baz.memo

      class Coll
        def initialize
          @v = "inst"
        end
        def v_inst
          @v
        end
        def self.v
          @v ||= "cls"
        end
      end
      o = Coll.new
      p o.v_inst
      p Coll.v
      p o.v_inst

      class NR
        def self.get
          @z
        end
      end
      p NR.get
    RUBY

    _(result).must_answer <<~'OUT'
      42
      "config"
      "config"
      8
      7
      7
      100
      "inst"
      "cls"
      "inst"
      nil
    OUT
  end

  it "class ivar is reachable from a block inside a class method" do
    _(ze0(<<~'RUBY')).must_answer "[10, 20, 30]\n"
      # The block captures `self` as a plain `RubyValue::Class`, so the ivar
      # resolves through `ivar_get_dyn`/`ivar_set_dyn`'s Class arm rather than
      # the static class-id path -- the two must agree on the same storage.

      class Blk
        @vals = []
        def self.collect
          [1, 2, 3].each { |i| @vals << i * 10 }
          @vals
        end
      end
      p Blk.collect
    RUBY
  end

  it "class ivar not inherited" do
    result = ze0(<<~'RUBY')
      # Class-level @ivars are NOT inherited: each class holds its own, and an
      # inherited class method binds to the CALLING class's storage.
      class Base
        @tag = "base"
        def self.tag = @tag
        def self.set(v); @tag = v; end
      end
      class Sub < Base
      end
      Base.set("B")
      Sub.set("S")
      p Base.tag      # "B" -- Base's own @tag
      p Sub.tag       # "S" -- Sub's own @tag (not Base's)

      # read-only: a subclass that never sets its @ivar reads nil, not the parent's
      class Reader
        @v = "r"
        def self.v = @v
      end
      class RSub < Reader
      end
      p Reader.v      # "r"
      p RSub.v        # nil

      # three levels + counter mutation, each class independent
      class A
        @c = 0
        def self.bump; @c += 1; @c; end
        def self.c = @c
      end
      class B < A
        @c = 100
      end
      class C < B
      end
      A.bump; A.bump
      B.bump
      p A.c           # 2
      p B.c           # 101
      p C.c           # nil
    RUBY

    _(result).must_answer <<~'OUT'
      "B"
      "S"
      "r"
      nil
      2
      101
      nil
    OUT
  end

  it "class ivar slots" do
    result = ze0(<<~'RUBY')
      class Base
        @reg = "base-ivar"
        @@cv = "base-cvar"
        def self.reg = @reg
        def self.cv = @@cv
        def self.bump; @n = (@n || 0) + 1; end
        def self.never = @never_written
        def self.pair = [@reg, @reg]
      end
      class Sub < Base; end

      p Base.reg
      p Sub.reg
      p Sub.cv
      p Base.pair

      # Reading a never-assigned class ivar answers nil and must NOT make the name
      # appear in `instance_variables` -- the read is what first reserves storage.
      p Base.never
      p Base.instance_variables

      Base.bump
      Base.bump
      p Base.instance_variable_get(:@n)
      p Base.instance_variables.sort

      # A name the compiler never saw still reaches the same storage.
      Base.instance_variable_set(:@invented, 7)
      p Base.instance_variable_get(:@invented)
      p Base.instance_variables.sort
      p Base.instance_variable_defined?(:@never_written)
      p Base.instance_variable_defined?(:@reg)

      # A subclass gets its own slot, written through the inherited class method.
      Sub.bump
      p [Base.instance_variable_get(:@n), Sub.instance_variable_get(:@n)]

      # One class-level ivar bumped in a thread is visible to the parent.
      module Counter
        @hits = 0
        def self.hit; @hits = @hits + 1; end
        def self.hits = @hits
      end
      Thread.new { 5.times { Counter.hit } }.join
      p Counter.hits

      Base.freeze
      begin
        Base.bump
      rescue => e
        p [e.class, e.message]
      end
    RUBY

    _(result).must_answer <<~'OUT'
      "base-ivar"
      nil
      "base-cvar"
      ["base-ivar", "base-ivar"]
      nil
      [:@reg]
      2
      [:@n, :@reg]
      7
      [:@invented, :@n, :@reg]
      false
      true
      [2, 1]
      5
      [FrozenError, "can't modify frozen Class: Base"]
    OUT
  end

  it "class ivars report assignment order" do
    result = ze0(<<~'RUBY')
      # `Class#instance_variables` reports names in FIRST-ASSIGNMENT order.
      #
      # The intern table cannot supply that order -- a name is interned the first
      # time any emitted site MENTIONS it, which for a read-only `@x` happens
      # before, or instead of, a write -- so a sorted answer stood in for it and
      # a class assigning `@b` before `@a` reported `[:@a, :@b]`. Each slot now
      # stamps its own first write.

      class Ord
        @b = 1
        @a = 2
        @m = 3
      end
      p Ord.instance_variables

      module ModOrd
        @z = 1
        @y = 2
      end
      p ModOrd.instance_variables

      # The INSTANCE side already reports assignment order, and is here so a
      # regression names which half broke.
      class Inst
        def initialize
          @b = 1
          @a = 2
        end
      end
      p Inst.new.instance_variables
    RUBY

    _(result).must_answer <<~'OUT'
      [:@b, :@a, :@m]
      [:@z, :@y]
      [:@b, :@a]
    OUT
  end

  it "default arg ivar value receiver" do
    _(ze0(<<~'RUBY')).must_answer "v\n"
      # An @ivar read in a default-argument value, on a value-type receiver, must
      # dereference the receiver with `.` (value struct), not `->`.
      class C
        def initialize
          @r = "v"
        end
        def get_it(r = @r)
          r
        end
      end
      puts C.new.get_it
    RUBY
  end

  it "dup and clone on user objects copy ivars shallowly" do
    result = ze0(<<~'RUBY')
      class Point
        attr_accessor :x, :y

        def initialize(x, y)
          @x = x
          @y = y
        end
      end

      p1 = Point.new(1, 2)
      p2 = p1.dup
      p2.x = 99
      puts p1.x
      puts p2.x
      puts p2.y
      p1.freeze
      puts p1.clone.frozen?
      puts p1.dup.frozen?
    RUBY

    _(result).must_answer <<~'OUT'
      1
      99
      2
      true
      false
    OUT
  end

  it "if ivar generated writer" do
    result = ze0(<<~'RUBY')
      # `if obj.attr` had its live branch dropped when the backing ivar's only
      # VISIBLE write was the constructor's nil and the real value arrived through a
      # generated setter. emit_if folds a branch away when every program-wide write
      # to the ivar assigns nil, but attr_writer / attr_accessor synthesize the
      # setter, so `c.w = [0.5]` is a CallNode against a body that has no AST and the
      # scan never saw it. The program took the else branch forever, silently.
      # (matz/spinel#4107)
      class Ctx
        attr_accessor :w
        def initialize
          @w = nil
        end
      end

      def probe(c)
        if c.w
          "truthy"
        else
          "falsy"
        end
      end

      c = Ctx.new
      c.w = [0.5, 0.25]
      puts probe(c)
      # The same read reported the value as present all along, which is what made the
      # bad branch silent rather than loud.
      puts c.w.nil?
      puts c.w.is_a?(Array)

      # The other entry point: a generated writer plus a direct @w read inside the
      # class, which reaches the fold through static_nil_ivar_cond instead.
      class Direct
        attr_writer :v
        def initialize
          @v = nil
        end
        def check
          if @v
            "set"
          else
            "unset"
          end
        end
      end

      d = Direct.new
      d.v = 7
      puts d.check

      # A Struct's members are generated writers too.
      Point = Struct.new(:x)
      pt = Point.new(nil)
      pt.x = 3
      puts(pt.x ? "struct-set" : "struct-unset")

      # A writer reached through the superclass counts as generated as well.
      class Base
        attr_accessor :z
      end
      class Derived < Base
        def initialize
          @z = nil
        end
        def check
          if @z
            "inherited-set"
          else
            "inherited-unset"
          end
        end
      end
      dd = Derived.new
      dd.z = "here"
      puts dd.check

      # A hand-written setter is the boundary on the other side: its body holds a
      # real write node, which the scan already counts, so nothing about the fold
      # changes for it. (This case comes from bartleusink's #4108, which found the
      # same bug and drew the boundary in both directions.)
      class HandWritten
        attr_reader :h
        def initialize
          @h = nil
        end
        def h=(v)
          @h = v
        end
      end
      hw = HandWritten.new
      hw.h = [2.0]
      puts(hw.h ? "hand-written-set" : "hand-written-unset")

      # The fold itself is still wanted: with no writer of any kind, an ivar written
      # only nil really is statically falsy, and the branch really is dead.
      class NoWriter
        attr_reader :m
        def initialize
          @m = nil
        end
      end
      nw = NoWriter.new
      puts(nw.m ? "unreachable" : "correctly-falsy")
    RUBY

    _(result).must_answer <<~'OUT'
      truthy
      false
      true
      set
      struct-set
      inherited-set
      hand-written-set
      correctly-falsy
    OUT
  end

  it "included module method mutates an ivar on the includer" do
    _(ze0(<<~'RUBY')).must_answer "3\n"
      # Real self/ivar capture for a materialized module method -- proves
      # the module body was re-typechecked against the INCLUDER's own
      # concrete struct, not some shared/aliased representation.

      module Counter
        def bump
          @count += 1
        end
      end
      class Widget
        include Counter
        def initialize
          @count = 0
        end
        def count
          @count
        end
      end
      w = Widget.new
      w.bump
      w.bump
      w.bump
      puts w.count
    RUBY
  end

  it "instance variable get poly recv" do
    result = ze0(<<~'RUBY')
      # instance_variable_get with a literal :@name on a receiver whose static
      # type is poly: dispatch the field read over every instantiated class that
      # owns the slot, unifying the declared slot types (mixed types stay poly,
      # a single shared type stays concrete).

      class Grid
        def initialize
          @columns = [["a", 1], ["b", 2], ["c", 3]]
        end
      end

      class Table
        def initialize
          @columns = { "w" => "hash-w", "h" => "hash-h" }
        end
      end

      class Deck
        def initialize
          @rows = [10, 20, 30]
        end
      end

      class Pile
        def initialize
          @rows = [7, 8]
        end
      end

      class Manager
        # called with Grid and Table, so obj unifies to poly; the slot types
        # differ (array vs hash), so the result stays poly too
        def describe(obj)
          cols = obj.instance_variable_get(:@columns)
          puts cols.length
          if obj.is_a?(Grid)
            p cols[0]
          else
            p cols["w"]
          end
        end

        # called with Deck and Pile, so obj unifies to poly; both slots are
        # integer arrays, so the unified result type is concrete
        def row_info(obj)
          rows = obj.instance_variable_get(:@rows)
          puts rows.length
          puts rows[1]
        end
      end

      m = Manager.new
      m.describe(Grid.new)
      m.describe(Table.new)
      m.row_info(Deck.new)
      m.row_info(Pile.new)
    RUBY

    _(result).must_answer <<~'OUT'
      3
      ["a", 1]
      2
      "hash-w"
      3
      20
      2
      8
    OUT
  end

  it "instance variables" do
    result = ze0(<<~'RUBY')
      # Any object can reflect over its instance variables by name.
      class Point
        def initialize(x, y)
          @x = x
          @y = y
        end
      end

      p1 = Point.new(3, 4)
      p p1.instance_variables               # [:@x, :@y]
      p p1.instance_variable_get(:@x)       # 3

      # Setting works too, and the string form of the name is accepted.
      p1.instance_variable_set(:@x, 30)
      p p1.instance_variable_get("@x")      # 30

      # A never-declared name reads as nil; an object with no ivars lists none.
      p p1.instance_variable_get(:@z)       # nil
      class Empty; end
      p Empty.new.instance_variables        # []

      # The same reflection works when the receiver's class isn't statically known
      # -- e.g. a method parameter that receives objects of different classes.
      class Circle
        def initialize(r)
          @r = r
        end
      end

      def radius_or_x(shape)
        shape.instance_variable_get(:@r) || shape.instance_variable_get(:@x)
      end

      p radius_or_x(Circle.new(5))          # 5
      p radius_or_x(Point.new(1, 2))        # 1

      # A malformed ivar name raises NameError.
      begin
        p1.instance_variable_get(:x)
      rescue NameError => e
        puts e.message                      # 'x' is not allowed as an instance variable name
      end
    RUBY

    _(result).must_answer <<~'OUT'
      [:@x, :@y]
      3
      30
      nil
      []
      5
      1
      'x' is not allowed as an instance variable name
    OUT
  end

  it "instance variables list" do
    result = ze0(<<~'RUBY')
      # Object#instance_variables lists the object's ivar names as symbols
      # (the class layout is static, so the list is compile-time known).
      class C
        def initialize
          @a = 1
          @b = 2
        end
      end
      p C.new.instance_variables
      c = C.new
      p c.instance_variables
      p c.instance_variable_get(:@a)
      c.instance_variable_set(:@a, 9)
      p c.instance_variable_get(:@a)
      class Empty; end
      p Empty.new.instance_variables
    RUBY

    _(result).must_answer <<~'OUT'
      [:@a, :@b]
      [:@a, :@b]
      1
      9
      []
    OUT
  end

  it "ivar assign and expr" do
    result = ze0(<<~'RUBY')
      # `@x = expr and rest` parses as `(@x = expr) and rest`; @x must be
      # typed from expr (poly), not the boolean `and` result.
      class C
        def initialize(o = {})
          @debug = o[:debug] and o[:debug] == true
        end
        def debug; @debug; end
      end
      p C.new(debug: true).debug
      p C.new.debug
      # `@x = @x + 1` as a method's value returns the (boxed) slot value.
      class A
        def initialize(attrs = {})
          @id = attrs[:id] || 0
        end
        def bump = (@id = @id + 1)
        def id = @id
      end
      a = A.new(id: 10)
      a.bump
      a.bump
      puts a.id
    RUBY

    _(result).must_answer <<~'OUT'
      true
      nil
      12
    OUT
  end

  it "ivar assignment order" do
    result = ze0(<<~'RUBY')
      # `instance_variables` and the default `inspect` report ivars in the order they
      # were first ASSIGNED, which two instances of one class can disagree about.
      class S
        def initialize(reverse)
          if reverse
            @b = 2
            @a = 1
          else
            @a = 1
            @b = 2
          end
        end
      end
      p S.new(false).instance_variables
      p S.new(true).instance_variables
      # The address in an object's default inspect is not reproducible.
      def shape(o) = o.inspect.sub(/0x\h+/, "0xX")
      p shape(S.new(false))
      p shape(S.new(true))

      # Removing an ivar and assigning it again moves it to the END.
      class T
        def initialize
          @a = 1
          @b = 2
          @c = 3
        end

        def shuffle
          remove_instance_variable(:@a)
          @a = 9
        end
      end
      t = T.new
      p t.instance_variables
      t.shuffle
      p t.instance_variables
      p shape(t)

      # An invented ivar takes its place in the same sequence.
      u = T.new
      u.instance_variable_set(:@z, 26)
      u.shuffle
      p u.instance_variables
      p u.dup.instance_variables

      # Assigning nil still counts as an assignment; reading never does.
      class V
        def initialize(assign)
          @first = nil if assign
          @second = 2
        end

        def peek = @first
      end
      v = V.new(false)
      p v.peek
      p v.instance_variables
      p V.new(true).instance_variables
    RUBY

    _(result).must_answer <<~'OUT'
      [:@a, :@b]
      [:@b, :@a]
      "#<S:0xX @a=1, @b=2>"
      "#<S:0xX @b=2, @a=1>"
      [:@a, :@b, :@c]
      [:@b, :@c, :@a]
      "#<T:0xX @b=2, @c=3, @a=9>"
      [:@b, :@c, :@z, :@a]
      [:@b, :@c, :@z, :@a]
      nil
      [:@second]
      [:@first, :@second]
    OUT
  end

  it "ivar conditional nil" do
    result = ze0(<<~'RUBY')
      # An unwritten instance variable reads as nil, so a conditional first write
      # (`||=`) sees nil and assigns rather than seeing a typed zero.
      class Counter
        def bump
          @n ||= 10
          @n += 1
          @n
        end
      end
      p Counter.new.bump      # 11  (was 1: @n had started at 0, so `0 ||= 10` kept 0)

      # `.nil?` and `|| default` on an unwritten int ivar.
      class Box
        def empty?
          @v.nil?
        end

        def value
          @v || 42
        end
      end
      b = Box.new
      p b.empty?              # true
      p b.value               # 42

      # An unconditionally initialized int ivar is unaffected (stays its real value).
      class Init
        def initialize
          @k = 0
        end

        def k
          @k
        end
      end
      p Init.new.k            # 0
    RUBY

    _(result).must_answer <<~'OUT'
      11
      true
      42
      0
    OUT
  end

  it "ivar definedness" do
    result = ze0(<<~'RUBY')
      # Ruby distinguishes a never-assigned ivar from one assigned `nil`: both READ
      # as nil, but only the second is `defined?` and only the second appears in
      # `instance_variables`. `@x = {} unless defined? @x` -- observer's idiom --
      # depends on it.
      class Slot
        def probe
          before = [defined?(@a), instance_variables]
          @a = nil
          middle = [defined?(@a), instance_variables]
          @a = 1
          [before, middle, [defined?(@a), instance_variables]]
        end

        def lazy
          @memo = [] unless defined? @memo
          @memo << :x
          @memo
        end

        def drop
          @gone = 1
          removed = remove_instance_variable(:@gone)
          [removed, defined?(@gone), @gone]
        end
      end

      p Slot.new.probe
      p Slot.new.lazy
      p Slot.new.drop

      begin
        Slot.new.send(:remove_instance_variable, :@never)
      rescue NameError => e
        puts e.message
      end

      # A fresh object has no ivars at all, so `inspect` shows none.
      class Empty
        def initialize(set) = (@v = 1 if set)
      end
      p Empty.new(false).instance_variables
      p Empty.new(true).instance_variables
      p Empty.new(false).instance_variable_get(:@v)
      p Empty.new(false).instance_variable_defined?(:@v)
      p Empty.new(true).instance_variable_defined?(:@v)

      # ...and dup/clone carry only what was actually assigned.
      p Empty.new(false).dup.instance_variables
      p Empty.new(true).clone.instance_variables

      # An ivar invented at runtime behaves the same way.
      o = Empty.new(false)
      p o.instance_variable_defined?(:@invented)
      o.instance_variable_set(:@invented, 7)
      p o.instance_variables, o.instance_variable_defined?(:@invented)
    RUBY

    _(result).must_answer <<~'OUT'
      [[nil, []], ["instance-variable", [:@a]], ["instance-variable", [:@a]]]
      [:x]
      [1, nil, nil]
      instance variable @never not defined
      []
      [:@v]
      nil
      false
      true
      []
      [:@v]
      false
      [:@invented]
      true
    OUT
  end

  it "ivar empty seed explicit grow" do
    result = ze0(<<~'RUBY')
      class B
        def initialize
          @a = []
          nil
        end

        def add(x)
          @a = @a + [x]
          nil
        end

        def get
          @a
        end
      end

      b = B.new
      b.add("z")
      p b.get

      m = B.new
      m.add("x")
      m.add("y")
      m.add("z")
      p m.get
      p m.get.length
      p m.get.join(",")

      class S
        def initialize
          @a = []
          nil
        end

        def add(x)
          @a = @a + [x]
          nil
        end

        def get
          @a
        end
      end

      [:z, 1.5, true, 1].each do |v|
        s = S.new
        s.add(v)
        p s.get
      end

      # the desugared and mutating spellings already worked; keep them pinned
      class T
        def initialize
          @a = []
          nil
        end

        def plus(x)
          @a += [x]
          nil
        end

        def shovel(x)
          @a << x
          nil
        end

        def get
          @a
        end
      end

      t = T.new
      t.plus("p")
      t.shovel("s")
      p t.get

      # computed inside the class, which was correct before too
      class U
        def initialize
          @a = []
          nil
        end

        def add(x)
          @a = @a + [x]
          nil
        end

        def joined
          @a.join(",")
        end

        def sorted
          @a.sort.join(",")
        end
      end

      u = U.new
      u.add("b")
      u.add("a")
      p u.joined
      p u.sorted
    RUBY

    _(result).must_answer <<~'OUT'
      ["z"]
      ["x", "y", "z"]
      3
      "x,y,z"
      [:z]
      [1.5]
      [true]
      [1]
      ["p", "s"]
      "b,a"
      "a,b"
    OUT
  end

  it "ivar name is validated in full" do
    result = ze0(<<~'RUBY')
      # `instance_variable_get`/`set` validate the whole name: "@@bad" (a class
      # variable spelling) raises NameError "'@@bad' is not allowed as an
      # instance variable name". zeo answers nil for the get. A plain bad name
      # (:novar) is already refused. (Found by the 2026-08-24 probe sweep.)
      begin
        p Object.new.instance_variable_get("@@bad")
      rescue NameError => e
        puts e.message
      end
      begin
        Object.new.instance_variable_set("@@bad", 1)
      rescue NameError => e
        puts e.message
      end
    RUBY

    _(result).must_answer <<~'OUT'
      '@@bad' is not allowed as an instance variable name
      '@@bad' is not allowed as an instance variable name
    OUT
  end

  it "ivar on a bare value survives address reuse" do
    result = ze0(<<~'RUBY')
      # An ivar written on a bare heap value is filed under the value's ADDRESS,
      # which is unique only while the value lives. The table holds a WEAK reference
      # to every owner so the allocation -- and therefore the address -- stays
      # reserved; the ivar row is dropped in the same sweep that lets the pin go.
      #
      # The order inside that sweep is the whole of it. Dropping the pin is what
      # frees the allocation and lets the allocator hand the address out again, so
      # the ivar row has to go first. Reversing the two lines makes both counts
      # below read 2000: every later value of the same shape lands on a dead one's
      # address and inherits its ivars. `tests/spinel/singleton_address_reuse.rb` is
      # the same test for the singleton table, which made exactly that mistake.
      def with_ivar
        a = [1, 2, 3]
        a.instance_variable_set(:@tag, "mine")
        a
      end

      def with_str_ivar
        s = "victim"
        s.instance_variable_set(:@mark, 1)
        s
      end

      400.times { with_ivar }
      400.times { with_str_ivar }
      GC.start

      strays = [0, 0]
      2000.times do
        strays[0] += 1 unless [9, 8, 7].instance_variables.empty?
        strays[1] += 1 unless ("x" * 6).instance_variables.empty?
      end
      p strays

      # The live owners still answer, which is what the pin has to preserve.
      p with_ivar.instance_variable_get(:@tag)
      p with_str_ivar.instance_variable_get(:@mark)

      # `dup` carries ivars (only singletons are clone-only), onto a fresh identity.
      kept = with_ivar
      p kept.dup.instance_variable_get(:@tag)
      p kept.dup.equal?(kept)
    RUBY

    _(result).must_answer <<~'OUT'
      [0, 0]
      "mine"
      1
      "mine"
      false
    OUT
  end

  it "ivar or write empty literal variant" do
    result = ze0(<<~'RUBY')
      # An empty `{}` / `[]` has no elements to type it, so inference gives the
      # literal whatever the reads elsewhere suggest. The plain ivar write lends the
      # literal its slot's variant; `||=` did not, so a module registry built one
      # hash layout while every write and read of the slot used another, and the C
      # build stopped on the pointer types. (matz/spinel#4111)
      module Registry
        @reg ||= {}
        def self.register(extension, klass)
          extension = [extension] unless Array === extension
          extension.each { |e| @reg[e] = klass }
        end
        def self.find(path)
          @reg[path.gsub(/.*\./, "")]
        end
      end
      Registry.register("rb", Object)
      Registry.register(["txt", "md"], String)
      p Registry.find("x.rb")
      p Registry.find("notes.md")
      p Registry.find("x.zzz")

      # The same on an instance ivar, and with the empty literal on the right of a
      # `&&=` as well as a `||=`.
      class Bag
        def initialize
          @items ||= {}
          @seen  ||= []
        end
        def add(k, v)
          @items[k] = v
          @seen << k
          self
        end
        def get(k) = @items[k]
        def seen = @seen
      end
      b = Bag.new
      b.add(1, "one").add(:two, 2)
      p b.get(1)
      p b.get(:two)
      p b.seen

      # A poly-keyed write and a String-keyed read on the same slot: the pairing that
      # split the variant in the first place.
      module Mixed
        @m ||= {}
        def self.put(k) = @m[k] = k.to_s
        def self.get(k) = @m[k]
      end
      Mixed.put("s")
      Mixed.put(7)
      p Mixed.get("s")
      p Mixed.get(7)
    RUBY

    _(result).must_answer <<~'OUT'
      Object
      String
      nil
      "one"
      2
      [1, :two]
      "s"
      "7"
    OUT
  end

  it "ivar polymorphic" do
    result = ze0(<<~'RUBY')
      # Issue #130: instance variable assigned different definite-typed values
      # across methods used to either fail to compile (-Wint-conversion under
      # -Werror), silently coerce (Integer→Float when slot won inference as Float),
      # or segfault. Fix is in scan_ivars: when both writes are definite-literal
      # and types disagree, widen the slot to poly. Write sites then box every
      # concrete-typed RHS to sp_RbVal; read sites already use sp_poly_puts and
      # friends.
      #
      # Variant 3 of the issue (ternary RHS with mixed types in a single-write
      # slot) is a different root — the slot widens to "int" because IfNode
      # isn't a definite-literal — and is filed separately.

      # 1. String + Integer — variant 1 from the issue. Original symptom:
      #    -Wint-conversion warning, indeterminate runtime output.
      class C1
        def set_int; @x = 42; end
        def set_str; @x = "hello"; end
        def show; puts @x; end
      end

      c1 = C1.new
      c1.set_int; c1.show                  # 42
      c1.set_str; c1.show                  # hello

      # 2. Integer + Float — variant 2. Original symptom: silent coercion;
      #    `42` printed as `42.0` because the slot won inference as Float.
      class C2
        def set_int; @x = 42; end
        def set_float; @x = 3.14; end
        def show; puts @x; end
      end

      c2 = C2.new
      c2.set_int; c2.show                  # 42
      c2.set_float; c2.show                # 3.14

      # 3. String + Symbol — already widened to poly in pre-#130 inference but
      #    didn't compile because write sites weren't boxed. Pins the boxing fix.
      class C3
        def set_str; @x = "hello"; end
        def set_sym; @x = :world; end
        def show; puts @x; end
      end

      c3 = C3.new
      c3.set_str; c3.show                  # hello
      c3.set_sym; c3.show                  # world

      # 4. Three concrete types in different methods — slot stays poly across
      #    each disagreement.
      class C4
        def set_int; @x = 100; end
        def set_str; @x = "txt"; end
        def set_float; @x = 2.5; end
        def show; puts @x; end
      end

      c4 = C4.new
      c4.set_int; c4.show                  # 100
      c4.set_str; c4.show                  # txt
      c4.set_float; c4.show                # 2.5

      # 5. Single-type ivar — regression guard. The pre-#130 happy path stays
      #    happy. No widening, slot stays mrb_int.
      class C5
        def set; @x = 42; end
        def show; puts @x; end
      end

      c5 = C5.new
      c5.set; c5.show                      # 42

      # 6. Initialize sets one type, another method sets another. Constructor
      #    body has its own ivar-write emit path (separate from the general
      #    InstanceVariableWriteNode case); this pins both paths box correctly.
      class C6
        def initialize
          @x = 42
        end
        def set_str; @x = "hello"; end
        def show; puts @x; end
      end

      c6 = C6.new
      c6.show                              # 42
      c6.set_str
      c6.show                              # hello
    RUBY

    _(result).must_answer <<~'OUT'
      42
      hello
      42
      3.14
      hello
      world
      100
      txt
      2.5
      42
      42
      hello
    OUT
  end

  it "ivar tail write return" do
    result = ze0(<<~'RUBY')
      # A plain tail instance-variable write is the method's value in Ruby
      # (`def m; @x = v; end` answers v). Returning the statement default instead
      # handed back the slot type's nil: NULL for an Array (the caller segfaulted on
      # the first `.length`), 0 for an Integer, "" for a String, {} for a Hash.
      # #3317 routed only an OBJECT-valued tail ivar write through the value path,
      # and `def m = (@x = v)` parses as a value so the endless form was already
      # right; the ordinary statement form was not. (matz/spinel#1484 covers the
      # operator-assignment form, which already worked.)
      class Slots
        def initialize
          @i = nil
          @s = nil
          @a = nil
          @h = nil
          @f = nil
        end

        def int_tail;   @i = 7;         end
        def str_tail;   @s = "hi";      end
        def arr_tail;   @a = [1, 2, 3]; end
        def hash_tail;  @h = { a: 1 };  end
        def float_tail; @f = 2.5;       end
      end

      s = Slots.new
      p s.int_tail
      p s.str_tail
      p s.arr_tail
      p s.hash_tail
      p s.float_tail

      # The value is returned AND stored: the slot keeps it for the next read.
      class Once
        def initialize; @v = nil; end
        def store; @v = [4, 5]; end
        def read; @v; end
      end
      o = Once.new
      p o.store
      p o.read

      # The classic memoization guard: first call must build and answer the value,
      # not the unassigned slot. The Array case used to segfault the caller here.
      class Memo
        def initialize; @cache = nil; end
        def build
          return @cache if @cache
          @cache = [1, 2, 3]
        end
      end
      m = Memo.new
      puts m.build.length
      puts m.build.length

      # Assigning a value computed into a local, with the write as the last
      # expression (no trailing bare read to rescue it).
      class FromLocal
        def initialize; @c = nil; end
        def build
          r = []
          3.times { |i| r << i }
          @c = r
        end
      end
      p FromLocal.new.build

      # A tail write whose value came in as a parameter.
      class FromParam
        def initialize; @p = nil; end
        def set(list); @p = list; end
      end
      p FromParam.new.set([9, 9])

      # The endless-def form keeps working (it already did).
      class Endless
        def initialize; @e = nil; end
        def set = (@e = [1, 2, 3])
      end
      p Endless.new.set

      # The write is evaluated exactly once -- a side-effecting value expression
      # must not run twice now that the slot is read back.
      class OnceOnly
        def initialize; @n = nil; @calls = 0; end
        def bump; @calls += 1; [@calls]; end
        def set; @n = bump; end
        def calls; @calls; end
      end
      oo = OnceOnly.new
      p oo.set
      p oo.calls
    RUBY

    _(result).must_answer <<~'OUT'
      7
      "hi"
      [1, 2, 3]
      {a: 1}
      2.5
      [4, 5]
      [4, 5]
      3
      3
      [0, 1, 2]
      [9, 9]
      [1, 2, 3]
      [1]
      1
    OUT
  end

  it "ivar ternary mixed" do
    result = ze0(<<~'RUBY')
      # Issue #131: a single-write ivar whose RHS is a ternary (or if-as-
      # expression) with branches of different concrete types used to type
      # the slot from `infer_ivar_init_type`'s default fallback ("int") and
      # emit a raw `(cond ? then : else)` C ternary into a typed slot —
      # pointer/integer mismatch warning, segfault at runtime.
      #
      # Fix: `infer_ivar_init_type` recurses into IfNode branches with strict
      # unification (no "int is default" escape hatch); `box_expr_to_poly`
      # always per-branch boxes IfNode in poly contexts. Slot widens to poly
      # for mixed-type branches; same-type branches infer as that type and
      # the existing path applies.

      # 1. Ternary mixing String and Integer — variant 3 from #130.
      #    Was: -Wconditional-type-mismatch and segfault.
      class C1
        def init(use_str)
          @x = use_str ? "hello" : 42
        end
        def show; puts @x; end
      end

      c1 = C1.new
      c1.init(false); c1.show              # 42
      c1.init(true);  c1.show              # hello

      # 2. Same shape with Integer/Float — silent-coerce in pre-fix codegen.
      class C2
        def init(use_int)
          @x = use_int ? 100 : 1.5
        end
        def show; puts @x; end
      end

      c2 = C2.new
      c2.init(true);  c2.show              # 100
      c2.init(false); c2.show              # 1.5

      # 3. Mixed-type ternary combined with later concrete write — must
      #    interact with #130's multi-write widening: poly + concrete = stay poly.
      class C3
        def init(use_str)
          @x = use_str ? "hello" : 42
        end
        def overwrite_sym
          @x = :sym
        end
        def show; puts @x; end
      end

      c3 = C3.new
      c3.init(true);  c3.show              # hello
      c3.overwrite_sym; c3.show            # sym
      c3.init(false); c3.show              # 42

      # 4. Same-type ternary — regression guard. Both branches int, slot
      #    stays mrb_int, no boxing overhead.
      class C4
        def init(big)
          @x = big ? 1000 : 1
        end
        def show; puts @x; end
      end

      c4 = C4.new
      c4.init(true);  c4.show              # 1000
      c4.init(false); c4.show              # 1

      # 5. Same-type-string ternary — regression guard. Slot stays string.
      class C5
        def init(loud)
          @x = loud ? "HEY" : "hi"
        end
        def show; puts @x; end
      end

      c5 = C5.new
      c5.init(true);  c5.show              # HEY
      c5.init(false); c5.show              # hi

      # 6. if-as-expression form (statement-style) with mixed types.
      #    Same AST shape (IfNode) as ternary, just multi-line surface syntax.
      class C6
        def init(use_str)
          @x = if use_str
                 "world"
               else
                 99
               end
        end
        def show; puts @x; end
      end

      c6 = C6.new
      c6.init(true);  c6.show              # world
      c6.init(false); c6.show              # 99

      # 7. Ternary with nil branch — should widen to nullable string,
      #    not poly. Let the existing nullable widening flow through.
      class C7
        def init(have)
          @x = have ? "yes" : nil
        end
        def show; puts @x.nil? ? "nope" : @x; end
      end

      c7 = C7.new
      c7.init(true);  c7.show              # yes
      c7.init(false); c7.show              # nope
    RUBY

    _(result).must_answer <<~'OUT'
      42
      hello
      100
      1.5
      hello
      sym
      42
      1000
      1
      HEY
      hi
      world
      99
      yes
      nope
    OUT
  end

  it "ivar type per owning class" do
    result = ze0(<<~'RUBY')
      # An ivar's element type must not leak between classes that merely share the
      # ivar's NAME. Ivar slots are per-class, but the two queries that disambiguate
      # `<<` (Array#push vs Integer#<< shift vs a user-defined operator) index writes
      # by name and then filter by SCOPE for a local and by nothing for an ivar. So a
      # numeric `@threads = 1` in one class answered a question asked about a
      # completely unrelated `@threads` in another: the push promotion was declined
      # there, the bare `[]` never learned its element type, and the slot kept the
      # empty literal's default int array. Pushing a pointer element into it then
      # failed at `cc` with an int-conversion error.
      #
      # Same family as the `strbuf_mut_kind` gate: a name-keyed table cannot tell
      # `out << "x"` from `b0 << 4`, so every use needs the owner as part of the key.

      class Config
        def initialize
          @threads = 1
        end
        def n
          @threads
        end
      end

      class Pool
        def initialize
          @threads = []
          @threads << "w1"
          @threads << "w2"
        end
        def names
          @threads
        end
      end

      p Config.new.n
      p Pool.new.names

      # The owner can also be the top-level main object, whose ivars live outside any
      # class -- it must not collide with the first real class either.
      @threads = 3
      class Box
        def initialize
          @threads = []
          @threads << "b"
        end
        def items
          @threads
        end
      end

      p @threads
      p Box.new.items

      # The guard the above narrows still has to fire WITHIN one class: `@bits` really
      # is numeric here, so `@bits << 3` is Integer#<< (a shift), not a push. Getting
      # this wrong is silent -- a wrong answer, not a compile error.
      class Shifter
        def initialize
          @bits = 1
        end
        def shl
          @bits = @bits << 3
          @bits
        end
      end

      p Shifter.new.shl
    RUBY

    _(result).must_answer <<~'OUT'
      1
      ["w1", "w2"]
      3
      ["b"]
      8
    OUT
  end

  it "ivars" do
    _(ze0(<<~'RUBY')).must_answer "5\n"
      class Point
        def initialize(x)
          @x = x
        end

        def x
          @x
        end
      end

      puts Point.new(5).x
    RUBY
  end

  it "ivars on a bare value" do
    result = ze0(<<~'RUBY')
      # Ruby lets you hang an instance variable on almost anything. An Object keeps
      # its ivars in its own struct and a class keeps them in `civars`; a bare
      # Array/String/Hash/Proc has neither, so zeo stores theirs in an
      # identity-keyed table beside the value (`value_ivars`).
      #
      # The permanently-frozen tier is the only refusal, and it is a FrozenError
      # rather than a silent no-op: an Integer, a Symbol, `nil`, a Range.

      puts "== the heap kinds accept one"
      [[], +"s", {}, proc {}, Regexp.new("x"), /x/.match("x")].each do |v|
        v.instance_variable_set(:@x, 1)
        p [v.class, v.instance_variable_get(:@x), v.instance_variables, v.instance_variable_defined?(:@x)]
      end

      puts "== the frozen tier raises"
      [1, 1.5, :s, nil, true, (1..2), [].freeze].each do |v|
        begin
          v.instance_variable_set(:@x, 1)
        rescue => e
          puts "#{v.class}: #{e.class}"
        end
      end

      puts "== assignment order, and a second write keeps its place"
      a = []
      a.instance_variable_set(:@b, 2)
      a.instance_variable_set(:@a, 1)
      a.instance_variable_set(:@b, 9)
      p [a.instance_variables, a.instance_variable_get(:@b)]

      puts "== two values of the same kind do not share"
      one = []
      two = []
      one.instance_variable_set(:@k, 1)
      p [one.instance_variables, two.instance_variables, two.instance_variable_get(:@k)]

      puts "== remove"
      p a.remove_instance_variable(:@b)
      p a.instance_variables
      begin
        a.remove_instance_variable(:@b)
      rescue NameError => e
        puts e.message
      end

      puts "== instance_eval and instance_exec reach the same store"
      b = []
      b.instance_eval { @y = 5 }
      p [b.instance_variables, b.instance_eval { @y }]
      b.instance_exec(7) { |n| @y = n }
      p b.instance_variable_get(:@y)

      puts "== an unset ivar reads nil, it does not raise"
      p [[].instance_variable_get(:@nope), [].instance_eval { @nope }]

      puts "== dup and clone carry them"
      c = +"str"
      c.instance_variable_set(:@z, 9)
      p [c.dup.instance_variables, c.clone.instance_variables, c.dup.instance_variable_get(:@z)]
      # The copy is its own value: writing one must not touch the other.
      d = c.dup
      d.instance_variable_set(:@z, 100)
      p [c.instance_variable_get(:@z), d.instance_variable_get(:@z)]

      puts "== the value itself is unchanged -- inspect and == ignore ivars"
      p c
      p [c == "str", b, b == []]

      puts "== a module mixed in with extend can read them"
      module Reader
        def z = @z
      end
      e = []
      e.extend(Reader)
      e.instance_variable_set(:@z, 42)
      p e.z

      puts "== defined?"
      f = []
      p defined?(f.instance_variables)
      f.instance_variable_set(:@q, 1)
      p f.instance_eval { defined?(@q) }
      p f.instance_eval { defined?(@never) }
    RUBY

    _(result).must_answer <<~'OUT'
      == the heap kinds accept one
      [Array, 1, [:@x], true]
      [String, 1, [:@x], true]
      [Hash, 1, [:@x], true]
      [Proc, 1, [:@x], true]
      [Regexp, 1, [:@x], true]
      [MatchData, 1, [:@x], true]
      == the frozen tier raises
      Integer: FrozenError
      Float: FrozenError
      Symbol: FrozenError
      NilClass: FrozenError
      TrueClass: FrozenError
      Range: FrozenError
      Array: FrozenError
      == assignment order, and a second write keeps its place
      [[:@b, :@a], 9]
      == two values of the same kind do not share
      [[:@k], [], nil]
      == remove
      9
      [:@a]
      instance variable @b not defined
      == instance_eval and instance_exec reach the same store
      [[:@y], 5]
      7
      == an unset ivar reads nil, it does not raise
      [nil, nil]
      == dup and clone carry them
      [[:@z], [:@z], 9]
      [9, 100]
      == the value itself is unchanged -- inspect and == ignore ivars
      "str"
      [true, [], true]
      == a module mixed in with extend can read them
      42
      == defined?
      "method"
      "instance-variable"
      nil
    OUT
  end

  it "masgn ivar empty literals" do
    result = ze0(<<~'RUBY')
      # Instance-variable multi-assignment with empty hash/array literals: the
      # element temps adopt the ivar's type (poly ivars take a fresh boxed
      # container), and the assignment boxes from the temp's resolved type (#3280).
      class MyClass
        attr_reader :foo, :bar, :baz, :qux, :quux
        def initialize
          @foo, @bar = {}, {}
          @baz, @qux, @quux = [], [], []
        end
      end
      m = MyClass.new
      p m.foo
      p m.bar
      p m.baz
      p m.quux
      puts "OK"
    RUBY

    _(result).must_answer <<~'OUT'
      {}
      {}
      []
      []
      OK
    OUT
  end

  it "module def self ivar" do
    result = ze0(<<~'RUBY')
      # Issue #713. Module class methods (`def self.X`) writing/reading
      # `@ivar` need a module-level `cst_<Mod>_<ivar>` slot or the codegen
      # emits `self->iv_X` against a non-existent `self` in the top-level
      # function. The walk now scans each `def self.X` body and pre-registers
      # every observed @ivar as a const slot.

      module M
        def self.set(v); @v = v; end
        def self.get; @v; end
      end
      M.set(42)
      puts M.get
      M.set(100)
      puts M.get
    RUBY

    _(result).must_answer <<~'OUT'
      42
      100
    OUT
  end

  it "module ivar nil poly" do
    _(ze0(<<~'RUBY')).must_answer "ok\n"
      # A module-level instance variable initialized to nil and later widened
      # to a polymorphic value (it holds nil, an empty [], and a String push)
      # must box the nil initializer as sp_box_nil(), not a bare 0, or the
      # assignment to the sp_RbVal const slot fails to compile.
      module Store
        @log = nil

        def self.capture
          prev = @log
          @log = []
          @log.push("select 1")
          @log = prev
        end
      end

      Store.capture
      puts "ok"
    RUBY
  end

  it "module ivar op write" do
    result = ze0(<<~'RUBY')
      # Module-level @ivar referenced inside `def self.X` (the canonical
      # Ruby singleton-state pattern) used to emit as `self->iv_X` in C.
      # The class method has no self parameter -- module class methods
      # dispatch through the module's static table rather than an
      # instance pointer -- so the use site failed to compile.
      #
      # Fix: `ivar_lhs` now detects the "current emit scope is a module
      # class method" case and routes the lhs / rhs to the module's
      # `cst_<Mod>_<name>` static slot. The InstanceVariableReadNode
      # arm already had this dispatch inline; the operator-write / or-
      # write / and-write arms reached `ivar_lhs` and got the wrong
      # `self->iv_X` expansion.
      #
      # Coverage:
      #   - Plain `@count += 1` (InstanceVariableOperatorWriteNode).
      #   - `@count = N` (InstanceVariableWriteNode).
      #   - `@flag ||= true` (InstanceVariableOrWriteNode).
      #   - Read access via `@count` (InstanceVariableReadNode) --
      #     unchanged but exercised by the puts below.

      module Counter
        @count = 0
        @flag = false

        def self.increment
          @count += 1
        end

        def self.reset
          @count = 0
        end

        def self.set_flag
          @flag ||= true
        end

        def self.value
          @count
        end

        def self.flag?
          @flag
        end
      end

      Counter.increment
      Counter.increment
      Counter.increment
      puts Counter.value
      Counter.set_flag
      puts Counter.flag?
      Counter.reset
      puts Counter.value
    RUBY

    _(result).must_answer <<~'OUT'
      3
      true
      0
    OUT
  end

  it "module method serves two ivar layouts" do
    result = ze0(<<~'RUBY')
      # One `def` in a module, included into classes that lay their ivars out
      # differently. `codegen::share` emits a widely-inherited body ONCE, over a
      # `RubyValue` receiver, and an ivar access in that body carries the SLOT INDEX
      # -- so a group whose members disagree about where a name sits must not share.
      #
      # `analyze::mro` lays slots out furthest-ancestor-first, which makes the module's
      # own names sort ahead of the includer's: `A` and `B` below would agree if the
      # only difference were their own ivars. A SUPERCLASS is what splits them --
      # `Base#initialize`'s `@a` takes slot 0 on `A`, pushing the module's `@x` to
      # slot 1, while on `B` it is slot 0.
      #
      # The two must therefore behave identically despite being emitted differently,
      # which is the property `ZEO_VERIFY_SHARE=1` reports on.

      class Base
        def initialize
          @a = 99
        end
      end

      module Counter
        def bump
          @x = (@x || 0) + 1
          "#{@x} #{@x.class} #{@x + 1} #{@x * 2} #{@x - 1} #{@x.abs} #{@x.to_s}"
        end

        def peek = @x
      end

      class WithSuper < Base
        include Counter
      end

      class WithoutSuper
        include Counter
      end

      a = WithSuper.new
      b = WithoutSuper.new

      p a.bump.split.first
      p a.bump.split.first
      p b.bump.split.first

      p [a.peek, b.peek]

      # The layouts really are different, and each class reports only its own names.
      p a.instance_variables
      p b.instance_variables

      # A third includer that shares WithoutSuper's layout exactly still works.
      class AlsoWithoutSuper
        include Counter
      end
      c = AlsoWithoutSuper.new
      p c.bump.split.first
      p [c.peek, c.instance_variables]

      # The module's own method is one definition, however many classes carry it.
      p Counter.instance_method(:bump).owner
      p [WithSuper.new.method(:bump).owner, WithoutSuper.new.method(:bump).owner]
    RUBY

    _(result).must_answer <<~'OUT'
      "1"
      "2"
      "1"
      [2, 1]
      [:@a, :@x]
      [:@x]
      "1"
      [1, [:@x]]
      Counter
      [Counter, Counter]
    OUT
  end

  it "module removes its own instance variable" do
    result = ze0(<<~'RUBY')
      # `instance_variables` and `remove_instance_variable` have to agree about a
      # CLASS or MODULE receiver, and they did not.
      #
      # A class keeps its ivars in a store of their own, and only the write and the
      # listing knew about it -- the removal fell through to the plain-object store,
      # found nothing, and raised NameError for a name the listing had just
      # reported. `Bundler::Plugin.reset!` runs the pair one line apart:
      #
      #   instance_variables.each { |i| remove_instance_variable(i) }
      #
      # so every `bundle` command died on its own reset.

      module M
        module_function

        def seed
          @sources = { a: 1 }
          @commands = {}
        end

        def wipe = instance_variables.each { |i| remove_instance_variable(i) }
      end

      M.seed
      p M.instance_variables
      p M.instance_variable_defined?(:@sources)

      # The removal answers what the slot held, as ruby's does.
      p M.remove_instance_variable(:@sources)
      p M.instance_variables
      p M.instance_variable_defined?(:@sources)

      # A removed name reads back as nil, not as a stale value.
      p M.instance_variable_get(:@sources)

      # Removing what is not there raises, and names the ivar.
      begin
        M.remove_instance_variable(:@sources)
      rescue NameError => e
        p [e.class, e.message]
      end

      # The whole loop, which is bundler's own.
      M.seed
      M.wipe
      p M.instance_variables

      # A CLASS behaves the same way, and a re-seed re-lists in assignment order.
      class C
        def self.seed
          @b = 2
          @a = 1
        end
      end
      C.seed
      p C.instance_variables
      p C.remove_instance_variable(:@b)
      p C.instance_variables
      C.instance_variable_set(:@b, 3)
      p C.instance_variables

      # A frozen class refuses the removal.
      class F
        def self.seed = @x = 1
      end
      F.seed
      F.freeze
      begin
        F.remove_instance_variable(:@x)
      rescue => e
        p [e.class, e.message]
      end
    RUBY

    _(result).must_answer <<~'OUT'
      [:@sources, :@commands]
      true
      {a: 1}
      [:@commands]
      false
      nil
      [NameError, "instance variable @sources not defined"]
      []
      [:@b, :@a]
      2
      [:@a]
      [:@a, :@b]
      [FrozenError, "can't modify frozen Class: F"]
    OUT
  end

  it "multi assign ivar type" do
    result = ze0(<<~'RUBY')
      # `@a, @b = x, y` must propagate the param types into the ivars just
      # like separate `@a = x; @b = y` assignments do. Previously the
      # destructuring target wasn't recognized as an assignment, so an
      # attr_reader ivar got widened to poly and a chained <=> mis-dispatched.
      class V
        include Comparable
        attr_reader :maj, :min
        def initialize(maj, min); @maj, @min = maj, min; end
        def <=>(other)
          cmp = @maj <=> other.maj
          if cmp == 0
            cmp = @min <=> other.min
          end
          cmp
        end
      end
      a = V.new(1, 2)
      b = V.new(1, 10)
      puts "a<b=#{a < b}"
      puts "b<a=#{b < a}"
      puts "eq=#{V.new(3, 4) == V.new(3, 4)}"
    RUBY

    _(result).must_answer <<~'OUT'
      a<b=true
      b<a=false
      eq=true
    OUT
  end

  it "nil ivar" do
    result = ze0(<<~'RUBY')
      # Test: nil-initialized ivar type inference
      # When @left/@right are initialized to nil and later assigned Node objects,
      # the compiler should infer them as OBJECT(Node), not NIL.

      class Node
        attr_accessor :left, :right, :val
        def initialize(v)
          @val = v
          @left = nil
          @right = nil
        end
      end

      class Tree
        attr_accessor :root
        def initialize
          @root = nil
        end
        def set_root(n)
          @root = n
        end
      end

      def make_node(depth)
        n = Node.new(depth)
        if depth > 0
          child_l = make_node(depth - 1)
          child_r = make_node(depth - 1)
          n.left = child_l
          n.right = child_r
        end
        n
      end

      tree = make_node(10)
      puts tree.val
      puts tree.left.val
      puts tree.right.val

      t = Tree.new
      t.set_root(tree)
      puts t.root.val

      puts "done"
    RUBY

    _(result).must_answer <<~'OUT'
      10
      9
      9
      10
      done
    OUT
  end

  it "singleton body ivar lands on the singleton" do
    result = ze0(<<~'RUBY')
      # An `@x = v` inside `class << self` writes an ivar of the SINGLETON class,
      # which is a different object from the class -- so an `attr_accessor` written
      # beside it (a CLASS method, whose self is the class) does not read it back.

      class Widget
        class << self
          @registry = "singleton-ivar"

          attr_accessor :registry

          def peek
            @registry
          end
        end
      end

      p Widget.registry
      p Widget.peek
      p Widget.singleton_class.instance_variable_get(:@registry)
      p Widget.instance_variable_get(:@registry)

      Widget.registry = "set-on-the-class"
      p Widget.registry
      p Widget.singleton_class.instance_variable_get(:@registry)
    RUBY

    _(result).must_answer <<~'OUT'
      nil
      nil
      "singleton-ivar"
      nil
      "set-on-the-class"
      "singleton-ivar"
    OUT
  end

  it "singleton body ivar reaches the singleton class" do
    result = ze0(<<~'RUBY')
      # An ivar named inside `class << X` belongs to X's SINGLETON CLASS, which is a
      # different object from X. Both spellings of the body have to agree.

      def try(tag)
        puts "#{tag}: #{yield.inspect}"
      rescue StandardError => e
        puts "#{tag}: #{e.class}: #{e.message}"
      end

      # a: per-object form, plain write.
      A = Module.new
      class << A
        @plain = 7
      end
      try("a") { [A.singleton_class.instance_variable_get(:@plain), A.instance_variable_get(:@plain)] }

      # b: the `class << self` form, which already agreed.
      class B
        class << self
          @plain = 7
        end
      end
      try("b") { [B.singleton_class.instance_variable_get(:@plain), B.instance_variable_get(:@plain)] }

      # c: read back inside the same body.
      C = Module.new
      class << C
        @seen = 3
        @echo = @seen
      end
      try("c") { C.singleton_class.instance_variable_get(:@echo) }

      # d: an operator-assign and an or-assign, which read before they write.
      D = Module.new
      class << D
        @n = 1
        @n += 1
        @m ||= "set"
        @m ||= "not this"
      end
      try("d") { [D.singleton_class.instance_variable_get(:@n), D.singleton_class.instance_variable_get(:@m)] }

      # e: an unset ivar reads nil, not an error.
      E = Module.new
      class << E
        @out = @never_set.inspect
      end
      try("e") { E.singleton_class.instance_variable_get(:@out) }

      # f: the accessor written BESIDE it reads the object's own ivars, so it does
      #    not see what the body wrote -- oracle-verified, and the reason the write
      #    cannot simply stay where it stands.
      F = Module.new
      class << F
        @slack = "x"
        attr_accessor :slack
      end
      try("f") { F.slack }

      # g: two objects do not share.
      G1 = Module.new
      G2 = Module.new
      class << G1
        @who = "g1"
      end
      class << G2
        @who = "g2"
      end
      try("g") { [G1.singleton_class.instance_variable_get(:@who), G2.singleton_class.instance_variable_get(:@who)] }

      # i: instance_variables reports it on the singleton class.
      I = Module.new
      class << I
        @a = 1
        @b = 2
      end
      try("i") { I.singleton_class.instance_variables.sort }

      # The `class << self` spelling, whose nested reads were wrong in the same way:
      # only the two bare statement forms used to be mapped.
      class J
        class << self
          @seen = 3
          @echo = @seen
          @n = 1
          @n += 1
        end
      end
      try("j") { [J.singleton_class.instance_variable_get(:@echo), J.singleton_class.instance_variable_get(:@n)] }

      # A `def` body's ivars belong to whatever `self` it runs against, so the
      # rewrite must stop at the definition boundary.
      K = Module.new
      class << K
        @outer = "singleton"
        def peek = @outer
      end
      try("k") { [K.peek, K.singleton_class.instance_variable_get(:@outer)] }
    RUBY

    _(result).must_answer <<~'OUT'
      a: [7, nil]
      b: [7, nil]
      c: 3
      d: [2, "set"]
      e: "nil"
      f: nil
      g: ["g1", "g2"]
      i: [:@a, :@b]
      j: [3, 2]
      k: [nil, "singleton"]
    OUT
  end

  it "singleton method reads ivars and yields" do
    _(ze0(<<~'RUBY')).must_answer "105\n"
      obj = Object.new
      obj.instance_variable_set(:@base, 100)
      def obj.add
        @base + yield
      end
      p obj.add { 5 }
    RUBY
  end

  it "stdlib class in ivar" do
    result = ze0(<<~'RUBY')
      # A `.new` on a stdlib class Spinel does not implement (Pathname, OpenStruct,
      # IPAddr, ...) used to silently degrade to an inert 0 -- the object's methods
      # then returned nil, so a program that actually used it diverged from CRuby with
      # no signal. It now raises NameError instead: if it can't work, it fails loudly.
      #
      # A class Spinel models as a no-op (Mutex, single-threaded) and user-defined
      # classes are unaffected. The ivar slot still compiles either way (the raise
      # expression is int-typed, so no undeclared `sp_<Class> *` field is emitted).
      #
      # ostruct/ipaddr are unimplemented stdlib: under SPINEL_REQUIRE_GATE the
      # `require` itself is a compile error, so a real program omits it and the .new
      # still raises NameError at the use site. Mutex is core (no require needed).
      #
      # Pathname used to stand here too. It is a bundled library now, so naming it
      # without requiring it is a compile error that says which require is missing --
      # a different (and better) answer than this file is about.

      require "ipaddr"

      class WithMutex
        def initialize
          @lock = Mutex.new   # special-cased no-op; works
          @n = 5
        end
        def n
          @n
        end
      end

      class WithIPAddr
        def initialize
          @addr = IPAddr.new('127.0.0.1')   # unsupported stdlib class -> raises here
          @v = 7
        end
        def v
          @v
        end
      end

      # A Mutex ivar works (single-threaded no-op); another ivar reads fine.
      puts WithMutex.new.n          #=> 5

      # A user-defined class is unaffected.
      class Point
        def initialize(x)
          @x = x
        end
        def x
          @x
        end
      end

      class Holder
        def initialize
          @p = Point.new(42)
        end
        def px
          @p.x
        end
      end

      puts Holder.new.px            #=> 42

      # Constructing the unsupported-stdlib holder raises (loud), not a silent inert 0.
      begin
        WithIPAddr.new
        puts "no raise"
      rescue NameError
        puts "ipaddr raised"
      end

      # A direct `.new` on an unsupported stdlib class raises too.
      begin
        OpenStruct.new
        puts "no raise"
      rescue NameError
        puts "openstruct raised"
      end

      puts "done"
    RUBY

    _(result).must_answer <<~'OUT'
      5
      42
      no raise
      openstruct raised
      done
    OUT
  end

  it "top level def touching an ivar does not taint builtins" do
    result = ze0(<<~'RUBY')
      # `mro::materialize_methods` collects ivars from every ancestor, but a
      # BUILTIN never materializes Object's methods -- so the ivar loop has to
      # skip Object for builtins exactly as the method loop does. It didn't,
      # which made this program fail to compile with a rejection blaming
      # `Integer` for a `@count` that Integer has nothing to do with.

      def bump; @count = (@count || 0) + 1; end
      bump
      p @count
      p 1 + 2
      p "s".length
      p [1, 2].map { |i| i * 2 }
    RUBY

    _(result).must_answer <<~'OUT'
      1
      3
      1
      [2, 4]
    OUT
  end

  it "top level ivars live on the main object" do
    result = ze0(<<~'RUBY')
      # Was rejected as "the `main` object has no ivar storage". It has some
      # now (`dispatch::Object`'s name-keyed map), so a top-level `@x` -- read
      # or written, at the top level or from a top-level `def`, which is a
      # private method of Object whose self IS main -- is ordinary state.
      # A never-assigned one reads nil rather than raising.

      @x = 1
      p @x
      p @never
      def read_it; @x; end
      p read_it
      def bump; @count = (@count || 0) + 1; end
      bump
      bump
      p @count
    RUBY

    _(result).must_answer <<~'OUT'
      1
      nil
      1
      2
    OUT
  end

  it "toplevel ivar opassign" do
    result = ze0(<<~'RUBY')
      # A top-level `@ivar ||=` / `@ivar &&=` must emit its store. Previously the
      # top-level slot was unresolved (class_id < 0), so no branch matched and the
      # assignment was silently dropped.
      @y ||= 5
      p @y                 # 5
      @y ||= 99
      p @y                 # 5  (already set, ||= is a no-op)

      @s ||= "hi"
      p @s                 # "hi"

      @a = 3
      @a &&= 10
      p @a                 # 10
      @b &&= 10
      p @b                 # nil (unset stays nil under &&=)
    RUBY

    _(result).must_answer <<~'OUT'
      5
      5
      "hi"
      10
      nil
    OUT
  end

  it "toplevel method shares mains ivars" do
    result = ze0(<<~'RUBY')
      # A method written at the TOP LEVEL lands on Object, and its receiver is
      # the runtime `main` object -- name-keyed ivars, the same storage the
      # top-level scope itself writes.
      @config = "top"
      def read_config
        x = 1
        @config
      end
      p read_config
      def read2 = @config
      p read2
      def w(v)
        @config = v
        nil
      end
      w("changed")
      p @config
      p read_config
    RUBY

    _(result).must_answer <<~'OUT'
      "top"
      "top"
      "changed"
      "changed"
    OUT
  end

  it "unassigned ivar reads nil" do
    result = ze0(<<~'RUBY')
      # Reading an instance variable that is never assigned anywhere in the program
      # is nil in Ruby, not a compile error. A top-level method reading such an ivar
      # gets a nil-valued slot in the Toplevel pseudo-class.
      def f; @x; end
      p f            # nil

      p @top        # nil, read at top level

      def g; @z.nil?; end
      p g           # true

      def h; @w.inspect; end
      p h           # "nil"

      # defined? still reports it as absent until assigned.
      p defined?(@never)   # nil
    RUBY

    _(result).must_answer <<~'OUT'
      nil
      nil
      true
      "nil"
      nil
    OUT
  end

  it "uninit ivar returns nil" do
    result = ze0(<<~'RUBY')
      # Issue #712. A read-only @ivar (never assigned anywhere in the class)
      # must read as nil, not fail with "struct has no field iv_x". The scan
      # pass now adds a "nil" slot for any read-only ivar so the struct gets
      # the field and Ruby semantics surface for `.inspect` / `.nil?`.

      class C
        def x; @x; end
        def y_nilp; @y.nil?; end
      end
      puts C.new.x.inspect
      puts C.new.y_nilp

      # When a method writes the ivar but another method reads it before
      # write, the slot still has to widen correctly across writers. Here
      # `@n` gets a string write so reads must see "" or the written value.
      class D
        def set; @n = "x"; end
        def get; @n; end
      end
      d = D.new
      puts d.get.inspect
      d.set
      puts d.get
    RUBY

    _(result).must_answer <<~'OUT'
      nil
      true
      nil
      x
    OUT
  end
end
